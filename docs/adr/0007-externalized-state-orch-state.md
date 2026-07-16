---
Status: Accepted
Date: 2026-07-02
---

# ADR-0007 — Externalized project state via the `orch state` adapter contract

## Context
The template's state files are mono-writer whole-file rewrites: `docs/HANDOFF.md`
(overwritten each session), `docs/ROADMAP.md` (shared status table), `conception/tasks.md`
(76KB checkbox file), committed `.claude/agent-memory/`. A senior-developer review
(2026-07-01) called them merge-conflict magnets for team/parallel work and recommended an
external PM tool with a CLI/MCP the agent can call. The orchestrator design
(`conception/2026-07-01-agentic-orchestrator-design.md`) independently requires a
pluggable PM adapter. But the template's flagship value is zero dependency (`jq`+`git`
only) — forcing Jira/Notion on a solo POC is exactly the overkill the review warned about.

## Decision
- **Externalization is the architecture, not the tool**: all backlog/spec/status/session
  state goes through one CLI facade — `orch state <op>` — backed by per-backend adapters
  (`orchestrator/adapters/pm-<backend>.js`) implementing a single contract:
  `pushSession/pullSession`, `pushSpec/getSpec/listSpecs`, `pushBacklog/pushEpic/
  getEpic/listEpics/pushPlan/getPlan`, `pushStatus/pullStatus`, `pullFeedback`,
  `pushDigest`, `capabilities`, `health`.
- **`none` is the first-class default backend**: pure shell/`jq`, sharded local files
  under `.orch/` (`sessions/<branch>.json`, `epics/<id>.json`, `specs/<id>.md`, …).
  Sharding by branch/epic id means parallel worktrees touch different filenames — git
  auto-merges; aggregation moves from write-time to read-time (`pull-status` globs).
  Node is required only when a *remote* backend is chosen.
- Implement **`none` + `github-projects` (gh) + `gitlab` (glab) fully**;
  jira/notion/linear/trello ship as contract-stubs (interface + auth env NAMES) until
  needed. MCP is used only inside remote adapters, interactive only; headless uses
  REST-via-token.
- **State backend ≠ feedback source** (load-bearing): review signals (`/orch approve*`,
  PR reviews) always come from the code forge via `gh`/`glab`, never from the board.
- The backend is a `/new-project`-level choice, owned independently of the orchestrator;
  `/enable-orchestrator` reuses it and `/disable-orchestrator` never touches it. The
  in-repo `.orch/` board exists **only** for `none`; remote backends get a gitignored
  read-cache, never a second board.
- Session injection (`inject-session.sh`) is `timeout`-wrapped and **fail-open**
  (backend → cache → legacy `HANDOFF.md`): a slow or VPN-gated board never stalls a
  session start.
- `docs/adr/`, `docs/CODEMAP.md`, `.claude/rules/` stay in-repo (immutable or
  low-conflict reference, not session state). Existing `conception/` content is archived
  in place, not migrated.

## Consequences
- `/handoff`, `/spec`, `/doc-health`, `/codemap` route state through `orch state`;
  CLAUDE.md's Layer 3 is redefined accordingly.
- Two parallel agents/humans no longer clobber each other's session or status files —
  the original complaint — even fully offline with `none`.
- Secrets discipline is unchanged: adapters read tokens from `process.env` by NAME
  (`GITHUB_TOKEN`, `GITLAB_TOKEN`/`GITLAB_HOST`, `JIRA_API_TOKEN`…); no value ever
  touches the repo; output is token-scrubbed.
- Teams choosing a remote board accept degraded offline behavior (cache reads only) —
  `/new-project` states this at selection time and recommends `none` for poc/solo.
