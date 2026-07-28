#!/bin/bash
# Per-project Slack notifications (one channel per repo, `cchar-<repo>`).
# The invariant under test is NOT that Slack works — it is that a notification
# can never break a run, and that the token never leaks into a log or a commit.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."
A="$R/plugins/orchestrator/templates/orchestrator/adapters/notify-slack.sh"
DRIVER="$R/plugins/orchestrator/templates/orchestrator/runtime/run-to-done.sh"
AL="$R/plugins/orchestrator/templates/orchestrator/egress-allowlist.txt"
SET="$R/plugins/orchestrator/templates/orchestrator/settings.orchestrator.json"

[ -f "$A" ] && bash -n "$A"; check "adapter parses" $?
[ -x "$A" ]; check "adapter is executable (cp -R preserves the bit)" $?

# --- never break a run --------------------------------------------------------
# No token is the NORMAL case (most installs never configure Slack). It must be
# a silent success, not a warning and certainly not a failure.
out=$(env -u SLACK_BOT_TOKEN CLAUDE_PROJECT_DIR="$(mktemp -d)" bash "$A" note "hello" 2>&1); rc=$?
[ "$rc" -eq 0 ]; check "no token → exit 0 (unconfigured is normal, not an error)" $?
[ -z "$out" ]; check "…and silent: no noise on stderr for the common case" $?

# Empty message must not post an empty line to a channel.
env -u SLACK_BOT_TOKEN bash "$A" note "" </dev/null >/dev/null 2>&1
[ $? -eq 0 ]; check "empty message → exit 0, nothing posted" $?

# A token present but the network unreachable must still exit 0. This is the
# sandbox case: slack.com not allowlisted, every call fails closed.
T=$(mktemp -d); mkdir -p "$T/.orch/cache"
out=$(SLACK_BOT_TOKEN="xoxb-not-a-real-token" CLAUDE_PROJECT_DIR="$T" \
      ORCH_SLACK_CHANNEL="cchar-test-unreachable" \
      http_proxy="http://127.0.0.1:9" https_proxy="http://127.0.0.1:9" \
      bash "$A" note "should not hang or fail" 2>&1); rc=$?
[ "$rc" -eq 0 ]; check "token set but network dead → still exit 0 (never fails a run)" $?
echo "$out" | grep -qi "egress-allowlist\|slack.com"; check "…and the diagnosis names the egress allowlist" $?
echo "$out" | grep -q "xoxb-not-a-real-token"; [ $? -ne 0 ]
check "THE TOKEN IS NEVER ECHOED, even on failure" $?
rm -rf "$T"

# --- channel derivation -------------------------------------------------------
# Slack rejects uppercase and punctuation outright, so the slug is a correctness
# requirement, not cosmetics.
slug_of() { # run the adapter's own derivation in isolation
  sed -n '/^slugify()/,/^}/p' "$A" > "$TMPF"
  # shellcheck disable=SC1090
  . "$TMPF"; slugify "$1"
}
TMPF=$(mktemp)
[ "$(slug_of 'My Repo')" = "my-repo" ]; check "slug: spaces and case → my-repo" $?
[ "$(slug_of 'agentic-harness-template-plugin')" = "agentic-harness-template-plugin" ]
check "slug: an already-valid name is unchanged" $?
[ "$(slug_of 'Foo..Bar!!')" = "foo-bar" ]; check "slug: punctuation collapses, no trailing hyphen" $?
[ "$(slug_of "$(printf 'a%.0s' $(seq 1 120))")" = "$(printf 'a%.0s' $(seq 1 80))" ]
check "slug: clamped to Slack's 80-char limit" $?
rm -f "$TMPF"
grep -q 'ORCH_SLACK_PREFIX:-cchar-' "$A"; check "default prefix is cchar-" $?
grep -q 'prefix first, then clamp' "$A"; check "…and a long repo name cannot truncate the prefix away" $?

# --- the credential is parsed, never sourced ----------------------------------
grep -q 'Parsed, not sourced' "$A"; check "the .env read is documented as a parse" $?
! grep -qE '^\s*(\.|source) .*\.env' "$A"; check "the adapter never sources .env (which would execute it)" $?

# --- driver wiring ------------------------------------------------------------
grep -q '^notify()' "$DRIVER"; check "driver has a notify wrapper" $?
grep -q '\[ -x "\$a" \] || return 0' "$DRIVER"; check "…that no-ops when the adapter is absent (old scaffold)" $?
for ev in wave merged escalated blocked done; do
  grep -q "notify $ev " "$DRIVER"; check "milestone wired: $ev" $?
done
grep -q 'stopped_by' "$DRIVER"; check "the closing notification carries WHY the run ended" $?

# --- sandbox posture ----------------------------------------------------------
grep -q "slack.com" "$AL"; check "allowlist documents slack.com" $?
grep -qE '^\s*#\s*slack\.com' "$AL"; check "…commented by default (every entry widens the blast radius)" $?
if command -v jq >/dev/null 2>&1; then
  jq -e '[.sandbox.credentials.envVars[] | select(.name=="SLACK_BOT_TOKEN" and .mode=="deny")] | length == 1' "$SET" >/dev/null 2>&1
  check "the agent cannot read the notification token (denied to tool subprocesses)" $?
fi

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
