#!/bin/bash
# Minimal test harness: inject the JSON Claude Code would send on stdin,
# then assert on exit code and/or output. Shared by every tests/test-*.sh.
PASS=0; FAIL=0

check() { # usage: check <label> <exit-code-of-assertion>
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"
  else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi
}

assert_exit() { # usage: assert_exit <expected exit> <script> <stdin-json> <label>
  local expected="$1" script="$2" json="$3" label="$4"
  echo "$json" | bash "$script" >/dev/null 2>&1
  local code=$?
  if [ "$code" -eq "$expected" ]; then PASS=$((PASS+1)); echo "  ok   — $label"
  else FAIL=$((FAIL+1)); echo "  FAIL — $label (expected exit $expected, got $code)"; fi
}

assert_cmd_exit() { # usage: assert_cmd_exit <expected exit> <label> <cmd...>
  local expected="$1" label="$2"; shift 2
  "$@" >/dev/null 2>&1
  local code=$?
  if [ "$code" -eq "$expected" ]; then PASS=$((PASS+1)); echo "  ok   — $label"
  else FAIL=$((FAIL+1)); echo "  FAIL — $label (expected exit $expected, got $code)"; fi
}

assert_stdout_contains() { # usage: assert_stdout_contains <script> <stdin-json> <needle> <label>
  local script="$1" json="$2" needle="$3" label="$4"
  local out; out=$(echo "$json" | bash "$script" 2>/dev/null)
  if echo "$out" | grep -qF "$needle"; then PASS=$((PASS+1)); echo "  ok   — $label"
  else FAIL=$((FAIL+1)); echo "  FAIL — $label (output does not contain \"$needle\")"; fi
}

assert_stdout_empty() { # usage: assert_stdout_empty <script> <stdin-json> <label>
  local script="$1" json="$2" label="$3"
  local out; out=$(echo "$json" | bash "$script" 2>/dev/null)
  if [ -z "$out" ]; then PASS=$((PASS+1)); echo "  ok   — $label"
  else FAIL=$((FAIL+1)); echo "  FAIL — $label (non-empty output: $out)"; fi
}

summary() { echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]; }
