export const meta = {
  name: 'nightly-orchestrator',
  description: 'Phase B of the nightly loop: build every Planned epic in its own worktree, integrate serially, consistency-check overlaps, deploy staging, write the daily digest',
  whenToUse: 'Fired by the scheduled runtime (routines / GitHub Actions / GitLab CI) after a kickoff (Phase A) approved plans. Do not run without approved plans.',
  phases: [
    { title: 'Reconcile', detail: 'read epics + PR feedback from git/forge — source of truth' },
    { title: 'Build', detail: 'one worker per Planned epic, isolated worktree; verify like a user (browser) against feature_list' },
    { title: 'Blocked-check', detail: 'non-progress backstop: block + escalate epics that failed N nights' },
    { title: 'Integrate', detail: 'serialized merges into the integration branch, full suite after each' },
    { title: 'Consistency', detail: 'overlap-flagged epics: combined behavioral check' },
    { title: 'Deploy', detail: 'integration branch → staging (deploy.sh)' },
    { title: 'Gardening', detail: 'reserved cleanup slot: doc-health, scoped simplify, deviation scan' },
    { title: 'Digest', detail: 'immutable daily HTML digest + state push' },
  ],
}

// ---- Two-prompt model (initializer vs coder) -------------------------------
// /core:new-project is the INITIALIZER — it builds the environment ONCE
// (contract, state layer, feature_list contract, plugins). THIS workflow is the
// repeating CODER — one fresh-context session per unit of work per night. It never
// re-initializes; it reconciles from git+forge and builds against approved plans.
//
// ---- Guardrails (ADR-0008) -------------------------------------------------
// - HITL invariants: nothing merges to main here. Approved+green PRs merge at
//   the NEXT KICKOFF (Phase A, operator present). This run only builds,
//   integrates on the integration branch, deploys staging, reports.
// - Done is decided by the per-epic feature_list.json, NOT the agent's judgement:
//   every feature has E2E `steps` + `passes:false`; a worker may ONLY flip `passes`
//   to true after driving those steps in a REAL browser. It must never edit/remove
//   steps or add/delete features (CLAUDE.md rule 2). This kills premature-victory.
// - Non-progress: an epic that fails N nights is marked Blocked + escalated via the
//   notifications hook — never looped forever (the agent doesn't self-terminate).
// - Budget is a HARD cost cap (distinct from rate limits — WS5): stop cleanly.
// - Rate limits: workers run via claude -p (auto-backoff on 429). Hard stops
//   (billing_error / weekly cap) are detected by the runtime wrapper which
//   reschedules to the reset time; this script just stops cleanly — the next
//   run reconciles from reality (git+forge = idempotent source of truth).

const MIN_BUDGET_PER_EPIC = 60_000
// Non-progress backstop (harness lesson): an epic that fails to land green this
// many NIGHTS in a row is marked Blocked and escalated — never looped forever.
const BLOCK_AFTER_ATTEMPTS = 3

const ORCH = 'orchestrator/bin/orch'
const today = args?.date  // passed by the runtime wrapper (Date.now unavailable)
if (!today) throw new Error('args.date (YYYY-MM-DD) is required — the runtime wrapper passes it')
const maxEpics = args?.maxEpics ?? 4
// Hard per-night cap (audit L-I1): the harness budget directive if set, else
// the wrapper's ORCH_BUDGET_TOKENS via args. remaining() is computed from
// budget.spent(), which works regardless of how the cap arrived.
const CAP = budget.total ?? args?.budgetTokens ?? null
const capRemaining = () => (CAP ? Math.max(0, CAP - budget.spent()) : Infinity)

// ---- Phase: Reconcile -------------------------------------------------------
phase('Reconcile')
const reconciled = await agent(
  `Reconcile orchestrator state from reality (git + forge are the source of truth).
   1. Run: bash ${ORCH} state pull-feedback --pr-state open  → operator signals.
      (Normally /orchestrator:kickoff already applied these; re-applying is idempotent and safe.)
   2. For each unapplied signal: approve → push-status --state Approved; revise →
      push-status --state Changes-requested --note "<notes>".
   3. Gather epics to build = state Planned (new work) PLUS state Changes-requested
      (rework, back from a negative review): run
      bash ${ORCH} state list-epics --state Planned  and
      bash ${ORCH} state list-epics --state Changes-requested.
      Every one MUST have an approved plan (get-plan exists) — an epic without one
      MUST NOT build, drop it and note why.
   4. Also list epics in state Paused — if their paused-until timestamp has passed,
      push-status back to Planned (or Changes-requested if it was mid-rework).
   4b. EXCLUDE state Blocked entirely: those failed the retry budget and await human
      triage (they were escalated via the notifications hook). Never auto-rebuild them.
      Also read each buildable epic's "attempts=<n>" marker from its note (0 if absent)
      and return it — the build phase uses it for the non-progress backstop.
   5. RESCUE ORPHANS (audit L-B6): bash ${ORCH} state list-epics --state In-progress
      — any epic still In-progress now was left by a crashed/unfinished worker
      (no worker runs while reconcile does). Re-queue each: has a pr/branch →
      rework (fold its last note in); else new work.
   6. For each epic to build, classify its foreseen "complexity" from the approved
      plan — so we spend the right model on it (design §Runtime/models):
        low    = small footprint, no risky paths, mostly mechanical
        medium = normal feature work
        high   = large/tricky footprint, touches auth/security/migrations/infra,
                 many edge cases, or it's a re-attempt after a hard failure.
   Return JSON only. Put both new and rework epics in "planned"; mark each with
   "rework": true|false so the worker knows to fold in revise-notes, and
   "complexity": low|medium|high. Signals from pull-feedback carry "epicId"
   (resolved from the orch/<id> PR branch) — route by that, never by title.`,
  { label: 'reconcile', schema: {
      type: 'object',
      properties: {
        planned: { type: 'array', items: { type: 'object', properties: {
          id: { type: 'string' }, title: { type: 'string' }, rework: { type: 'boolean' },
          complexity: { type: 'string', enum: ['low','medium','high'] },
          attempts: { type: 'number' },
          footprint: { type: 'array', items: { type: 'string' } },
          overlaps: { type: 'array', items: { type: 'string' } } }, required: ['id'] } },
        dropped: { type: 'array', items: { type: 'string' } },
        feedbackApplied: { type: 'number' },
      }, required: ['planned'] } }
)

// Right-size the model to the foreseen complexity (design §Runtime/models):
// workers are Sonnet by default; Opus only for genuinely hard/high-risk epics;
// effort scales within a tier. A failed non-Opus worker escalates once to Opus.
function modelFor(complexity) {
  return complexity === 'high'
    ? { model: 'opus', effort: 'high' }
    : { model: 'sonnet', effort: complexity === 'low' ? 'low' : 'medium' }
}

const cleared = reconciled?.planned ?? []
const planned = cleared.slice(0, maxEpics)
const deferred = cleared.slice(maxEpics).map(e => e.id)
if (deferred.length) log(`maxEpics=${maxEpics}: deferring ${deferred.join(', ')} to the next run (still Planned)`)
log(`${planned.length} epic(s) cleared to build (${reconciled?.dropped?.length ?? 0} dropped, ${reconciled?.feedbackApplied ?? 0} feedback signals applied)`)

// ---- Phase: Build — one worker per epic, isolated worktree ------------------
phase('Build')
const results = []
if (planned.length) {
  const WORKER_SCHEMA = {
    type: 'object', properties: {
      id: { type: 'string' }, pr: { type: ['number','string','null'] },
      branch: { type: 'string' }, testsGreen: { type: 'boolean' },
      featuresPassed: { type: 'number' }, featuresTotal: { type: 'number' },
      capitalized: { type: ['boolean','string','null'] },
      linesChanged: { type: 'number' },
      touchedPaths: { type: 'array', items: { type: 'string' } },
      done: { type: 'boolean' }, notes: { type: 'string' } },
    required: ['id','branch','testsGreen','done'] }
  const workerPrompt = (e, escalated) =>
      `You are the build worker for epic ${e.id} (${e.title ?? ''})${e.rework ? ' — this is REWORK (it came back from a negative review; fold in the revise-notes on the epic record)' : ' — this is new work'}.${escalated ? ' [ESCALATED to Opus after a failed first attempt — be especially careful.]' : ''}
       CONTRACT — build strictly against the approved plan:
       0. bash ${ORCH} state push-status --id ${e.id} --state In-progress   (a worker is now on it)
       1. bash ${ORCH} state get-plan --epic ${e.id}   → the plan. Stay inside it
          and inside your assigned footprint: ${JSON.stringify(e.footprint ?? [])}.
          Files outside the footprint belong to other epics tonight (single-writer
          rule) — if you MUST touch one, stop that change and note the conflict.
       2. Work on branch orch/${e.id} (create from the integration branch if new;
          otherwise continue it, folding in the revise-notes from the epic record).
       3. Implement → run the FULL test suite → self-review adversarially
          (correctness, edge cases, plan conformity) → fix → re-run.
       3b. VERIFY LIKE A USER against the feature list, NOT like CI. Read
          .orch/epics/${e.id}/feature_list.json (each feature has E2E "steps" +
          "passes":false). For EACH feature: drive its steps in a REAL browser via
          the playwright MCP (open the app, click/type/navigate as a user would) and
          observe whether "expected" holds. Flip "passes" to true ONLY on a real pass.
          It is UNACCEPTABLE to remove or edit steps, or add/delete features, or flip
          passes without observing the outcome (CLAUDE.md rule 2) — the ONLY write you
          make to this file is a false→true on "passes". If a feature's surface is a
          known blindspot (e.g. a native OS dialog the browser can't see), leave
          passes:false and record it in "blindspots" so the digest flags it — never
          auto-pass it. "done" is true ONLY when every feature passes (or is an
          acknowledged blindspot). If no feature_list.json exists yet, build it from
          the approved plan's acceptance criteria first (schema: .orch/feature-list.schema.json).
       4. Commit as EXACTLY ONE commit per epic: do the work, then squash to a
          single, well-messaged commit on orch/${e.id} before opening the PR
          (e.g. \`git reset --soft <branch base>\` then one \`git commit\`, or amend
          as you go). A clean one-commit diff is what the reviewer reads in the
          morning digest — many WIP commits bury the review. Then open/update the PR
          for orch/${e.id} (gh/glab): body = what changed & why, plan link, test
          evidence. NEVER push to main. NEVER merge.
       5. bash ${ORCH} state push-status --id ${e.id} --state Needs-review --pr <PR-number>
          — the --pr link is MANDATORY when a PR exists (it is the deterministic
          PR↔epic mapping the feedback loop depends on). If you could not finish,
          leave In-progress with a note saying exactly where you stopped.
       6. CAPITALIZE (only if you solved something non-trivial — a tricky bug, a
          reusable pattern, a gotcha): write it down so future sessions inherit it —
          a short topic doc under docs/ or a note in the relevant .claude/rules file,
          or your agent memory. Extends the "a file is earned after 3 delegations"
          convention. Skip for routine work. Set "capitalized" accordingly.
       Return JSON: {id, pr, branch, testsGreen, featuresPassed, featuresTotal, capitalized, linesChanged, touchedPaths, done, notes}.`

  const built = await parallel(planned.map(e => async () => {
    if (capRemaining() < MIN_BUDGET_PER_EPIC) {
      log(`budget guard: skipping ${e.id} (${Math.round(capRemaining()/1000)}k tokens left of cap ${CAP})`)
      return null
    }
    const pick = modelFor(e.complexity)
    log(`build ${e.id}: complexity=${e.complexity ?? 'medium'} → ${pick.model}/${pick.effort}${e.rework ? ' (rework)' : ''}`)
    let r = await agent(workerPrompt(e, false),
      { label: `build:${e.id}`, phase: 'Build', isolation: 'worktree', model: pick.model, effort: pick.effort, schema: WORKER_SCHEMA })
    // Escalate once to Opus if a non-Opus worker didn't land it green (design: "escalate to Opus on failure").
    if (r && pick.model !== 'opus' && !(r.done && r.testsGreen)
        && capRemaining() > MIN_BUDGET_PER_EPIC) {
      log(`build ${e.id}: first attempt not green on ${pick.model} — escalating to opus/high`)
      const r2 = await agent(workerPrompt(e, true),
        { label: `build:${e.id}:opus`, phase: 'Build', isolation: 'worktree', model: 'opus', effort: 'high', schema: WORKER_SCHEMA })
      if (r2) r = r2
    }
    return r
  }))
  results.push(...built.filter(Boolean))
}
log(`${results.length}/${planned.length} workers returned; green: ${results.filter(r => r.testsGreen).length}`)

// ---- Phase: Blocked-check — non-progress backstop (never loop an epic forever) --
// Every epic that did NOT land green tonight had a full attempt (sonnet, escalated
// to opus). Bump its persisted attempt counter; at BLOCK_AFTER_ATTEMPTS mark it
// Blocked and escalate via the notifications hook. The agent never decides global
// termination — this counter + the feature_list do (harness lesson).
phase('Blocked-check')
const stalled = planned.filter(e => {
  const r = results.find(x => x.id === e.id)
  return !r || !(r.done && r.testsGreen)
})
const blocked = []
for (const e of stalled) {
  const attempts = (e.attempts ?? 0) + 1
  const r = results.find(x => x.id === e.id)
  const decision = await agent(
    `Non-progress bookkeeping for epic ${e.id}. It failed to land green this run
     (attempt #${attempts}${BLOCK_AFTER_ATTEMPTS ? ` of ${BLOCK_AFTER_ATTEMPTS}` : ''}).
     Last worker note: ${JSON.stringify(r?.notes ?? 'no worker result (skipped/crashed)')}.
     If ${attempts} >= ${BLOCK_AFTER_ATTEMPTS}: run
       bash ${ORCH} state push-status --id ${e.id} --state Blocked --note "attempts=${attempts} blocked: <one-line reason> — needs human triage"
     and ESCALATE by emitting a Notification the notifications hook will forward
     (print a line starting "ESCALATE: epic ${e.id} blocked after ${attempts} attempts — <reason>").
     Otherwise (still under the limit): push-status back to its prior buildable state
     (Changes-requested if it has a PR/branch, else Planned) with note "attempts=${attempts} <where it stopped>",
     so the next night retries with the counter preserved.
     Return JSON: {id:"${e.id}", attempts:${attempts}, blocked:<bool>, reason:<string>}.`,
    { label: `blocked-check:${e.id}`, phase: 'Blocked-check', schema: {
        type: 'object', properties: {
          id: { type: 'string' }, attempts: { type: 'number' },
          blocked: { type: 'boolean' }, reason: { type: ['string','null'] } },
        required: ['id','blocked'] } }
  )
  if (decision?.blocked) blocked.push(decision)
}
if (blocked.length) log(`blocked ${blocked.length} epic(s) after ${BLOCK_AFTER_ATTEMPTS} attempts: ${blocked.map(b => b.id).join(', ')} — escalated`)

// ---- Phase: Integrate — SERIALIZED (Cursor's integrator-bottleneck lesson) --
phase('Integrate')
const integrated = []
for (const r of results.filter(r => r.done && r.testsGreen)) {
  const ok = await agent(
    `Serialized integration step. Merge branch ${r.branch} into the integration
     branch (orch/integration — create from main if missing). Then run the FULL
     test suite on the result. Green → keep the merge, report ok:true.
     Red → revert THIS merge only, push-status --id ${r.id} --state Changes-requested
     --note "integration failure: <first failing test>", report ok:false.
     Never touch main. Return JSON: {id:"${r.id}", ok, failure}.`,
    { label: `integrate:${r.id}`, phase: 'Integrate', schema: {
        type: 'object', properties: { id: { type: 'string' }, ok: { type: 'boolean' }, failure: { type: ['string','null'] } },
        required: ['id','ok'] } }
  )
  if (ok) integrated.push({ ...r, integrated: ok.ok, failure: ok.failure })
}

// ---- Phase: Consistency — only where overlaps were flagged (scoped, no bottleneck)
phase('Consistency')
const overlapping = integrated.filter(r =>
  r.integrated && (planned.find(e => e.id === r.id)?.overlaps?.length))
let consistency = null
if (overlapping.length) {
  consistency = await agent(
    `Consistency check on the integration branch (overlap-flagged epics:
     ${overlapping.map(r => r.id).join(', ')}). Run the full regression suite,
     then a targeted behavioral check that EACH epic's acceptance criteria still
     hold in the combined result (read each plan: bash ${ORCH} state get-plan
     --epic <id>). Use the integration-checker methodology. If the combined
     result breaks a feature that worked in isolation, that is a FAIL —
     push-status the broken epics to Changes-requested with a precise note.
     Return JSON: {pass, brokenEpics, evidence}.`,
    { label: 'consistency', agentType: 'integration-checker', schema: {
        type: 'object', properties: { pass: { type: 'boolean' },
          brokenEpics: { type: 'array', items: { type: 'string' } },
          evidence: { type: 'string' } }, required: ['pass'] } }
  )
} else {
  log('no overlapping epics — consistency check scoped out (footprints disjoint)')
}

// ---- Phase: Deploy — integration branch (ALL epics) → one staging env -------
phase('Deploy')
const greenCount = integrated.filter(r => r.integrated).length
let deploy = null
// Deploy only when there were no overlaps, or the consistency agent RAN and
// passed — a crashed checker must not open the gate (audit L-I7).
const consistencyOk = overlapping.length === 0 ? true : consistency?.pass === true
if (greenCount && consistencyOk) {
  deploy = await agent(
    `Deploy the integration branch to staging: bash orchestrator/adapters/deploy.sh
     orch/integration. Capture the staging URL/routes it prints. If the script is
     the unconfigured template, report deployed:false reason:"deploy.sh not configured".
     Return JSON: {deployed, url, reason}.`,
    { label: 'deploy', schema: { type: 'object', properties: {
        deployed: { type: 'boolean' }, url: { type: ['string','null'] }, reason: { type: ['string','null'] } },
        required: ['deployed'] } }
  )
} else {
  log(`deploy skipped (green integrations: ${greenCount}, consistencyOk: ${consistencyOk}${consistency === null && overlapping.length ? ' — checker did not run: gate stays CLOSED' : ''})`)
}

// ---- Phase: Gardening — the "20% cleanup" lane (entropy control) ------------
// Reserve one slot for entropy control rather than only features: run when the
// night was light (built < maxEpics) or budget remains. One agent does doc-health,
// a scoped /simplify on tonight's merged diff, and a deviation scan; it opens a
// SMALL gardening PR (never touches main, never merges) so the morning review sees
// it alongside the feature PRs. Skipped entirely if the budget is exhausted.
let gardening = null
if (capRemaining() >= MIN_BUDGET_PER_EPIC && (planned.length < maxEpics || greenCount === 0)) {
  gardening = await agent(
    `Gardening lane (the reserved cleanup slot). On a fresh branch orch/gardening-${today}
     off the integration branch, do LIGHT entropy control — NOT feature work:
     1. Doc/state health: stale pointers, dead references, growth-detection findings
        (docs/SUGGESTIONS.md) worth acting on now.
     2. A scoped simplification pass over tonight's merged diff only (reuse, dead code,
        needless complexity) — surgical, no rewrites of working code.
     3. A deviation scan: code that drifted from .claude/rules or CLAUDE.md.
     Make only small, safe changes; run the full suite; commit as ONE commit and open a
     SMALL PR (body: what & why). NEVER push to main, NEVER merge. If nothing is worth
     doing, do nothing and report skipped:true. Return JSON: {done, pr, skipped, summary}.`,
    { label: 'gardening', phase: 'Gardening', isolation: 'worktree', model: 'sonnet', effort: 'low', schema: {
        type: 'object', properties: {
          done: { type: 'boolean' }, pr: { type: ['number','string','null'] },
          skipped: { type: 'boolean' }, summary: { type: 'string' } }, required: ['done'] } }
  )
} else {
  log('gardening lane skipped (no spare slot/budget this run)')
}

// ---- Phase: Digest — immutable daily HTML, append on re-run -----------------
phase('Digest')
await agent(
  `Write the morning digest for ${today} — the SINGLE human touchpoint — following
   orchestrator/digest-template.html EXACTLY (self-contained HTML, inline CSS,
   CSS-only ordinal-slot tabs: Overview = slot 1, then ONE tab per epic IN ORDER —
   emit <input id="tK">, a <label for="tK"> in .tabbar, and a <section class="panel">
   per slot; the CSS activates by slot, don't touch it). Run inputs (JSON): ${JSON.stringify({
     epics: integrated, consistency, deploy, blocked, gardening,
     spent: budget.spent(), budgetTotal: budget.total, dropped: reconciled?.dropped ?? [],
   })}. Read orchestrator/state.config.json for backend + forge.
   FLAG in "needs attention": every Blocked epic (from "blocked" — escalated, awaiting
   human triage) AND every feature whose feature_list.json entry has a non-empty
   "blindspots" (a surface the browser verify could NOT exercise — it is NOT proven,
   never report it as passed). Add the gardening PR (from "gardening") to the review
   list if one was opened.
   For EACH epic, build its panel from git + state (do NOT invent):
   - recap: title + a one-line what & why from the approved plan (bash ${ORCH} state
     get-plan --epic <id>); its state; risk.
   - risk: classify from orchestrator/risk-policy.json (linesChanged vs thresholds;
     touchedPaths vs highRiskPaths globs). HIGH → RISK_GATE_NOTE = "security-auditor
     pass REQUIRED before OK" and count it under "need attention".
   - ticket: ONLY if backend is a remote board — link the epic's board item URL
     (bash ${ORCH} state get-epic --id <id> / the adapter's cached URL). On backend
     "none": DROP the Ticket row entirely.
   - review: the PR number + forge URL; commit(s) via
     base=$(git merge-base orch/integration orch/<id>); git log <base>..orch/<id>
     --format='%h %s' — expect ONE commit (note it if >1), link each to the forge
     commit URL. Keep the approve/revise actions line.
   - what to test: the plan's acceptance checks as an ordered list (action → expected
     → staging route) + a cross-epic interaction check per overlap flag.
   - gates: tests / lint+typecheck / build / self-review.
   - diff: git diff <base>..orch/<id>, HTML-ESCAPE it, wrap each line in the
     template's spans (hunk @@…, meta for diff --git/+++/---, add for +lines, del for
     -lines); first ~200 lines then "…full diff on the PR". git diff --shortstat for
     FILES_CHANGED/ADDED/REMOVED.
   Header: N_EPICS; N_READY = green+integrated and NOT high-risk-awaiting-audit;
   N_ATTENTION = failed/paused/consistency-broken/high-risk-awaiting-audit. Overview
   panel: consistency verdict+evidence, deploy detail, deferred/paused (resume time).
   Write it in THREE places:
   1. docs/reports/nightly/${today}.html — if it exists, APPEND a
      "<details><summary>Run N …</summary>…</details>" block at the end, NEVER overwrite;
   2. bash ${ORCH} state push-digest --date ${today} < the same content;
   3. docs/reports/nightly/${today}.summary.md — SHORT plain-markdown for Slack/email:
      "✅ Went well" (green, OK-ready epics) + "⚠️ Needs attention" (failed/paused/
      consistency-broken/high-risk-awaiting-audit), 6–10 bullets, no HTML.
   Return JSON: {written: true, path}.`,
  { label: 'digest', schema: { type: 'object', properties: {
      written: { type: 'boolean' }, path: { type: 'string' } }, required: ['written'] } }
)

return {
  date: today,
  built: results.length,
  integrated: greenCount,
  consistency: consistency?.pass ?? null,
  deployed: deploy?.deployed ?? false,
  blocked: blocked.map(b => b.id),
  gardeningPr: gardening?.pr ?? null,
  tokensSpent: budget.spent(),
}
