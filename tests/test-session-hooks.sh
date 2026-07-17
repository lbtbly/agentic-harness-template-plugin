#!/bin/bash
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
CTX=../plugins/core/hooks/session-context.sh
INJ=../plugins/core/hooks/inject-session.sh
PRE=../plugins/core/hooks/precompact-save-state.sh

TMP=$(mktemp -d); mkdir -p "$TMP/docs"
git -C "$TMP" init -q -b main
echo "x" > "$TMP/f.txt"; git -C "$TMP" add f.txt
git -C "$TMP" -c user.email=t@t -c user.name=t commit -qm "init"
echo "dirty" >> "$TMP/f.txt"
printf "# HANDOFF\nBranch: main\nNext steps: test\n" > "$TMP/docs/HANDOFF.md"
export CLAUDE_PROJECT_DIR="$TMP"

assert_stdout_contains "$CTX" '{}' "Branch" "session-context shows the branch"
assert_stdout_contains "$CTX" '{}' "init" "session-context shows the last commit"

# inject-session: legacy fallback (no .orch) → HANDOFF.md content injected
assert_stdout_contains "$INJ" '{}' "Next steps: test" "inject-session falls back to legacy HANDOFF.md"

# inject-session: state-layer path (.orch session shadows legacy)
mkdir -p "$TMP/.orch/sessions"
printf '{"branch":"main","status":"green","nextSteps":["wire the DLQ"]}' > "$TMP/.orch/sessions/main.json"
assert_stdout_contains "$INJ" '{}' "wire the DLQ" "inject-session reads .orch session (none backend)"
rm -rf "$TMP/.orch"

# precompact legacy path (no orch binary in TMP)
assert_exit 0 "$PRE" '{"trigger":"auto"}' "precompact exit 0"
echo '{"trigger":"auto"}' | bash "$PRE" >/dev/null 2>&1
grep -q "Auto snapshot" "$TMP/docs/HANDOFF.md" && { PASS=$((PASS+1)); echo "  ok   — snapshot appended to HANDOFF (legacy)"; } || { FAIL=$((FAIL+1)); echo "  FAIL — snapshot missing"; }
# Cap: a 2nd and 3rd compaction must not accumulate snapshots (only the latest survives)
echo '{"trigger":"auto"}' | bash "$PRE" >/dev/null 2>&1
echo '{"trigger":"auto"}' | bash "$PRE" >/dev/null 2>&1
N=$(grep -c "^## Auto snapshot" "$TMP/docs/HANDOFF.md")
[ "$N" -eq 1 ] && { PASS=$((PASS+1)); echo "  ok   — auto snapshots capped at 1 (found $N)"; } || { FAIL=$((FAIL+1)); echo "  FAIL — snapshots accumulated (found $N)"; }
grep -q "Next steps: test" "$TMP/docs/HANDOFF.md" && { PASS=$((PASS+1)); echo "  ok   — curated HANDOFF content survives snapshots"; } || { FAIL=$((FAIL+1)); echo "  FAIL — curated content lost"; }

# precompact state-layer path: with orch installed, snapshot goes to .orch, not HANDOFF
mkdir -p "$TMP/orchestrator/bin" "$TMP/orchestrator"
cp ../plugins/core/templates/orchestrator/bin/orch "$TMP/orchestrator/bin/orch"; chmod +x "$TMP/orchestrator/bin/orch"
printf '{"backend":"none","forge":"none"}' > "$TMP/orchestrator/state.config.json"
BEFORE=$(cat "$TMP/docs/HANDOFF.md")
(cd "$TMP" && echo '{"trigger":"auto"}' | CLAUDE_PROJECT_DIR="$TMP" bash "$OLDPWD/$PRE") >/dev/null 2>&1
[ -f "$TMP/.orch/sessions/main.json" ] && grep -q "mechanical" "$TMP/.orch/sessions/main.json" && { PASS=$((PASS+1)); echo "  ok   — precompact pushes auto snapshot to state layer"; } || { FAIL=$((FAIL+1)); echo "  FAIL — no state-layer snapshot"; }
[ "$BEFORE" = "$(cat "$TMP/docs/HANDOFF.md")" ] && { PASS=$((PASS+1)); echo "  ok   — legacy HANDOFF untouched when state layer present"; } || { FAIL=$((FAIL+1)); echo "  FAIL — HANDOFF modified despite state layer"; }

# Robustness out of context
unset CLAUDE_PROJECT_DIR
NOGIT=$(mktemp -d); export CLAUDE_PROJECT_DIR="$NOGIT"
assert_exit 0 "$CTX" '{}' "session-context no-op outside git"
assert_stdout_empty "$INJ" '{}' "inject-session silent without any state"
unset CLAUDE_PROJECT_DIR; rm -rf "$TMP" "$NOGIT"
# Gap E (lecture 12): handoff carries an explicit clean-exit checklist
HS="../plugins/core/skills/handoff/SKILL.md"
grep -qi "cleanState" "$HS"; ok2=$?; if [ $ok2 -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — handoff records cleanState in the snapshot"; else FAIL=$((FAIL+1)); echo "  FAIL — handoff records cleanState in the snapshot"; fi
grep -qi "console.log\|debug" "$HS"; ok2=$?; if [ $ok2 -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — handoff scans the diff for debug artifacts"; else FAIL=$((FAIL+1)); echo "  FAIL — handoff scans the diff for debug artifacts"; fi

summary
