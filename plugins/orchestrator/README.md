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
  `kickoff` (the daily morning driver), `watch` (live agent tree for a
  run-to-completion build), `run`, `plan`, `goals`, `compost`.
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
- **It tells you what happened, per project.** `adapters/notify-slack.sh` posts to
  one channel per repo (`cchar-<repo>`, created on first use) at four moments: wave
  admitted, epic landed, epic escalated, run finished with its `stopped_by`. It posts
  as a **bot**, so the loop's messages are never confusable with yours, and it
  **no-ops silently** without `SLACK_BOT_TOKEN` — a notification may never break a
  build. Uncomment `slack.com` in the egress allowlist or it fails closed.
- **The run is observable while it runs.** `run-to-done.sh` streams the engine to
  `.orch/logs/run-<date>.jsonl` and its stderr beside it; `/orchestrator:watch`
  renders that as a live agent tree. A failed wave prints its reason instead of
  escalating silently. Note what this is *not*: a headless run has no interactive
  channel, so a subagent can never ask you a question mid-run — uncertainty fails
  closed to `Needs-review`/`Blocked` with a note, and you answer on the PR.

## Turn it on

```
/plugin install orchestrator@harness
/orchestrator:enable-orchestrator
```

Requires the `autonomous` profile, green tests, a staging deploy, the
egress-firewalled sandbox, branch protection on `main`, and a forge (feedback is
forge-sourced — a no-forge setup can only stage config, not drive the loop).

Two of those bend where the environment cannot supply them, by decision rather
than by drift: where the forge **cannot** protect `main` (a private repo on a
free GitHub plan has neither branch protection nor rulesets), the operator may
accept that once via `forgeProtection: "unavailable-accepted"`, which
force-disables auto-merge so every merge stays human (ADR-0032); and the `local`
runtime may substitute a **fail-closed** OS sandbox for the devcontainer on the
operator's own machine (ADR-0033), where it also needs no secrets at all.

## How the workflows execute (honest note)

`workflows/*.js` are **prompt-interpreted specs, not executed JavaScript**: the
runtime invokes `claude -p "Run the nightly-orchestrator workflow …"` and the
model interprets `agent()` / `parallel()` / `phase()` / `budget` by convention.
This is tested at the contract level (see tests/), but the semantics live in the
model's reading, not a JS engine. A Claude Agent SDK port is the recorded
follow-up (CONTRIBUTING.md backlog) — it must first verify the subscription-token
auth lane (ADR-0019).
