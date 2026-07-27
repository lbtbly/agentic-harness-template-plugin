---
Status: Accepted
Date: 2026-07-27
---

# ADR-0026 — Autonomy is earned per class of work, not configured once

## Context

Autonomy was a binary the operator chose up front: the gated nightly flavour (one PR per epic,
human merges each morning) or run-to-completion (low-risk epics auto-merge after the DoD passes).
The README's own advice — "turn this on only after the gated flavour has earned your trust" —
described a judgement the operator had to make from memory, with nothing measuring whether trust
had in fact been earned.

The risk policy answers a different question. It says *how bad it would be to get this wrong*:
lines changed, sensitive paths. It says nothing about *how often this harness has actually got
this kind of thing right in this repo*. A low-risk epic in a corner of the codebase where every
previous attempt needed rework is still not something to merge unattended.

## Decision

A per-class ledger, `.orch/trust.tsv`, with three tiers:

| tier | rule (default) | effect |
|---|---|---|
| `watch` | <10 runs, or <90% verified pass | draft only |
| `queue` | ≥10 runs at ≥90% | verified, but waits for review |
| `auto`  | ≥20 runs at ≥95% | may auto-merge, still subject to the risk policy |

Auto-merge now requires **risk-allows AND tier == auto**. Both, never either.

**The class is `<footprint-root>/<complexity>`** — the top directory the epic touches plus how
hard the planner judged it. Coarse on purpose. "Can this harness be trusted" is the wrong
question: it can be trusted with dependency bumps under `docs/` long before it can be trusted
with a migration. A finer key would be more precise and never accumulate enough runs to leave
`watch`, which is what makes ledgers like this decorative. An epic with no footprint classes as
`unknown` rather than silently sharing a class with real work — a missing footprint is a planner
defect and should not inherit someone else's record.

**Slow to grant, fast to revoke.** Reaching `auto` needs a sustained record; the tier is
recomputed on every single run and drops the moment the rate falls below the floor. It is a
*rate*, not a streak: one miss in a clean 20 is 95.2% and keeps `auto`, the second does not.
Demotion prints to stderr, which cron mails — a class quietly losing autonomy is exactly what an
operator needs to hear about.

**A fresh install auto-merges nothing.** No ledger means every class is `watch`. The safe
default is the default, and it requires no configuration to get.

Outcomes are recorded from what actually happened, not from the builder's self-report: a landed
epic is a pass; a failed DoD verdict is a fail; and an epic that was green in isolation but went
red after merging is a fail, because that is precisely the case the class-level record exists to
catch.

## Consequences

This replaces "choose a flavour and hope" with a measurement, and it is what makes the
run-to-completion mode safe to actually enable — the first nights produce reviewed PRs regardless
of the flavour chosen, and autonomy arrives per corner of the codebase as evidence accumulates.

Thresholds are tunable through `ORCH_TRUST_*`, but the defaults are the conservative ones, and a
repo that wants faster autonomy should lower them deliberately rather than discover they were
low.

The ledger is local (`.orch/`), not board state: it is a property of this harness in this repo,
not of the work. It is also the substrate the compost loop reads — a class stuck at `watch` is a
question about the framework, not about the operator.
