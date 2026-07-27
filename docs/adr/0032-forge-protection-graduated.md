---
Status: Accepted
Date: 2026-07-27
---

# ADR-0032 — Forge branch protection: required, or explicitly accepted as unavailable

Extends ADR-0008 (precondition list) and ADR-0015 (risk-gated auto-merge).
Neither is superseded: where protection exists, nothing changes.

## Context
`/orchestrator:enable-orchestrator` treated branch protection on `main` as a binary
precondition — present, or **stop and list what's missing**. That models one failure
mode (the operator has not configured it yet) and misses a second, common one: the
forge **cannot** provide it on the account's plan.

On GitHub, a **private repository on the free plan** has neither branch protection nor
rulesets — both APIs answer `403 "Upgrade to GitHub Pro or make this repository public"`.
No credential shape works around it: fine-grained PATs, GitHub App installation tokens
and deploy keys all grant `contents:write` repo-wide, with no branch scoping. The
precondition is not unmet, it is **unsatisfiable**.

The observed consequence on a real solo project was worse than the risk it guarded:

- The skill stopped, re-derived the same argument on every subsequent invocation, and
  never converged — there was nowhere to record "decided".
- It recommended making the repository **public** as the remedy, trading a real
  confidentiality property for a policy nicety.
- With no field to write the decision into, the warning landed as prose in three files
  (`CLAUDE.md`, `docs/STACK.md`, `docs/SECURITY.md`). `CLAUDE.md` has a line budget and
  is loaded every session, so the same paragraph was billed three times, permanently —
  and a later session re-litigated anyway, because prose is not a gate.

The underlying concern is real and unchanged: deny rules in `settings.orchestrator.json`
cannot stop a refspec push (`git push origin HEAD:refs/heads/main`), and ADR-0009 already
records that the Bash layer is porous. Only the forge can refuse. What was wrong was
treating an unsatisfiable condition as a blocker, and a decision as prose.

## Decision
Protection becomes a **three-state, machine-readable** property, not a binary prose gate.
`orchestrator/risk-policy.json` gains `forgeProtection`:

| Value | Meaning | Effect |
|---|---|---|
| `required` (default) | protection must be verified at the forge before the loop runs | unchanged behavior; auto-merge allowed per `autoMergeRiskLevels` |
| `unavailable-accepted` | the forge cannot provide it on this plan; the operator accepted the exposure | **auto-merge is force-disabled** — every merge is human, regardless of `autoMergeRiskLevels` |

Enablement distinguishes the three outcomes by the forge's own answer, not by guesswork:
protection present · absent-but-settable (`404`) → stop, as before · **unsatisfiable**
(`403` + upgrade message) → offer the acceptance **once**.

The acceptance is a mechanism, not a warning:

- `may_automerge()` in `run-to-done.sh` returns false unless `forgeProtection` is
  `required`. Accepting the exposure mechanically disables unattended merges, and editing
  `autoMergeRiskLevels` alone cannot re-arm them.
- The decision is recorded **once**, in the JSON. Skills read the field instead of
  re-deriving the argument; the project's `CLAUDE.md` carries at most a one-line pointer.
- Making a private repository public is **removed** from the suggested remedies.

## Consequences
- A solo/private/free-plan project can run the gated nightly loop — its intended
  audience per ADR-0018 — instead of being blocked by a condition its plan forbids.
- `/orchestrator:run` (ADR-0015) still runs under `unavailable-accepted`, but
  "run to completion" completes to **PRs**, never to `main`. That is stated where the
  mode is documented rather than discovered at 3am.
- The residual exposure is honest and unmitigated at the forge: the loop's token can
  push to `main`, and nothing server-side will refuse it. What remains is the
  `permissions.deny` layer, the `orch/*`-only push allowlist, and the fact that no merge
  happens without a human. Recovery, not prevention, is the control — `main` is
  reconstructible from the operator's clone and the reflog.
- Two isolation-adjacent claims must stay in sync: this ADR and the enable skill's
  precondition list. `tests/test-forge-protection.sh` pins both.
