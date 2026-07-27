#!/bin/bash
# ADR-0033 — the `local` runtime: the loop on the operator's own machine, with
# NO stored credentials and a fail-closed sandbox. The failure this pins: a
# runtime menu where every option is remote, so a solo operator picks
# github-actions by elimination and inherits three secrets they never needed.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."
EN="$R/plugins/orchestrator/skills/enable-orchestrator/SKILL.md"
RT="$R/plugins/orchestrator/templates/orchestrator/runtime"
DOC="$RT/local.md"
SH="$RT/local-run.sh"

[ -f "$R/docs/adr/0033-local-runtime.md" ]; check "ADR-0033 exists" $?
[ -f "$DOC" ]; check "runtime/local.md exists" $?
[ -f "$SH" ]; check "runtime/local-run.sh exists" $?
bash -n "$SH"; check "local-run.sh parses" $?

# --- the ASK offers it, and does not steer to CI by elimination ---
grep -q '`local`' "$EN"; check "enable-orchestrator offers the local runtime" $?
grep -qi "zero secrets" "$EN"; check "the skill states local needs no secrets" $?
grep -qi "skip this ASK entirely" "$EN"; check "the secrets ASK is skipped on local" $?
grep -qi "not steer to \`github-actions\` by elimination\|by elimination" "$EN"
check "the skill warns against defaulting to CI by elimination" $?
grep -qi "whether or not the machine is awake\|not the machine is awake" "$EN"
check "the awake-machine trade-off is stated where the choice is made" $?

# --- budget is asked per auth lane, not unconditionally ---
grep -qi "only on the metered lane" "$EN"; check "token cap is asked only on the metered lane" $?
grep -qi "headroom" "$EN"; check "subscription: the cap is framed as headroom, not spend" $?

# --- both lanes, one script ---
grep -q "nightly" "$SH" && grep -q "retry" "$SH"; check "local-run.sh carries the build + retry lanes" $?
grep -q "ORCH_LANE" "$SH"; check "lane is passed through ORCH_LANE like every other runtime" $?
grep -q "run-with-limits.sh" "$SH"; check "it delegates to the shared usage-limit wrapper" $?
grep -q "StartCalendarInterval" "$DOC"; check "macOS launchd recipe present" $?
grep -q "OnCalendar" "$DOC"; check "Linux systemd timer recipe present" $?
grep -qi "sources no profile\|source no profile\|minimal PATH" "$DOC"; check "the scheduler PATH trap is documented" $?

# --- no stored credentials, by construction ---
grep -q 'CLAUDE_CODE_OAUTH_TOKEN=\|ANTHROPIC_API_KEY=\|GH_TOKEN=' "$SH"
[ $? -ne 0 ]; check "local-run.sh sets no model/forge credential" $?
grep -qi "narrows what already works" "$DOC"; check "local.md says why setting a token would be wrong" $?

# --- the fail-closed sandbox is enforced, not just documented ---
grep -q "failIfUnavailable" "$SH"; check "local-run.sh checks failIfUnavailable" $?
if command -v jq >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  mkdir -p "$TMP/orchestrator/runtime" "$TMP/hooks"
  cp "$SH" "$TMP/orchestrator/runtime/"
  printf '#!/bin/bash\nexit 0\n' > "$TMP/orchestrator/runtime/run-with-limits.sh"
  export CLAUDE_PROJECT_DIR="$TMP" ORCH_CORE_HOOKS="$TMP/hooks" ORCH_LOCAL_SANDBOX=host

  # CI's settings (failIfUnavailable false — the devcontainer is the wall there)
  # must be REFUSED on the host lane, where there is no outer wall.
  echo '{"sandbox":{"enabled":true,"failIfUnavailable":false}}' > "$TMP/orchestrator/settings.orchestrator.json"
  bash "$TMP/orchestrator/runtime/local-run.sh" retry; rc=$?
  [ "$rc" -eq 78 ]; check "host lane REFUSES a sandbox that is not fail-closed (exit 78)" $?
  grep -q "REFUSING to run" "$TMP/.orch/logs/local-$(date +%F)-retry.log" 2>/dev/null
  check "the refusal is written to the run log" $?

  # ...and a correctly fail-closed sandbox passes the guard (the positive path:
  # whatever auth does next, the run must get PAST the sandbox check).
  echo '{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"failIfUnavailable":true}}' \
    > "$TMP/orchestrator/settings.orchestrator.json"
  bash "$TMP/orchestrator/runtime/local-run.sh" retry >/dev/null 2>&1
  grep -q "sandbox: native (fail-closed)" "$TMP/.orch/logs/local-$(date +%F)-retry.log" 2>/dev/null
  check "fail-closed sandbox passes the guard" $?
  [ -f "$TMP/.orch/logs/.gitignore" ]; check "run logs are self-ignoring (never reach orch/state)" $?
  # the lock must be RELEASED when the run ends, or every later scheduled run
  # exits as "already running" and the loop stops without saying so.
  [ ! -d "$TMP/.orch/.local-run.lock" ]; check "the single-instance lock is released after a completed run" $?

  # a missing settings file is equally refused (fails closed, ADR-0017 posture)
  rm -f "$TMP/orchestrator/settings.orchestrator.json"
  bash "$TMP/orchestrator/runtime/local-run.sh" retry; [ $? -eq 78 ]
  check "absent settings file also refuses (no silent unsandboxed run)" $?
  rm -rf "$TMP"
else
  echo "  skip — jq not available"
fi

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
