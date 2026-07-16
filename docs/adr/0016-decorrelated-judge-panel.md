---
Status: Accepted
Date: 2026-07-16
---

# ADR-0016 — Decorrelated judge panel (distinct model per lens)

## Context
The DoD's fourth stage is an adversarial judge panel (correctness / pm / design
lenses, strict majority + blocking dissent). 2026 correlated-errors research
(arXiv 2605.29800 "Nine Judges, Two Effective Votes") shows same-family judges
fail together: a 3-vote panel of one model is ≈ one judge, so majority voting
adds little. Blocking-dissent rules are independently supported (arXiv 2606.07834).

## Decision
`dod-verify.js` pins a model per lens (`JUDGE_MODELS`, ≥2 distinct models across
the panel — enforced by `tests/test-dod-verify.sh`). The tally keeps strict
majority + zero blocking objections, and fails closed on ties and zero votes.
A single strong evaluator with hard per-criterion thresholds (Anthropic's 2026
harness follow-up) is an acceptable operator alternative.

## Consequences
Votes are less correlated at slightly higher cost. Operators tuning `LENSES`
must keep model diversity or the majority becomes decorative. See
docs/DEVIATIONS.md §1 for sources.
