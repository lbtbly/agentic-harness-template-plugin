---
Status: Accepted
Date: 2026-07-27
---

# ADR-0024 — Observe CI, then repair it

## Context

The harness was CI-*aware* but neither CI-*observant* nor CI-*reactive*. The only CI signal in
the entire codebase was one boolean derived from `statusCheckRollup` inside
`orch state pull-feedback`, and it carried two defects:

- `PENDING`, `QUEUED`, `IN_PROGRESS` and a null conclusion were **not** in the failure list, so
  a check that had not started counted as green. A PR whose CI had not begun read as
  merge-eligible.
- The result set was filtered with `select(.signal != null)`, so a red build on a PR that no
  operator had commented on was dropped entirely — invisible to the harness.

GitLab had no CI signal at all: `green` was hardcoded `null`.

Nothing anywhere called `gh run`, read a failed job log, waited for a check, or reacted to
redness. A red PR was skipped at merge time and never diagnosed. The agents that could do the
diagnosis existed (`debugger`, `test-runner`) but were never fed CI output, because the network
path was open — `api.github.com` is allowlisted in both the native sandbox and the devcontainer
firewall, and parity-tested — while the *code* and the *permissions* were not.

## Decision

Split the lane in two, matching the propose/apply separation the rest of the harness already uses.

**Observation** — `orch state pull-checks [--pr N]`, returning
`{pr, epicId, status, failedJobs:[{job, run, logExcerpt}]}` per open PR. `status` has **three**
states plus absence: `red | pending | green | none`. An unfinished check is not a passing one,
and "no checks configured" is not "checks passed". Log excerpts are a bounded tail
(`ORCH_CI_LOG_BYTES`, default 4000) and are never interpreted here. GitLab gets the real
pipeline status via `glab api`, replacing the hardcoded null.

**Reaction** — `fix-ci.js`: observe → triage → repair, pipelined so one PR can be repairing
while another is still being triaged. Triage runs as the `ci-triage` agent, which classifies and
proposes but never edits, matching `debugger.md`'s contract.

Two limits are structural rather than tuning:

1. **The agent cannot edit CI configuration.** `protect-policy-paths.sh` blocks
   `.github/workflows/**` and `.gitlab-ci.yml`, so only the code the workflow *runs* is in
   scope. A CI config that needs changing is a human's call, and that was already true.
2. **`flake`, `infra`, `dependency` and `unknown` escalate rather than repair.** "Fixing" a
   flake means retrying until it passes, which is the mechanism by which a real bug gets merged.
   A triage agent that cannot tell must say `unknown`, not guess.

Repair is bounded by rounds per PR (default 2) and by PR count per run (default 6), and stops
early when a patch could not be applied at all — a second attempt at an inapplicable fix is
waste. Every outcome, repaired or escalated, is written to the journal (ADR-0023) with a
`corrected` boolean, so the framework accumulates evidence about which CI failure classes it can
actually handle.

Permissions: `actions: read` on the orchestrator runtime workflow, and read-only
`Bash(gh run view|gh run list|gh pr checks|glab ci …)` in the unattended allowlist.
`Bash(gh pr merge:*)` stays **out** of the allowlist and a direct `main` push stays denied — the
builder still cannot land anything (ADR-0015).

Both loops gain a post-push check wait, so an epic is not marked `Needs-review` and forgotten
until the next morning's kickoff while its CI is still running.

## Consequences

`pull-feedback` now reports CI for every PR, not only signalled ones, and exposes `checks` with
the three-state value alongside the legacy `green` boolean (which now correctly excludes
pending).

The framework dogfoods this: a `workflow_run`-triggered triage job on this repo's own CI.

The remaining gap is deliberate: nothing auto-merges on green. Landing still goes through the
forge with branch protection and CODEOWNERS as the enforcer.
