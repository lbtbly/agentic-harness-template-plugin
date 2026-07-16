#!/bin/bash
# Subsystem 3b — driver mechanics: scope selection, wave partitioning, guards,
# usage throttle, and the outer loop's termination. Risk-gated merge is
# subsystem 4; here the loop must default to ESCALATE (conservative).
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
DRIVER="../plugins/orchestrator/templates/orchestrator/runtime/run-to-done.sh"
[ -f "$DRIVER" ] || { echo "  FAIL — driver missing at $DRIVER"; echo "---"; echo "0 ok, 1 failure(s)"; exit 1; }

# guard_safety must be testable against an arbitrary project dir at call time
SAFE=$(mktemp -d); mkdir -p "$SAFE/.claude"
cat > "$SAFE/.claude/settings.json" <<'JSON'
{ "permissions": { "defaultMode": "plan" }, "disableBypassPermissionsMode": "disable" }
JSON
export CLAUDE_PROJECT_DIR="$SAFE"

# fake orch: fixed 3-epic board
TMP=$(mktemp -d)
cat > "$TMP/orch" <<'FAKE'
#!/bin/bash
case "$1 $2" in
  "state list-epics")
    echo '[{"id":"a","title":"Alpha","state":"Backlog"},{"id":"b","title":"Bravo","state":"Backlog"},{"id":"c","title":"Charlie","state":"Backlog"}]' ;;
  *) echo '[]' ;;
esac
FAKE
chmod +x "$TMP/orch"
export ORCH_BIN="$TMP/orch"

source "$DRIVER"

# --- scope selection ---
out=$(select_scope all); [ "$(echo "$out" | tr '\n' ' ')" = "a b c " ]; check "select_scope all → a b c (board order)" $?
out=$(select_scope first 2); [ "$(echo "$out" | tr '\n' ' ')" = "a b " ]; check "select_scope first 2 → a b" $?
out=$(select_scope first 99); [ "$(echo "$out" | wc -l | tr -d ' ')" = "3" ]; check "select_scope first N clamps to available" $?
rm -rf "$TMP"

# --- wave partitioning: disjoint footprints run together; overlaps deferred ---
EPICS='[{"id":"a","footprint":["src/x/**"]},{"id":"b","footprint":["src/y/**"]},{"id":"c","footprint":["src/x/**"]}]'
w=$(echo "$EPICS" | partition_wave); [ "$(echo "$w" | tr '\n' ' ')" = "a b " ]; check "wave 1 = a,b (c overlaps a → deferred)" $?

# --- guards ---
[ "$(guard_no_progress 3 3)" = "blocked" ]; check "no-progress trips at K" $?
[ "$(guard_no_progress 1 3)" = "continue" ]; check "no-progress ok below K" $?
[ "$(guard_budget 100 50)" = "stop" ]; check "budget stop when spent>=cap" $?
[ "$(guard_budget 100 0)" = "continue" ]; check "budget disabled when cap=0" $?
[ "$(guard_wallclock 100 50)" = "stop" ]; check "wallclock stop past deadline" $?
[ "$(guard_thrash 0)" = "stop" ]; check "thrash stop when 0 advanced" $?
[ "$(guard_thrash 2)" = "continue" ]; check "thrash ok when progress made" $?
[ "$(guard_safety)" = "ok" ]; check "safety ok with plan-mode settings intact" $?
BAD=$(mktemp -d); mkdir -p "$BAD/.claude"; echo '{"permissions":{}}' > "$BAD/.claude/settings.json"
[ "$(CLAUDE_PROJECT_DIR=$BAD guard_safety)" = "abort" ]; check "safety abort when plan-mode gone (tampered settings)" $?
rm -rf "$BAD"

# --- usage throttle (mocked signal) ---
export ORCH_USAGE_SLOW_PCT=80 ORCH_USAGE_PAUSE_PCT=95
export ORCH_USAGE_CMD='echo 50'; [ "$(usage_pct)" = "50" ]; check "usage_pct reads ORCH_USAGE_CMD" $?
[ "$(throttle_decision 50)" = "continue" ]; check "throttle continue < slow" $?
[ "$(throttle_decision 85)" = "slow" ]; check "throttle slow at 85" $?
[ "$(throttle_decision 96)" = "pause" ]; check "throttle pause at 96" $?
[ "$(throttle_decision -1)" = "continue" ]; check "throttle continue on unknown signal" $?
[ "$(throttled_cap 85 4)" = "2" ]; check "slow halves the cap (4→2)" $?
[ "$(throttled_cap 96 4)" = "0" ]; check "pause zeroes the cap" $?
[ "$(throttled_cap 50 4)" = "4" ]; check "continue keeps base cap" $?
unset ORCH_USAGE_CMD

# --- outer loop: a merges, b blocks after K rounds ---
TMP2=$(mktemp -d)
cat > "$TMP2/orch" <<'FAKE'
#!/bin/bash
case "$1 $2" in
  "state list-epics") echo '[{"id":"a","title":"A","state":"Planned","footprint":["x/**"]},{"id":"b","title":"B","state":"Planned","footprint":["y/**"]}]';;
  *) echo '[]';;
esac
FAKE
chmod +x "$TMP2/orch"; export ORCH_BIN="$TMP2/orch"
export ORCH_NOPROGRESS_K=2
export ORCH_BUILD_CMD='true'
export ORCH_VERIFY_CMD='case "$1" in a) echo "{\"epic\":\"a\",\"done\":true}";; *) echo "{\"epic\":\"$1\",\"done\":false,\"blocking\":[\"tests\"]}";; esac'
export ORCH_RISK_CMD='echo low'
export ORCH_MERGE_CMD='echo merged'
summary=$(run_loop all)
echo "$summary" | jq -e '.merged | index("a")' >/dev/null; check "loop merges the done epic a" $?
echo "$summary" | jq -e '.blocked | index("b")' >/dev/null; check "loop blocks stuck epic b (no-progress)" $?

# --- the loop passes COMPUTED risk to the merge hook; high risk → escalated ---
export ORCH_RISK_CMD='echo high'
export ORCH_MERGE_CMD='case "$2" in high) echo escalated;; *) echo merged;; esac'
summary=$(run_loop first 1)
echo "$summary" | jq -e '.escalated | index("a")' >/dev/null; check "done epic with HIGH computed risk → escalated, not merged" $?

# --- without a risk hook the default is CONSERVATIVE (high) → never auto-merge ---
unset ORCH_RISK_CMD
summary=$(run_loop first 1)
echo "$summary" | jq -e '.escalated | index("a")' >/dev/null; check "no risk signal → defaults high → escalated (safe by default)" $?

# --- wallclock deadline in the past stops the loop with a clean checkpoint ---
export ORCH_RISK_CMD='echo low' ORCH_MERGE_CMD='echo merged'
export ORCH_WALLCLOCK_DEADLINE=1
summary=$(run_loop all)
echo "$summary" | jq -e '.stopped_by == "WALLCLOCK"' >/dev/null; check "past wallclock deadline → stopped_by=WALLCLOCK" $?
unset ORCH_WALLCLOCK_DEADLINE

# --- budget cap reached stops the loop ---
export ORCH_BUDGET_TOKENS=100 ORCH_SPENT_CMD='echo 150'
summary=$(run_loop all)
echo "$summary" | jq -e '.stopped_by == "BUDGET"' >/dev/null; check "spend >= budget cap → stopped_by=BUDGET" $?
unset ORCH_BUDGET_TOKENS ORCH_SPENT_CMD

rm -rf "$TMP2" "$SAFE"
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
