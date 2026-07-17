#!/bin/bash
# Project test runner — scaffolded by /core:new-project so the DoD has a real
# target from day 0 (initialization must establish a verifiable test framework
# with at least one passing example test). Runs every tests/*.test.sh, then the
# stack's native runner when one is configured. Green on a fresh scaffold via
# the shipped smoke test; epics add their own tests/*.test.sh (test-first).
cd "$(dirname "$0")/.." || exit 1
FAIL=0
for t in tests/*.test.sh; do
  [ -f "$t" ] || continue
  echo "== $t"
  bash "$t" || FAIL=1
  echo
done
# Stack-native runner — only when one is actually configured, so an empty
# scaffold stays green instead of failing on a missing app.
if [ -f package.json ] && command -v jq >/dev/null 2>&1 \
   && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
  npm test || FAIL=1
elif [ -f pyproject.toml ] && command -v pytest >/dev/null 2>&1 \
   && ls tests/*_test.py tests/test_*.py >/dev/null 2>&1; then
  pytest || FAIL=1
elif [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  cargo test || FAIL=1
elif [ -f go.mod ] && command -v go >/dev/null 2>&1; then
  go test ./... || FAIL=1
fi
echo "===================="
if [ "$FAIL" -eq 0 ]; then echo "ALL GREEN"; else echo "FAILURES"; fi
exit $FAIL
