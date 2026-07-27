# Changelog

All notable changes to the harness marketplace. Format: Keep a Changelog; versions are
the marketplace `metadata.version` (per-plugin versions in each plugin.json).

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
