# orchestrator

The nightly autonomous EPIC loop for the template harness — plan-gated,
human-merged, risk-classified, and limit-resilient (ADR-0008).

## The two-prompt model (initializer vs coder)

Autonomous coding splits into two distinct prompts, and this plugin is only the
second one:

- **Initializer** — `/core:new-project`. Runs **once** to build the
  environment: the contract (`CLAUDE.md`), the state layer (`orch` + `.orch/`),
  the `feature_list.json` anti-drift contract, and the plugin set. It never writes
  product code.
- **Coder** — the `nightly-orchestrator` workflow in this plugin. Runs **every
  night**, one fresh-context session per unit of work. It never re-initializes; it
  reconciles from git+forge (the idempotent source of truth) and builds strictly
  against approved plans and each epic's `feature_list.json`.

Keeping these separate is what lets the loop stay stateless between nights: a
killed run is always safe to re-enter because reality (branches, PRs, `.orch/`
state) — not a session file — is the source of truth.

## What ships here

- **Skills**: `enable-orchestrator` (scaffolds the runtime + host scheduler into a
  project), `disable-orchestrator` (removes the loop; the board is preserved),
  `kickoff` (the daily morning driver).
- **Agent**: `integration-checker` (verifies overlapping epics still work together).
- **Workflow**: `nightly-orchestrator` (Phase B — build → verify-like-a-user →
  block-check → integrate → consistency → deploy → gardening → digest).
- **Templates**: the runtime payload scaffolded into the project by
  `enable-orchestrator` (`risk-policy.json`, `settings.orchestrator.json`,
  `runtime/*`, `adapters/{deploy,notify-digest}.sh`, `digest-template.html`).

## Autonomy guardrails baked in

- **Done is decided by `feature_list.json`, not the agent.** Every feature has E2E
  `steps` and `passes:false`; a worker may only flip `passes` after driving the
  steps in a **real browser** (playwright MCP). Editing/removing steps or
  adding/deleting features is prohibited (CLAUDE.md rule 2).
- **Test like a user, not like CI.** The verify step is browser-driven. Surfaces the
  browser can't see (native OS dialogs) are recorded as `blindspots` and flagged in
  the digest — never silently passed.
- **Non-progress escalates.** An epic that fails to land green `BLOCK_AFTER_ATTEMPTS`
  nights is marked `Blocked` and escalated via the notifications hook — never looped
  forever.
- **A reserved gardening lane** spends spare capacity on entropy control
  (doc-health, scoped simplify, deviation scan) instead of only features.
- **Nothing merges to `main` here.** Approved+green PRs merge at the next kickoff,
  operator present.

## Turn it on

```
/plugin install orchestrator@harness
/orchestrator:enable-orchestrator
```

Requires the `autonomous` profile, green tests, a staging deploy, the
egress-firewalled sandbox, branch protection on `main`, and a forge (feedback is
forge-sourced — a no-forge setup can only stage config, not drive the loop).
