#!/bin/bash
# Subsystem 3c — usage-limit resilience wrapper: pause bookkeeping, lane rules,
# and hard-limit checkpointing. Never sleeps in-process; exits clean and lets
# the runtime's retry schedule resume.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
WRAP_SRC="../plugins/orchestrator/templates/orchestrator/runtime/run-with-limits.sh"
ORCH_SRC="../plugins/core/templates/orchestrator/bin/orch"
[ -f "$WRAP_SRC" ] || { echo "  FAIL — wrapper missing at $WRAP_SRC"; echo "---"; echo "0 ok, 1 failure(s)"; exit 1; }
WRAP=$(cd "$(dirname "$WRAP_SRC")" && pwd)/$(basename "$WRAP_SRC")

mk_project() { # fresh project dir with a real orch (none backend) + a stubbed claude
  local d; d=$(mktemp -d)
  mkdir -p "$d/orchestrator/bin" "$d/bin"
  cp "$ORCH_SRC" "$d/orchestrator/bin/orch"; chmod +x "$d/orchestrator/bin/orch"
  printf '{"backend":"none","forge":"none"}' > "$d/orchestrator/state.config.json"
  echo "$d"
}
stub_claude() { # stub_claude <dir> <mode: ok|limit> — writes a claude stub + call log
  cat > "$1/bin/claude" <<STUB
#!/bin/bash
echo called >> "$1/claude.calls"
STUB
  if [ "$2" = "limit" ]; then
    cat >> "$1/bin/claude" <<'STUB'
echo 'usage limit reached |1799999999'
exit 1
STUB
  else
    echo 'echo "{\"result\":\"done\"}"' >> "$1/bin/claude"
  fi
  chmod +x "$1/bin/claude"
}

# --- active pause → exits cleanly WITHOUT spending a token ---
D=$(mk_project); stub_claude "$D" ok
FUTURE=$(date -u -v+2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+2 hours" +%Y-%m-%dT%H:%M:%SZ)
CLAUDE_PROJECT_DIR="$D" "$D/orchestrator/bin/orch" state push-epic <<< '{"id":"e1","state":"Paused","note":"paused-until '"$FUTURE"' from=Planned (usage limit)"}' >/dev/null
( export CLAUDE_PROJECT_DIR="$D" PATH="$D/bin:$PATH"; bash "$WRAP" >/dev/null 2>&1 ); check "active pause → exit 0" $?
[ ! -f "$D/claude.calls" ]; check "active pause → claude never invoked" $?
rm -rf "$D"

# --- expired pause → restored to its origin state, then the build runs ---
D=$(mk_project); stub_claude "$D" ok
CLAUDE_PROJECT_DIR="$D" "$D/orchestrator/bin/orch" state push-epic <<< '{"id":"e1","state":"Paused","note":"paused-until 2020-01-01T00:00:00Z from=Changes-requested (usage limit)"}' >/dev/null
( export CLAUDE_PROJECT_DIR="$D" PATH="$D/bin:$PATH"; bash "$WRAP" >/dev/null 2>&1 ); check "expired pause → wrapper runs and exits 0" $?
CLAUDE_PROJECT_DIR="$D" "$D/orchestrator/bin/orch" state get-epic --id e1 | jq -e '.state == "Changes-requested"' >/dev/null; check "expired pause restored to its origin state (from=)" $?
[ -f "$D/claude.calls" ]; check "nightly lane builds after restore" $?
rm -rf "$D"

# --- retry lane with nothing to resume → exits without running ---
D=$(mk_project); stub_claude "$D" ok
( export CLAUDE_PROJECT_DIR="$D" PATH="$D/bin:$PATH" ORCH_LANE=retry; bash "$WRAP" >/dev/null 2>&1 ); check "retry lane, no expired pause → exit 0" $?
[ ! -f "$D/claude.calls" ]; check "retry lane spent no tokens" $?
rm -rf "$D"

# --- hard usage limit → epics checkpointed Paused with a reset timestamp ---
D=$(mk_project); stub_claude "$D" limit
CLAUDE_PROJECT_DIR="$D" "$D/orchestrator/bin/orch" state push-epic <<< '{"id":"e1","state":"Planned"}' >/dev/null
CLAUDE_PROJECT_DIR="$D" "$D/orchestrator/bin/orch" state push-epic <<< '{"id":"e2","state":"In-progress"}' >/dev/null
( export CLAUDE_PROJECT_DIR="$D" PATH="$D/bin:$PATH"; bash "$WRAP" >/dev/null 2>&1 ); check "hard limit → clean exit 0 (no in-process sleep)" $?
CLAUDE_PROJECT_DIR="$D" "$D/orchestrator/bin/orch" state get-epic --id e1 | jq -e '.state == "Paused" and (.note | test("paused-until .* from=Planned"))' >/dev/null; check "Planned epic paused with origin recorded" $?
CLAUDE_PROJECT_DIR="$D" "$D/orchestrator/bin/orch" state get-epic --id e2 | jq -e '.state == "Paused" and (.note | test("from=In-progress"))' >/dev/null; check "In-progress epic paused too (mid-build limit)" $?
rm -rf "$D"

# R12: wrapper hardening
grep -q "ORCH_MAX_TURNS" "$WRAP_SRC"; check "wrapper caps turns" $?
grep -q "ORCH_MAX_BUDGET_USD" "$WRAP_SRC"; check "wrapper supports the native cost cap (optional)" $?
grep -q -- "--strict-mcp-config" "$WRAP_SRC"; check "wrapper pins MCP config" $?
! grep -- "--bare" "$WRAP_SRC" | grep -v "^\s*#" | grep -q .; check "wrapper never uses --bare (ADR-0019; comments excepted)" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
