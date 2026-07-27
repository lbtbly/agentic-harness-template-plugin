export const meta = {
  name: 'fix-ci',
  description: 'Triage red PRs from their CI logs and repair the fixable ones',
  whenToUse: 'After a build wave, or when orch state pull-checks reports open PRs red.',
  phases: [
    { title: 'Observe', detail: 'pull-checks: which PRs are red, and why' },
    { title: 'Triage',  detail: 'classify each failure from its job logs' },
    { title: 'Repair',  detail: 'patch, push, re-check — bounded' },
  ],
}

// Reaction half of the CI lane (ADR-0024). The observation half is
// `orch state pull-checks`, which is the first thing in this framework that can
// read a failing job's log.
//
// Two limits are structural, not tuning:
//   1. The agent CANNOT edit workflow files — protect-policy-paths.sh blocks it.
//      Only the code the workflow runs is in scope. A CI config that needs
//      changing is a human's call.
//   2. flake / infra / dependency escalate. "Fixing" a flake means retrying
//      until it passes, which is how a real bug gets merged.
const ORCH = 'orchestrator/bin/orch'
const MAX_ROUNDS = args?.maxRounds ?? 2      // per PR; a third attempt is a human's job
const MAX_PRS = args?.maxPrs ?? 6

const CHECKS_SCHEMA = {
  type: 'object',
  properties: {
    red: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          pr: { type: 'number' },
          epicId: { type: ['string', 'null'] },
          jobs: { type: 'array', items: { type: 'string' } },
        },
        required: ['pr'],
      },
    },
  },
  required: ['red'],
}

const TRIAGE_SCHEMA = {
  type: 'object',
  properties: {
    pr: { type: 'number' },
    class: {
      type: 'string',
      enum: ['test_regression', 'test_outdated', 'type_error', 'lint', 'build',
             'dependency', 'flake', 'infra', 'unknown'],
    },
    rootCause: { type: 'string' },
    fix: { type: 'string' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    escalate: { type: 'boolean' },
  },
  required: ['pr', 'class', 'rootCause', 'escalate'],
}

const REPAIR_SCHEMA = {
  type: 'object',
  properties: {
    pr: { type: 'number' },
    patched: { type: 'boolean' },
    pushed: { type: 'boolean' },
    status: { type: 'string', enum: ['green', 'red', 'pending', 'none', 'unknown'] },
    notes: { type: 'string' },
  },
  required: ['pr', 'patched', 'status'],
}

const NOT_FIXABLE = new Set(['flake', 'infra', 'dependency', 'unknown'])

phase('Observe')
const observed = await agent(
  `Run: bash ${ORCH} state pull-checks
   It returns one record per open PR: {pr, epicId, status, failedJobs:[{job,run,logExcerpt}]}.
   Return ONLY the PRs whose status is exactly "red", at most ${MAX_PRS} of them, as
   {red:[{pr, epicId, jobs:[<failing job names>]}]}. A "pending" PR is NOT red — its
   checks have not finished. Report what you found; do not fix anything.`,
  { label: 'pull-checks', phase: 'Observe', schema: CHECKS_SCHEMA })

const red = (observed?.red ?? []).slice(0, MAX_PRS)
if (!red.length) {
  log('no red PRs — nothing to repair')
  return { triaged: [], repaired: [], escalated: [] }
}
log(`${red.length} red PR(s): ${red.map(r => `#${r.pr}`).join(', ')}`)

// Pipeline, not a barrier: PR #7 can be repaired while #9 is still being triaged.
const outcomes = await pipeline(
  red,

  // --- Triage: read the logs, classify, propose. Never edits. ---
  r => agent(
    `Triage the CI failure on PR #${r.pr}${r.epicId ? ` (epic ${r.epicId}, branch orch/${r.epicId})` : ''}.
     Get the logs: bash ${ORCH} state pull-checks --pr ${r.pr}
     Check out the PR branch and REPRODUCE the failure locally before you conclude anything —
     the log you were given is a truncated tail, and a fix proposed from reading alone is a guess.
     Follow the ci-triage agent's contract: classify, name the root cause in one sentence,
     propose the smallest fix. Escalate flake/infra/dependency/unknown, and anything whose fix
     would touch auth, billing, migrations, or CI configuration.`,
    { label: `triage:#${r.pr}`, phase: 'Triage', agentType: 'ci-triage', schema: TRIAGE_SCHEMA }),

  // --- Repair: only what triage said is fixable, and only on the epic branch ---
  async (t, r) => {
    if (!t) return { pr: r.pr, skipped: 'triage returned nothing' }
    if (t.escalate || NOT_FIXABLE.has(t.class)) {
      log(`#${r.pr}: ${t.class} — escalating, not patching (${t.rootCause})`)
      await agent(
        `PR #${r.pr} failed CI with class "${t.class}": ${t.rootCause}
         This class is NOT repairable by patching code. Record it and hand it to a human:
         bash ${ORCH} state push-status --id ${r.epicId ?? 'unknown'} --state Needs-review \\
           --note "CI ${t.class}: ${t.rootCause}"
         bash ${ORCH} state push-journal --kind ci_escalation --key ${t.class} \\
           --extra '{"pr":${r.pr}}'
         Then post ONE comment on the PR stating the class and the root cause. Change no code.`,
        { label: `escalate:#${r.pr}`, phase: 'Repair' })
      return { pr: r.pr, escalated: true, class: t.class, rootCause: t.rootCause }
    }

    let last = null
    for (let round = 1; round <= MAX_ROUNDS; round++) {
      last = await agent(
        `Repair PR #${r.pr} (branch orch/${r.epicId}), attempt ${round} of ${MAX_ROUNDS}.
         Diagnosis (class ${t.class}): ${t.rootCause}
         Proposed fix: ${t.fix ?? '(none given — derive the smallest one yourself)'}

         Apply ONLY that fix. Do not refactor, do not clean up surrounding code, do not add
         error handling for cases that cannot happen. Never weaken, skip or delete a test to
         make CI pass — if the test is genuinely wrong, say so and stop.
         You cannot edit .github/workflows/** or .gitlab-ci.yml; a hook blocks it. If the fix
         requires that, stop and report patched:false.

         Then: run the failing command locally until it passes, commit to orch/${r.epicId},
         push, and wait for the checks —
           bash ${ORCH} state pull-checks --pr ${r.pr}
         Poll with backoff up to ~10 minutes. Report the final status. "pending" means the
         checks had not finished; report it as pending rather than guessing green.`,
        { label: `repair:#${r.pr}:${round}`, phase: 'Repair', isolation: 'worktree', schema: REPAIR_SCHEMA })
      if (last?.status === 'green') break
      if (!last?.patched) break        // it could not apply the fix — a second try won't help
      log(`#${r.pr}: attempt ${round} left CI ${last?.status ?? 'unknown'}`)
    }

    const fixed = last?.status === 'green'
    await agent(
      `Record the outcome for PR #${r.pr}, exactly:
       bash ${ORCH} state push-journal --kind ci_repair --key ${t.class} \\
         --extra '{"pr":${r.pr},"corrected":${fixed},"rounds":${MAX_ROUNDS}}'
       ${fixed ? '' : `bash ${ORCH} state push-status --id ${r.epicId ?? 'unknown'} --state Changes-requested --note "CI still red after ${MAX_ROUNDS} repair attempts: ${t.rootCause}"`}`,
      { label: `record:#${r.pr}`, phase: 'Repair' })

    return { pr: r.pr, class: t.class, rootCause: t.rootCause, fixed, status: last?.status ?? 'unknown' }
  },
)

const done = outcomes.filter(Boolean)
const repaired = done.filter(o => o.fixed)
const escalated = done.filter(o => o.escalated)
const stuck = done.filter(o => !o.fixed && !o.escalated)

log(`repaired ${repaired.length}, escalated ${escalated.length}, still red ${stuck.length}`)
return { repaired, escalated, stuck }
