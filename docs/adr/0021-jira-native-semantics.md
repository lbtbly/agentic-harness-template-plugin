---
Status: Accepted
Date: 2026-07-16
---

# ADR-0021 — Native Jira semantics for the state backend (extends ADR-0007's Jira note)

## Context
ADR-0007's original Jira note modeled orchestrator epics as label-carrying
Tasks (`orch-epic` + `orch-state-<State>`), on the grounds that team-managed
workflow/status creation "is not reliably scriptable". A field test on a real
team-managed project (studi-pedago / TCATEST) verified the native model works
and is preferable: an orchestrator epic can be a real Jira `Epic` (verified),
work items can be children via `parent` (verified TCATEST-3 → TCATEST-2), and
lifecycle can ride real status TRANSITIONS (verified Idea→In Progress, →Done).
It also confirmed the hard limit: statuses/columns are created, renamed and
reordered ONLY in the Jira UI (team-managed board: "+" adds a column,
double-click renames, drag reorders) — the read/write:jira-work API and the
MCP connector cannot create statuses or reconfigure the board/workflow. The
stock team-managed workflow (Idea/To Do/In Progress/Testing/Done) does not
cover the 12 orchestrator states.

## Decision
pm-jira.js uses native semantics, configured in `state.config.json`:
`jira: { projectKey, epicIssueType ("Epic"), childIssueType ("Task"),
statusMap: { <lifecycleState>: <jira status name> } }` (many-to-one allowed).
Epics are created as `epicIssueType`; records carrying `parent: <epicId>`
become `childIssueType` issues linked via `parent`. State changes read the
issue's AVAILABLE transitions and POST the one whose target matches
`statusMap[state]`. The adapter MAPS onto pre-existing statuses — it never
creates them; /core:board-setup prints the manual creation steps and
`orch state health` validates every mapped target against the project's real
statuses (warning per missing one).

**The graph caveat.** A Jira workflow is a graph: the mapped target may not
exist, may be unreachable in one hop, or may be unavailable from the current
status. The adapter attempts exactly ONE direct transition; multi-hop pathing
through unknown intermediate statuses is deliberately not attempted (each hop
can fire screens/validators/post-functions we cannot see).

**Label fallback.** On any gap — no statusMap, an unmapped state, a missing or
unreachable target — that update reverts to the `orch-state-<State>` label,
logged to stderr, and the run continues. The EXACT state always lives in the
epic-record JSON in the description (source of truth); reads derive state as
payload → reverse statusMap → label. So an unconfigured or mis-mapped project
degrades to the ADR-0007 label scheme — a poorer board view, never a broken loop.

## Consequences
- Boards read natively (real Epics, real columns); teams keep their workflow —
  on lived-in projects the schema is never modified (many-to-one mapping only).
- Setup gains one manual, unavoidable step (status creation in the UI),
  compensated by health-time validation.
- Unchanged: description-code-block payload, .orch/cache mirroring, forge-only
  feedback, env-NAME-only auth, no tokens/headers/env in errors.
- Consumer upgrade path (adapters are policy-protected TCB in projects, so the
  change ships as plugin source): `/plugin update core@harness` →
  `/reload-plugins` → re-copy `orchestrator/adapters/pm-jira.js` from the
  plugin templates (or re-run `/core:board-setup`), then add `statusMap` to
  `state.config.json` and re-run `orch state health`.
- TCATEST observations (issue-type ids, transition ids) are project-specific
  evidence only — nothing from them is hardcoded.
