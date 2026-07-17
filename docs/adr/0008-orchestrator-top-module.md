---
Status: Accepted
Date: 2026-07-02
---

# ADR-0008 — Orchestrator as opt-in top module with pluggable runtimes

> ADR-0006: historical, unported — the reference implementation's decision;
> see docs/adr/README.md.

## Context
The nightly agentic orchestrator (`conception/2026-07-01-agentic-orchestrator-design.md`)
runs several EPICs in parallel, unattended. Two framings competed: a *mode switch*
(interactive template ⟷ autonomous template) vs an *additive module*. The orchestrator's
own Phase A (reconcile, plan gate, partition) is interactive CLI work — the human-in-the-
loop base is never turned off, so a mode switch is incoherent. The original design also
listed only Anthropic Routines + GitHub Actions as runtimes, while the team's real forge
is GitLab behind a VPN.

## Decision
- The orchestrator is the **heaviest opt-in module** (ADR-0006), installed onto the
  always-interactive base by `/enable-orchestrator` and removed by
  `/disable-orchestrator`. `requires`: state/pm-adapter (ADR-0007), sandbox
  (devcontainer egress firewall — mandatory for unattended runs), a CI/runtime backend,
  session-memory, specialized-agents.
- **Runtimes**: `routines` | `github-actions` | **`gitlab-ci`** (new — scheduled pipeline
  on a self-hosted runner, masked+protected CI/CD variables, `glab` for state+feedback).
- **HITL invariants survive every mode**: plan approval gates any build; merge to `main`
  requires a per-PR operator OK (never bulk) + green checks; the committed
  `settings.json` (plan-mode, `disableBypassPermissionsMode`) is untouched — the
  orchestrator runs under its own `settings.orchestrator.json` inside a sandbox.
- **Risk-gated review**: `orchestrator/risk-policy.json` (line thresholds, path globs
  forcing high risk — auth/migrations/infra/CI, which levels require a `security-auditor`
  pass before OK-eligibility) is proposed at enable time and editable anytime — re-read
  each run.
- **Immutable daily digest**: one self-contained HTML file per day
  (`docs/reports/nightly/<date>.html`, mirrored via `pushDigest`); same-date re-runs
  append a run section, never overwrite.
- **Usage-limit resilience**: rate limits (429) ride on `claude -p`'s built-in
  backoff (prefer the CLI over the Agent SDK, which crashes on 429); hard stops
  (weekly/monthly caps, routine daily run-cap) checkpoint (`paused-until <ts>` via
  `push-status`), reschedule to the reset time via the runtime's own scheduler, and
  **reconcile from the forge on resume** — git+forge is the idempotent source of truth,
  so a killed run is always safe to re-enter. Budget caps are cost controls, distinct
  from rate handling.
- `/disable-orchestrator` removes the module's files and schedule but **preserves the
  board and all its data**, ADRs, and CHANGELOG history.

## Consequences
- A project can adopt the loop the day its preconditions exist (green suite, staging,
  sandbox, budget) instead of at scaffold time — and drop it without losing state.
- Three runtime templates to maintain; the GitLab path makes the loop usable behind a
  VPN with no Anthropic-cloud dependency.
- Corrects the design doc's stale claim that headless bills from a separate Agent SDK
  credit pool since 2026-06-15 — that change was paused; verify current billing at
  implementation time.
