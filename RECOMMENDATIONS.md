# RECOMMENDATIONS — market audit, 2026-07-17

Audit of this marketplace against the July 2026 state of the art: official Claude Code
docs (code.claude.com/docs), Anthropic engineering posts on long-running-agent
harnesses, and community/power-user practice (Superpowers, HumanLayer, Ralph loops,
awesome-claude-code, security research). Complements `AUDIT.md` (2026-07-17 rubric
audit + remediation addendum); items already closed there are **not** repeated.
All evidence re-verified against `c372ad2` (post-remediation-round HEAD, 2026-07-17).

## How to implement this file (instructions for the Claude Code session)

- Work top-down: P0 → P1 → P2. One item per commit (Conventional Commits), referencing
  the item ID (e.g. `fix(hooks): guards fail closed without jq (R6)`).
- Every item lands **with its acceptance criteria satisfied**, including the test
  assertions it names. Run `bash tests/run-tests.sh` before and after each item.
- Items cite Claude Code fields/flags/versions as reported by the docs on 2026-07-17.
  **Before implementing any item that depends on a specific flag, field, or version,
  fetch and verify the cited page under `https://code.claude.com/docs/en/`** — the CLI
  ships near-daily; do not trust this file over the live docs.
- Do **not** implement anything in the "Product decisions" section without explicit
  owner sign-off. Those items include doc-only sub-tasks that ARE safe to do; they are
  marked as such.
- Do not "fix" anything listed in "Already at or above market" — those are deliberate
  and verified conformant.

## Already at or above market — do not touch

- **Skills-only surface (no `commands/`)**: matches current guidance (`commands/*.md`
  is legacy; "use skills/ for new plugins"). Layout `skills/<name>/SKILL.md`,
  `agents/*.md`, `hooks/hooks.json`, `${CLAUDE_PLUGIN_ROOT}` everywhere — all standard.
- **`disable-model-invocation: true` on all 9 side-effectful skills**, test-enforced
  (`tests/test-plugin-manifests.sh:86-88`). Done in the AUDIT.md remediation round.
- **Scaffolded `CLAUDE.md` at 74 lines**, security-top, pointers not procedures —
  under the official ~200-line guidance and aligned with the community "short,
  human-written, progressive disclosure" consensus (HumanLayer, ETH agentfiles study).
- **`.claude/rules/` with `paths:`-scoped stack packs** — officially supported (see
  R-watch note in P2 about known `paths:` bugs).
- **DoD contract** (`feature_list.json`, JSON for tamper resistance, `passes:false`,
  only-flip-`passes`, browser E2E before flipping) — matches the canonical pattern from
  Anthropic's "Effective harnesses for long-running agents" (Nov 2025) almost clause
  for clause, including the "unacceptable to remove or edit" wording.
- **Fresh-context worker per epic, worktree isolation, external state in files/git,
  reconcile-from-reality on restart** — matches both Anthropic harness posts and the
  community consensus (Ralph doctrine: one item per loop, progress in files not context).
- **Gated-nightly default** (ADR-0018), **risk fails closed** (ADR-0017), **no
  self-elevation hooks**, **secrets: names never values**, **devcontainer egress
  firewall + native OS sandbox layering** (ADR-0020) — all current best practice.
- **Honest security docs**: ADR-0009 (Bash redirection hole) and SECURITY.md's caveat
  that `disableBypassPermissionsMode` only binds from managed settings. Keep this tone.

---

## P0 — correctness, distribution, legal

### R1 — Add the missing LICENSE file
- **Problem**: all 5 `plugins/*/.claude-plugin/plugin.json` declare `"license": "MIT"`
  and marketplace consumers rely on it, but there is no `LICENSE` file anywhere in the
  repo. Declared-but-absent license is a legal inconsistency and blocks any
  community-marketplace submission (review pipelines check SPDX consistency).
- **Change**: add `LICENSE` (MIT, copyright Lambert Bouley) at repo root.
- **Acceptance**: file exists; `tests/test-plugin-manifests.sh` gains an assertion:
  if any `plugin.json` declares `license`, `LICENSE` must exist at repo root.
- **Effort**: S. **Source**: SPDX field in plugin manifest schema
  (code.claude.com/docs/en/plugins-reference); community-marketplace review criteria.

### R2 — Version discipline exists in practice, not in policy
- **Problem**: the 2026-07-17 remediation round (commit `3ba350f`) bumped versions
  per-plugin (core → 1.3.0, orchestrator/workbench/ci → 1.1.0, marketplace → 1.3.0,
  formatting untouched at 1.0.0) — but earlier feature commits had shipped **without**
  bumps (e.g. ADR-0021's Jira changes landed while orchestrator sat at 1.0.0), and
  nothing prevents that from recurring: no written policy, no enforcement. Per current
  docs, when `version` is set it is the **update cache key** — an unbumped version can
  leave installed users on stale cached content after `plugin update`. Distribution
  bug, not cosmetics.
- **Change**: write the policy (per-plugin semver: any commit touching
  `plugins/<name>/` bumps that plugin; any release bumps `marketplace.json`
  `metadata.version`) into `CONTRIBUTING.md` (R17), and enforce it in CI (R8): diff
  changed paths since the last release tag vs version changes, fail on mismatch.
  Alternative (docs-supported): remove `version` keys entirely → version-by-git-SHA.
- **Acceptance**: policy written; CI job fails when a plugin dir changes without a
  version bump (fixture-tested or verified on a deliberate no-bump branch); release
  tags introduced (`v1.3.0` now).
- **Effort**: S/M. **Source**: code.claude.com/docs/en/plugins-reference (version as
  update cache key; omit to version by SHA); community pain: anthropics/claude-code
  issues #43763, #49410, #61954 (stale-cache update bugs — set versions deliberately).

### R3 — Personal-data leak in a shipped template
- **Problem**: `plugins/core/templates/docs/SUGGESTIONS.md:13` contains a real
  personal path — `/private/tmp/claude-502/-Users-lambertbouley-Documents-Tech-claude-code-template-env/…/commit-msg-2.txt`
  — embedding the username and an old machine path into **every scaffolded project**.
  Ironically it sits next to the comment explaining the hook was rewritten to record
  repo-relative paths to avoid exactly this.
- **Change**: rewrite the example entry with a synthetic repo-relative path
  (e.g. `apps/web/src/checkout.ts`); sweep for other personal strings.
- **Acceptance**: `grep -rn "lambertbouley\|/private/tmp\|claude-code-template-env" plugins/`
  returns nothing; add that grep as a test assertion (personal-string denylist).
- **Effort**: S. **Source**: the repo's own GDPR-minimization rationale
  (`plugins/core/hooks/growth-detection.sh`).

### R4 — Nightly CI clones a private repo unauthenticated
- **Problem**: `plugins/orchestrator/templates/orchestrator/runtime/github-actions.yml:58`
  does `git clone --depth 1 https://github.com/lbtbly/agentic-harness-template-plugin`.
  `docs/TEST-PROTOCOL.md` states this repo is **private** → the clone fails on a GitHub
  runner without credentials, so the scheduled nightly breaks at step one. The URL is
  also hardcoded (the GitLab template correctly parameterizes via
  `ORCH_PLUGIN_MARKETPLACE_URL`, set at enable time).
- **Change**: parameterize the repo (env var set by `/orchestrator:enable-orchestrator`,
  mirroring the GitLab lane) and authenticate — `actions/checkout` with `repository:` +
  `token:` (fine-grained PAT, contents:read), or fetch a released zip via
  `claude --plugin-url`. Document the required secret in the workflow header.
- **Acceptance**: no hardcoded `github.com/lbtbly/...` URL in any template
  (`grep -rn "lbtbly" plugins/` → nothing); enable-orchestrator SKILL.md asks for /
  writes the repo location; `tests/test-run-to-done.sh` (or a new assertion) covers the
  variable's presence in the workflow.
- **Effort**: M. **Source**: code.claude.com/docs/en/github-actions (`--plugin-url`,
  plugin install in CI); GitHub Actions private-checkout norms.

### R5 — Stale-reference sweep (five verified instances)
- **Problem** (each verified at the cited line):
  1. `plugins/core/templates/orchestrator/state.config.json` `$comment` says
     "last four are stubs" — false: `pm-jira.js` (372 L) and `pm-notion.js` (271 L) are
     fully implemented; only linear + trello are stubs.
  2. `plugins/core/templates/docs/TOOLING.md:53,60` cite
     `plugins/core/skills/new-project/templates/{runtime,devcontainer}/` — paths that
     don't exist (templates live at `plugins/core/templates/`); `TOOLING.md:44` still
     calls Layer 3 "`HANDOFF.md`" (it's the orch state layer; HANDOFF.md is fallback).
  3. `plugins/orchestrator/templates/orchestrator/runtime/gitlab-ci.yml:22` example URL
     still points at the pre-rename project `claude-code-template.git`.
  4. `docs/adr/0013-plugin-only-distribution.md` references ADR-0002 (5×) and
     ADR-0014 (`:32`), and `docs/adr/0015…md:26` references ADR-0014 — neither file
     exists (deliberately unported history), but nothing marks the references as
     external, and `tests/test-adr-refs.sh` structurally can't catch them (it only
     scans `plugins/`).
  5. `plugins/workbench/templates/docs/{TOOLING.md,SCHEDULED-AGENTS.md}` are drifted
     near-duplicates of the core copies.
- **Change**: fix 1–3 textually; for 4, annotate first mention per file
  ("ADR-0002/0014: historical, unported — see docs/adr/README.md") and extend
  `docs/adr/README.md`'s gap list; for 5, either delete the workbench copies (if core's
  are canonical) or add a sync test.
- **Acceptance**: extend `tests/test-adr-refs.sh` to also scan `docs/adr/` and fail on
  references to absent ADRs lacking the "historical" annotation; add a staleness grep
  test for `claude-code-template` and the wrong template paths; workbench/core doc pairs
  byte-identical or removed.
- **Effort**: S/M.

---

## P1 — market conformity, high value

### R6 — Security guards fail OPEN when `jq` is missing
- **Problem**: `plugins/core/hooks/secret-guard.sh:6-7` — if `jq` is absent,
  `TARGET` is empty and the script hits `[ -z "$TARGET" ] && exit 0`: the **secret
  guard silently disables itself**. Same construction in the other guards. All 13 hook
  scripts require `jq`, which is not bundled by Claude Code nor preinstalled on macOS.
  Community: undeclared jq dependency is a known plugin failure class
  (anthropics/claude-code #14817).
- **Change**: in the four security/policy guards (`secret-guard.sh`,
  `protect-paths.sh`, `protect-policy-paths.sh`, `block-no-verify.sh`) add a preflight:
  `command -v jq >/dev/null || { echo "guard cannot run: jq missing — blocking (install jq)" >&2; exit 2; }`
  → **fail closed**. Advisory hooks (growth-detection, notify, session-context,
  inject-session, precompact, handoff-reminder, format-on-edit) keep failing open but
  log once. Add a `jq`/`git` preflight to `/core:new-project` (step 0) and to
  `/orchestrator:enable-orchestrator`'s precondition gate.
- **Acceptance**: new test: run each guard with `PATH` stripped of jq; guards exit 2,
  advisory hooks exit 0. new-project SKILL.md documents the dependency check.
- **Effort**: S/M. **Source**: hooks exit-code semantics
  (code.claude.com/docs/en/hooks — only exit 2 blocks; exit 1 proceeds); fail-closed
  principle is the repo's own ADR-0017.

### R7 — No hook timeouts anywhere
- **Problem**: neither `plugins/core/hooks/hooks.json` nor
  `plugins/formatting/hooks/hooks.json` sets `timeout`; the documented default for
  command hooks is **600 s**. A hung guard (network-mounted FS, broken jq) stalls every
  single tool call for up to 10 minutes. PreToolUse guards run on `Read|Edit|Write|Bash`
  — the hottest path in the product.
- **Change**: set explicit per-hook `timeout` (seconds): guards 10; growth-detection 15;
  notify 10; session-context / inject-session 30; precompact-save-state 60;
  handoff-reminder 15; format-on-edit 60. Note in each script header that timeout ⇒
  non-blocking (fail-open) — acceptable for advisory hooks, and R6's preflight covers
  the guard-integrity case.
- **Acceptance**: `tests/test-plugin-manifests.sh` asserts every hook entry in every
  `hooks.json` carries a numeric `timeout`.
- **Effort**: S. **Source**: code.claude.com/docs/en/hooks (timeout defaults);
  community "hooks run in the hot path — keep PreToolUse to milliseconds" (HumanLayer).

### R8 — The marketplace repo has no CI on itself
- **Problem**: no `.github/` at repo root. Tests run only when someone remembers
  `bash tests/run-tests.sh`; `claude plugin validate` is never run; START_HERE.html can
  silently drift from the files it embeds. A marketplace that ships CI templates but
  runs none on itself is a credibility gap.
- **Change**: add `.github/workflows/ci.yml`: (1) `bash tests/run-tests.sh`;
  (2) `npm i -g @anthropic-ai/claude-code` then `claude plugin validate --strict` on
  each of the 5 plugins + the marketplace root; (3) optional: regenerate START_HERE via
  `tools/embed-files.py` and fail on diff.
- **Acceptance**: CI green on push/PR to main; a badge or note in README.
- **Effort**: S/M. **Source**: code.claude.com/docs/en/plugins-reference
  (`claude plugin validate --strict` recommended in CI).

### R9 — Enrich manifests for discovery and tooling
- **Problem**: `plugin.json` files carry only `name/description/version/author/license`;
  no `homepage`, `repository`, `keywords`, `$schema`. `marketplace.json` has no
  `$schema` and plugin entries have no `category`/`keywords`. Harmless today, but
  editor validation, marketplace browsers, and the community-marketplace pipeline all
  key on these.
- **Change**: add to each `plugin.json`: `$schema`
  (`https://json.schemastore.org/claude-code-plugin-manifest.json`), `repository`,
  `homepage`, `keywords` (e.g. core: `["scaffold","harness","hooks","dod"]`).
  Add `$schema` + per-entry `category`/`keywords` to `marketplace.json`. While there:
  shorten `core`'s ~380-char run-on description; the component inventory belongs in
  README, not the manifest.
- **Acceptance**: `claude plugin validate --strict` passes (ties into R8); fields
  present on all 5 + marketplace.
- **Effort**: S. **Source**: code.claude.com/docs/en/plugins-reference.

### R10 — Machine-enforce "install core first"
- **Problem**: orchestrator/formatting/workbench/ci depend on core (its hooks are the
  TCB the orchestrator settings reference via `$ORCH_CORE_HOOKS`; skills call
  `orch state`), but the dependency lives only in README prose and skill checks.
  The manifest schema now has a `dependencies` field.
- **Change**: add `"dependencies": [{"name": "core", "version": "~1.2.0"}]` (range per
  R2's chosen policy) to the four dependent plugins' `plugin.json`.
- **Acceptance**: `claude plugin validate --strict` accepts it; manual check: installing
  `orchestrator@harness` on a bare setup surfaces the core requirement; README keeps the
  human-readable install order.
- **Effort**: S. **Source**: code.claude.com/docs/en/plugins-reference (plugin
  `dependencies`; marketplace `allowCrossMarketplaceDependenciesOn`).

### R11 — Use plugin `userConfig` for tokens and notify settings
- **Problem**: board tokens (Jira/Notion lanes) and notification settings
  (`notify.config.json`: email, deliver_at) are collected by skills at setup time and
  parked in project files / env. The manifest now supports typed `userConfig` prompted
  at enable time, with `sensitive: true` values stored in the **OS keychain** and
  exported as `CLAUDE_PLUGIN_OPTION_<KEY>` — exactly this use case, and stronger than
  anything a project file can offer.
- **Change**: declare `userConfig` in `orchestrator/plugin.json` (and core if board
  setup stays there): `boardToken` (sensitive), `notifyEmail`, `deliverAt`,
  `pluginRepoUrl` (feeds R4). `board-setup`/`enable-orchestrator` SKILL.md read
  `CLAUDE_PLUGIN_OPTION_*` first, fall back to today's flow. Never write token values to
  disk (already the rule — this removes the temptation entirely).
- **Acceptance**: enable flow works with values pre-set via userConfig (manual test);
  skills document the precedence; grep test: no token names read from project JSON.
- **Effort**: M. **Source**: code.claude.com/docs/en/plugins-reference (`userConfig`,
  `sensitive`, keychain, `CLAUDE_PLUGIN_OPTION_*`; note: since v2.1.207
  `${user_config.*}` must not appear in shell-form hook commands — use the env vars).

### R12 — Harden the headless `claude -p` invocations
- **Problem**: `runtime/run-to-done.sh:106-109` and `runtime/run-with-limits.sh:59-62`
  call `claude -p "…" --settings … --output-format json` and nothing else. Missing,
  all now first-class: `--max-turns`, `--max-budget-usd` (native cost cap — today the
  budget guard is only the wrapper's token arithmetic), `--json-schema` for the
  dod-verify call (validated `structured_output` instead of "output only the verdict
  JSON" + `jq '.result // .'` guessing — the JSON schemas already exist in
  `workflows/dod-verify.js` as `JUDGE_SCHEMA`/`STAGE_SCHEMA`), `--strict-mcp-config`
  (don't inherit stray user MCP servers into an unattended run), `--session-id`
  (traceable per-epic/per-night transcripts), and `--bare` (recommended for scripted
  calls; slated to become the `-p` default — pair it with the explicit `--settings`).
- **Change**: extract the verdict schema to
  `orchestrator/templates/orchestrator/verdict.schema.json`; add the flags with env
  overrides (`ORCH_MAX_TURNS`, `ORCH_MAX_BUDGET_USD`); parse `structured_output` in
  run-to-done; keep the wrapper's throttle as the outer wall.
- **Acceptance**: `tests/test-run-to-done.sh` / `test-run-with-limits.sh` assert the
  flags and the schema file; verdict path covered by a fixture.
- **Effort**: M. **Source**: code.claude.com/docs/en/headless (flags,
  `structured_output`, `--bare` guidance).

### R13 — Modernize the unattended sandbox settings
- **Problem**: `settings.orchestrator.json` predates three sandbox capabilities:
  (1) `sandbox.network.allowedDomains` — today egress control exists **only** inside
  the devcontainer firewall; on a runner without the devcontainer the native sandbox
  runs with unrestricted egress (ADR-0020 calls the devcontainer the outer wall, but
  parity is now expressible in settings); (2) `sandbox.credentials.files/envVars` with
  `mode: deny|mask` (mask substitutes real secrets only at the TLS-terminating proxy,
  ≥v2.1.199) — a fourth, OS-level wall for `ANTHROPIC_API_KEY` and friends;
  (3) `enableAllProjectMcpServers: true` is broader than needed — the granular
  `enabledMcpjsonServers: ["playwright"]` exists.
- **Change**: add a `network.allowedDomains` list generated from the same allowlist as
  `init-firewall.sh` (single source: generate both from one list at enable time);
  add `credentials.envVars` deny/mask for the token names in `.env.example`; swap the
  MCP toggle for the explicit list.
- **Acceptance**: keys present and consistent with the firewall allowlist (test:
  parity check like the existing CODEOWNERS↔risk-policy test);
  `templates/docs/SECURITY.md` updated (4 walls).
- **Effort**: M. **Source**: code.claude.com/docs/en/sandboxing (network/credentials
  config); code.claude.com/docs/en/settings (`enabledMcpjsonServers`).

### R14 — Skill descriptions: trim the top four; add `argument-hint`
- **Problem**: skill descriptions land verbatim in the budget-constrained skill listing
  (combined description budget ≈1% of context; per-skill cap; community-documented
  silent drops when listings overflow — Superpowers' "skills not triggering"
  post-mortem). Four descriptions are 300+ chars of workflow narrative:
  kickoff 330, new-project 320, run 311, board-setup 306. Also: no skill declares
  `argument-hint`, though `/orchestrator:run` (scope) and `/core:spec` (topic) take
  arguments in prose.
- **Change**: rewrite the four to ≤200 chars, third person, "does X. Use when Y"
  shape (move the workflow narrative into the body — it's loaded on invocation
  anyway). Add `argument-hint: [scope]` to run, `[topic]` to spec (and `$ARGUMENTS`
  in their bodies where the prose says "the argument").
- **Acceptance**: test asserts every SKILL.md description ≤200 chars; run/spec carry
  `argument-hint`; invocation semantics unchanged (body carries what was cut).
- **Effort**: S. **Source**: platform skill-authoring best practices (third-person,
  what+when); code.claude.com/docs/en/skills (listing budget, `argument-hint`,
  `$ARGUMENTS`); blog.fsck.com (Jesse Vincent) on listing-budget drops.

### R15 — Make read-only skills mechanically read-only (and off-context)
- **Problem**: `doc-health` says "STRICTLY READ-ONLY" in prose only; `codemap` is
  read-mostly. Both run in the main context and pollute it with audit detail. Skills
  now support `context: fork` (run in a subagent) + `agent: Explore` and
  `disallowed-tools`.
- **Change**: `doc-health/SKILL.md`: add `context: fork`, `agent: Explore`,
  `disallowed-tools: Edit, Write`. `codemap`: add `context: fork` (it writes
  `docs/CODEMAP.md` at the end — keep Write; use `agent: general-purpose`).
- **Acceptance**: frontmatter present; one manual run each confirming the report/update
  still lands; body notes the fork behavior.
- **Effort**: S. **Source**: code.claude.com/docs/en/skills (`context: fork`, `agent`,
  `disallowed-tools`).

### R16 — `refactorer` agent inherits every tool
- **Problem**: `plugins/workbench/agents/refactorer.md` has no `tools:` field → the
  widest-write agent (mass mechanical edits, worktree, 60 turns) inherits ALL tools,
  including WebSearch/WebFetch and any MCP tools present. Every other agent in the
  marketplace is explicitly scoped.
- **Change**: add `tools: Read, Grep, Glob, Edit, Write, Bash`.
- **Acceptance**: frontmatter updated; `tests/test-plugin-manifests.sh` gains
  "every agent declares `tools:`".
- **Effort**: S. **Source**: code.claude.com/docs/en/sub-agents (least-privilege tool
  allowlists); the repo's own pattern in the other 10 agents.

---

## P2 — polish and hygiene

### R17 — CHANGELOG.md + release checklist at repo root
Dogfood the `changelog.d` fragment pattern the harness scaffolds into projects. Add
`CHANGELOG.md` (backfill from git tags/log: 1.0.0 → 1.2.0), plus a short
`CONTRIBUTING.md` with the release checklist (bump versions per R2, update CHANGELOG,
regenerate START_HERE, run tests + validate). Effort: S.

### R18 — State the platform support honestly
All hooks are bash+jq; statusline is bash+jq. Windows (non-WSL) is unsupported and
nothing says so. Add one line to README and to `new-project` preflight (R6): "macOS /
Linux / WSL2; native Windows unsupported (hooks are POSIX shell)". The community
long-term fix (rewrite hooks in Node for portability) is deliberately **not**
recommended now — document instead. Effort: S. Source: hooks `shell` field docs;
anthropics/claude-code #14817, #29321.

### R19 — Duplication sync tests
`policy-lib.sh` is duplicated core↔formatting (cross-plugin refs unsupported — fine),
and workbench duplicates two core template docs (R5.5). Add a byte-equality sync test
so drift fails CI instead of rotting silently. Effort: S.

### R20 — `paths:`-scoped rules: add a canary
Community reports open bugs on `paths:` rules (`paths:` ignored at user level #21858,
rules loading globally #16299, documented format broken vs `globs:` #17204). The stack
packs rely on `paths:`. Add to `docs/DEVIATIONS.md` a verification note + a manual
canary check in `/core:doc-health` ("stack rule loaded only in matching paths? y/n").
Do not switch to `globs:` unless the canary fails on current CC. Effort: S.

### R21 — CI runners: adopt the Setup-hook lane
`runtime/github-actions.yml` does ad-hoc install steps. Claude Code now has a `Setup`
hook event fired by `claude -p --init` / `--init-only`, designed for one-time CI prep.
Evaluate moving runner prep (plugin install, deps) into a Setup hook so local and CI
runs share one path. Effort: M (evaluate first). Source:
code.claude.com/docs/en/hooks (Setup event), /en/headless.

### R22 — Consolidate the PreToolUse guard chain (optional)
`Edit|Write` fires 3 guard scripts (secret-guard, protect-paths, protect-policy-paths)
= 3 process spawns per edit. A single dispatcher script sourcing the three checks would
cut spawn overhead ~3× on the hottest path. Only worth it if R7's timeouts reveal
real latency; measure first (`time` in tests). Effort: M.

---

## Product decisions — owner sign-off required (do NOT implement blindly)

### D1 — Stop-gate (AUDIT.md P0-3, still open)
The official best-practices ladder now explicitly names the deterministic **Stop-hook
gate** as a verification tier, and the runtime enforces a hard cap of **8 consecutive
Stop blocks** — which removes the infinite-loop risk that justified keeping
`handoff-reminder.sh` advisory-only. **Recommendation**: implement the policy-toggled
blocking mode (exit 2 / `decision:"block"` when `cleanState` shows failing build/tests
or debug artifacts), default **off** (advisory stays default; field-tested UX
preserved). Safe sub-task now: none — this is the decision itself.
Files if approved: `plugins/core/hooks/handoff-reminder.sh`, `.claude/policy.json` key
`stop_gate`, `tests/test-handoff-reminder.sh`. Source:
code.claude.com/docs/en/best-practices (verification ladder), /en/hooks (8-block cap,
`stop_hook_active`).

### D2 — Judge panel: correct the decorrelation claim; consider a single calibrated evaluator
Two facts against the current design (`workflows/dod-verify.js:11`,
`JUDGE_MODELS = {correctness:'opus', pm:'sonnet', design:'opus'}`; ADR-0016):
1. **Same-family judges correlate.** Research reported this year ("Nine Judges, Two
   Effective Votes", arXiv:2605.29800): correlated errors make N same-family judges
   worth ≈2 effective votes. The panel uses 2 models, 1 family — "decorrelated" as
   claimed by ADR-0016 is overstated; it decorrelates *lenses*, marginally *models*,
   not *families*.
2. **Anthropic's Mar 2026 harness post** ("Harness design for long-running application
   development") lands on ONE standalone evaluator, tuned skeptical, that interacts
   with the live app (Playwright) before scoring — arguing tuning a skeptical evaluator
   is far more tractable than panel aggregation. Its cost data also shows judging is
   cheap relative to building ($3-4 vs $37-71 per round) — so the panel isn't a cost
   problem; the question is efficacy and maintenance.
**Options**: (a) keep 3-lens panel, fix ADR-0016's claim, tune the shared skeptical
baseline; (b) collapse to one calibrated evaluator + keep the blocking-dissent
semantics; (c) keep panel and add an optional cross-family judge via a multi-model MCP
bridge (zen/pal-style) for `high` risk only — adds API keys + injection surface;
gate behind policy. **Safe sub-task now (doc-only)**: amend ADR-0016 wording
("distinct lenses, partially decorrelated models — same family; full decorrelation
requires cross-family judges") + cite the paper in `docs/DEVIATIONS.md` §1.

### D3 — Workflow runtime: spike a Claude Agent SDK port
`workflows/*.js` (orchestrator: 3, workbench: 3) are an **invented surface**: JS-shaped
specs using globals that exist nowhere (`agent()`, `parallel()`, `phase()`, `budget`…),
executed by prompting `claude -p "Run the nightly-orchestrator workflow…"` to interpret
the file. It works, it's tested at the contract level, and ADR-0008 made runtimes
pluggable — but it is semantics-by-convention: nothing guarantees the model's
interpretation of `parallel()` or `budget` tomorrow. The official recommendation for
production autonomous loops is the **Claude Agent SDK** (TS/Python), which gives real
`query()` loops, hooks, session forking, checkpointing, structured outputs — i.e. the
exact primitives these files pantomime. Constraint to respect: ADR-0019's
subscription-token auth lane (verify SDK auth compatibility during the spike).
**Recommendation**: spike-port `dod-verify.js` (the smallest, purest workflow) to a
real SDK script invoked by `run-to-done.sh`; measure fidelity/cost; decide on the rest
after. **Safe sub-task now (doc-only)**: note in `plugins/orchestrator/README.md` that
workflows are prompt-interpreted specs, not executed JS — today a reader cannot tell.
Source: code.claude.com/docs/en/agent-sdk/overview; anthropics/cwc-long-running-agents.

### D4 — Model ladder: externalize + evaluate `fable` for the overnight lane
Model choices are hardcoded aliases across `nightly-orchestrator.js:120-121,206-210,345`
and agent frontmatter. Aliases are the right default (they track model releases —
today `opus`→Opus 4.8, `sonnet`→Sonnet 5), but: (1) the ladder should be **config**,
not code — an enable-time map in `orchestrator/` config consumed by the workflow;
(2) **Claude Fable 5** (`fable` alias, requires CC ≥2.1.170) is positioned precisely
for long-horizon autonomous work — the overnight builder lane and the rework-escalation
lane are the natural fit; (3) `[1m]` context variants may fit the Integrate phase.
Pricing and availability move fast — evaluate on your subscription before defaulting.
**Safe sub-task now**: externalize the model map to config with current values
unchanged (pure refactor, test-covered). Decision: whether/where fable becomes default.
Source: code.claude.com/docs/en/model-config; anthropic.com/news/claude-fable-5-mythos-5.

### D5 — AGENTS.md: keep ADR-0022, sharpen its revisit triggers
ADR-0022 (accepted 2026-07-17) deliberately rejects AGENTS.md; the reasoning
(enforcement layer is CC-only; portable prose without portable gates is a worse
failure mode) is sound and this audit does **not** reopen it. Two facts belong in the
ADR's revisit clause, though: (1) the official docs now document the `@AGENTS.md`
import bridge as the sanctioned interop pattern — near-zero-cost if ever needed;
(2) community trackers claim CC gained native AGENTS.md *fallback* reading in spring
2026 (unverified — check the official changelog when revisiting). **Safe sub-task now
(doc-only)**: append both triggers to ADR-0022's "Revisit when" clause.
Source: code.claude.com/docs/en/memory (@imports, AGENTS.md bridge).

---

## Sources

Official (fetch live before implementing — near-daily releases):
- https://code.claude.com/docs/en/plugins — plugin structure, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`
- https://code.claude.com/docs/en/plugins-reference — plugin.json/marketplace.json schemas, `userConfig`, `dependencies`, `validate --strict`, version-as-cache-key
- https://code.claude.com/docs/en/skills — frontmatter (`context: fork`, `agent`, `disallowed-tools`, `argument-hint`), listing budget
- https://code.claude.com/docs/en/hooks + /en/hooks-guide — events, timeout defaults, exit-code semantics, Stop 8-block cap, Setup event
- https://code.claude.com/docs/en/sub-agents — agent frontmatter (incl. `memory`, `skills`, `isolation`, `maxTurns`, `background` — all used here and confirmed supported)
- https://code.claude.com/docs/en/settings · /en/permissions · /en/memory — settings schema, rules dir, @imports
- https://code.claude.com/docs/en/sandboxing · /en/sandbox-environments · /en/devcontainer — native sandbox network/credentials config
- https://code.claude.com/docs/en/headless · /en/agent-sdk/overview — `-p` flags, `--json-schema`, `--bare`, SDK positioning
- https://code.claude.com/docs/en/best-practices — verification ladder, CLAUDE.md guidance
- https://code.claude.com/docs/en/github-actions · /en/gitlab-ci-cd — claude-code-action v1, CI patterns
- https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents (Nov 2025) — feature_list.json / passes:false origin
- https://www.anthropic.com/engineering/harness-design-long-running-apps (Mar 2026) — planner/generator/evaluator, skeptical evaluator, cost tables

Community / research (as reported 2026-07-17):
- https://blog.fsck.com/2025/12/17/claude-code-skills-not-triggering/ — skill-listing budget drops (Jesse Vincent)
- https://www.humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents · /writing-a-good-claude-md · /context-efficient-backpressure — harness engineering, CLAUDE.md minimalism, Stop-hook backpressure
- https://ghuntley.com/ralph/ — fresh-context loop doctrine
- arXiv:2605.29800 ("Nine Judges, Two Effective Votes") — judge-panel correlation
- arXiv:2602.11988 (ETH Zurich agentfiles study) — context-file length/efficacy
- anthropics/claude-code issues #14817 (jq), #24846 (.env deny bypass), #43763/#49410/#61954 (plugin update cache), #17204/#16299/#21858 (rules `paths:`)
- https://snyk.io/blog/toxicskills-malicious-ai-agent-skills-clawhub/ — skill supply-chain risk (context for marketplace posture)
