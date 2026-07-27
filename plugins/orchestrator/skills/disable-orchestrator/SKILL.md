---
name: disable-orchestrator
description: Removes the nightly loop cleanly — schedule, runtime job, loop config. The board and ALL its data are preserved. Use to pause or retire autonomy; re-enable anytime.
disable-model-invocation: true
---

# /orchestrator:disable-orchestrator

Idempotent removal of the loop. **The board survives**: the orchestrator is a
consumer of the state layer, not its owner.

## Remove (loop only)

1. The schedules: `.github/workflows/nightly-orchestrator.yml`, or the
   `nightly-orchestrator`/`deliver-digest` jobs in `.gitlab-ci.yml`, or the
   routine(s) (`/schedule` list → delete the nightly, retry, and delivery lanes),
   or — `local` runtime (ADR-0033) — the OS scheduler entries, which live
   **outside the repo** and therefore survive any amount of file deletion:
   macOS `launchctl bootout gui/$(id -u)/com.harness.orch.{nightly,retry}` then
   remove the plists from `~/Library/LaunchAgents/`; Linux
   `systemctl --user disable --now orch-{nightly,retry}.timer`; or the crontab
   lines. Verify with `launchctl list | grep orch` / `systemctl --user list-timers`
   — a disable that leaves a live timer is not a disable.
2. Loop config: `orchestrator/risk-policy.json`,
   `orchestrator/settings.orchestrator.json`, `orchestrator/adapters/deploy.sh`,
   `orchestrator/adapters/notify-digest.sh`, `orchestrator/notify.config.json`,
   `orchestrator/runtime/`, `orchestrator/digest-template.html`.
3. Optionally remove the scaffolded runtime files above (the state layer stays).

This removes the **loop** but leaves the `orchestrator` plugin installed, so
`/orchestrator:enable-orchestrator` stays available for a one-step re-enable. To
remove the skills/agent/workflow entirely, **uninstall the plugin**
(`/plugin uninstall orchestrator`) — that is the on/off gate now; there is no
park/unpark.

## Preserve (never touch)

- **The state layer**: `orchestrator/bin/orch`, `orchestrator/adapters/pm-*.js`,
  `orchestrator/state.config.json` — /core:handoff and the session hooks use them daily.
- **The board and all its data**: `.orch/` (none backend) or the external board
  (epics, specs, plans, statuses stay where they are).
- Past digests (`docs/reports/nightly/`), `docs/adr/`, CHANGELOG history.
- The committed `settings.json` (was never modified by enable).

## Verify

`bash tests/run-tests.sh` green; `orch state health` still ok;
`orch state pull-status` still returns the epics; no schedule left
(`gh workflow list` / `.gitlab-ci.yml` grep / `/schedule` list /
`launchctl list | grep orch` / `systemctl --user list-timers`).
Propose commit: `chore: disable nightly orchestrator (board preserved)`.
