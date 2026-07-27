---
Status: Accepted
Date: 2026-07-27
---

# ADR-0029 — Linear, mapped onto its own model

Supersedes the closing note of [ADR-0027](0027-board-is-the-golden-source.md)
("`pm-linear.js` remains a stub"), and the `linear` entry in ADR-0007's
stub-until-needed list.

## Context

`pm-linear.js` was twelve lines that exited 64. ADR-0027 built a board-sourced
initiative tier across four backends and observed that Linear — whose own model is
Initiative → Project → Issue → Sub-issue — was the closest conceptual fit of any of
them and the only one not implemented.

## Decision

| harness | Linear | why |
|---|---|---|
| initiative | **Project** | issues carry `projectId` natively; one field, no join |
| epic | **Issue** (`orch-epic`) | the contract is issue-shaped: 12 states, labels, assignee, PR, a description that can hold the record |
| child | **Sub-issue** (`parentId`, `orch-child`) | Linear's own sub-issue relation |
| lifecycle state | **WorkflowState** via `linear.stateMap` | the exact parallel of Jira's `statusMap` |

Epics map to Issues rather than to Projects because the harness contract is
issue-shaped — a twelve-state lifecycle, labels, an assignee carrying the claim, a
PR number, and a description that can hold the record payload. Linear Projects have
none of that; they have a five-value status enum. The tier that *is* project-shaped
is the initiative, and that is where Projects are used.

Two properties are deliberately different from Jira:

**A Linear workflow is not a transition graph.** `stateId` is set directly, so
there is no "unreachable status" case and no multi-hop pathing — the mapped state
either exists in the team or it does not. This deletes the riskiest part of the
Jira adapter rather than porting it. The fallback is unchanged: unmapped or missing
→ `orch-state-<State>` label, logged, never a failed run, with the exact state
always living in the record JSON.

**Projects are never created implicitly.** A project is a human artefact;
conjuring one from a free-text `initiative` field is how boards get littered. No
match → warn, keep the payload field, carry on (ADR-0021's discipline).

Auth: personal keys (`lin_api_…`) go in `Authorization` **raw**; only OAuth tokens
take `Bearer`. Sending a personal key as `Bearer` is a silent 401, so the adapter
detects from the prefix rather than assuming. GraphQL also answers **200 with an
`errors` array**, so HTTP status alone is not a success check — both are pinned by
tests.

## Consequences

Every field, type, query and filter key was validated against Linear's published
schema before use rather than assumed, and `health` validates the configured
`stateMap` against the team's real workflow states — the same self-check the Jira
adapter does against real Jira statuses.

This surfaced a **pre-existing gap affecting every remote backend**: the egress
allowlist contained no board host at all, so a Notion or Jira backend's
`orch state push-*` calls would fail closed inside the sandbox mid-run — reading as
the loop mysteriously losing its state. Board hosts are now documented in the
allowlist (commented, opt-in, since every entry widens the blast radius) and
`/orchestrator:enable-orchestrator` verifies the configured backend's host is
reachable before enabling the loop.

It also corrected the shared initiative rollup across **all five** adapters and the
`none` backend: it grouped *every* non-initiative record, so a sub-issue with no
`initiative` field conjured an "unassigned" initiative that exists on nobody's
board. A child belongs to its parent epic, not directly to an initiative.

`pm-trello.js` remains a stub. Trello has no workflow states, no sub-issues and no
project tier — lists on a board are the whole model — so it would be the
label-scheme-only backend, and nobody has asked.
