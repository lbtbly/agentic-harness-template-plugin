#!/bin/bash
# Local runtime entrypoint (ADR-0033) — the nightly loop on the operator's own
# machine, scheduled by launchd / systemd / cron. Setup: runtime/local.md.
#
# What this adds around run-with-limits.sh, which is otherwise runtime-agnostic:
#   1. NO stored credentials. The local `claude` and `gh` logins are used as-is —
#      CLAUDE_CODE_OAUTH_TOKEN and a forge token are deliberately NOT set here.
#   2. Sandbox selection: devcontainer when a container runtime is present,
#      else the host with the native OS sandbox required to be FAIL-CLOSED.
#   3. A scheduler-proof environment: launchd/cron give a minimal PATH and no
#      shell profile, so `claude`, `gh` and `jq` are verified before spending a
#      token, and the run is logged instead of vanishing into the void.
#   4. One run at a time: the build lane and the 2-hourly retry lane share a
#      machine, unlike CI where the runtime enforces concurrency.
#
# Usage: bash orchestrator/runtime/local-run.sh [nightly|retry]
set -u

LANE="${1:-${ORCH_LANE:-nightly}}"
R="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
cd "$R" 2>/dev/null || { echo "cannot enter project dir: $R" >&2; exit 78; }

LOG_DIR="$R/.orch/logs"; mkdir -p "$LOG_DIR"
# Self-ignoring: `.orch` is force-added to the orch/state branch by the CI runtimes,
# and a project's own .gitignore is not ours to assume. Machine-local logs must not
# become commits.
[ -f "$LOG_DIR/.gitignore" ] || printf '*\n!.gitignore\n' > "$LOG_DIR/.gitignore"
LOG="$LOG_DIR/local-$(date +%F)-$LANE.log"
# Scheduled: everything to the log, since nobody is watching. Interactive (the
# documented smoke test): to the terminal AND the log, so `local-run.sh retry`
# tells you what it decided instead of appearing to do nothing.
if [ -t 1 ]; then exec > >(tee -a "$LOG") 2>&1; else exec >>"$LOG" 2>&1; fi
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) lane=$LANE ==="

# --- single-instance lock (mkdir is atomic everywhere; no flock on macOS) -----
LOCK="$R/.orch/.local-run.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  # a lock older than the run timeout is a crashed run, not a live one
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +"${ORCH_LOCK_STALE_MIN:-360}" 2>/dev/null)" ]; then
    echo "stale lock (> ${ORCH_LOCK_STALE_MIN:-360}m) — reclaiming."; rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || exit 0
  else
    echo "another local run holds the lock — exiting without spending a token."; exit 0
  fi
fi
trap 'rm -rf "$LOCK"' EXIT INT TERM

# --- scheduler-proof PATH ----------------------------------------------------
# launchd/cron start from a minimal PATH with no profile sourced. Prepend the
# usual install roots (npm-global, Homebrew on both arches, mise shims) so a
# subscription-authenticated `claude` is found the way it is interactively.
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:$PATH"
# Only what the GUARDS themselves need. `claude` and `gh` are auth concerns and are
# asserted at the end, AFTER the sandbox check — so a machine with a misconfigured
# sandbox is told so, rather than being told its PATH is wrong.
for bin in jq git; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "MISSING on PATH: $bin — set PATH explicitly in the launchd plist / systemd unit (runtime/local.md)."; exit 78; }
done

# --- plugin resolution --------------------------------------------------------
# On CI the orchestrator plugin is fetched into the workspace; locally it is
# already installed, so ORCH_PLUGIN_DIR stays unset and `claude -p` resolves the
# nightly-orchestrator workflow itself. The hooks in settings.orchestrator.json
# resolve via $ORCH_CORE_HOOKS, which nothing exports outside CI.
if [ -z "${ORCH_CORE_HOOKS:-}" ]; then
  for c in "$HOME"/.claude/plugins/marketplaces/*/plugins/core/hooks; do
    [ -d "$c" ] && { ORCH_CORE_HOOKS="$c"; break; }
  done
fi
[ -d "${ORCH_CORE_HOOKS:-}" ] || { echo "core plugin hooks dir not found — export ORCH_CORE_HOOKS (runtime/local.md)."; exit 78; }
export ORCH_CORE_HOOKS
export ORCH_LANE="$LANE"
export ORCH_MAX_EPICS="${ORCH_MAX_EPICS:-2}"   # one machine, shared with your foreground work

SETTINGS="$R/orchestrator/settings.orchestrator.json"

# --- sandbox: fail-closed native by default, devcontainer opt-in -------------
# ADR-0033: the local lane may substitute the OS sandbox for the devcontainer,
# but only in its fail-closed form — a missing Seatbelt/bubblewrap must abort the
# run, never silently downgrade it to no isolation at all.
# The container lane is OPT-IN (ORCH_LOCAL_SANDBOX=devcontainer) because it is not
# free here the way it is on CI: inside the container there is no local `claude`
# login and no installed plugin, so it only works once .devcontainer/ mounts your
# ~/.claude and ORCH_CORE_HOOKS names the IN-CONTAINER path (runtime/local.md).
# Auto-detecting Docker and jumping in would produce a run that fails on auth.
SANDBOX="${ORCH_LOCAL_SANDBOX:-host}"
if [ "$SANDBOX" = "devcontainer" ]; then
  echo "sandbox: devcontainer (opt-in)"
  command -v devcontainer >/dev/null 2>&1 || { echo "ORCH_LOCAL_SANDBOX=devcontainer but the devcontainer CLI is absent."; exit 78; }
  devcontainer up --workspace-folder "$R" || { echo "devcontainer up failed — refusing to fall back silently."; exit 1; }
  # NOT `exec`: exec replaces this process, so the EXIT trap never fires and the
  # lock dir leaks — every later scheduled run would then exit as "already
  # running" until the staleness window passed, silently stopping the loop.
  devcontainer exec --workspace-folder "$R" \
    --remote-env "ORCH_LANE=$LANE" --remote-env "ORCH_MAX_EPICS=$ORCH_MAX_EPICS" \
    --remote-env "ORCH_CORE_HOOKS=${ORCH_CORE_HOOKS_IN_CONTAINER:-$ORCH_CORE_HOOKS}" \
    bash orchestrator/runtime/run-with-limits.sh
  exit $?
fi
if ! jq -e '.sandbox.enabled == true and .sandbox.failIfUnavailable == true' "$SETTINGS" >/dev/null 2>&1; then
  echo "REFUSING to run: the host lane needs sandbox.enabled AND sandbox.failIfUnavailable = true in"
  echo "orchestrator/settings.orchestrator.json (ADR-0033). Without failIfUnavailable the run would"
  echo "proceed unsandboxed on a machine holding your real credentials."
  exit 78
fi
echo "sandbox: native (fail-closed)"

# --- auth: assert the local lanes, store nothing ------------------------------
# Host lane only — the container lane exec'd out above and carries its own logins.
# A token in this environment would only NARROW what already works, so the check
# is for a live local login, not for a secret. Ordered last among the guards: it
# is the only one that touches the network, and a misconfigured sandbox or PATH
# should be reported without waiting on it.
claude --version >/dev/null 2>&1 || { echo "the local claude CLI is not usable — run \`claude\` once interactively."; exit 78; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated — run \`gh auth login\` once."; exit 78; }

bash "$R/orchestrator/runtime/run-with-limits.sh"   # not `exec` — see above: the lock must be released
exit $?
