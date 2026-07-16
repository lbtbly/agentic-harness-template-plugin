---
Status: Accepted
Date: 2026-06-11
---

# ADR-0001 — Record architecture decisions

## Context
Structural decisions made without a written trace get re-debated in loops
and their rationale gets lost. AI agents need the WHY so they don't
undo deliberate choices.

## Decision
Every structural decision is recorded in an ADR following this template
(Context / Decision / Consequences), numbered, immutable once accepted.

## Consequences
- /core:doc-health audits decisions that lack an ADR.
- The CHANGELOG "Decided" section references every accepted ADR.
- Accepted ADRs are write-protected (protect-paths hook).
