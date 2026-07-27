#!/bin/bash
# pm-notion native relations (ADR-0030): Type=Epic/Task, a "Parent epic"
# self-relation for tasks, and a SEPARATE Initiatives data source for the tier.
# Every relation feature is optional — the degradation paths matter most,
# because existing boards have none of them.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v node >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "  skip — node/jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
A="$(cd .. && pwd)/plugins/core/templates/orchestrator/adapters/pm-notion.js"
MOCK="$(pwd)/mocks/notion-fetch-mock.js"
export NOTION_TOKEN="not-a-real-token"

mkproj() { local d; d=$(mktemp -d); mkdir -p "$d/orchestrator" "$d/.orch/cache"
  printf '{"backend":"notion","forge":"none","notion":%s}' "$1" > "$d/orchestrator/state.config.json"; echo "$d"; }
run_op() { local d="$1" scen="$2"; shift 2
  echo "$scen" > "$d/scenario.json"; : > "$d/wire.log"
  if [ -n "${RUN_STDIN:-}" ]; then
    echo "$RUN_STDIN" | CLAUDE_PROJECT_DIR="$d" MOCK_SCENARIO_FILE="$d/scenario.json" MOCK_LOG="$d/wire.log" \
      node --require "$MOCK" "$A" "$@" 2>"$d/stderr.log"
  else
    CLAUDE_PROJECT_DIR="$d" MOCK_SCENARIO_FILE="$d/scenario.json" MOCK_LOG="$d/wire.log" \
      node --require "$MOCK" "$A" "$@" 2>"$d/stderr.log"
  fi
}
# a board carrying the full native schema
FULL='"props":{"Name":{"type":"title"},"State":{"type":"select"},"Epic ID":{"type":"rich_text"},"Type":{"type":"select"},"Parent epic":{"type":"relation"},"Initiative":{"type":"relation"}},"initProps":{"Name":{"type":"title"}}'
# a legacy board: title + state only
FLAT='"props":{"Name":{"type":"title"},"State":{"type":"select"},"Epic ID":{"type":"rich_text"}}'
CFG_FULL='{"dataSourceId":"ds_epics","initiativesDataSourceId":"ds_inits"}'
CFG_FLAT='{"dataSourceId":"ds_epics"}'

# --- the API version bump ----------------------------------------------------
D=$(mkproj "$CFG_FULL")
run_op "$D" "{$FULL}" health >/dev/null
jq -se 'all(.[]; .version != "2022-06-28")' "$D/wire.log" >/dev/null
check "no request still pins the pre-data-source API version" $?
jq -se 'any(.[]; .path | test("^/data_sources/"))' "$D/wire.log" >/dev/null
check "talks to /data_sources (not /databases)" $?
rm -rf "$D"

# --- legacy config: databaseId is resolved, loudly ---------------------------
D=$(mkproj '{"databaseId":"db_legacy"}')
run_op "$D" "{$FLAT}" health >/dev/null
jq -se 'any(.[]; .method=="GET" and .path=="/databases/db_legacy")' "$D/wire.log" >/dev/null
check "a legacy databaseId config still works (resolves its data source)" $?
grep -qi "record it in state.config.json" "$D/stderr.log"
check "…and tells the operator to record the dataSourceId" $?
rm -rf "$D"

# --- push: Type, parent self-relation, initiative relation -------------------
D=$(mkproj "$CFG_FULL")
PAGES='"pages":[{"id":"pg_parent","properties":{"Name":{"type":"title","title":[{"plain_text":"[e1] Parent epic"}]}}}]'
INITS='"initPages":[{"id":"pg_init","properties":{"Name":{"type":"title","title":[{"plain_text":"Auth revamp"}]}}}]'
RUN_STDIN='{"id":"e1-c1","title":"A task","state":"Planned","parent":"e1","initiative":"Auth revamp"}' \
  run_op "$D" "{$FULL,$PAGES,$INITS}" push-epic >/dev/null
POST='[.[]|select(.method=="POST" and .path=="/pages")][0]'
jq -se "$POST.body.properties.Type.select.name == \"Task\"" "$D/wire.log" >/dev/null
check "a record with a parent is written as Type=Task" $?
jq -se "$POST.body.properties.\"Parent epic\".relation[0].id == \"pg_parent\"" "$D/wire.log" >/dev/null
check "…and linked by the Parent epic self-relation" $?
jq -se "$POST.body.properties.Initiative.relation[0].id == \"pg_init\"" "$D/wire.log" >/dev/null
check "…and filed under the matching Initiative page" $?
jq -se "$POST.body.parent.data_source_id == \"ds_epics\"" "$D/wire.log" >/dev/null
check "pages are created under a data_source_id parent (not database_id)" $?
jq -se "$POST.body.parent | has(\"database_id\") | not" "$D/wire.log" >/dev/null
check "database_id is never sent (rejected for relation writes since 2025-09-03)" $?
RUN_STDIN='{"id":"e2","title":"An epic","state":"Planned"}' run_op "$D" "{$FULL,$INITS}" push-epic >/dev/null
jq -se "$POST.body.properties.Type.select.name == \"Epic\"" "$D/wire.log" >/dev/null
check "a record with no parent is written as Type=Epic" $?
rm -rf "$D"

# --- a missing parent/initiative warns and carries on, never fails -----------
D=$(mkproj "$CFG_FULL")
RUN_STDIN='{"id":"x","title":"Orphan","state":"Planned","parent":"nope","initiative":"Nonexistent"}' \
  run_op "$D" "{$FULL}" push-epic >/dev/null
check "a missing parent AND initiative still exits 0" $?
jq -se "$POST.body.properties | has(\"Parent epic\") | not" "$D/wire.log" >/dev/null
check "…the parent relation is omitted rather than cleared" $?
grep -qi "not found" "$D/stderr.log"; check "…and the missing parent is warned" $?
grep -qi "no Initiative page" "$D/stderr.log"; check "…and the missing initiative is warned" $?
rm -rf "$D"

# --- DEGRADATION: a board with none of the new properties keeps working ------
D=$(mkproj "$CFG_FLAT")
RUN_STDIN='{"id":"e9","title":"Legacy board","state":"Planned","parent":"e1"}' \
  run_op "$D" "{$FLAT}" push-epic >/dev/null
check "a board with no Type/Parent/Initiative still accepts a push" $?
jq -se "$POST.body.properties | has(\"Type\") | not" "$D/wire.log" >/dev/null
check "…Type is not written to a board that lacks it" $?
jq -se "$POST.body.properties | has(\"Parent epic\") | not" "$D/wire.log" >/dev/null
check "…nor the parent relation" $?
run_op "$D" "{$FLAT}" capabilities | jq -e '.hierarchy == "derived"' >/dev/null
check "…and capabilities reports hierarchy=derived, not native" $?
rm -rf "$D"
D=$(mkproj "$CFG_FULL")
run_op "$D" "{$FULL}" capabilities | jq -e '.hierarchy == "native"' >/dev/null
check "a full board reports hierarchy=native" $?
rm -rf "$D"

# --- reads: native values win over a stale payload ---------------------------
D=$(mkproj "$CFG_FULL")
READS='"pages":[
 {"id":"pg_a","properties":{"Name":{"type":"title","title":[{"plain_text":"[a] Epic A"}]},"Epic ID":{"type":"rich_text","rich_text":[{"plain_text":"a"}]},"State":{"type":"select","select":{"name":"Planned"}},"Type":{"type":"select","select":{"name":"Epic"}},"Initiative":{"type":"relation","relation":[{"id":"pg_init"}]}}},
 {"id":"pg_t","properties":{"Name":{"type":"title","title":[{"plain_text":"[a-t1] Task one"}]},"Epic ID":{"type":"rich_text","rich_text":[{"plain_text":"a-t1"}]},"State":{"type":"select","select":{"name":"Planned"}},"Type":{"type":"select","select":{"name":"Task"}},"Parent epic":{"type":"relation","relation":[{"id":"pg_a"}]}}}
],"blocks":{"pg_t":[{"id":"blk","type":"code","code":{"rich_text":[{"plain_text":"{\"id\":\"a-t1\",\"state\":\"Planned\",\"parentId\":\"STALE\"}"}]}}]}'
out=$(run_op "$D" "{$FULL,$READS,$INITS}" list-epics --level child)
echo "$out" | jq -e '.[0].parentId == "a"' >/dev/null
check "the NATIVE parent relation overrides a stale payload value" $?
out=$(run_op "$D" "{$FULL,$READS,$INITS}" list-epics)
echo "$out" | jq -e 'length == 1 and .[0].id == "a"' >/dev/null
check "un-flagged list-epics still excludes Tasks (no behaviour change)" $?
echo "$out" | jq -e '.[0].initiative == "Auth revamp"' >/dev/null
check "the NATIVE Initiative relation is read back" $?
rm -rf "$D"

# --- initiatives come from real pages when configured ------------------------
D=$(mkproj "$CFG_FULL")
INITS2='"initPages":[{"id":"pg_init","properties":{"Name":{"type":"title","title":[{"plain_text":"Auth revamp"}]},"State":{"type":"select","select":{"name":"In-progress"}}}}]'
out=$(run_op "$D" "{$FULL,$READS,$INITS2}" list-initiatives)
echo "$out" | jq -e 'length == 1 and .[0].id == "Auth revamp"' >/dev/null
check "list-initiatives returns the real Initiative page" $?
echo "$out" | jq -e '.[0].state == "In-progress"' >/dev/null
check "…with the state from the page, not synthesized" $?
echo "$out" | jq -e '.[0].epics == ["a"]' >/dev/null
check "…and its child epics (tasks excluded)" $?
echo "$out" | jq -e '.[0] | has("synthesized") | not' >/dev/null
check "…and it is not marked synthesized" $?
D2=$(mkproj "$CFG_FLAT")
run_op "$D2" "{$FLAT,$READS}" list-initiatives | jq -e 'all(.synthesized == true)' >/dev/null
check "without an Initiatives source the tier is still synthesized (never errors)" $?
rm -rf "$D" "$D2"

# --- health reports what the board is missing --------------------------------
D=$(mkproj "$CFG_FLAT")
out=$(run_op "$D" "{$FLAT}" health)
echo "$out" | jq -e '.ok == true and .hierarchy == "derived"' >/dev/null; check "health ok on a flat board" $?
echo "$out" | jq -e '.schema.missing | length >= 2' >/dev/null; check "health names the missing relation properties" $?
grep -qi "stays in the payload only" "$D/stderr.log"; check "…and explains the consequence on stderr" $?
rm -rf "$D"
# the related database must ALSO be shared, and that failure is a confusing 404
D=$(mkproj "$CFG_FULL")
run_op "$D" "{$FULL,\"initsUnreachable\":true}" health >/dev/null 2>&1
[ $? -ne 0 ]; check "an unreachable Initiatives source fails health" $?
grep -qi "shared with the integration" "$D/stderr.log"
check "…naming the real cause (both databases must be shared)" $?
rm -rf "$D"

# --- secrets never leak ------------------------------------------------------
D=$(mkproj "$CFG_FULL")
run_op "$D" '{"databaseMissing":true,"props":{}}' get-epic --id nope >/dev/null 2>&1
grep -qiE "not-a-real-token|Authorization|Bearer " "$D/stderr.log" && r=1 || r=0; [ "$r" = 0 ]
check "stderr never echoes the token or headers" $?
rm -rf "$D"

# --- the 16-op contract is intact --------------------------------------------
for o in health capabilities push-epic push-backlog get-epic list-epics push-status pull-status \
         push-spec get-spec list-specs push-plan get-plan push-session pull-session push-digest; do
  grep -q "'$o'" "$A"; check "contract op present: $o" $?
done

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
