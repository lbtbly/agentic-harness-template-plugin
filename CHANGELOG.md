# Changelog

All notable changes to the harness marketplace. Format: Keep a Changelog; versions are
the marketplace `metadata.version` (per-plugin versions in each plugin.json).

## [1.10.0] — 2026-07-28
### Added
- **Per-project Slack notifications** — `orchestrator/adapters/notify-slack.sh`. One
  channel per repo (`cchar-<repo>`, derived from the git toplevel, slugified to Slack's
  rules and created on first use), posted at four milestones: wave admitted, epic landed,
  epic escalated, run finished with its `stopped_by` reason. Configured by a single
  `SLACK_BOT_TOKEN` (scopes `chat:write`, `chat:write.public`, `channels:manage`,
  `channels:read`), read from the environment or **parsed** — never sourced — out of a
  local env file.
  - **A notification may never break a run.** No token, no network, a Slack error, a
    malformed reply: every path exits 0. Unconfigured is the normal case and is silent.
  - **It posts as a bot**, which is the point. Investigated first: the claude.ai Slack
    connector posts with the *user's* token, so agent and human are one identity, and it
    is unreachable from a headless run anyway — connectors are not loaded when
    `CLAUDE_CODE_OAUTH_TOKEN` is the auth lane, and `--strict-mcp-config` excludes them.
  - **The agent cannot read the token**: `SLACK_BOT_TOKEN` joins the model and delivery
    credentials denied to tool subprocesses. The driver invokes the adapter outside the
    model's tool surface, so denying it costs nothing and closes an exfiltration path.
  - `slack.com` is documented in `egress-allowlist.txt` but ships **commented** — same
    posture as the board backends, since every entry widens the blast radius. The adapter
    names the allowlist explicitly when a call gets no response, because a fail-closed
    sandbox is otherwise indistinguishable from "nothing happened".
  - New `test-notify-slack.sh` (27 assertions), including that the token is never echoed
    on a failure path and that the slug clamps to 80 chars without truncating the prefix.
- This repo now carries the secret-ignoring rules it scaffolds into every project it
  initializes — it had none, and the token would have been one `git add -A` from
  publication.

## [1.9.0] — 2026-07-28
### Fixed
- **The run-to-completion build is no longer invisible.** Reported from use: launching
  `/orchestrator:run` hands the build to a shell loop, and there was no way to see what
  it was doing. The cause was two discards — `build_wave` ended in
  `--output-format json >/dev/null 2>&1` and the call site redirected again — which
  also threw away the **reason** a wave failed, so escalations arrived undiagnosable.
  The engine now streams to `.orch/logs/run-<date>.jsonl` with stderr beside it, a
  failed wave prints its exit code and the tail of its stderr, and `verify_epic` keeps
  its stderr while its stdout stays parseable JSON. Logs are appended rather than piped
  so the wave's exit code survives, and the log dir self-ignores — the CI runtimes
  force-add `.orch` to the `orch/state` branch, and machine-local logs must never
  become commits. `ORCH_STREAM=0` reverts to whole-run JSON, still logged, never
  discarded.

### Added
- **`/orchestrator:watch`** — a live agent tree for a running build, plus
  `orchestrator/bin/watch` (`--replay`, `--errors`, `--date`). Indentation is the tree:
  child lines are matched to their parent on `parent_tool_use_id`, so you see which
  subagent called which tool, what failed, and what the run cost. Streaming requests
  `--forward-subagent-text` (CLI v2.1.211+) but **probes** for it first — passing an
  unknown flag would have failed every wave on an older CLI — and degrades to a flat
  stream instead. New `test-run-observability.sh` (26 assertions) pins the regression
  and renders a synthetic stream end-to-end.
- Both the `run` skill and the plugin README now state plainly that a headless run has
  no interactive channel: a subagent cannot ask a question mid-run, so uncertainty
  fails closed to `Needs-review`/`Blocked` with a note and is answered on the PR.

## [1.8.0] — 2026-07-27
### Added
- **`local` runtime — the nightly loop on the operator's own machine** (ADR-0033). All
  three shipped runtimes were remote, so a solo operator picked `github-actions` by
  elimination and inherited three secrets, CI minutes and a plugin-fetch step that exist
  only because the work moved off the machine. `local` schedules
  `orchestrator/runtime/local-run.sh` from launchd / systemd / cron and uses the `claude`
  and `gh` already logged in: **zero secrets** (`CLAUDE_CODE_OAUTH_TOKEN`, `GH_TOKEN` and
  `ORCH_PLUGIN_REPO_TOKEN` are all skipped by construction), zero CI minutes, no cloud
  dependency. The wrapper adds a single-instance lock, a scheduler-proof `PATH` (launchd
  and cron source no profile), run logs under `.orch/logs/`, and refuses to start unless
  the OS sandbox is **fail-closed** — on your own machine there is no devcontainer as an
  outer wall, so `sandbox.failIfUnavailable` must be `true`. The container lane stays
  opt-in. New `runtime/local.md` (launchd plist, systemd timer, cron, wake scheduling,
  the awake-machine caveat) and `test-local-runtime.sh` (23 assertions, including a live
  exercise of the fail-closed refusal).

### Changed
- **Branch protection is now three-state and machine-readable** (ADR-0032). Reported from
  a real first install: on a **private repo on a free GitHub plan** neither branch
  protection nor rulesets exist — both APIs answer `403 "Upgrade to GitHub Pro or make
  this repository public"` — and no token shape is branch-scopable. The precondition was
  binary, so the skill could only stop; it re-derived the same argument on every
  invocation, recommended making the repository **public**, and left the decision as prose
  in three documents (including the line-budgeted `CLAUDE.md`, billed every session).
  `risk-policy.json` gains `forgeProtection`: `required` (default, unchanged behavior) or
  `unavailable-accepted`, which **force-disables auto-merge in `may_automerge()`** — every
  merge stays human, and editing `autoMergeRiskLevels` cannot re-arm it. Enablement now
  distinguishes protected / absent-but-settable (`404`) / unsatisfiable (`403`), records
  the answer in that one field, and no longer proposes publishing a private repo.
  Run-to-completion under acceptance completes to **PRs, never to `main`** — stated where
  the mode is documented. New `test-forge-protection.sh` (17 assertions).
- **The per-night token cap is asked per auth lane, not unconditionally.** It is a cost
  control on the metered lane; on a subscription the binding constraint is the usage
  limit, which `run-with-limits.sh` already handles by checkpointing and resuming. On
  `local`, `ORCH_MAX_EPICS` defaults to **2** — one machine, shared with your own work.
- `/orchestrator:disable-orchestrator` removes OS scheduler entries too. launchd agents
  and systemd timers live **outside the repo** and survive any amount of file deletion.

### Decided
- [ADR-0032 — Forge branch protection: required, or explicitly accepted as unavailable](docs/adr/0032-forge-protection-graduated.md)
- [ADR-0033 — `local` runtime: the nightly loop on the operator's own machine](docs/adr/0033-local-runtime.md)

## [1.7.0] — 2026-07-27
### Changed
- **Version alignment.** Every plugin (core, orchestrator, workbench, formatting, ci) and
  the marketplace now report **1.7.0** — a one-time sync that forces an update-cache
  refresh for all installed copies. No content changes beyond 1.6.0. First tagged release
  since v1.4.2 (`v1.7.0`).

## [1.6.0] — 2026-07-27
### Added
- **Third-party design plugins for UI projects** (ADR-0031). `/core:new-project` gains a
  **UI surface?** question; `web UI` projects get `templates/settings-design.json`
  deep-merged (additive jq merge) into `.claude/settings.json`, declaring two external
  plugins with `autoUpdate: true`: **impeccable** (`pbakaus/impeccable` — anti-slop
  detector hooks after every UI edit + Stop deep pass, `/impeccable` with 23 commands)
  and **styles-library** (`lbtbly/styles-library`, private — style-picker visual
  direction briefs). Claude Code prompts installs on repo trust and refreshes both in
  the background. The scaffolder also appends impeccable's marker-wrapped gitignore
  block (`templates/gitignore-impeccable`), pins `node = "22"` when runtime pinning is
  on (the hooks need Node ≥ 22), chains the workflow (style-picker direction →
  `/impeccable init` → hooks enforce), and bakes a CLAUDE.md rule: `/impeccable audit`
  before a UI feature is done, `/impeccable polish` before shipping. Upgrade mode offers
  the same block additively to existing scaffolds. Neither plugin is vendored or added
  to the marketplace (still 5 entries); no orchestrator DoD wiring (deferred).

## [1.5.3] — 2026-07-27
### Added
- **Notion gets a real hierarchy** (ADR-0030). Reported from use: the board was flat — no
  initiative, no parent, no type marker, all three living only inside the record JSON, so
  initiatives were invisible in Notion and a task was pushed as a flat sibling of its epic.
  Now: a `Type` select (Epic/Task) — the parallel of Jira's and Linear's `orch-epic`/`orch-child`
  labels, which Notion alone lacked; a `Parent epic` **self-relation** whose synced `Sub-tasks`
  inverse Notion maintains itself; and a **separate Initiatives data source**, making the
  initiative a real page with its own board and state rather than a string. Notion joins Jira and
  Linear at `hierarchy: native`.
- The adapter moves to the current Notion API (`2026-03-11`) and the **data-source** model,
  matching the MCP lane. This was forced, not optional: since `2025-09-03` relation writes may
  only use `data_source_id` — `database_id` is rejected.
- New `test-pm-notion.sh` (49 assertions) against a scripted Notion double, weighted toward the
  degradation paths, since every existing board has none of the new properties.

### Changed
- **Every relation feature is optional and detected, never assumed.** A board without `Type`,
  without `Parent epic`, or without an Initiatives source keeps working exactly as before with
  that part of the hierarchy in the payload only; `health` names what is missing and
  `capabilities.hierarchy` reports `derived` instead of `native`. A legacy `databaseId` config
  still resolves its data source, with a warning to record the new id.
- Native values now win over the payload: a parent or initiative a human set in Notion overrides
  a stale value the harness wrote earlier (ADR-0027). A missing one warns and continues, and the
  relation is *omitted* rather than written as `[]` — clearing a human's link would be worse.

## [1.5.2] — 2026-07-27
### Added
- **`BOARD_SETUP.html`** — a step-by-step provisioning guide for Notion, Jira and Linear,
  linked from START_HERE. Exact menu paths, the properties and states to create, which kind of
  token to make, the three commands that prove it works, and a symptom→cause→fix table. UI
  paths were researched against vendor documentation rather than recalled. New
  `test-board-guide.sh` pins the factual claims against the adapters — env var names, config
  keys, the sample `stateMap`, the egress hosts — so the guide cannot rot silently.

### Fixed
- **The Linear `stateMap` example targeted a state that does not exist.** A new Linear team
  ships with `Backlog · Todo · In Progress · Done · Canceled` — there is **no "In Review"** —
  so the map shipped in 1.5.1 would have failed `health` on a stock team and silently fallen
  back to labels for `Needs-review` and `Changes-requested`. The default map now targets only
  stock states, with adding *In Review* offered as a deliberate improvement.
- Two wrong Linear settings paths: workflow states are at **Settings → Teams → *team* → Issue
  statuses**, and personal keys at **Settings → Account → Security & Access**.

## [1.5.1] — 2026-07-27
### Added
- **Linear is implemented** (ADR-0029) — the last stub with a real model behind it.
  Epics are Issues, records carrying a parent become **sub-issues** via `parentId`, and the
  initiative tier is a Linear **Project**: the hierarchy is read from the board rather than
  synthesized, so `capabilities.hierarchy` is `native`. Lifecycle state maps onto real
  workflow states via `linear.stateMap`, the exact parallel of Jira's `statusMap` — but a
  Linear workflow is not a transition graph, so `stateId` is set directly and the riskiest
  part of the Jira adapter simply does not exist here. Projects are never created
  implicitly. `health` validates the map against the team's real states. Every field, type,
  query and filter key was checked against Linear's published schema before use.
  New `/core:board-setup` Linear lane and a 58-assertion suite against a GraphQL double.

### Fixed
- **No board host was in the egress allowlist.** A remote backend pushes state from inside
  the sandbox, so a Notion or Jira install's `orch state push-*` calls would fail closed
  mid-run — reading as the loop mysteriously losing its state. Board hosts are now
  documented (commented, opt-in) and `/orchestrator:enable-orchestrator` verifies the
  configured backend's host before enabling the loop. Pre-existing; found while adding Linear.
- **The initiative rollup grouped children as initiatives.** In all five adapters and the
  `none` backend, a sub-issue with no `initiative` field conjured an "unassigned" initiative
  that exists on nobody's board. A child belongs to its parent epic, not directly to an
  initiative.
- `orchestrator/README.md` still called Jira, Notion and Linear "contract stubs".

## [1.5.0] — 2026-07-27
### Added
- **The harness can now see why CI is red, and repair it** (ADR-0024). New
  `orch state pull-checks` returns `red | pending | green | none` per PR plus the failing
  job's log excerpt — the first code in this framework that reads a CI log. New `fix-ci`
  workflow triages from those logs and repairs the mechanical failures, bounded per PR;
  `flake`/`infra`/`dependency`/`unknown` escalate to a human instead of being retried
  until they pass. New `ci-triage` agent diagnoses but never edits. `actions: read` on the
  runtime workflow and read-only `gh run`/`gh pr checks` in the unattended allowlist —
  `gh pr merge` stays denied, so observation grants no landing power. Both loops now wait
  for checks after pushing a PR instead of reading them the next morning. This repo runs a
  failure-triage job on its own CI.
- **Standing goals** (ADR-0028). A merged epic's acceptance criteria graduate into shell
  predicates re-verified daily by `verify-goals.sh`; `passes:true` was terminal and nothing ever
  looked again, so a regression stayed invisible until a human tripped over it. Detects only —
  a violation goes through the normal pipeline. A predicate that times out is a violation, not a
  skip. New `/orchestrator:goals` and `/orchestrator:compost` (weekly: reads the journal, trust
  and goal ledgers, proposes at most three framework fixes — which finally makes kickoff's
  "skipped proposals are dropped, not remembered" untrue).
- **The board is the golden source** (ADR-0027). `list-epics` gains `--initiative`/`--parent`/
  `--level` and a new `list-initiatives`, all optional so the un-flagged call is byte-for-byte
  unchanged and the drivers were not touched. Every backend answers at whatever fidelity it has —
  Jira natively, the rest derived from the record payload, synthesized where the board is flat —
  and `capabilities` reports which. Human-authored cards are now read on all four backends
  instead of two. `claim`/`release`/`list-claimable` give cards an **expiring lease**, so two
  agents never take the same work and a crashed agent's card returns to the pool.
- **`/core:doctor`** — reports what the harness itself costs you per turn (CLAUDE.md size, hook
  injections, skill sizes, MCP schemas) and what to cut, ranked. Read-only, and it refuses to
  propose cutting a security rule to save tokens.
- Official autonomous-lane prompt language (anti-gold-plating, grounded progress claims, the
  don't-stop-early reminder) added verbatim to the worker and verifier prompts; a blindspot pass
  before the DoD is authored; an anti-AI-writing rubric for `docs-writer`.
- **Graduated autonomy** (ADR-0026). Auto-merge now requires risk-allows **and** the epic's
  class having earned tier `auto` in `.orch/trust.tsv` — ≥20 runs at ≥95% verified pass, tracked
  per `<footprint-root>/<complexity>`. Slow to grant, fast to revoke: the tier is recomputed
  every run and demotion is announced on stderr. A fresh install has no ledger, so nothing
  auto-merges until a class has a record — the safe default now requires no configuration.
- **Findings can be carried back to the framework** (ADR-0025). `/core:export-journal` +
  `orchestrator/bin/journal-export` produce a redacted bundle: redaction is an ALLOWLIST, so a
  field added to the journal later cannot leak by default, and the exporter verifies its own
  output and **refuses to write** if a `$HOME` fragment, absolute path, `@` or URL survives.
  The repo is a salted local hash — stable across exports so batches join, not reversible to a
  path. No network, no transport, no upstream identity: it writes a file and moving it is your
  call. `/ingest-findings` on the marketplace side ranks by how many distinct repos hit a thing.
- **An append-only journal of the harness's own mistakes** (ADR-0023).
  `.orch/journal/<date>.jsonl`, written by hooks rather than by the agent: all six
  guard-block sites, failing Bash commands, human corrections, subagent failures, formatter
  rewrites, model escalations and integration reverts. It records classifications, never
  content — the verb of a failed command, not the command line; the shape of a correction,
  not your words. Advisory, never blocking, and refusable via `{"journal": false}`.

### Fixed
- **CI status was wrong in two ways.** `PENDING`/`QUEUED`/`IN_PROGRESS` counted as green, so
  a PR whose checks had not started read as merge-eligible; and `select(.signal != null)`
  dropped every PR without an operator comment, so a red build nobody had commented on was
  invisible. GitLab had no CI signal at all (`green` was hardcoded null) — it now reports the
  real pipeline status.
- **The nightly integrated on the builder's own word.** `dod-verify` ran only in the
  run-to-completion driver; the nightly filtered on the builder's self-reported `done`, so
  "no self-grading anywhere" was true of one flavour and false of the other. It now verifies
  independently before integrating, and a builder overclaim is journalled.
- **One malformed issue made a whole board unreadable.** `JSON.parse` on the issue-body fence was
  unguarded in the GitHub and GitLab listers, so a single bad payload threw and killed the entire
  listing. Both now skip the item with a warning — which required defining `warn()`, which
  neither adapter had despite the other two using it.
- **`push-status` dropped `--pr` and `--assignee` on GitHub and GitLab** (Jira and Notion honoured
  them), and their `pull-status` omitted `pr` entirely. `assignee` is now load-bearing: it
  carries the claim.
- **Every distribution URL pointed at the wrong org.** The marketplace install command, all five
  plugin manifests' `homepage`/`repository`, the scaffolder's install snippet and the ADR template
  all said `lambertstudi/…`; the repo lives at `lbtbly/…`. The hygiene guard that was supposed to
  catch a hardcoded forge URL named that one org, so it stopped guarding anything the moment the
  repo moved — it is now org-agnostic.
- **The journal wrote into the current directory** when `CLAUDE_PROJECT_DIR` was unset — it now
  resolves a real project root (env, then git toplevel) and writes nothing without one. Caught by
  the framework's own tests polluting `tests/.orch/`.
- **`bin/orch` delegated local-only ops to the board adapter.** On any remote backend
  `import`, `push-suggestion`, `pull-suggestions` and `triage-suggestion` reached an adapter
  that threw `unknown op` and exited 1 — the whole suggestion lifecycle worked on
  `backend: none` alone, while `/core:triage-suggestions` claimed otherwise.
- **The run-to-completion driver did not run on stock macOS.** `/bin/bash` there is
  3.2.57; `declare -A` is bash 4+ and a bare `"${arr[@]}"` on an empty array is an
  unbound-variable error under `set -u` before bash 4.4. `run_loop` exited 1 with empty
  output and `run-with-limits.sh` died before invoking `claude` — 11 test assertions were
  failing on a platform the README claims to support. Both files are now bash-3.2 clean, and
  `test-repo-hygiene.sh` fails the build if either construct reappears in a shipped
  `set -u` script.
- **The loop's documented behaviour was largely dead code.** `partition_wave` and the usage
  throttle (`usage_pct`/`throttled_cap`) were defined and unit-tested but never called by
  `run_loop`; `guard_thrash` was unreachable (both branches set `advanced=1`); the budget
  guard was inert because `spent_tokens()` returned a literal `0`; `build_wave` re-ran the
  entire nightly wave once per pending epic; `epic.deps[]` was authored by the planner and
  read by nothing. All now wired: admission is dependency-topological, then
  footprint-disjoint, then capped by the throttle, and the wave is built exactly once per
  round. A dependency cycle stops with `stopped_by:"DEPS"`; a paused throttle with
  `"USAGE"`; a wave that returns no usable verdict with `"THRASH"`. `spent_tokens` now
  reports `-1` for unknown and the loop warns loudly when a budget cap has no spend signal
  rather than pretending to be guarded.
- **A killed run lost its progress.** Loop state lived only in bash locals. It is now
  reconstructed from the board on entry, and per-epic attempt counts persist through the
  same `attempts=<n>` note convention the nightly workflow already writes.
- **A reverted merge was reported as escalated.** `merge_epic` returns `reverted` when the
  post-merge suite goes red; the loop swallowed it into `escalated`, so a red merge looked
  like it was waiting for review. It now consumes a round and re-queues as rework.
- **Auto-merged epics never left the machine.** `merge_epic` moved local `main` and nothing
  pushed. The local merge is now framed as the run-local integration proof, and a new
  `publish_epic` requests the landing through the forge with `--auto` so branch protection,
  required checks and CODEOWNERS stay the enforcer (ADR-0015). `gh pr merge` is still absent
  from the builder allowlist and a direct `main` push is still denied.


## [1.4.1] — 2026-07-17
### Fixed
- CI's first run caught three real bugs: 7 skill frontmatters were unparseable
  (unquoted colons from the 1.4.0 description rewrites — they loaded with EMPTY
  metadata at runtime, silently dropping disable-model-invocation); the
  parallel-merge test lacked git identity on CI runners; the START_HERE embed
  payload was platform-dependent (unsorted walk order). New frontmatter-lint
  suite prevents the first class permanently.

## [1.4.0] — 2026-07-17
### Security
- Guard hooks FAIL CLOSED when jq is missing (they silently disabled themselves);
  explicit timeouts on every hook (guards 10s vs the 600s default); sandbox
  credential walls + egress allowlist parity (native sandbox ↔ devcontainer
  firewall, single source); pinned MCP server list for unattended runs.
### Added
- LICENSE (MIT); CI on the marketplace itself (tests, plugin validate, embed
  drift, version discipline); CONTRIBUTING release policy; manifest discovery
  metadata + core dependency declarations; keychain-backed userConfig
  (board_token, plugin_repo_url); policy-gated Stop gate (default OFF); model
  ladder externalized to models.config.json; verdict.schema.json for
  schema-validated headless verify; argument-hints + listing-budget skill
  descriptions; forked read-only doc-health/codemap.
### Fixed
- Personal path scrubbed from a shipped template; authenticated parameterized
  runner clone (private marketplaces); six stale references; refactorer agent
  least-privilege tools; ADR-0016 decorrelation wording corrected.

## [1.3.0] — 2026-07-17
### Added
- Market-audit remediation: ADR-0022 (Claude-Code-native by design), upgrade mode in
  new-project, review→rule capture in kickoff, `disable-model-invocation` on all
  side-effectful skills.
### Fixed
- README test-count freshness.

## [1.2.0] — 2026-07-17
### Added
- Lecture-audit round: day-0 test harness scaffolding, verifier-owned `evidence` on the
  feature contract, per-phase run metrics + VCR in the digest, clean-exit checklist in
  handoff, rule `since:/expires:` metadata + doc-health instruction audit.

## [1.1.0] — 2026-07-16
### Added
- Native Jira semantics (ADR-0021): Epic issue type, parent links, statusMap
  transitions with label fallback; board-setup MCP-first lane; assignee + complexity
  on board cards; per-day report folders with screenshots; terracotta digest palette.

## [1.0.0] — 2026-07-16
### Added
- Initial marketplace: core / formatting / orchestrator / ci / workbench; DoD contract
  + independent verifier; planner; run-to-completion driver + guards; risk-gated
  auto-merge + safety wiring; field-test protocol.
