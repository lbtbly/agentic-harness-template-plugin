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
# Auto-merge now needs risk AND trust (ADR-0026). These tests exercise the merge
# path, so grant the class `auto`; the trust gate itself is tested below.
export ORCH_TRUST_TIER_CMD='echo auto' ORCH_TRUST_RECORD_CMD='true'
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

# --- bash 3.2 (stock macOS): no assoc arrays, no array expansion under set -u ---
! grep -v '^[[:space:]]*#' "$DRIVER" | grep -q 'declare -A'; check "driver uses no 'declare -A' (bash 3.2 / stock macOS; comments excepted)" $?
! grep -qE '\$\{(merged|escalated|blocked|rounds)\[' "$DRIVER"; check "driver keeps no bash arrays for loop state" $?
m=$(rounds_set "" a 1); m=$(rounds_set "$m" b 2); m=$(rounds_set "$m" a 3)
[ "$(rounds_get "$m" a)" = "3" ]; check "rounds map: set overwrites an existing key" $?
[ "$(rounds_get "$m" b)" = "2" ]; check "rounds map: keys are independent" $?
[ "$(rounds_get "$m" zz)" = "0" ]; check "rounds map: missing key → 0" $?
set_has "a b" b; check "set_has finds a member" $?
set_has "a b" c && r=1 || r=0; [ "$r" = 0 ]; check "set_has rejects a non-member" $?
set_has "ab" a && r=1 || r=0; [ "$r" = 0 ]; check "set_has is not a substring match (ab != a)" $?
[ "$(json_arr)" = "[]" ]; check "json_arr with no args → [] (empty set under set -u)" $?
[ "$(rounds_json "")" = "{}" ]; check "rounds_json of an empty map → {}" $?
export ORCH_SYNC_CMD='echo synced'
[ "$(do_sync)" = "synced" ]; check "do_sync honours the ORCH_SYNC_CMD seam" $?
unset ORCH_SYNC_CMD
( cd "$SAFE" && sync_main ); check "sync_main is a clean no-op outside a git repo" $?

# --- ONE build_wave per ROUND, scoped to the admitted wave (not once per epic) ---
TMP3=$(mktemp -d)
mkboard() { cat > "$TMP3/orch" <<FAKE
#!/bin/bash
case "\$1 \$2" in
  "state list-epics") echo '$1' ;;
  *) echo '{}' ;;
esac
FAKE
chmod +x "$TMP3/orch"; }
export ORCH_BIN="$TMP3/orch" ORCH_MAX_CONCURRENT=4 ORCH_NOPROGRESS_K=3
export ORCH_TRUST_TIER_CMD='echo auto' ORCH_TRUST_RECORD_CMD='true'
export ORCH_BUILD_CMD="printf '%s\n' \"\$*\" >> $TMP3/build.log"
export ORCH_VERIFY_CMD='echo "{\"epic\":\"$1\",\"done\":true}"'
export ORCH_RISK_CMD='echo low' ORCH_MERGE_CMD='echo merged' ORCH_PUBLISH_CMD='true'

mkboard '[{"id":"a","state":"Planned","footprint":["x/**"]},{"id":"b","state":"Planned","footprint":["y/**"]},{"id":"c","state":"Planned","footprint":["x/**"]}]'
: > "$TMP3/build.log"; summary=$(run_loop all)
[ "$(sed -n 1p "$TMP3/build.log")" = "a b" ]; check "round 1 builds the disjoint wave a b (c overlaps a → deferred)" $?
[ "$(sed -n 2p "$TMP3/build.log")" = "c" ]; check "round 2 builds the deferred c" $?
[ "$(grep -c . "$TMP3/build.log")" = "2" ]; check "build_wave runs ONCE per round (2 rounds, not 5 per-epic waves)" $?
echo "$summary" | jq -e 'has("merged") and has("stopped_by")' >/dev/null; check "run_loop emits a parseable summary on this bash ($BASH_VERSION)" $?

# --- deps: topological admission, never raw board order ---
mkboard '[{"id":"b","state":"Planned","footprint":["y/**"],"deps":["a"]},{"id":"a","state":"Planned","footprint":["x/**"],"deps":[]}]'
: > "$TMP3/build.log"; summary=$(run_loop all)
[ "$(sed -n 1p "$TMP3/build.log")" = "a" ]; check "deps: only a is admitted first (b declares deps:[a], despite board order)" $?
[ "$(sed -n 2p "$TMP3/build.log")" = "b" ]; check "deps: b is admitted only after a landed" $?
mkboard '[{"id":"a","state":"Planned","footprint":["x/**"],"deps":["z"]},{"id":"z","state":"Merged","footprint":["q/**"]}]'
: > "$TMP3/build.log"; summary=$(run_loop all)
[ "$(sed -n 1p "$TMP3/build.log")" = "a" ]; check "deps: a dep already Merged on the board does not gate" $?
mkboard '[{"id":"a","state":"Planned","footprint":["x/**"],"deps":["ghost"]}]'
: > "$TMP3/build.log"; summary=$(run_loop all)
[ "$(sed -n 1p "$TMP3/build.log")" = "a" ]; check "deps: a dep naming no board record is ignored (typo must not deadlock)" $?
mkboard '[{"id":"a","state":"Planned","footprint":["x/**"],"deps":["b"]},{"id":"b","state":"Planned","footprint":["y/**"],"deps":["a"]}]'
summary=$(run_loop all)
echo "$summary" | jq -e '.stopped_by == "DEPS"' >/dev/null; check "dependency cycle → stopped_by=DEPS (terminates, no infinite loop)" $?

# --- the usage throttle actually reaches the loop ---
mkboard '[{"id":"a","state":"Planned","footprint":["w/**"]},{"id":"b","state":"Planned","footprint":["x/**"]},{"id":"c","state":"Planned","footprint":["y/**"]},{"id":"d","state":"Planned","footprint":["z/**"]}]'
export ORCH_BUILD_CMD="printf '%s|%s\n' \"\$ORCH_MAX_CONCURRENT\" \"\$*\" >> $TMP3/build.log"
export ORCH_USAGE_CMD='echo 85' ORCH_MAX_CONCURRENT=4
: > "$TMP3/build.log"; summary=$(run_loop all)
[ "$(sed -n 1p "$TMP3/build.log")" = "2|a b" ]; check "usage 85 (slow) halves the cap 4→2 — the wave is capped, not the footprint" $?
export ORCH_USAGE_CMD='echo 50'
: > "$TMP3/build.log"; summary=$(run_loop all)
[ "$(sed -n 1p "$TMP3/build.log")" = "4|a b c d" ]; check "usage 50 keeps the full cap (all 4 disjoint epics in one wave)" $?
export ORCH_USAGE_CMD='echo 96'
: > "$TMP3/build.log"; summary=$(run_loop all)
echo "$summary" | jq -e '.stopped_by == "USAGE"' >/dev/null; check "usage >= PAUSE_PCT → cap 0 → stopped_by=USAGE (throttle has runtime effect)" $?
[ ! -s "$TMP3/build.log" ]; check "a paused run spends nothing (no build after the pause decision)" $?
unset ORCH_USAGE_CMD
export ORCH_BUILD_CMD="printf '%s\n' \"\$*\" >> $TMP3/build.log"

# --- the thrash guard is REACHABLE ---
mkboard '[{"id":"a","state":"Planned","footprint":["x/**"]}]'
export ORCH_VERIFY_CMD='true'      # engine returns nothing: no attributable work
summary=$(run_loop all)
echo "$summary" | jq -e '.stopped_by == "THRASH"' >/dev/null; check "no usable verdict from the whole wave → stopped_by=THRASH (guard is reachable)" $?
export ORCH_VERIFY_CMD='echo "{\"epic\":\"$1\",\"done\":false,\"blocking\":[\"tests\"]}"'
summary=$(run_loop all)
echo "$summary" | jq -e '.stopped_by == null and (.blocked | index("a"))' >/dev/null; check "a real not-done verdict is progress: blocks at K, never THRASH" $?

# --- re-entry: state is reconstructed from the board, not from memory ---
mkboard '[{"id":"a","state":"Merged","footprint":["x/**"]},{"id":"b","state":"Blocked","note":"attempts=3","footprint":["y/**"]},{"id":"c","state":"Planned","footprint":["z/**"]}]'
export ORCH_VERIFY_CMD='echo "{\"epic\":\"$1\",\"done\":true}"'
: > "$TMP3/build.log"; summary=$(run_loop all)
echo "$summary" | jq -e '.merged  | index("a")' >/dev/null; check "re-entry: board state Merged is reconstructed as merged" $?
echo "$summary" | jq -e '.blocked | index("b")' >/dev/null; check "re-entry: board state Blocked is reconstructed as blocked" $?
[ "$(cat "$TMP3/build.log")" = "c" ]; check "re-entry: only the un-landed epic c is rebuilt (a and b are never re-run)" $?
mkboard '[{"id":"a","state":"Needs-review","pr":7,"footprint":["x/**"]},{"id":"b","state":"Cancelled","footprint":["y/**"]}]'
: > "$TMP3/build.log"; summary=$(run_loop all)
echo "$summary" | jq -e '.escalated | index("a")' >/dev/null; check "re-entry: Needs-review is reconstructed as escalated (awaiting /orch approve)" $?
echo "$summary" | jq -e '.merged==[] and .blocked==[]' >/dev/null; check "re-entry: Cancelled is skipped entirely, not built" $?
[ ! -s "$TMP3/build.log" ]; check "re-entry: a fully settled scope builds nothing" $?

# --- durable round counters: read from and written back to the board note ---
mkboard '[{"id":"c","state":"Changes-requested","pr":9,"note":"attempts=2 stopped at tests","footprint":["z/**"]}]'
export ORCH_NOPROGRESS_K=3 ORCH_VERIFY_CMD='echo "{\"epic\":\"$1\",\"done\":false,\"blocking\":[\"e2e\"]}"'
export ORCH_STATUS_CMD="printf '%s\n' \"\$1|\$2|\$3\" >> $TMP3/status.log"
: > "$TMP3/build.log"; : > "$TMP3/status.log"; summary=$(run_loop all)
echo "$summary" | jq -e '.blocked | index("c")' >/dev/null; check "durable counter: attempts=2 from the note + 1 failed round → Blocked at K=3" $?
[ "$(grep -c . "$TMP3/build.log")" = "1" ]; check "durable counter: the persisted count is honoured (1 round this run, not 3)" $?
grep -q 'attempts=3' "$TMP3/status.log"; check "durable counter: the new count is persisted via push-status --note" $?
grep -q '^c|Blocked|' "$TMP3/status.log"; check "hitting K persists state Blocked to the board" $?
echo "$summary" | jq -e '.rounds.c == 3' >/dev/null; check "summary reports the per-epic round count" $?
mkboard '[{"id":"c","state":"Planned","note":"attempts=1 tests","footprint":["z/**"]}]'
: > "$TMP3/status.log"; summary=$(run_loop all)
grep -q '^c|Planned|attempts=2' "$TMP3/status.log"; check "an under-K round re-queues the epic buildable with attempts bumped" $?
grep -q 'e2e' "$TMP3/status.log"; check "the note carries the verdict's blocking reason forward" $?

# --- a reverted merge is rework, never a silent escalation ---
mkboard '[{"id":"a","state":"Planned","footprint":["x/**"]}]'
export ORCH_VERIFY_CMD='echo "{\"epic\":\"$1\",\"done\":true}"' ORCH_MERGE_CMD='echo reverted' ORCH_NOPROGRESS_K=2
export ORCH_PUBLISH_CMD="printf '%s\n' \"\$1\" >> $TMP3/publish.log"
: > "$TMP3/status.log"; : > "$TMP3/publish.log"; summary=$(run_loop all)
echo "$summary" | jq -e '.merged == [] and .escalated == []' >/dev/null; check "a reverted merge counts as neither merged nor escalated" $?
echo "$summary" | jq -e '.blocked | index("a")' >/dev/null; check "a reverted merge consumes a round and blocks at K" $?
[ ! -s "$TMP3/publish.log" ]; check "a reverted merge is never published to the forge" $?

# --- landing: the forge merges, the driver never pushes main (ADR-0015) ---
! grep -qE 'git .*push[^|;&]*origin[[:space:]]+main' "$DRIVER"; check "driver never pushes main directly (branch protection is the enforcer)" $?
grep -q 'git push -q origin "orch/\$id"' "$DRIVER"; check "driver publishes the epic branch orch/<id> (the allowlisted push)" $?
grep -q -- '--auto' "$DRIVER"; check "landing is requested with --auto so protection/CODEOWNERS still gate it" $?
export ORCH_MERGE_CMD='echo merged'
: > "$TMP3/publish.log"; summary=$(run_loop all)
grep -qx 'a' "$TMP3/publish.log"; check "a locally proven merge is published for the forge to land" $?
export ORCH_RISK_CMD='echo high' ORCH_MERGE_CMD='case "$2" in high) echo escalated;; *) echo merged;; esac'
: > "$TMP3/publish.log"; summary=$(run_loop all)
[ ! -s "$TMP3/publish.log" ]; check "an escalated epic is never published (no unreviewed high-risk landing)" $?
export ORCH_RISK_CMD='echo low' ORCH_MERGE_CMD='echo merged'
SET="../plugins/orchestrator/templates/orchestrator/settings.orchestrator.json"
jq -e '.permissions.deny  | index("Bash(git push origin main:*)")' "$SET" >/dev/null; check "settings still DENY a direct main push to the builder" $?
jq -e '(.permissions.allow | index("Bash(gh pr merge:*)")) == null' "$SET" >/dev/null; check "gh pr merge stays OUT of the builder allowlist (only the driver requests a landing)" $?

# --- the budget guard must not be silently inert ---
unset ORCH_SPENT_CMD
[ "$(spent_tokens)" = "-1" ] || command -v ccusage >/dev/null 2>&1; check "spent_tokens with no signal → -1 (unknown), never a fake 0" $?
[ "$(guard_budget -1 100)" = "continue" ]; check "an unknown spend does not trip the budget guard" $?
export ORCH_BUDGET_TOKENS=100
err=$(run_loop all 2>&1 >/dev/null)
echo "$err" | grep -qi "budget guard INERT"; check "a budget cap with no spend signal warns loudly on stderr" $?
unset ORCH_BUDGET_TOKENS
export ORCH_SPENT_CMD='echo 5'; err=$(run_loop all 2>&1 >/dev/null)
! echo "$err" | grep -qi "budget guard INERT"; check "no inertness warning when a real spend signal exists" $?
unset ORCH_SPENT_CMD

rm -rf "$TMP3"
unset ORCH_BUILD_CMD ORCH_VERIFY_CMD ORCH_RISK_CMD ORCH_MERGE_CMD \
      ORCH_PUBLISH_CMD ORCH_STATUS_CMD ORCH_SYNC_CMD ORCH_MAX_CONCURRENT ORCH_NOPROGRESS_K

# --- graduated autonomy: risk says how bad, trust says how often we got it right ---
TMP4=$(mktemp -d)
cat > "$TMP4/orch" <<'FAKE'
#!/bin/bash
case "$1 $2" in
  "state list-epics") echo '[{"id":"a","state":"Planned","footprint":["src/**"],"complexity":"low"}]';;
  *) echo '{}';;
esac
FAKE
chmod +x "$TMP4/orch"; export ORCH_BIN="$TMP4/orch"
export ORCH_BUILD_CMD='true' ORCH_VERIFY_CMD='echo "{\"epic\":\"$1\",\"done\":true}"'
export ORCH_RISK_CMD='echo low' ORCH_MERGE_CMD='echo merged'
export ORCH_PUBLISH_CMD="printf '%s\n' \"\$1\" >> $TMP4/publish.log"
export ORCH_TRUST_RECORD_CMD="printf '%s|%s\n' \"\$1\" \"\$2\" >> $TMP4/trust.log"

for t in watch queue; do
  export ORCH_TRUST_TIER_CMD="echo $t"
  : > "$TMP4/publish.log"; summary=$(run_loop all)
  echo "$summary" | jq -e '.escalated | index("a")' >/dev/null
  check "tier=$t: a VERIFIED low-risk epic is escalated, not merged" $?
  [ ! -s "$TMP4/publish.log" ]; check "tier=$t: nothing is published" $?
done
export ORCH_TRUST_TIER_CMD='echo auto'
: > "$TMP4/publish.log"; summary=$(run_loop all)
echo "$summary" | jq -e '.merged | index("a")' >/dev/null; check "tier=auto: the same epic now merges" $?
grep -qx 'a' "$TMP4/publish.log"; check "tier=auto: and is published" $?

# the default for a fresh install must be "nothing auto-merges"
unset ORCH_TRUST_TIER_CMD
: > "$TMP4/publish.log"; summary=$(run_loop all)
echo "$summary" | jq -e '.merged == []' >/dev/null; check "no ledger at all → nothing auto-merges (safe default)" $?

# outcomes feed the ledger
export ORCH_TRUST_TIER_CMD='echo auto'
: > "$TMP4/trust.log"; summary=$(run_loop all)
grep -q '|pass' "$TMP4/trust.log"; check "a landed epic records a pass for its class" $?
export ORCH_MERGE_CMD='echo reverted' ORCH_NOPROGRESS_K=1
: > "$TMP4/trust.log"; summary=$(run_loop all)
grep -q '|fail' "$TMP4/trust.log"; check "green in isolation but red after merging records a FAIL" $?
export ORCH_VERIFY_CMD='echo "{\"epic\":\"$1\",\"done\":false}"'
: > "$TMP4/trust.log"; summary=$(run_loop all)
grep -q '|fail' "$TMP4/trust.log"; check "a failed DoD verdict records a fail for its class" $?
rm -rf "$TMP4"
unset ORCH_TRUST_TIER_CMD ORCH_TRUST_RECORD_CMD ORCH_PUBLISH_CMD ORCH_BUILD_CMD \
      ORCH_VERIFY_CMD ORCH_RISK_CMD ORCH_MERGE_CMD ORCH_NOPROGRESS_K

# --- R12: hardened headless invocations + extracted verdict schema ---
VS="../plugins/orchestrator/templates/orchestrator/verdict.schema.json"
jq -e . "$VS" >/dev/null 2>&1; check "verdict.schema.json ships and parses" $?
jq -e '.required | index("done") and index("escalate")' "$VS" >/dev/null 2>&1; check "verdict schema requires done + escalate" $?
grep -q -- "--json-schema" "$DRIVER"; check "verify call uses --json-schema (validated structured output)" $?
grep -q "structured_output" "$DRIVER"; check "driver parses structured_output" $?
grep -q "ORCH_MAX_TURNS" "$DRIVER"; check "driver caps turns (ORCH_MAX_TURNS)" $?
grep -q -- "--strict-mcp-config" "$DRIVER"; check "driver pins MCP config (no stray user servers)" $?
! grep -- "--bare" "$DRIVER" | grep -v "^\s*#" | grep -q .; check "driver never uses --bare (ADR-0019 subscription lane; comments excepted)" $?

rm -rf "$TMP2" "$SAFE"
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
