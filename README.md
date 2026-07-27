# The Overnight Harness

Run a coding agent unattended overnight on Claude Code — packaged as a plugin
marketplace, gated where it counts, and built around the one hard problem:
knowing when the work is actually **done**.

Built from the field manual *"The Overnight Harness"*; every subsystem was
verified against the July 2026 state of the art before implementation
(see [docs/DEVIATIONS.md](docs/DEVIATIONS.md) for what changed and why).
**Platforms:** macOS / Linux / WSL2 — native Windows is unsupported (hooks and the
state CLI are POSIX shell + jq). **Claude Code native, by design** — the product's edge is the enforcement and
autonomy layer (hooks, permission profiles, the loop), which only Claude Code
runs; there is deliberately no AGENTS.md interop (ADR-0022).

## Install

```
/plugin marketplace add lbtbly/agentic-harness-template-plugin
/plugin install core@harness
/reload-plugins        # REQUIRED: a freshly installed plugin's skills are
                       # "Unknown command" until you reload
```

Then stand up a project and, when ready for autonomy:

```
/core:new-project                      # the initializer: questionnaire → green scaffold
/plugin install orchestrator@harness   # the overnight loop
/reload-plugins
/orchestrator:enable-orchestrator      # six verified preconditions + runtime + schedule
```

Opt-in extras: `formatting@harness` (format-on-edit), `workbench@harness`
(security-auditor, refactorer, researcher, test-runner), `ci@harness`
(PR-assistant CI templates).

## The two flavors

- **Gated nightly (recommended default).** A scheduled build produces one PR per
  epic overnight; each morning you review the digest, leave `/orch approve` or
  `/orch revise: <notes>` per PR, and run `/orchestrator:kickoff`. Nothing
  reaches `main` without your per-PR OK. Current research still shows most
  agent merges are human-governed — start here.
- **Run-to-completion (`/orchestrator:run`).** Point it at an initiative or the whole
  board and it drains the scope: each round admits a wave — dependency-topological on
  `deps[]`, then footprint-disjoint, then capped by the usage throttle — builds it,
  verifies it, and lands what has earned the right to land. Everything else escalates.
  Re-entry is safe: the loop reconstructs its state from the board, never from memory.

**Autonomy is earned, not chosen.** Auto-merge needs the risk policy to allow it *and* the
epic's class (`<footprint-root>/<complexity>`) to have reached tier `auto` — 20 runs at 95%
verified pass. A fresh install has no ledger, so nothing auto-merges until a class has a
record. Slow to grant, fast to revoke (ADR-0026).

## The definition of done (the crux)

Per-epic `feature_list.json` — JSON, user-level E2E steps, `passes:false`, and a
hard prohibition: the only permitted mutation is flipping `passes` to true after
a real end-to-end pass. Verification is four stages, all independent of the
builder: tests at every level → browser E2E as a user → acceptance assertions →
an adversarial judge panel (distinct lenses, distinct models, strict majority +
blocking dissent). The verdict — not the agent — decides termination.

No self-grading anywhere: planner authors the DoD → design-reviewer validates it
→ builder implements → judge panel verifies → the forge (branch protection +
CODEOWNERS) gates the merge.

## The board is the golden source

Initiatives, epics and tasks live on your board — Jira, Notion, Linear, GitHub, GitLab — and
that is what "exists". Each backend answers at whatever fidelity it has: **Linear** maps the
whole hierarchy natively (Issues, sub-issues, Projects as the initiative tier — ADR-0029),
**Jira** uses Epics with parent-linked children, and the rest derive the tier from the record.
`.orch/` is a working mirror the agents read while work is in flight,
reconciled back to the board, which always wins. Cards are **claimed with an expiring lease**,
so two agents never take the same work and a crashed agent's card returns to the pool instead of
being stranded. A card a human wrote is picked up like any other; the harness does not have to
have invented it (ADR-0027).

## When it gets something wrong

Three loops close on the harness itself:

- **The journal** (ADR-0023) — an append-only `.orch/journal/*.jsonl` written by hooks, not by
  the agent: guard blocks, failing commands, human corrections, model escalations, reverts. It
  records classifications, never content. `/core:export-journal` produces a redacted bundle you
  can carry back to this repo so the next install repeats fewer of this one's mistakes.
- **Standing goals** (ADR-0028) — a merged epic's acceptance criteria graduate into shell
  predicates re-verified daily. `passes:true` used to be terminal; now finished work keeps being
  checked, and a silent regression surfaces the next morning.
- **CI** (ADR-0024) — `orch state pull-checks` reads the failing job's log, and the `fix-ci`
  lane repairs the mechanical failures. Flake, infra and dependency failures escalate rather
  than being retried until they pass.

`/orchestrator:compost` reads all three weekly and proposes **at most three** framework fixes,
asking the same question each time: is this a rule the harness enforced after the fact that it
should have taught up front? A recurring guard block is a missing line in CLAUDE.md; a recurring
human correction is a framework problem, not an operator problem. Proposals only — the guard
hooks stop a harness rewriting its own guardrails, which is the point of having them.

`/core:doctor` reports the other side of the bill: what the harness itself costs you per turn —
CLAUDE.md size, hook injections, skill sizes, MCP schemas — and what to cut. It will not propose
cutting a security rule to save tokens.

## The safety model

- **Secrets stay secret** — gitignore + deny rules + secret-guard hook; names,
  never values; egress-firewalled devcontainer + native OS sandbox for
  unattended runs.
- **No self-elevation** — the agent cannot edit its own permissions, guardrail
  hooks, or allow-listed scripts (protect-paths / protect-policy-paths).
- **Main is gated twice** — branch protection the token cannot bypass, plus
  CODEOWNERS human review on every high-risk path (parity-tested against
  `risk-policy.json`).
- **External bounds** — budget, wall-clock, no-progress, thrash, dependency-deadlock
  and safety guards; a usage throttle that halves concurrency at 80% and pauses at 95%,
  then auto-resumes on reset. A guard that cannot measure says so: a budget cap with no
  spend signal warns loudly rather than reporting itself as guarded.
- **Escalation is the default** — unknown risk classifies high; a crashed
  checker keeps the deploy gate closed; a red post-merge suite auto-reverts.

## Layout

```
.claude-plugin/marketplace.json   the marketplace (5 plugins)
plugins/core/                     scaffolder, guard + journal hooks, state layer, trust ledger, review agents
plugins/orchestrator/             the loop: skills, planner, ci-triage, workflows, runtime, goal sentinel, risk policy
plugins/workbench/                security-auditor + extra specialists
plugins/formatting/  plugins/ci/  small opt-ins
tests/                            34 suites (counts are minimums); run: bash tests/run-tests.sh
docs/DEVIATIONS.md                verified deviations from the field manual
```

## Tests

```
bash tests/run-tests.sh
```

Every subsystem shipped test-first: the DoD contract and verifier, the planner
contracts, the state layer (parallel branches merge conflict-free), the driver
guards and throttle, the risk gate (fail-closed), the guard hooks, and the
packaging manifests.
