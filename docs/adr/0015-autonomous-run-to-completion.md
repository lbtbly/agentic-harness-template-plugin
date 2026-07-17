---
Status: Accepted
Date: 2026-07-15
---

# ADR-0015 — Autonomous run-to-completion with risk-gated auto-merge (supersedes the merge-gate clause of ADR-0008)

> ADR-0002 / ADR-0014: historical, unported — decisions of the reference
> implementation this repo was distilled from; see docs/adr/README.md.

## Context
ADR-0008 set the orchestrator invariant: "autonomy adds a build phase, it never removes a
control" — every merge to `main` required a per-PR human OK at kickoff. That made the human
the sole authority on "done," because the machine-checkable definition-of-done was incomplete
(engineering-centric; PM/design largely unencoded). Users asking for "launch it and it runs
until done" need the machine to terminate against a trustworthy contract instead of stopping
at "PRs ready."

## Decision
Add a run-to-completion mode (`/orchestrator:run`) that runs unattended until the
selected scope is done or a guard trips, with **risk-gated auto-merge**:
- **Low-risk** epics that pass the full DoD merge to `main` with **no human gate**.
- **High-risk** epics (risk-policy `highRiskPaths` / size thresholds) always **escalate**.
This supersedes ADR-0008's per-PR-human-merge clause **for low-risk work**. The rest of
ADR-0008 stands (runtimes, limit-resilience, sandbox, plan-gate). The gated nightly mode
remains available — this is additive.

The removed control is replaced by compensating, independent controls:
1. A **complete external DoD contract** (ADR-0014's feature_list, extended in Phase 1 with
   acceptance criteria + required test levels + epic tests + design refs).
2. **4-stage verification**: multi-level tests + browser E2E + acceptance assertions + an
   **independent adversarial judge panel** (builder ≠ judge; majority ≥2-of-3 AND no
   blocking dissent).
3. A **double risk-gate**: the orchestrator's classifier won't attempt a high-risk merge,
   AND the forge's branch protection + CODEOWNERS require a human review on high-risk paths,
   enforced independently of the orchestrator.
4. **Sandbox isolation, secret-guard, no self-elevation** — unchanged.
5. **Escalation + human scope-pick** — the human owns launch scope, all ambiguity, and every
   high-risk / dissenting / churning epic.

No single agent both defines and certifies its own success: planner authors the DoD →
design-reviewer validates it vs intent → builder builds → judge panel verifies →
forge + CODEOWNERS check. Human intent (the initiative) is the root ground truth.

## Branch-protection reconciliation
`main` stays protected (direct pushes rejected, merges via PR only, required status checks
green, token cannot bypass). The *required review* is specified by risk:
- **Low-risk** → satisfied by the judge panel's approving review from a distinct reviewer
  identity (not builder, not human).
- **High-risk** → CODEOWNERS on `highRiskPaths` requires a **human** approving review; the
  forge blocks the merge even if the orchestrator misclassified.

## Consequences
- True launch-and-run: the loop ends when the selected scope is drained or a guard
  (no-progress / usage / budget / wall-clock / thrash / safety) trips.
- Trust shifts from "a human merges everything" to "no unverified or non-low-risk change
  reaches `main` unattended; verification is independent and multi-layered."
- Residual risks (accepted, mitigated, not eliminated): the **judge panel is the load-bearing
  weak link** (mitigate: adversarial + diverse lenses + consensus + low-risk-only +
  escalate-on-dissent + post-hoc digest review); **auto-authored DoD can be lenient**
  (mitigate: independent design-reviewer validation + digest visibility); **screenshot
  design-verification is imperfect** (mitigate: risk-flag design-heavy epics to force human
  review); **"works but wrong product"** (mitigate: acceptance criteria + PM-lens judge;
  ultimate backstop is the human scope-pick + escalation).
- ADR-0008's merge-gate clause is superseded; the rest of 0008 stands.
