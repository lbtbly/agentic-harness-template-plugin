---
name: board-setup
description: Creates or adopts the epic-lifecycle board on Notion, Jira or Linear (MCP-first), audits adopted boards, wires state.config.json. Use when the backend is notion, jira or linear.
disable-model-invocation: true
---

# /core:board-setup — create the board & the epic lifecycle (Notion / Jira / Linear)

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

**MCP-first (no credentials):** if the session has an Atlassian/Jira, Notion or Linear MCP
connector, use IT for everything this skill does — creating the database/issues,
setting properties/labels, the verification roundtrip. Do not ask for a token.
**Keychain lane (R11)**: if `CLAUDE_PLUGIN_OPTION_BOARD_TOKEN` is set (the
orchestrator plugin's `userConfig` — the value lives in the OS keychain, never
in a file), the headless adapters use it as the board token: export it as
`NOTION_TOKEN`/`JIRA_API_TOKEN` in the runner env. Prefer it over ad-hoc env
setup; never echo it. **Token lane (only for the unattended loop):** the `pm-jira.js`/`pm-notion.js`
adapters (and `pm-linear.js`) run headlessly from cron, where interactive MCP OAuth does not exist
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
   - jira → **the connector cannot create a new project** (no MCP tool, and
     `write:jira-work` doesn't cover it) — so even in "create" mode the user
     provides a project URL. If none exists yet, print the 30-second UI step
     (team-managed Kanban project) and wait; then ask the fork below.
4. **Credentials (NAMES only, and only if no MCP connector is available or the
   unattended loop is being enabled)**: notion → `NOTION_TOKEN` (internal
   integration). jira → `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`,
   `JIRA_PROJECT_KEY`. Tell the user where to set each (shell env / vault / CI
   secrets); add the names to `.env.example`; never a value anywhere.

## DO — Notion (native relations — ADR-0030)

Model: initiative → a page in a **separate Initiatives data source**; epic → a page in the epics
data source with `Type = Epic`; task → a page in the SAME source with `Type = Task`, linked by
the **`Parent epic` self-relation** (Notion syncs `Sub-tasks` back automatically). The full epic
record JSON still lives in the page body as a code block — the precise source of truth; the
properties are the human/board view.

**Use the MCP connector when present** — it takes SQL DDL and does all of this in three calls.
The API version matters: this adapter speaks **data sources** (`2025-09-03`+), because relation
writes may only use `data_source_id` — `database_id` is rejected.

1. **Create the Initiatives data source** first (the epics source relates TO it):

   ```
   CREATE TABLE ("Name" TITLE,
                 "State" SELECT('Backlog':gray, 'In-progress':blue, 'Merged':green),
                 "Initiative ID" RICH_TEXT)
   ```

2. **Create the epics data source**, relating to it. `<init_ds>` is the id from step 1:

   ```
   CREATE TABLE ("Name" TITLE,
                 "Type" SELECT('Epic':purple, 'Task':gray),
                 "State" SELECT('Suggested':gray,'Backlog':gray,'Needs-plan':brown,
                                'Planned':orange,'In-progress':blue,'Needs-review':yellow,
                                'Changes-requested':red,'Approved':green,'Merged':green,
                                'Blocked':red,'Paused':gray,'Cancelled':default),
                 "Epic ID" RICH_TEXT,
                 "Initiative" RELATION('<init_ds>', DUAL 'Epics' 'epics'),
                 "Assigned to" RICH_TEXT,
                 "Complexity" SELECT('low':green, 'medium':yellow, 'high':red),
                 "PR" NUMBER, "Note" RICH_TEXT, "Updated" DATE)
   ```

   **Name BOTH sides of every relation.** A bare `DUAL` gets an auto-generated inverse name like
   `Related to <db> (Initiative)` on the other board — ugly and confusing, and it cannot be
   renamed from the DDL afterwards.

3. **Add the self-relation** — a second call, since it needs the epics source's own id:

   ```
   ADD COLUMN "Parent epic" RELATION('<epics_ds>', DUAL 'Sub-tasks' 'subtasks')
   ```

   One statement creates both sides. Setting `Parent epic` on a task populates `Sub-tasks` on the
   epic automatically — nothing writes the inverse.

4. **Group the board view by `State`** — that IS the board. Column order follows the State
   option order, so create the options in EXACTLY the lifecycle order above. The public API
   cannot configure a view: if the columns still show alphabetically, tell the user to drag one
   column once (Notion persists it). A second, useful view: filter `Type = Epic` for a clean
   epic board.

5. **Record both ids**:
   `{ "backend": "notion", "forge": "<existing>",
      "notion": { "dataSourceId": "<epics_ds>", "initiativesDataSourceId": "<init_ds>" } }`

6. **Share BOTH databases with the integration.** The related one too — otherwise every relation
   read 404s in a way that looks like a wrong id. `orch state health` probes it and says so.

**Degradation is deliberate.** Every relation feature is optional and detected, never assumed.
A board without `Type`, without `Parent epic`, or without an Initiatives source keeps working
with that part of the hierarchy in the payload only; `health` names what is missing and
`capabilities.hierarchy` reports `derived` instead of `native`. A legacy config carrying only
`databaseId` still resolves (with a warning to record the data source id).

## DO — Jira (native semantics — ADR-0021)

Model: orchestrator epic → a real Jira **Epic** (`epicIssueType`, default
`Epic`); work items → **child issues** (`childIssueType`, default `Task`)
linked via `parent` (a record carrying `"parent": "<epicId>"` is a child);
lifecycle state → **real Jira statuses applied as workflow TRANSITIONS**,
through a configurable `statusMap`. The EXACT orchestrator state always lives
in the epic-record JSON in the description; the Jira status is the coarse,
human/board view. Labels remain the identification (`orch-epic`/`orch-child`)
and the FALLBACK lane (`orch-state-*`) whenever a status is unmapped, missing,
or unreachable — a mis-mapped board degrades to labels, never breaks the loop.

1. Resolve the project from the user-provided URL (the connector cannot create
   projects — see above), then **ask the fork**: was this project **freshly
   created just for this** (empty, dedicated to the harness), or is it an
   **existing project with real work in it**?
2. **Statuses are created MANUALLY — the API/connector cannot create statuses
   or reconfigure the board/workflow.** Print the exact steps and wait:
   - team-managed board: **"+" adds a column (= a status)** · **double-click a
     column header to rename** · **drag headers to reorder** into lifecycle order;
   - company-managed: statuses/workflow via Jira admin → Workflows.
   Fresh dedicated project → recommend one column per lifecycle state (all 12).
   Lived-in project → **never modify the team's schema** (statuses, workflows,
   issue types belong to them): map many-to-one onto the statuses that already
   exist and skip this step entirely.
3. **Recommend a default `statusMap`** (12 keys; many-to-one allowed) and let
   the user edit it. Fresh project: the identity map onto the 12 new columns.
   Lived-in stock board (e.g. Idea/To Do/In Progress/Testing/Done):
   `Suggested→Idea · Backlog/Needs-plan/Planned/Blocked/Paused→To Do ·
   In-progress→In Progress · Needs-review/Changes-requested→Testing ·
   Approved/Merged/Cancelled→Done`.
4. Record in `orchestrator/state.config.json`:
   `{ "backend": "jira", "forge": "<existing>", "jira": { "projectKey": "<KEY>",
   "epicIssueType": "Epic", "childIssueType": "Task", "statusMap": { … } } }`.
5. **Validate**: `orch state health` checks every statusMap target against the
   project's REAL statuses and warns per missing one — re-run it after the
   manual column step until it reports none missing. A workflow is a graph:
   even an existing status may be unreachable from some current status; the
   adapter attempts one direct transition and falls back to the `orch-state-*`
   label for that update (logged), so a gap is visible, never fatal.

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
     `Updated` (date) — flag each missing one and any type mismatch;
   - the hierarchy properties (ADR-0030), each independently optional:
     `Type` (select Epic·Task), `Parent epic` (relation to this same source),
     `Initiative` (relation to the Initiatives source). Missing ones are NOT an
     error — report them as "hierarchy degraded to payload-only" and offer to add
     them, since adding a relation is additive and safe.
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

## Linear

Linear needs the least provisioning of any backend, because its model already
matches the harness's (ADR-0027):

| harness | Linear |
|---|---|
| initiative | **Project** |
| epic | **Issue** (label `orch-epic`) |
| child / task | **Sub-issue** via `parentId` (label `orch-child`) |
| lifecycle state | **workflow state**, via `linear.stateMap` |

**What to do**

1. **Pick the team.** Everything is scoped to one Linear team; record its key
   (the `ENG` in `ENG-123`) as `linear.teamKey` in `orchestrator/state.config.json`.
2. **Map the 12 lifecycle states onto the team's real workflow states.** A new team
   ships with exactly five: **Backlog · Todo · In Progress · Done · Canceled**
   (there is no "In Review" by default). The map is many-to-one, so **nothing needs
   creating** — this works on a stock team as-is:

   ```json
   { "backend": "linear", "forge": "github",
     "linear": { "teamKey": "ENG", "stateMap": {
       "Suggested": "Backlog", "Backlog": "Backlog", "Needs-plan": "Backlog",
       "Planned": "Todo", "In-progress": "In Progress",
       "Needs-review": "In Progress", "Changes-requested": "In Progress",
       "Approved": "Done", "Merged": "Done",
       "Blocked": "Todo", "Paused": "Todo", "Cancelled": "Canceled" } } }
   ```

   Adding one state — **In Review** (category: Started) — is worth the 30 seconds:
   point `Needs-review` and `Changes-requested` at it and the board separates "being
   built" from "waiting on you", which is the distinction you act on each morning.

   Run `orch state health` — it validates every target against the team's **real**
   workflow states and names any that are missing. Add those in Linear under
   **Settings → Teams → *your team* → Issue statuses** (the API cannot create
   workflow states), or leave them out and that state falls back to an
   `orch-state-*` label.
3. **Create a Project per initiative** if you want the native tier. The adapter
   files an epic under a Project whose name matches its `initiative` field, and
   **never creates one implicitly** — inventing projects from a free-text field is
   how boards get littered. No match → a warning, the value stays in the record,
   the run continues.
4. **Labels are created on demand** (`orch-epic`, `orch-child`, `orch-state-*`,
   `orch-complexity-*`). Set `linear.createMissingLabels: false` to forbid that on
   a governed workspace; the lifecycle then relies entirely on `stateMap`.

**Token (headless lane only).** `LINEAR_API_KEY` — a personal key from
**Settings → Account → Security & Access → Personal API keys**. Personal keys are sent raw in
the `Authorization` header; only OAuth tokens use `Bearer`, and the adapter
detects which from the prefix. **Name only, never the value** (`docs/SECURITY.md`).

**Egress.** Uncomment `api.linear.app` in `orchestrator/egress-allowlist.txt` and
mirror it into both enforcers before enabling the unattended loop — otherwise the
firewall fails closed on every state push mid-run.

**No audit lane.** Unlike Notion and Jira there is no schema to adopt or repair:
a Linear team already has states and labels, so `health` is the whole check.

