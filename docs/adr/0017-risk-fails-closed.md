---
Status: Accepted
Date: 2026-07-16
---

# ADR-0017 — Risk classification fails closed to high

## Context
The reference implementation's run loop hardcoded `low` risk when calling the
merge hook, so the classifier (`classify_risk`) existed but never gated the
unattended merge path — a misclassification-by-omission that would let any
done epic auto-merge.

## Decision
The driver computes risk per epic from the REAL diff (`compute_risk`:
`git diff --numstat main..orch/<id>` → lines + paths → `classify_risk` against
`risk-policy.json`). Every unreadable state — missing policy, unknown branch,
empty diff — classifies **high**. The default merge action without a verdict
and an auto-mergeable risk level is **escalate**.

## Consequences
Nothing merges on a shrug; a broken policy file degrades to "everything
escalates", never to "everything merges". Enforced by `tests/test-risk-gate.sh`
(fail-closed cases) and `tests/test-run-to-done.sh` (loop defaults).
