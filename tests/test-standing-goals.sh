#!/bin/bash
# Standing goals (ADR-0028): finished work is re-verified daily, so a merged
# epic cannot silently regress. Detects only — never fixes.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
V=../plugins/orchestrator/templates/orchestrator/runtime/verify-goals.sh
[ -f "$V" ] || { echo "  FAIL — verify-goals.sh missing"; echo "---"; echo "0 ok, 1 failure(s)"; exit 1; }
mkg() { mkdir -p "$1/.orch/goals"; printf 'predicate: %s\nstatus: satisfied\nlast-pass: 2026-07-01\non-violation: wake me\n' "$3" > "$1/.orch/goals/$2.md"; }

D=$(mktemp -d); export CLAUDE_PROJECT_DIR="$D"
bash "$V" >/dev/null 2>&1; check "no goals yet → exits 0, not an error" $?

mkg "$D" holds true; mkg "$D" broken false
bash "$V" >/dev/null 2>&1; [ $? -eq 1 ]; check "a violated invariant exits non-zero" $?
grep -q '^status: VIOLATED' "$D/.orch/goals/broken.md"; check "the violated goal is marked VIOLATED" $?
grep -q '^status: satisfied' "$D/.orch/goals/holds.md"; check "a holding goal stays satisfied" $?
grep -q "last-pass: $(date -u +%F)" "$D/.orch/goals/holds.md"; check "a holding goal's last-pass is refreshed" $?
[ "$(awk -F'\t' '$3=="pass"{n++} END{print n+0}' "$D/.orch/goal-ledger.tsv")" = "1" ]; check "the ledger records the pass" $?
[ "$(awk -F'\t' '$3=="FAIL"{n++} END{print n+0}' "$D/.orch/goal-ledger.tsv")" = "1" ]; check "the ledger records the failure" $?
err=$(bash "$V" 2>&1 >/dev/null); echo "$err" | grep -q 'broken'; check "the violation names the goal on stderr (cron mails it)" $?
echo "$err" | grep -q 'on-violation'; check "…and surfaces what the operator asked for" $?

# it must DETECT, never repair
before=$(cat "$D/.orch/goals/broken.md"); bash "$V" >/dev/null 2>&1
echo "$before" | grep -q 'predicate: false'; check "the predicate is never rewritten to make it pass" $?

# a timeout is a violation, not a skip — otherwise the sentinel goes blind
D2=$(mktemp -d); export CLAUDE_PROJECT_DIR="$D2"; mkg "$D2" slow "sleep 5"
ORCH_GOAL_TIMEOUT=1 bash "$V" >/dev/null 2>&1; [ $? -eq 1 ]; check "a predicate that TIMES OUT is a violation, not a pass" $?
grep -q 'TIMEOUT' "$D2/.orch/goal-ledger.tsv"; check "…and is distinguishable from a plain FAIL in the ledger" $?
grep -q '^status: VIOLATED' "$D2/.orch/goals/slow.md"; check "…and marks the goal VIOLATED" $?
rm -rf "$D2"

# retired goals are skipped, never deleted
D3=$(mktemp -d); export CLAUDE_PROJECT_DIR="$D3"; mkg "$D3" old false
printf 'predicate: false\nstatus: retired\n' > "$D3/.orch/goals/old.md"
bash "$V" >/dev/null 2>&1; check "a retired goal is skipped (exit 0 despite a false predicate)" $?
[ -f "$D3/.orch/goals/old.md" ]; check "…and the file survives (retired, never deleted)" $?
# a goal with no predicate cannot be verified and must say so
printf 'status: satisfied\n' > "$D3/.orch/goals/nopred.md"
err=$(bash "$V" 2>&1 >/dev/null); echo "$err" | grep -q 'no predicate'; check "a goal without a predicate warns rather than passing silently" $?
rm -rf "$D3"

grep -q 'never fixes\|It never fixes\|never fix' "$V"; check "the script states it detects but never fixes" $?
S=../plugins/orchestrator/skills/goals/SKILL.md
[ -f "$S" ]; check "/orchestrator:goals ships" $?
grep -qi 'assumption with a timestamp' "$S"; check "the skill states why a one-time verification is not enough" $?
grep -qi 'retired, never deleted' "$S"; check "the skill mandates retire-not-delete" $?
C=../plugins/orchestrator/skills/compost/SKILL.md
[ -f "$C" ]; check "/orchestrator:compost ships" $?
grep -qi 'propose only' "$C"; check "compost proposes, never edits" $?
grep -qi 'ceiling, not a target' "$C"; check "compost caps proposals rather than manufacturing them" $?
DOC=../plugins/core/skills/doctor/SKILL.md
[ -f "$DOC" ]; check "/core:doctor ships" $?
grep -q 'disallowed-tools: Edit, Write' "$DOC"; check "doctor is mechanically read-only" $?
grep -qi 'safety boundary' "$DOC"; check "doctor refuses to cut safety rules for tokens" $?

rm -rf "$D"; unset CLAUDE_PROJECT_DIR
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
