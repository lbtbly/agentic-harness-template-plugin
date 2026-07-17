---
name: kickoff
description: The DAILY driver of the autonomous loop, run each MORNING right after you've reviewed the overnight PRs. Reads your fresh OK/revise comments, merges the OK'd PRs (and verifies the merged branch), queues the commented ones for rework, adds/plans new EPICs, partitions — then the scheduled build works through the day + overnight.
disable-model-invocation: true
---

# /orchestrator:kickoff — the daily driver (run it each morning, after review)

Prerequisite: the orchestrator is enabled (`/orchestrator:enable-orchestrator` did the one-time
setup). The daily order is **review first, then kickoff**:

1. **(Before /orchestrator:kickoff — you)** Open the overnight digest
   (`docs/reports/nightly/<date>/index.html`, or the Slack/email copy) and, on each PR,
   leave `/orch approve` or `/orch revise: <notes>`. `/orchestrator:kickoff` reads exactly those
   fresh signals — so comment before you run it.

Then run `/orchestrator:kickoff` in the CLI / Claude Code web (interactive — plan approval needs
a live human):

2. **Sync state, then read the morning's feedback**:
   a. If the build runs on CI (`none` backend), pull last night's state first —
      the runner commits it to the `orch/state` branch:
      `git fetch origin orch/state && git checkout origin/orch/state -- .orch docs/reports/nightly`
   b. `orch state pull-feedback` (always from the forge: gh/glab; signals are
      accepted from owners/members/collaborators only and carry the `epicId`
      resolved from the `orch/<id>` PR branch). Split PRs into OK'd vs
      commented-for-rework.
3. **Risk gate, then merge the OK'd + green PRs to `main`** — one at a time, you present:
   a. **Risk check (mandatory, before any merge)**: classify each OK'd PR against
      `orchestrator/risk-policy.json` (lines changed vs thresholds; touched paths vs
      `highRiskPaths`). A **high-risk** PR is merge-eligible only if a
      `security-auditor` pass is recorded on the PR (a review/comment from the audit) —
      if missing, run the audit now or skip the PR (it stays Needs-review).
   b. **Merge**: `gh pr merge <n> --squash` (or `glab mr merge`) into the PR's base —
      the operator-present moment `main` moves, per PR, never bulk. Then
      `orch state push-status --id <epic> --state Merged --pr <n>`.
   c. **Verify the merged branch is healthy**: full suite on `main` after each merge;
      a red merge is reverted immediately and its epic goes to `Changes-requested`
      with the failure noted.
   d. **Recreate the integration branch** from the new `main`
      (`git branch -f orch/integration main && git push origin +orch/integration`)
      so tonight's integration starts clean instead of accreting stale merges.
4. **Queue the commented PRs for rework** — set each `revise`'d epic →
   `Changes-requested` with your notes attached (`push-status`). This is the
   "back from a negative review" state: it's awaiting rework, distinct from
   `In-progress` (a worker actively on it). Tonight's worker folds the notes in;
   minor tweak or full rework, the plan decides.
4b. **Review→rule capture (the improvement loop)** — classify each revise note:
   a **plan defect** (this epic got it wrong → rework covers it) or
   **missing context** (any future worker would make the same mistake — a convention,
   gotcha, or constraint the environment never told it). For each
   missing-context note, propose a one-line rule for `.claude/rules/` (with
   `since:`/`expires:` metadata) or a CODEMAP gotcha — **you approve each
   proposed rule line** before it's written; skipped proposals are dropped, not
   remembered. Every recurring review comment is a missing rule.
5. **Add / plan new EPICs** (in parallel with the reworks) — triage the backlog;
   for each `Needs-plan` epic the `architect` drafts a plan (`design-reviewer` can
   critique), you **approve it live** → `Planned`. Nothing builds without your
   approval here.
6. **Partition & detach** — compute each to-build epic's file footprint, flag
   overlaps, enforce the single-writer rule on hotspots. Then detach: the scheduled
   build (routines / GitHub Actions / GitLab CI) runs `nightly-orchestrator.js`
   through the day + overnight — it builds every epic in `Planned` **or**
   `Changes-requested` (new work and rework), moving each to `In-progress` while a
   worker is on it, then `Needs-review` when its PR is ready — one PR each — and
   writes tomorrow's digest for your next review.

Guardrails: no epic builds without an approved plan; merges happen here, observably,
never silently; you never bulk-approve — one signal per PR. Skipped a day? Just run
`/orchestrator:kickoff` the next morning — reconcile-from-reality (git + forge) makes it safe.
