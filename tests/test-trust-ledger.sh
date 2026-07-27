#!/bin/bash
# Graduated autonomy (ADR-0026): autonomy earned per epic class by measured
# pass rate, not configured once. Slow to grant, fast to revoke.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
SRC=../plugins/core/templates/orchestrator/bin/trust
D=$(mktemp -d); mkdir -p "$D/orchestrator/bin"; cp "$SRC" "$D/orchestrator/bin/trust"; chmod +x "$D/orchestrator/bin/trust"
export CLAUDE_PROJECT_DIR="$D"
T="$D/orchestrator/bin/trust"
rec() { local n=$1 c=$2 r=$3; while [ "$n" -gt 0 ]; do "$T" record "$c" "$r" >/dev/null 2>&1; n=$((n-1)); done; }

# --- a fresh class trusts nothing ---
[ "$("$T" tier src/low)" = "watch" ]; check "an unseen class starts at 'watch' (nothing auto-merges)" $?
[ ! -f "$D/.orch/trust.tsv" ]; check "reading a tier writes no ledger" $?

# --- the ladder ---
rec 9 src/low pass;  [ "$("$T" tier src/low)" = "watch" ]; check "9 clean runs is still 'watch' (under the run floor)" $?
rec 1 src/low pass;  [ "$("$T" tier src/low)" = "queue" ]; check "10 clean runs reaches 'queue' (drafts wait for review)" $?
rec 9 src/low pass;  [ "$("$T" tier src/low)" = "queue" ]; check "19 clean runs is still 'queue'" $?
rec 1 src/low pass;  [ "$("$T" tier src/low)" = "auto"  ]; check "20 clean runs earns 'auto'" $?

# --- revocation: the tier is recomputed every run and drops the moment the RATE
# --- falls below the floor. 20/21 is 95.24%, still above 95 — so one miss in a
# --- clean 20 does not revoke, and should not. The second one does.
"$T" record src/low fail >/dev/null 2>&1
[ "$("$T" tier src/low)" = "auto" ]; check "1 miss in 21 (95.2%) keeps 'auto' — the rate, not a streak" $?
out=$("$T" record src/low fail 2>&1 >/dev/null)
[ "$("$T" tier src/low)" = "queue" ]; check "2 misses in 22 (90.9%) drops below the auto floor" $?
echo "$out" | grep -q "TRUST: 'src/low' demoted auto"; check "the demotion is announced on stderr (cron mails it)" $?

# --- a poor record never climbs ---
rec 15 api/high pass; rec 15 api/high fail
[ "$("$T" tier api/high)" = "watch" ]; check "50% pass rate over 30 runs stays 'watch'" $?

# --- classes are independent: trust in docs/ is not trust in migrations/ ---
rec 20 docs/low pass
[ "$("$T" tier docs/low)" = "auto" ];  check "docs/low earns auto on its own record" $?
[ "$("$T" tier api/high)" = "watch" ]; check "…and api/high is unaffected by it" $?

# --- the class key ---
[ "$("$T" class '["src/auth/**","src/api/**"]' high)" = "src/high" ]; check "class = first footprint root + complexity" $?
[ "$("$T" class '[]' low)" = "unknown/low" ]; check "an epic with NO footprint is 'unknown', never lumped in with real work" $?
[ "$("$T" class 'garbage' medium)" = "unknown/medium" ]; check "unparseable footprint degrades to unknown, never crashes" $?

# --- render ---
"$T" render | grep -q 'docs/low'; check "render lists each class with its tier" $?
"$T" render | head -1 | grep -q 'tier'; check "render has a header row" $?

# --- thresholds are configurable, defaults are the conservative ones ---
[ "$(ORCH_TRUST_MIN_RUNS=2 ORCH_TRUST_PCT_AUTO=50 "$T" tier api/high)" = "auto" ]
check "thresholds are tunable via ORCH_TRUST_* env" $?
grep -q 'ORCH_TRUST_MIN_RUNS:-20' "$SRC"; check "default run floor for auto is 20" $?
grep -q 'ORCH_TRUST_PCT_AUTO:-95' "$SRC"; check "default pass-rate floor for auto is 95%" $?

# --- the ledger survives a malformed line rather than losing every class ---
printf 'junk-with-no-tabs\n' >> "$D/.orch/trust.tsv"
"$T" render >/dev/null 2>&1; check "render survives a malformed ledger line" $?
[ "$("$T" tier docs/low)" = "auto" ]; check "…and a good class keeps its tier" $?

# --- bad input ---
"$T" record src/low maybe >/dev/null 2>&1; [ $? -ne 0 ]; check "record rejects anything but pass|fail" $?
"$T" bogus >/dev/null 2>&1; [ $? -ne 0 ]; check "an unknown subcommand exits non-zero" $?

rm -rf "$D"; unset CLAUDE_PROJECT_DIR
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
