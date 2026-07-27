#!/bin/bash
# pm-linear native semantics (ADR-0027): epics are Issues, records carrying a
# parent become SUB-ISSUES via parentId, the initiative tier is a Linear PROJECT,
# and lifecycle state maps onto real workflow states with a label fallback —
# exercised against a scripted Linear GraphQL double (mocks/linear-fetch-mock.js).
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v node >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "  skip — node/jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
A="$(cd .. && pwd)/plugins/core/templates/orchestrator/adapters/pm-linear.js"
MOCK="$(pwd)/mocks/linear-fetch-mock.js"

export LINEAR_API_KEY="lin_api_not-a-real-token"

mkproj() { # mkproj <linear-config-json>
  local d; d=$(mktemp -d)
  mkdir -p "$d/orchestrator" "$d/.orch/cache"
  printf '{"backend":"linear","forge":"none","linear":%s}' "$1" > "$d/orchestrator/state.config.json"
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
# a team with the four workflow states the map targets, plus the orch labels
TEAM='{"teams":[{"id":"team_1","key":"ENG","name":"Engineering",
  "states":{"nodes":[{"id":"st_todo","name":"Todo","type":"unstarted"},{"id":"st_prog","name":"In Progress","type":"started"},{"id":"st_rev","name":"In Review","type":"started"},{"id":"st_done","name":"Done","type":"completed"}]},
  "labels":{"nodes":[{"id":"lbl_epic","name":"orch-epic"},{"id":"lbl_child","name":"orch-child"},{"id":"lbl_spec","name":"orch-spec"}]}}]}'
SM='{"teamKey":"ENG","stateMap":{"Suggested":"Todo","Backlog":"Todo","Needs-plan":"Todo","Planned":"Todo","In-progress":"In Progress","Needs-review":"In Review","Changes-requested":"In Review","Approved":"Done","Merged":"Done","Blocked":"Todo","Paused":"Todo","Cancelled":"Done"}}'
scen() { python3 -c "
import json,sys
base=json.loads('''$TEAM''')
base.update(json.loads(sys.argv[1] or '{}'))
print(json.dumps(base))" "$1"; }

# --- auth: a personal key goes RAW; only OAuth takes Bearer -------------------
D=$(mkproj "$SM")
run_op "$D" "$(scen '')" health >/dev/null
jq -se '.[0].auth == "lin_api_not-a-real-token"' "$D/wire.log" >/dev/null
check "personal API key is sent RAW (Bearer would be a silent 401)" $?
LINEAR_API_KEY="lin_oauth_abc" run_op "$D" "$(scen '')" health >/dev/null
jq -se '.[0].auth == "Bearer lin_oauth_abc"' "$D/wire.log" >/dev/null
check "an OAuth token IS sent as Bearer" $?
jq -se '.[0].url | test("api.linear.app/graphql")' "$D/wire.log" >/dev/null
check "talks to the GraphQL endpoint" $?
rm -rf "$D"

# --- 1. epic → Issue, with the mapped workflow state set directly ------------
D=$(mkproj "$SM")
RUN_STDIN='{"id":"e1","title":"Native epic","state":"Backlog"}' run_op "$D" "$(scen '')" push-epic >/dev/null
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.teamId == "team_1"' "$D/wire.log" >/dev/null
check "push-epic creates a Linear Issue on the configured team" $?
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.stateId == "st_todo"' "$D/wire.log" >/dev/null
check "state is set DIRECTLY via stateId (no transition graph, unlike Jira)" $?
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.labelIds | index("lbl_epic") != null' "$D/wire.log" >/dev/null
check "labelled orch-epic" $?
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.title == "[e1] Native epic"' "$D/wire.log" >/dev/null
check "title carries the [id] convention" $?
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.description | test("```json")' "$D/wire.log" >/dev/null
check "the record round-trips as a json fence in the description" $?
rm -rf "$D"

# --- 2. a record with a parent becomes a SUB-ISSUE ---------------------------
D=$(mkproj "$SM")
PARENT='{"issues":[{"id":"iss_parent","identifier":"ENG-9","title":"[e1] Native epic","description":null,"state":{"id":"st_todo","name":"Todo"},"labels":{"nodes":[{"name":"orch-epic"}]},"parent":null,"project":null}]}'
RUN_STDIN='{"id":"e1-c1","title":"Child work","state":"Backlog","parent":"e1"}' \
  run_op "$D" "$(scen "$PARENT")" push-epic >/dev/null
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.parentId == "iss_parent"' "$D/wire.log" >/dev/null
check "record with parent → sub-issue linked via parentId (native)" $?
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.labelIds | index("lbl_child") != null' "$D/wire.log" >/dev/null
check "child labelled orch-child" $?
rm -rf "$D"

# --- 3. the initiative tier is a real Linear PROJECT -------------------------
D=$(mkproj "$SM")
RUN_STDIN='{"id":"e2","title":"Auth work","state":"Backlog","initiative":"Auth revamp"}' \
  run_op "$D" "$(scen '{"projects":[{"id":"prj_auth","name":"Auth revamp"}]}')" push-epic >/dev/null
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.projectId == "prj_auth"' "$D/wire.log" >/dev/null
check "initiative → the issue is filed under the matching Linear PROJECT" $?
rm -rf "$D"
# a missing project must NOT be invented — warn, keep the payload field, carry on
D=$(mkproj "$SM")
RUN_STDIN='{"id":"e3","title":"Orphan","state":"Backlog","initiative":"Nonexistent"}' \
  run_op "$D" "$(scen '{"projects":[]}')" push-epic >/dev/null
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i | has("projectId") | not' "$D/wire.log" >/dev/null
check "a missing project is never created implicitly" $?
grep -qi "no Linear project" "$D/stderr.log"; check "…and it is warned on stderr" $?
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.description | test("Nonexistent")' "$D/wire.log" >/dev/null
check "…and the initiative survives in the payload (never fails the run)" $?
rm -rf "$D"

# --- 4. a workflow state missing from the team → label fallback --------------
D=$(mkproj '{"teamKey":"ENG","stateMap":{"In-progress":"Nonexistent State"}}')
RUN_STDIN='{"id":"e4","title":"Fallback","state":"In-progress"}' run_op "$D" "$(scen '')" push-epic >/dev/null
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i | has("stateId") | not' "$D/wire.log" >/dev/null
check "unknown workflow state → stateId omitted" $?
jq -se '[.[]|select(.op=="issueLabelCreate")]|any(.variables.i.name == "orch-state-In-progress")' "$D/wire.log" >/dev/null
check "…and the orch-state-* label is used instead" $?
grep -qi "does not exist" "$D/stderr.log"; check "…and the fallback is logged" $?
rm -rf "$D"

# --- 5. no stateMap at all → pure label behaviour ----------------------------
D=$(mkproj '{"teamKey":"ENG"}')
RUN_STDIN='{"id":"e5","title":"Legacy","state":"Planned"}' run_op "$D" "$(scen '')" push-epic >/dev/null
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i | has("stateId") | not' "$D/wire.log" >/dev/null
check "no stateMap → stateId never set" $?
jq -se '[.[]|select(.op=="issueLabelCreate")]|any(.variables.i.name == "orch-state-Planned")' "$D/wire.log" >/dev/null
check "no stateMap → orch-state-* label written" $?
rm -rf "$D"

# --- 6. reads: payload → reverse stateMap → label ----------------------------
D=$(mkproj "$SM")
READS='{"issues":[
 {"id":"i1","title":"[p1] Payload wins","description":"```json\n{\"id\":\"p1\",\"title\":\"Payload wins\",\"state\":\"Needs-review\"}\n```","state":{"name":"Done"},"labels":{"nodes":[{"name":"orch-epic"}]},"parent":null,"project":null},
 {"id":"i2","title":"[p2] Reverse mapped","description":null,"state":{"name":"In Progress"},"labels":{"nodes":[{"name":"orch-epic"}]},"parent":null,"project":null},
 {"id":"i3","title":"[p3] Label last resort","description":null,"state":{"name":"Unmapped"},"labels":{"nodes":[{"name":"orch-epic"},{"name":"orch-state-Paused"}]},"parent":null,"project":null}
]}'
out=$(run_op "$D" "$(scen "$READS")" list-epics)
echo "$out" | jq -e '[.[]|select(.id=="p1")][0].state == "Needs-review"' >/dev/null
check "read: exact state from the JSON payload (precise source of truth)" $?
echo "$out" | jq -e '[.[]|select(.id=="p2")][0].state == "In-progress"' >/dev/null
check "read: workflow state reverse-mapped to a lifecycle state" $?
echo "$out" | jq -e '[.[]|select(.id=="p3")][0].state == "Paused"' >/dev/null
check "read: orch-state-* label as last resort" $?
rm -rf "$D"

# --- 7. the board is the golden source: human-set parent/project win ---------
D=$(mkproj "$SM")
HUMAN='{"issues":[
 {"id":"i9","title":"[h1] Written by a human","description":null,"state":{"name":"Todo"},"labels":{"nodes":[{"name":"orch-epic"}]},"parent":{"id":"ip","title":"[top] Parent epic"},"project":{"id":"pj","name":"Platform"}}
]}'
out=$(run_op "$D" "$(scen "$HUMAN")" list-epics --level epic)
echo "$out" | jq -e '.[0].id == "h1" and .[0].title == "Written by a human"' >/dev/null
check "a card with NO payload is still read (board is the source of truth)" $?
echo "$out" | jq -e '.[0].parentId == "top"' >/dev/null
check "the NATIVE parent link is read back into parentId" $?
echo "$out" | jq -e '.[0].initiative == "Platform"' >/dev/null
check "the NATIVE project is read back as the initiative" $?
rm -rf "$D"

# --- 8. hierarchy filters + the un-flagged call is unchanged -----------------
D=$(mkproj "$SM")
MIX='{"issues":[
 {"id":"a","title":"[a] Epic A","description":"```json\n{\"id\":\"a\",\"state\":\"Planned\",\"initiative\":\"Auth\"}\n```","state":{"name":"Todo"},"labels":{"nodes":[{"name":"orch-epic"}]},"parent":null,"project":null},
 {"id":"b","title":"[b] Epic B","description":"```json\n{\"id\":\"b\",\"state\":\"Planned\",\"initiative\":\"UI\"}\n```","state":{"name":"Todo"},"labels":{"nodes":[{"name":"orch-epic"}]},"parent":null,"project":null},
 {"id":"c","title":"[c] Child of A","description":"```json\n{\"id\":\"c\",\"state\":\"Planned\"}\n```","state":{"name":"Todo"},"labels":{"nodes":[{"name":"orch-child"}]},"parent":{"id":"ia","title":"[a] Epic A"},"project":null}
]}'
S=$(scen "$MIX")
[ "$(run_op "$D" "$S" list-epics | jq -c 'map(.id)')" = '["a","b"]' ]
check "un-flagged list-epics excludes children (no behaviour change)" $?
[ "$(run_op "$D" "$S" list-epics --level child | jq -c 'map(.id)')" = '["c"]' ]
check "--level child surfaces sub-issues" $?
[ "$(run_op "$D" "$S" list-epics --initiative Auth | jq -c 'map(.id)')" = '["a"]' ]
check "--initiative filters" $?
[ "$(run_op "$D" "$S" list-epics --parent a --level child | jq -c 'map(.id)')" = '["c"]' ]
check "--parent filters to a parent's children" $?
run_op "$D" "$S" list-initiatives | jq -e 'length == 2' >/dev/null
check "list-initiatives returns the tier (epics only — a child is not an initiative)" $?
run_op "$D" "$S" list-initiatives | jq -e 'all(.id != "unassigned")' >/dev/null
check "…and a parented child never conjures an 'unassigned' initiative" $?
rm -rf "$D"

# --- 9. push-status carries pr / assignee / lease (the claim model) ----------
D=$(mkproj "$SM")
run_op "$D" "$(scen '')" push-status --id e9 --state In-progress --pr 42 --assignee agent-1 --lease-until 2026-07-27T12:00:00Z >/dev/null
jq -se '[.[]|select(.op=="issueCreate")][0].variables.i.description | fromjson? // (capture("```json\n(?<j>[\\s\\S]*?)\n```").j | fromjson) | .pr == 42 and .assignee == "agent-1" and .leaseUntil != null' "$D/wire.log" >/dev/null
check "push-status persists pr, assignee and leaseUntil" $?
rm -rf "$D"

# --- 10. health validates the stateMap against the team's REAL states --------
D=$(mkproj '{"teamKey":"ENG","stateMap":{"In-progress":"In Progress","Merged":"Shipped"}}')
out=$(run_op "$D" "$(scen '')" health)
echo "$out" | jq -e '.ok == true and .backend == "linear"' >/dev/null
check "health ok with a stateMap configured" $?
echo "$out" | jq -e '.stateMap.missing | index("Shipped") != null' >/dev/null
check "health reports stateMap targets missing from the team (Shipped)" $?
grep -qi "Shipped" "$D/stderr.log"; check "each missing state is warned on stderr" $?
rm -rf "$D"

# --- 11. failure handling ----------------------------------------------------
D=$(mkproj "$SM")
run_op "$D" '{"errors":[{"message":"Authentication required"}]}' health >/dev/null 2>&1
[ $? -ne 0 ]; check "a GraphQL 200-with-errors is treated as a FAILURE, not success" $?
grep -qi "Authentication required" "$D/stderr.log"; check "the API error message reaches stderr" $?
grep -qiE "lin_api_|Authorization|Bearer " "$D/stderr.log" && r=1 || r=0; [ "$r" = 0 ]
check "stderr never echoes tokens/headers" $?
D2=$(mkproj '{"teamKey":"NOPE"}')
run_op "$D2" "$(scen '{"teams":[]}')" health >/dev/null 2>&1
[ $? -ne 0 ]; check "an unknown team fails loudly" $?
rm -rf "$D" "$D2"

# --- 12. an unparseable payload skips ONE card, never the whole listing ------
D=$(mkproj "$SM")
BAD='{"issues":[
 {"id":"x","title":"[x] Broken","description":"```json\n{not valid json\n```","state":{"name":"Todo"},"labels":{"nodes":[{"name":"orch-epic"}]},"parent":null,"project":null},
 {"id":"y","title":"[y] Fine","description":"```json\n{\"id\":\"y\",\"state\":\"Planned\"}\n```","state":{"name":"Todo"},"labels":{"nodes":[{"name":"orch-epic"}]},"parent":null,"project":null}
]}'
out=$(run_op "$D" "$(scen "$BAD")" list-epics)
echo "$out" | jq -e 'any(.id == "y")' >/dev/null
check "a malformed payload does not kill the listing" $?
echo "$out" | jq -e 'any(.id == "x")' >/dev/null
check "…and the broken card still appears via the [id] title fallback" $?
rm -rf "$D"

# --- 13. the 16-op contract is intact (grep-enforced in test-board-setup too) -
for o in health capabilities push-epic push-backlog get-epic list-epics push-status pull-status \
         push-spec get-spec list-specs push-plan get-plan push-session pull-session push-digest; do
  grep -q "'$o'" "$A"; check "contract op present: $o" $?
done
grep -q "hierarchy: 'native'" "$A"; check "capabilities advertises native hierarchy" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
