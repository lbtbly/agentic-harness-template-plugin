---
Status: Accepted
Date: 2026-07-16
---

# ADR-0018 — The gated nightly flavor is the recommended default

## Context
Run-to-completion auto-merge is architecturally sound (risk-gated, double-locked
by CODEOWNERS) but empirically ahead of practice: an MSR 2026 mining study
(arXiv 2605.22534) found 61% of "automation-authorized" agent merges still had
a human review first, and no first-party lab post recommends unattended
auto-merge.

## Decision
Documentation (README, START_HERE) presents the gated nightly flavor as the
recommended default; `/orchestrator:run` is the opt-in for projects whose DoD
has earned trust. No structural change — "build the loops first, loosen the
gates second" is now backed by data.

## Consequences
New adopters get the per-PR human gate by default; auto-merge stays scoped to
low-risk epics when explicitly chosen.
