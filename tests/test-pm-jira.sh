#!/bin/bash
# pm-jira native semantics (ADR-0021): Epic issue type, parent-linked children,
# statusMap-driven transitions, and label fallback at every seam — exercised
# against a scripted Jira REST double (tests/mocks/jira-fetch-mock.js).
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v node >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "  skip — node/jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
A="$(cd .. && pwd)/plugins/core/templates/orchestrator/adapters/pm-jira.js"
MOCK="$(pwd)/mocks/jira-fetch-mock.js"

export JIRA_BASE_URL="https://mock.example" JIRA_EMAIL="t@t" JIRA_API_TOKEN="not-a-real-token"

mkproj() { # mkproj <jira-config-json>
  local d; d=$(mktemp -d)
  mkdir -p "$d/orchestrator" "$d/.orch/cache"
  printf '{"backend":"jira","forge":"none","jira":%s}' "$1" > "$d/orchestrator/state.config.json"
  echo "$d"
}
run_op() { # run_op <projdir> <scenario-json> <op...> [stdin via $RUN_STDIN]
  local d="$1" scen="$2"; shift 2
  echo "$scen" > "$d/scenario.json"
  : > "$d/wire.log"
  if [ -n "${RUN_STDIN:-}" ]; then
    echo "$RUN_STDIN" | CLAUDE_PROJECT_DIR="$d" MOCK_SCENARIO_FILE="$d/scenario.json" MOCK_LOG="$d/wire.log" \
      node --require "$MOCK" "$A" "$@" 2>"$d/stderr.log"
  else
    CLAUDE_PROJECT_DIR="$d" MOCK_SCENARIO_FILE="$d/scenario.json" MOCK_LOG="$d/wire.log" \
      node --require "$MOCK" "$A" "$@" 2>"$d/stderr.log"
  fi
}
SM='{"projectKey":"MOCK","statusMap":{"Suggested":"Idea","Backlog":"To Do","Needs-plan":"To Do","Planned":"To Do","In-progress":"In Progress","Needs-review":"Testing","Changes-requested":"Testing","Approved":"Done","Merged":"Done","Blocked":"To Do","Paused":"To Do","Cancelled":"Done"}}'

# --- 1. epic created as the Epic issue type + transitioned to the mapped status ---
D=$(mkproj "$SM")
RUN_STDIN='{"id":"e1","title":"Native epic","state":"Backlog"}' \
  run_op "$D" '{"transitions":[{"id":"21","to":{"name":"To Do"}}]}' push-epic >/dev/null
jq -se '[.[]|select(.method=="POST" and (.path|endswith("/issue")))][0].body.fields.issuetype.name == "Epic"' "$D/wire.log" >/dev/null
check "push-epic creates a Jira Epic (native issue type)" $?
jq -se '[.[]|select(.method=="POST" and (.path|test("/transitions$")))] | length == 1' "$D/wire.log" >/dev/null
check "state applied as a workflow TRANSITION to the mapped status" $?
jq -se '[.[]|select(.method=="POST" and (.path|endswith("/issue")))][0].body.fields.labels | index("orch-state-Backlog") == null' "$D/wire.log" >/dev/null
check "native mode: no orch-state-* label written" $?
rm -rf "$D"

# --- 2. child issue: parent link + childIssueType ---
D=$(mkproj "$SM")
PARENT='{"issues":[{"key":"MOCK-9","fields":{"summary":"[e1] Native epic","labels":["orch-epic"],"description":null,"status":{"name":"To Do"}}}],"total":1}'
RUN_STDIN='{"id":"e1-c1","title":"Child work item","state":"Backlog","parent":"e1"}' \
  run_op "$D" "{\"search\":$PARENT,\"transitions\":[{\"id\":\"21\",\"to\":{\"name\":\"To Do\"}}]}" push-epic >/dev/null
jq -se '[.[]|select(.method=="POST" and (.path|endswith("/issue")))][0].body.fields.parent.key == "MOCK-9"' "$D/wire.log" >/dev/null
check "record with parent → child issue linked to the Epic (parent.key)" $?
jq -se '[.[]|select(.method=="POST" and (.path|endswith("/issue")))][0].body.fields.issuetype.name == "Task"' "$D/wire.log" >/dev/null
check "child uses childIssueType (Task)" $?
rm -rf "$D"

# --- 3. target status unreachable via available transitions → label fallback ---
D=$(mkproj "$SM")
EXISTING='{"issues":[{"key":"MOCK-2","fields":{"summary":"[e2] Stuck","labels":["orch-epic"],"description":null,"status":{"name":"Idea"}}}],"total":1}'
run_op "$D" "{\"search\":$EXISTING,\"transitions\":[{\"id\":\"51\",\"to\":{\"name\":\"Done\"}}]}" \
  push-status --id e2 --state In-progress >/dev/null
jq -se '[.[]|select(.method=="PUT")]|any(.body.fields.labels | index("orch-state-In-progress"))' "$D/wire.log" >/dev/null
check "unreachable transition → orch-state-* label fallback applied" $?
grep -qi "fall" "$D/stderr.log"; check "fallback is logged to stderr" $?
grep -qiE "token|Authorization|Basic " "$D/stderr.log" && r=1 || r=0; [ "$r" = 0 ]
check "stderr never echoes tokens/headers" $?
rm -rf "$D"

# --- 4. no statusMap at all → pure label behavior, no transitions endpoint touched ---
D=$(mkproj '{"projectKey":"MOCK"}')
RUN_STDIN='{"id":"e3","title":"Legacy","state":"Planned"}' run_op "$D" '{}' push-epic >/dev/null
jq -se '[.[]|select(.path|test("/transitions"))] | length == 0' "$D/wire.log" >/dev/null
check "no statusMap → transitions never called (legacy label scheme)" $?
jq -se '[.[]|select(.method=="POST" and (.path|endswith("/issue")))][0].body.fields.labels | index("orch-state-Planned") != null' "$D/wire.log" >/dev/null
check "no statusMap → orch-state-* label written on create" $?
rm -rf "$D"

# --- 5. reads: payload first, else reverse statusMap, else orch-state label ---
D=$(mkproj "$SM")
READS='{"issues":[
 {"key":"M-1","fields":{"summary":"[p1] Payload wins","labels":["orch-epic"],"status":{"name":"Done"},
   "description":{"type":"doc","version":1,"content":[{"type":"codeBlock","attrs":{"language":"json"},"content":[{"type":"text","text":"{\"id\":\"p1\",\"title\":\"Payload wins\",\"state\":\"Needs-review\"}"}]}]}}},
 {"key":"M-2","fields":{"summary":"[p2] Status reverse-mapped","labels":["orch-epic"],"description":null,"status":{"name":"In Progress"}}},
 {"key":"M-3","fields":{"summary":"[p3] Label last resort","labels":["orch-epic","orch-state-Paused"],"description":null,"status":{"name":"Unmapped Status"}}}
],"total":3}'
out=$(run_op "$D" "{\"search\":$READS}" list-epics)
echo "$out" | jq -e '[.[]|select(.id=="p1")][0].state == "Needs-review"' >/dev/null
check "read: exact state from the JSON payload (precise source of truth)" $?
echo "$out" | jq -e '[.[]|select(.id=="p2")][0].state == "In-progress"' >/dev/null
check "read: status reverse-mapped to a lifecycle state" $?
echo "$out" | jq -e '[.[]|select(.id=="p3")][0].state == "Paused"' >/dev/null
check "read: orch-state-* label as last resort" $?
rm -rf "$D"

# --- 6. health validates every statusMap target against the project's real statuses ---
D=$(mkproj "$SM")
STATUSES='[{"name":"Task","statuses":[{"name":"To Do"},{"name":"In Progress"},{"name":"Testing"},{"name":"Done"}]}]'
out=$(run_op "$D" "{\"projectStatuses\":$STATUSES}" health)
echo "$out" | jq -e '.ok == true and .backend == "jira"' >/dev/null
check "health ok with statusMap configured" $?
echo "$out" | jq -e '.statusMap.missing | index("Idea") != null' >/dev/null
check "health reports statusMap targets missing from the project (Idea)" $?
grep -qi "Idea" "$D/stderr.log"; check "each missing status is warned on stderr" $?
rm -rf "$D"

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
