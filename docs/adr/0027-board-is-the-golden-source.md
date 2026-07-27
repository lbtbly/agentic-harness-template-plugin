---
Status: Accepted
Date: 2026-07-27
---

# ADR-0027 — The board is the golden source; `.orch/` is a working mirror

## Context

The board was, in practice, a **mirror of what the harness pushed**. Every epic on it was one
the framework invented: `/orchestrator:enable-orchestrator` turned each initiative the operator
*named in chat* into an epic record, and the planner pushed its decomposition. `list-epics` read
back only items carrying the harness's own marker (`labels = "orch-epic"`, `orch:epic`, a `[id]`
title) and its own JSON payload. An issue a human wrote on the board was picked up by accident on
Jira and Notion and **silently dropped** by GitHub and GitLab.

Hierarchy barely existed. `initiative` was a free-text field on the epic record that **no adapter
read**. `deps[]` was authored by the planner and read by nothing. Only `pm-jira.js` understood a
parent link at all — and only when *writing*: `EPIC_FIELDS` never requested `parent` back, and
`listEpicRecords()` queried `labels = "orch-epic"`, so children were invisible to `list-epics`
and `pull-status`. The hierarchy was write-only.

And nothing stopped two agents picking the same card.

## Decision

**The board is the golden source for every initiative, epic and task. `.orch/` is a working
mirror** — copied down while work is in flight so parallel agents can see what is taken, and
reconciled back to the board, which always wins. The harness continues to own only what a board
cannot express: the DoD contract, the footprint, the plan, the verdict.

**Hierarchy reads are additive and optional.** `list-epics` gains `--initiative`, `--parent` and
`--level`; a new `list-initiatives` returns the tier. With no flags, `list-epics` returns
byte-for-byte what it always did, so `run-to-done.sh`, `nightly-orchestrator.js` and
`run-with-limits.sh` were not touched. The 16-op contract (grep-enforced by
`tests/test-board-setup.sh`) is unchanged; ops were only added.

**Every backend answers the same question, at whatever fidelity it has.** Jira uses its native
`parent` link — now actually *requested* and read back, with a human-set parent winning over a
stale one in the payload. The others derive the tier from the record payload, which round-trips
verbatim through the issue body for free. Where no hierarchy is expressed at all, one initiative
is **synthesized** per distinct `initiative` value rather than erroring, so a flat board answers
the same question as a nested one. `capabilities` now reports `hierarchy: native | derived` so
callers can degrade instead of guessing.

**Human-authored cards are first-class.** The `[id] Title` fallback is promoted from an accident
on two backends to a designed path on all four. A board that is the source of truth must be
readable even when the harness did not write the record.

**Claims are leases, not flags.** `claim --id --owner --ttl`, `release`, and `list-claimable`.
A lease has an owner *and an expiry*, so a crashed agent's card returns to the pool instead of
being stranded — the same shape `run-with-limits.sh` already uses for usage pauses. Re-claiming
your own lease succeeds, so a resumed run keeps working; someone else's unexpired lease is
refused with exit 3.

## Consequences

This promoted a known cosmetic bug into a fixed blocker: `push-status` honoured `--pr` and
`--assignee` on Jira and Notion and **dropped them** on GitHub and GitLab, whose `pull-status`
omitted `pr` entirely. A claim model cannot be built on a field two of four backends throw away.
Both now carry `pr`, `assignee` and `leaseUntil`.

Also fixed: `JSON.parse` on the issue-body fence was unguarded in the GitHub and GitLab listers,
so **one malformed fence threw and killed the entire listing** — a single bad issue made the
whole board unreadable. Both now skip the item with a warning, matching what the `none` backend
already did. This required defining `warn()` in both, which neither had.

Deliberately not done: adding a Notion `relation` property. `board-setup/SKILL.md` mandates
ADDITIVE-ONLY schema changes on adopted boards, the property list is duplicated across three
places that must stay in sync, and the payload-derived hierarchy already answers the question.
It is the right change when someone needs the tier visible *in the Notion UI*, not before.

`pm-linear.js` remains a stub, which is a shame — Linear's native Initiative → Project → Issue is
the closest fit of any backend to this model.
