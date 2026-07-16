#!/bin/bash
# Runs every tests/test-*.sh and reports a global verdict.
cd "$(dirname "$0")" || exit 1
TOTAL_FAIL=0
for t in test-*.sh; do
  [ -f "$t" ] || continue
  echo "== $t"
  bash "$t" || TOTAL_FAIL=$((TOTAL_FAIL+1))
  echo
done
echo "===================="
if [ "$TOTAL_FAIL" -eq 0 ]; then echo "ALL SUITES GREEN"; else echo "$TOTAL_FAIL suite(s) FAILED"; fi
[ "$TOTAL_FAIL" -eq 0 ]
