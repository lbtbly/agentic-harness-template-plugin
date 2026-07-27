---
Status: Accepted
Date: 2026-07-27
---

# ADR-0033 — `local` runtime: the nightly loop on the operator's own machine

Extends ADR-0008's runtime list (`routines | github-actions | gitlab-ci`).

## Context
All three shipped runtimes are remote. `routines` runs on the claude.ai account,
`github-actions` on GitHub's runners, `gitlab-ci` on a GitLab runner. A solo operator
who wants the loop to run overnight **on the laptop that already has an authenticated
`claude` and `gh`** has no option, and picking `github-actions` by elimination drags in
consequences that exist only because the work moved off the machine:

- three secrets to mint, store and rotate — `CLAUDE_CODE_OAUTH_TOKEN` (or
  `ANTHROPIC_API_KEY`), a forge token, and `ORCH_PLUGIN_REPO_TOKEN` when the marketplace
  repo is private — where an on-device run needs **none**;
- CI minutes, and a plugin-fetch step that exists purely because the runner has no
  installed plugin (`run-with-limits.sh` already notes that local runs can skip it);
- a long-lived model token sitting in a forge secret store, which is a strictly larger
  exposure than the local keychain credential the operator already has.

`run-with-limits.sh` is already runtime-agnostic and local-capable; what is missing is a
scheduler recipe and an option in the ASK.

## Decision
Add `local` as a fourth runtime: an OS scheduler on the operator's machine
(**launchd** on macOS, **systemd timer** on Linux, cron as the fallback) invoking
`orchestrator/runtime/run-with-limits.sh` on the same build/retry lanes as every other
runtime. `ORCH_LANE` distinguishes them exactly as today.

- **Auth: none stored.** The local `claude` and `gh` credentials are used as-is. Neither
  `CLAUDE_CODE_OAUTH_TOKEN` nor a forge token is set for this runtime — a value in the
  environment would only *narrow* what already works.
- **Sandbox.** The devcontainer precondition is satisfied by `devcontainer exec` when a
  container runtime is present. Where it is not, the local lane runs on the host with
  `sandbox.failIfUnavailable` flipped to **`true`** in `settings.orchestrator.json`:
  one isolation layer instead of ADR-0020's two, but a **fail-closed** one — the run
  aborts if Seatbelt/bubblewrap is unavailable rather than silently running unsandboxed.
- **Budget.** The per-night cap is asked **per auth lane**. Metered
  (`ANTHROPIC_API_KEY`) → a token cap is a cost control and is asked. Subscription →
  the binding constraint is the usage limit, which `run-with-limits.sh` already handles
  by checkpointing and resuming; the cap defaults and is not put to the operator as a
  spend question it isn't.

## Consequences
- The loop becomes usable with zero forge secrets, zero CI minutes and no cloud
  dependency — the natural shape for the solo/private/free-plan project of ADR-0032.
- It runs only while the machine is awake and unlocked. launchd's `StartCalendarInterval`
  fires on wake if the window was missed; a closed lid means the night is skipped. State
  is reconciled from git+forge (ADR-0008), so a skipped night is never corrupting — but
  "it ran" is no longer something the operator can assume.
- Concurrency is bounded by one machine: `ORCH_MAX_EPICS` should start lower than on a
  runner, and a build competes with the operator's own foreground work.
- A fourth runtime template to keep in parity with the other three (lanes, plugin
  resolution, digest delivery). `tests/test-local-runtime.sh` pins the lane and
  no-secret properties.
- The native-sandbox trade is recorded here rather than amending ADR-0020: on CI the
  devcontainer stays mandatory; only the local lane may substitute a fail-closed OS
  sandbox for it.
