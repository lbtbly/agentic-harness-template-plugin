# Nightly orchestrator — Anthropic Routines runtime (ADR-0008)

Zero infra, research preview — the GitHub Actions / GitLab CI templates are the
battle-tested fallbacks.

## Setup (via /schedule or claude.ai/code/routines)
- Schedule: nightly at your kickoff+N hours (e.g. 01:00), repo connected with
  branch-push allowed for `orch/*` only.
- Prompt: `Run bash orchestrator/runtime/run-with-limits.sh from the repo root.`
- Secrets (routine env), ONE auth lane: CLAUDE_CODE_OAUTH_TOKEN (subscription, from `claude setup-token`; never combine with --bare) OR ANTHROPIC_API_KEY (metered — it takes precedence). Plus GH_TOKEN or GITLAB_TOKEN(+GITLAB_HOST). Cloud routines run on your claude.ai account and need no model key at all.
- **Plugin availability:** the `nightly-orchestrator` workflow lives in the
  `orchestrator` plugin, not the repo. Ensure the routine's environment has
  it installed (`/plugin install orchestrator@harness` in the
  connected environment), or clone the marketplace repo in the prompt and export
  `ORCH_PLUGIN_DIR=<clone>/plugins/orchestrator` before the run-with-limits
  call so it passes `--plugin-dir`.

## Digest delivery (optional)
- Add a THIRD routine at your chosen `deliver_at` (e.g. 08:00) with the prompt
  `Run bash orchestrator/adapters/notify-digest.sh from the repo root.` and the
  delivery secrets in its env (SLACK_WEBHOOK_URL and/or SENDGRID_API_KEY).
- It sends the "went well / needs attention" summary + the HTML digest to
  Slack/email right before your morning review, independent of when the build
  finished. Configured in `orchestrator/notify.config.json`.

## Usage-limit behavior (WS5)
- Routines have a per-account **daily run cap** (resets UTC midnight) and NO
  built-in pause-and-resume on limits.
- The wrapper handles it: on a hard stop it marks epics `Paused` with
  `paused-until <ts>` and exits cleanly. Add a SECOND routine every 2h as the
  retry lane — it no-ops while the pause is active, resumes after.
- If the routine itself is rejected by the daily run cap, nothing runs — the
  next scheduled fire re-enters; state is reconciled from git+forge, so a
  missed night can never corrupt anything.
