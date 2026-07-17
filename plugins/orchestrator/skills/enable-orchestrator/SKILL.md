---
name: enable-orchestrator
description: Installs the nightly autonomous EPIC loop onto the interactive base — preconditions check, runtime + risk-policy setup, schedule. The state backend/board chosen at /core:new-project is REUSED, never re-provisioned.
disable-model-invocation: true
---

# /orchestrator:enable-orchestrator

Installs the heaviest opt-in plugin's runtime. The interactive base (plan-mode, human
plan-gate, per-PR OK) stays untouched — this ADDS the unattended Phase B on top.

> **Prerequisite.** This skill ships in the **`orchestrator`** plugin — if
> `/orchestrator:enable-orchestrator` isn't found, install it first:
> `/plugin install orchestrator@harness` then `/reload-plugins` (a freshly installed
> plugin's skills are "Unknown command" until reload). Installing the plugin is the
> on/off gate. This skill scaffolds the **runtime payload** into the project and
> wires the host scheduler.

## ASK (AskUserQuestion)

1. **Profile**: must be (or become) `autonomous` — confirm the upgrade; prior
   /core:new-project choices are preserved. Refuse to proceed otherwise.
2. **Preconditions** (verify, don't trust): green test suite? staging deploy
   command exists? sandbox (`.devcontainer/` with egress firewall — scaffolded by
   `/core:new-project` when devcontainer/autonomous is chosen; refuse and
   tell the user to add it if absent)? **Branch protection on `main`**
   (the deny rules cannot stop a refspec push like `HEAD:refs/heads/main`;
   only the forge can): verify via
   `gh api repos/:owner/:repo/branches/main/protection` (or the GitLab
   protected-branches API) that direct pushes are rejected and PR + review +
   status checks are required, and that the orchestrator's token **cannot
   bypass** it. If any precondition fails → stop and list what's missing.
   The dry-run phase (below) is the only exception.
3. **Runtime**: `routines` · `github-actions` · `gitlab-ci` (VPN/self-hosted →
   gitlab-ci).
4. **State backend**: REUSE `orchestrator/state.config.json` from /core:new-project.
   Only ask if it's still `none`-with-no-forge: which forge do PRs live on
   (`github`/`gitlab`)? — feedback is always forge-sourced. **A forge is mandatory
   to *run* the loop**: with `forge: none`, `/orchestrator:kickoff`,
   `pull-feedback`, and the per-PR OK cycle have no source — you can stage config
   but the loop cannot be driven. Set a forge before enabling for real; a no-forge
   enablement is config-staging only.
5. **Staging**: the exact deploy command + staging base URL → fills
   `orchestrator/adapters/deploy.sh`.
6. **Budget & cadence**: per-night token cap, max concurrent epics (start 2–4),
   and the schedule — the daily human step is `/orchestrator:kickoff` each **morning**
   (after you review the overnight PRs); the build fires on its own schedule after
   that (e.g. midday), runs through the day + overnight, and the next morning's
   digest is ready for review.
7. **Risk policy**: present `orchestrator/risk-policy.json` defaults (line
   thresholds, high-risk path globs, security-auditor requirement) — adjust to
   taste. It stays editable anytime; re-read every run.
8. **Digest delivery**: Slack and/or email, and the **time** it should arrive
   (`deliver_at`, e.g. 08:00 — before your review). Fills
   `orchestrator/notify.config.json` (channels, deliver_at, email_to). The message
   is a "went well / needs attention" summary with the HTML digest attached/linked.
   **State plainly**: delivery sends repo-derived content (epic titles, file paths,
   staging URLs) to external SaaS — VPN/data-residency teams should pick an
   internal relay or link-only delivery (`docs/SECURITY.md`).
9. **Secrets** (NAMES only): per runtime+backend, list the env vars to set and
   where (Actions secrets / GitLab masked+protected variables / routine env):
   `CLAUDE_CODE_OAUTH_TOKEN` (subscription, from `claude setup-token` — do NOT
   combine with `--bare`) or `ANTHROPIC_API_KEY` (metered), `GH_TOKEN` (GitHub App
   token, not a PAT) or `GITLAB_TOKEN`+`GITLAB_HOST`; plus delivery secrets if
   chosen (`SLACK_WEBHOOK_URL`, `SENDGRID_API_KEY`). Never ask for or write a value.
10. **Plugin marketplace location**: set the runner variable `ORCH_PLUGIN_REPO_URL`
   (github: repo *variable*; gitlab: `ORCH_PLUGIN_MARKETPLACE_URL`) to the marketplace
   repo the runner fetches the orchestrator plugin from — and, ONLY if that repo is
   private, the secret NAME `ORCH_PLUGIN_REPO_TOKEN` (fine-grained PAT, contents:read).

## DO

1. **Guard**: verify base invariants intact — committed `settings.json` still
   has plan-mode as `defaultMode` + `disableBypassPermissionsMode`; secret-guard
   wired. Refuse if not.
2. **Scaffold the payload** from the plugin into the project — plugins cannot write
   files at install, so this skill does it:
   `cp -R "${CLAUDE_PLUGIN_ROOT}/templates/orchestrator/." orchestrator/`. This overlays
   the runtime onto the state layer `/core:new-project` already placed
   (`bin/orch` + `state.config.json` stay; the copy adds `risk-policy.json`,
   `settings.orchestrator.json`, `bin/validate-dod`, `adapters/{deploy.sh,notify-digest.sh}`,
   `runtime/`, `digest-template.html`, `notify.config.json`). Idempotent: re-copy any
   missing file. The nightly verify step drives the app in a real browser, so confirm
   `.mcp.json` has the `playwright` server (new-project's autonomous profile adds it).
3. **Fill** deploy.sh (the asked command), risk-policy.json (asked thresholds),
   and the chosen runtime template's schedule/cadence values.
4. **Install the runtime + schedules**: github-actions → copy
   `orchestrator/runtime/github-actions.yml` → `.github/workflows/nightly-orchestrator.yml`
   (Bash write — the path is policy-protected), set the build/retry/**delivery**
   crons; gitlab-ci → merge `orchestrator/runtime/gitlab-ci.yml` into `.gitlab-ci.yml`
   + tell the user to create the **three** pipeline schedules
   (`ORCH_NIGHTLY` / `ORCH_RETRY` / `ORCH_DELIVER`); routines → walk through
   `orchestrator/runtime/routines.md` (build + retry + a delivery routine at
   `deliver_at`). Skip the delivery schedule if no channel was chosen.
   **Headless plugin availability:** the build runs `claude -p` and invokes the
   `nightly-orchestrator` workflow, which lives in the `orchestrator` **plugin**,
   not the project. The runner MUST have the plugin available — every runtime
   template includes a step that adds the marketplace + installs the plugin
   (or passes `--plugin-dir`) before the build. Confirm it's wired for the chosen runtime.
5. **Seed the backlog**: for each initiative the operator names, `orch state
   push-epic` (state `Needs-plan`). Plans are approved live at kickoff
   (Phase A) — nothing builds without an approved plan.
6. **Verify**: `bash tests/run-tests.sh` green; `jq .` on every touched
   JSON; `orch state health` ok; push/pull roundtrip; **dry-run Phase A** on the
   seeded epics — reconcile + plan-gate + partition, NO merge, NO deploy
   (prove 2 disjoint epics before enabling deploy).
7. **Report** the morning ritual to the operator: read
   `docs/reports/nightly/<date>/index.html` → test on staging → `/orch approve` or
   `/orch revise: <notes>` per PR → next kickoff merges Approved+green.
8. **Propose commit**: `feat: enable nightly orchestrator (<runtime>/<backend>)`.

Never: touch the committed `settings.json`; store a secret value; enable
auto-merge without the per-PR operator OK (it does not exist in this gated design).

## Run-to-completion mode

`/orchestrator:run` adds an unattended **run-until-done** mode with **risk-gated
auto-merge**. Extra setup on top of the gated preconditions above:
- **Branch protection, specified by risk** (verify at the forge; cannot be set from here):
  required **status checks** green + token cannot bypass; **low-risk** merges are approved by
  the judge panel's review (a distinct reviewer identity), **high-risk** paths require a
  **human** review via **CODEOWNERS**.
- **Install CODEOWNERS**: copy `${CLAUDE_PLUGIN_ROOT}/templates/.github/CODEOWNERS` into the
  project's `.github/CODEOWNERS`, replace `@your-org/reviewers` with the real owners, and keep
  it in sync with `risk-policy.json` `highRiskPaths` (the parity test enforces this).
- `requiredReviewByRisk` in `risk-policy.json` records the policy (`low: judge-panel`,
  `high: human-codeowners`).
