#!/bin/bash
# Smoke test — the one passing example test the initializer ships to prove the
# framework works (startup readiness): contract present, configs parse, state
# layer reachable. Epics add their own tests/*.test.sh next to this file.
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }

[ -f CLAUDE.md ]; check "CLAUDE.md contract present" $?
command -v jq >/dev/null 2>&1; check "jq available (the harness's one dependency)" $?
for f in .claude/settings.json orchestrator/state.config.json; do
  jq -e . "$f" >/dev/null 2>&1; check "$f parses" $?
done
# health is only asserted on the zero-dependency local backend — remote
# backends need credentials the day-0 scaffold doesn't have yet.
B=$(jq -r '.backend // "none"' orchestrator/state.config.json 2>/dev/null)
if [ "$B" = "none" ]; then
  bash orchestrator/bin/orch state health >/dev/null 2>&1; check "orch state health ok (backend: none)" $?
else
  echo "  skip — backend '$B' needs credentials; health checked at enable time"
fi

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
