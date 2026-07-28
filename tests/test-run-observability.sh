#!/bin/bash
# The run used to be unobservable: build_wave sent stdout AND stderr to
# /dev/null, and the call site discarded again. A failed wave escalated with no
# diagnosis, and nobody could see which agent did what. This pins both the
# logging and the renderer that reads it.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."
DRIVER="$R/plugins/orchestrator/templates/orchestrator/runtime/run-to-done.sh"
WATCH="$R/plugins/orchestrator/templates/orchestrator/bin/watch"
SKILL="$R/plugins/orchestrator/skills/watch/SKILL.md"

[ -f "$DRIVER" ] && bash -n "$DRIVER"; check "driver parses" $?
[ -f "$WATCH" ] && bash -n "$WATCH"; check "watch parses" $?
[ -x "$WATCH" ]; check "watch is executable (cp -R preserves the bit)" $?
[ -f "$SKILL" ]; check "the watch skill ships" $?

# --- the regression itself -----------------------------------------------------
! grep -q 'output-format json >/dev/null 2>&1' "$DRIVER"
check "build_wave no longer discards stdout+stderr" $?
! grep -qE 'build_wave \$wave \) >/dev/null 2>&1' "$DRIVER"
check "the call site no longer discards either" $?
grep -q 'ORCH_RUN_LOG' "$DRIVER"; check "the run stream is written to a log" $?
grep -q 'ORCH_ERR_LOG' "$DRIVER"; check "stderr is kept, not dropped" $?
grep -q 'tail -5 "$ORCH_ERR_LOG"' "$DRIVER"; check "a failed wave surfaces its reason" $?
grep -q 'return \$rc' "$DRIVER"; check "the wave's exit code survives logging (no pipe)" $?
# verify_epic's stdout is PARSED — it must stay json, only its stderr may move
grep -q 'output-format json --json-schema' "$DRIVER"
check "verify_epic still returns parseable json on stdout" $?
grep -q '2>>"\$ORCH_ERR_LOG" | jq -c' "$DRIVER"; check "…with its stderr logged instead of dropped" $?

# --- the flag probe: an unknown flag would fail EVERY wave ----------------------
grep -q 'forward-subagent-text' "$DRIVER"; check "stream requests subagent text" $?
grep -q 'claude -p --help' "$DRIVER"; check "…but probes for the flag rather than assuming it" $?
grep -q 'ORCH_STREAM' "$DRIVER"; check "streaming has an escape hatch" $?

# --- logs must never become commits -------------------------------------------
grep -q "logs/.gitignore" "$DRIVER" || grep -q '.gitignore' "$DRIVER"
check "the log dir self-ignores (CI force-adds .orch to orch/state)" $?

# --- the renderer, against a real stream-json shape ----------------------------
if command -v jq >/dev/null 2>&1; then
  T=$(mktemp -d); mkdir -p "$T/.orch/logs" "$T/orchestrator/bin"
  cp "$WATCH" "$T/orchestrator/bin/watch"; D=$(date +%F)
  cat > "$T/.orch/logs/run-$D.jsonl" <<'JSONL'
{"type":"system","subtype":"init","session_id":"abc123def456","model":"claude-opus-5","cwd":"/repo"}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"t2","name":"Task","input":{"subagent_type":"core:code-reviewer","description":"review the diff"}}]}}
{"type":"assistant","parent_tool_use_id":"t2","message":{"content":[{"type":"tool_use","id":"t3","name":"Read","input":{"file_path":"src/auth/login.ts"}}]}}
{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"1 finding"}]}]}}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"t4","name":"Bash","input":{"command":"bash tests/run-tests.sh"}}]}}
{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"t4","is_error":true,"content":[{"type":"text","text":"2 suites FAILED"}]}]}}
{"type":"result","subtype":"success","num_turns":14,"total_cost_usd":1.23456,"duration_ms":92500}
JSONL
  out=$(CLAUDE_PROJECT_DIR="$T" NO_COLOR=1 bash "$T/orchestrator/bin/watch" --replay 2>&1)
  echo "$out" | grep -q "subagent core:code-reviewer"; check "renders the subagent by type" $?
  echo "$out" | grep -qE '^   │ ▸ Read src/auth/login.ts'
  check "a child tool call is INDENTED under its parent agent" $?
  echo "$out" | grep -q "✗ Bash"; check "a failed tool is marked, with the tool it failed in" $?
  echo "$out" | grep -q "└ subagent core:code-reviewer returned"; check "the agent's return closes the branch" $?
  echo "$out" | grep -q "14 turns"; check "the run's cost/turns land in the summary" $?
  [ -z "$(echo "$out" | grep -c $'\033')" ] || echo "$out" | grep -qv $'\033'
  check "NO_COLOR output carries no escape codes (pipeable)" $?
  # an unreadable/absent log must fail loudly, not print an empty tree
  CLAUDE_PROJECT_DIR="$T" bash "$T/orchestrator/bin/watch" --date 1999-01-01 >/dev/null 2>&1
  [ $? -ne 0 ]; check "a missing log exits non-zero instead of showing nothing" $?
  rm -rf "$T"
else
  echo "  skip — jq not available"
fi

# --- the skill tells the truth about what watching can and cannot do -----------
grep -qi "read-only" "$SKILL"; check "skill states it never mutates" $?
grep -qi "cannot ask you anything mid-run\|no interactive channel" "$SKILL"
check "skill states subagents cannot ask questions mid-run" $?
grep -q "orch state list-epics\|/orch approve" "$SKILL"; check "…and names where decisions actually go" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
