# orchestrator/ — state layer + (optional) nightly loop

Two things live here, with **different lifecycles**:

1. **The state layer** (`bin/orch`, `adapters/`, `state.config.json`) — installed by
   `/core:new-project`, used every day by `/core:handoff`, `/core:spec`, `/core:doc-health` and the
   session hooks. It exists whether or not the orchestrator loop is enabled.
2. **The nightly loop** (`deploy.sh`, `settings.orchestrator.json`,
   `risk-policy.json`, `notify.config.json`, `runtime/`, the schedules) —
   installed by `/orchestrator:enable-orchestrator`, removed by `/orchestrator:disable-orchestrator`.
   **Removing the loop never touches the state layer or the board data.**

## The daily cycle (one human touchpoint, in the morning)

1. **Review** — open the overnight digest (`docs/reports/nightly/<date>/index.html`,
   or the Slack/email copy delivered at your chosen time) and leave `/orch approve`
   or `/orch revise: <notes>` on each PR.
2. **`/orchestrator:kickoff`** — run it right after review. It reads those fresh signals,
   merges the OK'd + green PRs (verifying the merged branch), queues the commented
   ones for rework, adds/plans new EPICs, partitions — then detaches.
3. **Build** — the scheduled runtime runs `nightly-orchestrator.js` through the
   day + overnight (reworks + new epics → one PR each) and writes tomorrow's digest.

Delivery is a **separate scheduled job** (`adapters/notify-digest.sh` at
`notify.config.json`'s `deliver_at`) so the digest lands just before your review,
whatever hour the build finished.

## `orch state` — one contract, pluggable backends (ADR-0007)

```bash
orch state health                          # backend reachable / auth OK
orch state push-session  < session.json    # /core:handoff writes here
orch state pull-session [--branch B]       # SessionStart injection reads here
orch state push-spec --id ID < spec.md     # /core:spec freezes here
orch state push-epic     < epic.json       # backlog entry
orch state list-epics [--state Planned]
orch state push-status --id E --state In-progress [--note "..."]
orch state pull-status                     # read-time aggregation (no shared file)
orch state pull-feedback [--pr-state open] # ALWAYS forge-sourced (gh/glab)
orch state push-digest --date 2026-07-02 < digest.html   # stores the COMPLETE daily file (caller appends run sections)
orch state push-suggestion < suggestion.json               # queue an un-triaged finding (EDGE markers, growth-detection, etc.)
orch state pull-suggestions [--state Suggested]           # read the triage queue
orch state triage-suggestion --id N --decision accepted|rejected   # human triage: accept→Backlog, reject→Cancelled
```

- **`none`** (default): sharded files under `.orch/` — one file per
  branch/epic/core:spec, so parallel worktrees never conflict. Pure shell + `jq`,
  zero dependency.
- **`github-projects` / `gitlab`**: issues + `orch:*` labels via `gh`/`glab`;
  every push mirrors to `.orch/cache/` (gitignored) so reads fail open offline.
- **`jira` / `notion` / `linear` / `trello`**: contract stubs — implement on demand.
- **State ≠ feedback**: `/orch approve`, `/orch revise: <notes>`,
  `/orch approve-plan` and PR reviews are read from the **code forge**, never
  from the board.

## Operator signals (machine-readable, on the PR/MR)

| Signal | Meaning |
|---|---|
| `/orch approve-plan` (or plan-mode approval at kickoff) | The epic's plan may build |
| `/orch approve` or an approving review | PR is OK — merge-eligible when green |
| `/orch revise: <notes>` or "changes requested" | Back to In-progress with notes |

Merge requires: operator OK **and** all checks green **and** no unresolved
threads. **OK is per-PR, never bulk.** High-risk PRs (see `risk-policy.json`
once the loop is enabled) additionally need a `security-auditor` pass.

## Secrets

Env var NAMES only — values live in the vault / runner secrets
(`docs/SECURITY.md`): `GITHUB_TOKEN`/`GH_TOKEN` · `GITLAB_TOKEN`+`GITLAB_HOST`
· `JIRA_API_TOKEN`+`JIRA_BASE_URL`+`JIRA_EMAIL` · `NOTION_TOKEN` ·
`LINEAR_API_KEY` · `TRELLO_API_KEY`+`TRELLO_TOKEN` · `ANTHROPIC_API_KEY`
(headless runs). Adapters read `process.env` and never echo values.
