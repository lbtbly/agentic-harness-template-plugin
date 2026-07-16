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
2. **Mode**: create a **new board from the template**, or **adopt an existing
   board** — the user pastes its URL and you parse the id out of it (Notion
   database link → the 32-hex databaseId; Jira link → site + project key from
   `/browse/KEY-…`, `/projects/KEY` or `/jira/software/projects/KEY/boards/N`).
   /core:new-project may have already recorded this choice + URL — reuse it.
3. **Where** (create mode):
   - notion → the parent page (URL or id) the database should be created under,
     and confirm the integration is shared with that page.
   - jira → site URL (`https://<org>.atlassian.net`), and create a new
     team-managed Kanban project or reuse an existing one (ask the project key).
4. **Credentials (NAMES only, and only if no MCP connector is available or the
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
     (rich_text), `Assigned to` (rich_text — the worker currently on the card:
     set when a subagent picks it up, cleared with `--assignee -` when it hands
     off), `Complexity` (select: `low` · `medium` · `high` — the planner's
     estimate; the orchestrator right-sizes the model from it), `PR` (number),
     `Note` (rich_text), `Created` (created_time), `Edited` (last_edited_time),
     `Updated` (date — the adapter's state-change timestamp).
   - The full epic record JSON lives in the page body as a code block — the
     adapter reads/writes it there; properties are the human view.
2. Group the database view by `State` — that IS the board. **Column order must
   follow the lifecycle, never alphabetical**: board columns mirror the State
   select's option order, so create the options in EXACTLY the lifecycle order
   and, after creating, READ the property back and re-PATCH the options array if
   the order drifted (some clients append alphabetically). The public API does
   not expose view configuration — if the view still shows alphabetical groups,
   print the one manual step: open the board view → drag the columns once into
   lifecycle order (Notion persists it).
3. Record in `orchestrator/state.config.json`:
   `{ "backend": "notion", "forge": "<existing>", "notion": { "databaseId": "<id>" } }`.

## DO — Jira

1. Create (or adopt) the project: team-managed Kanban, the asked key.
2. States: the adapter tracks lifecycle authoritatively as **labels**
   (`orch-state-<State>`, plus `orch-complexity-<low|medium|high>` when the
   planner estimated it) and the JSON payload in the issue description — it
   never depends on Jira workflow statuses, because team-managed workflow/status
   creation is not reliably scriptable. For a column-per-state board view,
   either add the 12 statuses manually via Project settings → Board → Columns
   (print these exact steps), or use quick filters on the `orch-state-*` labels.
3. Record in `orchestrator/state.config.json`:
   `{ "backend": "jira", "forge": "<existing>", "jira": { "projectKey": "<KEY>" } }`.

## ADOPT an existing board — audit, then fix or guide

Never assume an existing board matches the contract; never silently rebuild it.

1. **Read the real schema**: notion → `GET /v1/databases/<id>` (or the MCP
   equivalent) → properties + the State select's options and their order;
   jira → verify the project resolves and issues are searchable; the label
   convention needs no schema, so the Jira audit covers access, the `Task`
   issue type, and (optionally) board columns/quick filters.
2. **Audit against the template contract** and build a gap report:
   - State select present, with ALL 12 lifecycle options, in lifecycle order
     (flag missing options AND wrong order — boards inherit option order);
   - properties: `Name` (title), `Epic ID` (rich_text), `Assigned to`
     (rich_text), `Complexity` (select low·medium·high), `PR` (number), `Note`
     (rich_text), `Created` (created_time), `Edited` (last_edited_time),
     `Updated` (date) — flag each missing one and any type mismatch.
3. **Report the gaps** in a compact table (missing / wrong type / out of
   order), then ask the user (AskUserQuestion): **update the board
   automatically**, or **do it themselves**?
   - **Automatic**: idempotent and **ADDITIVE ONLY — never delete, rename, or
     re-type an existing property or option** (other views/data may hang off
     them; a type mismatch is reported for the user to resolve, never forced).
     Add the missing options in lifecycle position, add the missing properties,
     re-read the schema and show the before/after so the fix is verifiable.
   - **Themselves**: print a precise, copy-ready **guide** — for each gap: the
     exact property name, type, and (for selects) the options in order, plus
     where to click (notion: database `⋯` → Edit properties; the board view
     columns follow the State option order — drag once if needed. jira:
     Project settings → Board → Columns, or quick filters on `orch-state-*`).
     Offer to re-run this audit afterwards to confirm the board is compliant.
4. Only after the audit passes (or the user accepts the residual gaps) record
   the board in `state.config.json` and proceed to VERIFY.

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
