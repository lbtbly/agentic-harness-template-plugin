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
/plugin marketplace add lambertstudi/agentic-harness-template-plugin
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
- **Run-to-completion (`/orchestrator:run`).** Launch with a confirmed scope and
  it runs until the scope is drained: low-risk epics auto-merge after the
  independent DoD passes; everything else escalates. Keeps the plan gate,
  trades the per-PR merge gate for a risk gate. Turn this on only after the
  gated flavor has earned your trust.

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

## The safety model

- **Secrets stay secret** — gitignore + deny rules + secret-guard hook; names,
  never values; egress-firewalled devcontainer + native OS sandbox for
  unattended runs.
- **No self-elevation** — the agent cannot edit its own permissions, guardrail
  hooks, or allow-listed scripts (protect-paths / protect-policy-paths).
- **Main is gated twice** — branch protection the token cannot bypass, plus
  CODEOWNERS human review on every high-risk path (parity-tested against
  `risk-policy.json`).
- **External bounds** — budget, wall-clock, no-progress, thrash and safety
  guards; a usage throttle that slows, then pauses, then auto-resumes on reset.
- **Escalation is the default** — unknown risk classifies high; a crashed
  checker keeps the deploy gate closed; a red post-merge suite auto-reverts.

## Layout

```
.claude-plugin/marketplace.json   the marketplace (5 plugins)
plugins/core/                     scaffolder, guard hooks, state layer, review agents
plugins/orchestrator/             the loop: skills, planner, workflows, runtime, risk policy
plugins/workbench/                security-auditor + extra specialists
plugins/formatting/  plugins/ci/  small opt-ins
tests/                            27 suites (counts are minimums); run: bash tests/run-tests.sh
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
