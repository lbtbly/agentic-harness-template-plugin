---
Status: Accepted
Date: 2026-07-27
---

# ADR-0030 — Notion gets a real hierarchy, on the current API

Supersedes the note in [ADR-0027](0027-board-is-the-golden-source.md) that deferred a Notion
relation property ("the payload-derived hierarchy already answers the question").

## Context

That deferral answered the wrong question. It was true that `list-initiatives` worked — the
rollup read `.initiative` out of the record JSON in the page body. What it missed is that
**none of the hierarchy was visible in Notion**. `epicProps()` wrote eight properties and not
one of them was `Initiative`, `Parent` or a type marker. So:

- initiatives could not be seen, filtered, grouped or sorted on the board;
- a task was pushed as a **flat sibling page** of its epic, with nothing linking or
  distinguishing them.

Jira distinguishes the two with `orch-epic`/`orch-child` labels *and* an issue type; Linear uses
the same labels. Notion had **no marker at all** — so a single flat table mixed epics and tasks
with no way for a human or an agent to tell which was which. That is a gap, not a modelling
choice, and it was reported from use.

## Decision

**A `Type` select (`Epic` / `Task`)** — the missing parallel of the labels every other backend
already has. Filter the board to `Type = Epic` for a clean epic board, or group by it.

**A `Parent epic` self-relation** for tasks. Verified against a live workspace before design:
one DDL statement creates the property *and* Notion auto-creates the synced inverse
(`Sub-tasks`), and setting only `Parent epic` populates the inverse with no second write.

**A separate Initiatives data source**, related to the epics data source. An initiative becomes
a real page with its own board and state, rather than a string. Chosen over an `Initiative`
select because the question asked was "how do I *manage* initiatives" — a select can be
labelled, not managed.

**The adapter moves to the current API (`2026-03-11`) and the data-source model**, matching the
Notion MCP lane so `/core:board-setup` and the headless runner speak the same language. This was
forced rather than optional: since `2025-09-03`, relation **writes** may only use
`data_source_id`, and `database_id` is rejected outright.

Three properties keep it safe for boards that already exist:

- **Every relation feature is optional and detected, never assumed.** The schema is read once;
  a board without `Type`, without `Parent epic`, or without a configured Initiatives source
  keeps working exactly as before, with that part of the hierarchy in the payload only.
  `capabilities.hierarchy` reports `native` or `derived` so callers degrade instead of guessing.
- **A legacy `databaseId` config still works.** The data source is resolved from it once per
  run, with a warning telling the operator to record the id.
- **Native values win over the payload.** A parent or initiative a human set in Notion overrides
  a stale value the harness wrote earlier — the board is the golden source (ADR-0027). A missing
  parent or initiative warns and continues; the relation is *omitted* rather than written as
  `[]`, because clearing a link a human made would be worse than leaving it.

## Consequences

Notion joins Jira and Linear at `hierarchy: native`, and is the only backend where the
initiative tier is a first-class page with its own state rather than a derived grouping.

Setup costs more: a second database, which **must also be shared with the integration** or every
relation read 404s in a way that looks like a wrong id. `health` now probes the Initiatives
source explicitly and names that cause, because the raw error does not.

Verified live before committing to the design — a scratch database in a real workspace,
exercising the self-relation, the cross-database relation, the synced inverse, and the payload
round-trip, then deleted. That surfaced one thing no documentation mentions: a bare `DUAL`
relation gets an auto-generated inverse name (`Related to <db> (<prop>)`), so both sides must be
named explicitly in the DDL.

The REST documentation still does not confirm self-referencing relations; the MCP tool schema
does, and the live test settles it. Recorded here so the next person does not re-derive it.
