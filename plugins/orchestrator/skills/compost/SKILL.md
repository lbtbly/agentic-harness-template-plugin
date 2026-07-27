---
name: compost
description: "Weekly: reads the journal, trust ledger and goal ledger, and proposes at most three concrete framework fixes. Proposes only — never edits."
argument-hint: "[--since YYYY-MM-DD]"
disable-model-invocation: true
---

# /orchestrator:compost — turn last week's failures into rules

The harness now records its own mistakes, its per-class pass rates, and its standing goals. None
of that improves anything on its own. This is the pass that reads the exhaust and proposes
changes.

It exists because of a specific gap: `/orchestrator:kickoff` already classifies review notes into
"plan defect" vs "missing context" and proposes a rule for the second — but **skipped proposals
are dropped, not remembered**. Every recurring review comment is a missing rule, and until now
the signal was discarded by design.

## Read

- `.orch/journal/*.jsonl` — guard blocks, tool errors, human corrections, escalations, reverts.
- `.orch/trust.tsv` — which classes of work are stuck at `watch`.
- `.orch/goal-ledger.tsv` — which invariants keep breaking.
- PRs closed unmerged, and `Changes-requested` epics with a high `attempts=`.

## Propose — at most three, and only what the evidence supports

For each candidate, the question is always the same: **is this a rule the harness enforced after
the fact that it should have taught up front?**

- A `guard_block` recurring on one rule → a missing line in `CLAUDE.md` or a stack rule. The
  agent kept trying something the environment never told it not to.
- A `tool_error` class recurring → a missing verification step, or a gotcha missing from
  `docs/CODEMAP.md`.
- A `user_correction` recurring → the sharpest signal available. A human said the same thing
  more than once; that is a framework problem, not an operator problem.
- A class stuck at `watch` in the trust ledger → look at *why* it fails, not at the number. It
  is usually the spec pattern, not the worker.
- A goal that keeps flapping → either a bad predicate or a genuinely unstable subsystem. Say
  which, with evidence.
- An `escalation` with a low `corrected` rate → the model ladder is mis-tuned for that
  complexity class.

**Three is a ceiling, not a target.** A clean week should produce "nothing worth changing" — say
that plainly. A compost run that always finds three things is generating noise, and the next one
will be ignored.

## Write

Proposals go to `docs/SUGGESTIONS.md` through `orch state push-suggestion`, entering the existing
human-gated lifecycle (ADR-0011): `Suggested → Accepted → Backlog`. The nightly loop never picks
up `Suggested`, so nothing here can start building itself.

Quote the evidence inline — the count, and the dates. A proposal without a number attached is an
opinion, and it will be triaged as one.

**Propose only. Never edit a rule, a hook, or a skill here.** The guard hooks block most of it
anyway, and that is correct: a harness that rewrites its own guardrails from its own telemetry is
the thing the guardrails exist to prevent.
