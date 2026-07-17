---
name: plan
description: "Turns Needs-plan initiatives into Planned epics: planner authors the DoD, validate-dod checks it, an independent reviewer gates it. Use inside /orchestrator:run or to pre-plan."
---

# /orchestrator:plan

For each initiative to plan (from `orch state list-epics` in state `Needs-plan`, or an
initiative id passed in):

1. **Decompose + author** — dispatch the `planner` agent on the initiative. It returns one
   or more epics, each with an epic record and a `.orch/epics/<id>/feature_list.json`.
2. **Validate the contract** — run `orchestrator/bin/validate-dod <epic-record> <feature_list>`
   for each epic. On non-zero, return the reasons to `planner` and re-author. An epic whose
   DoD cannot be completed is set aside for human escalation (never built blind).
3. **Independent design review** — dispatch the `design-reviewer` agent on each epic's DoD
   vs the initiative's intent (it never edits; it returns READY / READY-WITH-FIXES /
   NEEDS-REWORK). Record the verdict in the epic record's `designReview`. NEEDS-REWORK loops
   back to step 1; READY-WITH-FIXES applies the fixes then re-reviews. The reviewer is
   independent of the planner (no self-grading).
4. **Persist** — `orch state push-epic` each epic (state `Planned`, footprint, deps,
   riskHints, complexity, dodPath, designReview). Nothing is marked `Planned` until validate-dod exits 0
   AND the design review is not NEEDS-REWORK.

GUARDRAILS: the planner authors from the initiative's INTENT, never bloats acceptance
criteria to be easy to pass; the DoD is the termination authority; builder,
DoD-reviewer, and verifier are three different agents.

REUSE NOTE: if the project has a dedicated planning plugin, replace steps 1–2 with a call
to its skills and keep steps 3–4 (design-review + persist) — the `validate-dod` contract is
the stable seam.
