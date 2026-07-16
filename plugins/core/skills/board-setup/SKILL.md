---
name: board-setup
description: Provisions the epic-lifecycle board on a remote backend (Notion database or Jira project) and wires it into the state layer — run when /core:new-project chose the notion or jira backend, or later to migrate from the none backend. The board it creates is exactly what the pm-notion/pm-jira adapters drive.
---

# /core:board-setup — create the board & the epic lifecycle (Notion / Jira)

The board is the human-browsable face of the state layer: one column (or select
value) per lifecycle state, one item per epic. This skill creates it once and
records it in `orchestrator/state.config.json`. It works with token env var
**NAMES only — never ask for, echo, or write a token value** (the value lives in
the vault / CI secrets; see `docs/SECURITY.md`).

## The lifecycle (identical on every backend)

`Suggested → Backlog → Needs-plan → Planned → In-progress → Needs-review →
Changes-requested (rework loop) → Approved → Merged`, plus the loop's parking
states: `Blocked` (failed N attempts, awaiting human triage), `Paused`
(usage-limit checkpoint, auto-resumes), `Cancelled` (rejected suggestion).

Remember the split the whole design rests on: **the board shows state; your
approvals are read from the forge (the PR), never the board** — commenting on a
Notion page or Jira issue does nothing to the loop.

## Two lanes — use the one that's available

**MCP-first (no credentials):** if the session has an Atlassian/Jira or Notion MCP
connector, use IT for everything this skill does — creating the database/issues,
setting properties/labels, the verification roundtrip. Do not ask for a token.
**Token lane (only for the unattended loop):** the `pm-jira.js`/`pm-notion.js`
adapters run headlessly from cron, where interactive MCP OAuth does not exist
(ADR-0007) — so the env-var NAMES below become necessary only at
`/orchestrator:enable-orchestrator` time. Provisioning today needs none of them;
say so plainly and defer the token step until the loop is enabled.

## ASK (AskUserQuestion)

1. **Backend**: `notion` · `jira` (or confirm the one already in
   `orchestrator/state.config.json`).
2. **Where**:
   - notion → the parent page (URL or id) the database should be created under,
     and confirm the integration is shared with that page.
   - jira → site URL (`https://<org>.atlassian.net`), and create a new
     team-managed Kanban project or reuse an existing one (ask the project key).
3. **Credentials (NAMES only, and only if no MCP connector is available or the
   unattended loop is being enabled)**: notion → `NOTION_TOKEN` (internal
   integration). jira → `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`,
   `JIRA_PROJECT_KEY`. Tell the user where to set each (shell env / vault / CI
   secrets); add the names to `.env.example`; never a value anywhere.

## DO — Notion

1. Create the database (via the Notion MCP connector when present, else REST
   `POST /v1/databases`; parent = the asked page). Whichever lane created it,
   record the databaseId so the headless REST adapter can drive it later:
   - Title: `<project> — orchestrator board`
   - Properties: `Name` (title — `[<epicId>] <epic title>`), `State` (select
     with EXACTLY the 12 lifecycle options above, in order), `Epic ID`
     (rich_text), `PR` (number), `Note` (rich_text), `Updated` (date).
   - The full epic record JSON lives in the page body as a code block — the
     adapter reads/writes it there; properties are the human view.
2. Group the database view by `State` — that IS the board.
3. Record in `orchestrator/state.config.json`:
   `{ "backend": "notion", "forge": "<existing>", "notion": { "databaseId": "<id>" } }`.

## DO — Jira

1. Create (or adopt) the project: team-managed Kanban, the asked key.
2. States: the adapter tracks lifecycle authoritatively as **labels**
   (`orch-state-<State>`) plus the JSON payload in the issue description — it
   never depends on Jira workflow statuses, because team-managed workflow/status
   creation is not reliably scriptable. For a column-per-state board view,
   either add the 12 statuses manually via Project settings → Board → Columns
   (print these exact steps), or use quick filters on the `orch-state-*` labels.
3. Record in `orchestrator/state.config.json`:
   `{ "backend": "jira", "forge": "<existing>", "jira": { "projectKey": "<KEY>" } }`.

## VERIFY (both)

1. Roundtrip on the lane you used: MCP → create/read a smoke item via the
   connector; token lane → `orchestrator/bin/orch state health` →
   `{ok: true, backend: <chosen>}` with the credentials exported in the shell.
   (Without a token the orch CLI adapter will rightly fail naming the env var —
   expected until the unattended loop is enabled; don't present it as an error.)
2. Roundtrip: `echo '{"id":"board-smoke","title":"smoke","state":"Backlog"}' |
   orch state push-epic` → visible on the board → `orch state pull-status` shows
   it → clean it up (move to Cancelled or delete).
3. `.env.example` carries the env var NAMES; `jq .` passes on state.config.json.
4. Propose commit: `chore: provision <backend> board (epic lifecycle)`.

GUARDRAILS: never store a token value; never re-provision an existing board
without explicit confirmation (idempotent adopt-if-exists first); the `Suggested`
lane is human-triage-only (the night loop never builds from it); disabling the
orchestrator later PRESERVES this board and all its data.
