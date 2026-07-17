---
name: run
description: Launches the run-to-completion loop: confirm scope, build/verify/improve each epic until its DoD passes, auto-merge low-risk, escalate the rest. Use for an unattended run.
argument-hint: [scope — all | first N]
disable-model-invocation: true
---

# /orchestrator:run — autonomous run-to-completion

Prerequisite: `/orchestrator:enable-orchestrator` has run (runtime + sandbox + branch
protection + a forge). This is the unattended "launch and it finishes" mode (vs the
scheduled/gated nightly loop, which still exists).

## ASK (AskUserQuestion)
1. **Scope**: `$ARGUMENTS` when provided (e.g. `all` or `first 3`); otherwise ask — "all epics in order" or "first N" (ask N). Then **list the selected epic
   names** (`orch state list-epics`) and get explicit confirmation before building.
2. Confirm budget/cadence guards if overriding defaults (`ORCH_MAX_CONCURRENT`,
   `ORCH_BUDGET_TOKENS`, `ORCH_WALLCLOCK_DEADLINE`, `ORCH_NOPROGRESS_K`).

## DO
1. Fold prior-run feedback: `orch state pull-feedback` — `/orch approve` → merge-eligible,
   `/orch revise: <notes>` → re-queue `Changes-requested` with the notes.
2. Plan (Phase 3): decompose oversized initiatives → epics; author a DoD contract for any
   epic missing one; `design-reviewer` validates each DoD vs intent. Epics stay out of the
   build until they carry a validated DoD.
3. Launch the driver:
   `bash orchestrator/runtime/run-to-done.sh <all|first> [N]`
   It waves-partitions by footprint, builds each wave concurrently (one worktree/epic,
   capped by `ORCH_MAX_CONCURRENT`, lowered by the usage throttle), runs the Phase 2
   dod-verify improve-until-done inner loop per epic, and lands low-risk done epics through
   the serial risk-gated merge queue (high-risk/dissent/no-progress → escalate).
4. On termination, read the `run-summary` and write/deliver the digest; escalated epics wait
   as PRs for `/orch approve|revise`, folded in at the next launch.

Never: bypass the sandbox/branch-protection; auto-merge a non-low risk level; weaken a test.
