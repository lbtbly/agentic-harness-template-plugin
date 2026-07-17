#!/bin/bash
# Gap B (lecture 06): the initializer must establish a verifiable test framework
# with one passing example test. The core plugin ships tests/run-tests.sh +
# smoke.test.sh templates; a fresh scaffold must run them GREEN on day 0.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
T="../plugins/core/templates"

[ -f "$T/tests/run-tests.sh" ]; check "templates ship tests/run-tests.sh" $?
[ -x "$T/tests/run-tests.sh" ]; check "runner is executable" $?
[ -f "$T/tests/smoke.test.sh" ]; check "templates ship the passing example test (smoke.test.sh)" $?
grep -q "tests/run-tests.sh" "$T/CLAUDE.md"; check "CLAUDE.md template records the test command" $?
grep -q 'cp -R "$T/tests"' ../plugins/core/skills/new-project/SKILL.md || grep -q "tests/run-tests.sh" ../plugins/core/skills/new-project/SKILL.md
check "new-project scaffolds the test harness and runs it green" $?

# --- end-to-end: a minimal fresh scaffold runs GREEN including the smoke test ---
D=$(mktemp -d)
mkdir -p "$D/orchestrator/bin" "$D/.claude" "$D/.orch"
cp "$T/tests/." "$D/tests" -R 2>/dev/null || cp -R "$T/tests" "$D/tests"
cp "$T/orchestrator/bin/orch" "$D/orchestrator/bin/orch"; chmod +x "$D/orchestrator/bin/orch"
printf '{"backend":"none","forge":"none"}' > "$D/orchestrator/state.config.json"
cp "$T/settings.json" "$D/.claude/settings.json"
cp "$T/CLAUDE.md" "$D/CLAUDE.md"
( cd "$D" && CLAUDE_PROJECT_DIR="$D" bash tests/run-tests.sh >/dev/null 2>&1 )
check "fresh scaffold: tests/run-tests.sh exits green (day-0 suite exists)" $?
rm -rf "$D"

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
