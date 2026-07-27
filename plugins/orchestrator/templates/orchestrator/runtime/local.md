# Nightly orchestrator — `local` runtime (ADR-0033)

The loop on **your own machine**, scheduled by the OS. No forge secrets, no CI
minutes, no cloud dependency: the `claude` and `gh` you are already logged into
are the auth. Pick this when the project is solo and the laptop is where the
work happens anyway; pick `github-actions`/`gitlab-ci` when the loop must run
whether or not your machine is awake.

Everything is driven by `orchestrator/runtime/local-run.sh`, which wraps the
shared `run-with-limits.sh` with a lock, a scheduler-proof PATH, and the sandbox
check below.

## What you do NOT set
- `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` — the local CLI login is used.
  Setting either here only narrows what already works (and `ANTHROPIC_API_KEY`
  would silently move you onto the metered lane, ADR-0019).
- `GH_TOKEN` — `gh auth status` is the credential.
- `ORCH_PLUGIN_REPO_TOKEN` / `ORCH_PLUGIN_REPO_URL` — the plugin is installed
  locally, so nothing is fetched.

The one thing you may need to export is `ORCH_CORE_HOOKS` (the core plugin's
`hooks/` dir) if the auto-resolver misses it; it globs
`~/.claude/plugins/marketplaces/*/plugins/core/hooks`.

## Sandbox — read this before scheduling
Unattended runs are sandboxed (ADR-0008/0020). On the local lane the default is
the **native OS sandbox in its fail-closed form**, which means
`orchestrator/settings.orchestrator.json` must carry:

```json
"sandbox": { "enabled": true, "allowUnsandboxedCommands": false, "failIfUnavailable": true }
```

`failIfUnavailable: true` is the whole point — CI keeps it `false` because the
devcontainer is the outer wall there; on your machine there is no outer wall, so
a missing Seatbelt/bubblewrap must abort the run rather than let it proceed
unsandboxed next to your real credentials. `local-run.sh` refuses to start
otherwise. `/orchestrator:enable-orchestrator` flips it when you pick `local`.

The container lane is opt-in (`ORCH_LOCAL_SANDBOX=devcontainer`) and needs
preparation: inside the container there is no `claude` login and no installed
plugin, so `.devcontainer/` must mount your `~/.claude`, and
`ORCH_CORE_HOOKS_IN_CONTAINER` must name the in-container hooks path. Until you
have done that, leave it on the host lane.

## macOS — launchd
Two agents: the build lane, and the retry lane that resumes an expired
usage-limit pause (WS5). Write `~/Library/LaunchAgents/com.harness.orch.nightly.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.harness.orch.nightly</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/ABSOLUTE/PATH/TO/REPO/orchestrator/runtime/local-run.sh</string>
    <string>nightly</string>
  </array>
  <key>WorkingDirectory</key><string>/ABSOLUTE/PATH/TO/REPO</string>
  <key>EnvironmentVariables</key><dict>
    <!-- launchd starts from a minimal PATH and sources no profile. Paste the
         output of `echo $PATH` from your interactive shell here. -->
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>1</integer><key>Minute</key><integer>30</integer>
  </dict>
  <!-- launchd's own errors (before local-run.sh takes over logging) -->
  <key>StandardErrorPath</key><string>/ABSOLUTE/PATH/TO/REPO/.orch/logs/launchd.err</string>
</dict></plist>
```

The retry lane is the same file with `Label` …`.retry`, the argument `retry`,
and `StartCalendarInterval` replaced by `<key>StartInterval</key><integer>7200</integer>`.
It exits without spending a token unless it just restored an expired pause.

Load them (and re-load after any edit):

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.harness.orch.nightly.plist
launchctl bootout   gui/$(id -u)/com.harness.orch.nightly     # to remove
launchctl kickstart -p gui/$(id -u)/com.harness.orch.nightly  # run it now, to test
```

**Being awake is a precondition, not a detail.** A sleeping Mac runs nothing;
launchd fires a missed `StartCalendarInterval` on the next wake, which may be
your morning. To hold the window open, schedule a wake and keep the display off:
`sudo pmset repeat wakeorpoweron MTWRFSU 01:25:00` (check `man pmset` — syntax
varies by macOS release). A closed lid on battery still sleeps.

## Linux — systemd user timer
`~/.config/systemd/user/orch-nightly.service`:

```ini
[Service]
Type=oneshot
WorkingDirectory=/ABSOLUTE/PATH/TO/REPO
ExecStart=/bin/bash /ABSOLUTE/PATH/TO/REPO/orchestrator/runtime/local-run.sh nightly
Environment=PATH=/usr/local/bin:/usr/bin:/bin
```

`~/.config/systemd/user/orch-nightly.timer`:

```ini
[Timer]
OnCalendar=*-*-* 01:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user enable --now orch-nightly.timer
loginctl enable-linger "$USER"   # so it runs while you are logged out
```

Duplicate both as `orch-retry.*` with the `retry` argument and
`OnUnitActiveSec=2h`.

## cron — fallback
```cron
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
30 1 * * *  cd /ABSOLUTE/PATH/TO/REPO && bash orchestrator/runtime/local-run.sh nightly
0  */2 * * * cd /ABSOLUTE/PATH/TO/REPO && bash orchestrator/runtime/local-run.sh retry
```
On macOS `cron` needs Full Disk Access to reach your repo; launchd is the
supported path.

## Digest delivery (optional)
A third schedule at your `deliver_at`, running
`bash orchestrator/adapters/notify-digest.sh` with the delivery secrets in its
environment. Skip it entirely and read
`docs/reports/nightly/<date>/index.html` in the repo — on a local runtime the
digest is already on the machine you are sitting at.

## Budget
On the subscription lane the per-night **token cap is not a spend control** —
the binding constraint is your usage limit, and `run-with-limits.sh` already
checkpoints (`Paused`, `paused-until <ts>`) and lets the retry lane resume.
Set `ORCH_BUDGET_TOKENS` only if you want the loop to stop short of that limit
to leave headroom for your own foreground work. `ORCH_MAX_EPICS` defaults to
**2** here rather than 4: it is one machine, and it is also yours.

## Verifying it works
```bash
bash orchestrator/runtime/local-run.sh retry    # must exit fast, spending nothing
tail -f .orch/logs/local-$(date +%F)-retry.log
```
The retry lane with no expired pause is the free smoke test: it exercises PATH,
auth, hook resolution and the sandbox check without starting a build.
