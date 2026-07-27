#!/bin/bash
# The board is the golden source (ADR-0027): hierarchy reads, human-authored
# cards, and claim/lease so two agents never take the same work.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
SRC=../plugins/core/templates/orchestrator/bin/orch
A=../plugins/core/templates/orchestrator/adapters

D=$(mktemp -d); mkdir -p "$D/orchestrator/bin"; cp "$SRC" "$D/orchestrator/bin/orch"; chmod +x "$D/orchestrator/bin/orch"
export CLAUDE_PROJECT_DIR="$D"; printf '{"backend":"none","forge":"none"}' > "$D/orchestrator/state.config.json"
O="$D/orchestrator/bin/orch"
for e in '{"id":"a","title":"A","state":"Planned","initiative":"auth","footprint":["src/**"],"deps":[]}' \
         '{"id":"b","title":"B","state":"Planned","initiative":"auth","footprint":["api/**"],"deps":["a"]}' \
         '{"id":"c","title":"C","state":"Merged","initiative":"ui","footprint":["ui/**"]}'; do
  echo "$e" | "$O" state push-epic >/dev/null
done

# --- backwards compatibility is the whole design constraint ---
[ "$("$O" state list-epics | jq -c 'map(.id)')" = '["a","b","c"]' ]
check "list-epics with NO flags is unchanged (the drivers were not touched)" $?
[ "$("$O" state list-epics --state Planned | jq -c 'map(.id)')" = '["a","b"]' ]
check "--state still works exactly as before" $?

# --- hierarchy reads ---
[ "$("$O" state list-epics --initiative auth | jq -c 'map(.id)')" = '["a","b"]' ]; check "--initiative filters to one initiative" $?
"$O" state list-initiatives | jq -e 'length == 2' >/dev/null; check "list-initiatives returns the tier" $?
"$O" state list-initiatives | jq -e '.[] | select(.id=="ui") | .state == "Merged"' >/dev/null
check "an initiative whose epics are all Merged rolls up to Merged" $?
"$O" state list-initiatives | jq -e '.[] | select(.id=="auth") | .epics == ["a","b"]' >/dev/null
check "the rollup lists its child epics" $?
"$O" state list-initiatives | jq -e 'all(.synthesized == true)' >/dev/null
check "a FLAT board synthesizes the tier rather than erroring" $?
"$O" state list-initiatives --state Merged | jq -e 'length == 1' >/dev/null; check "list-initiatives --state filters" $?

# --- claim / lease: two agents must never take the same card ---
"$O" state claim --id a --owner agent-1 | jq -e '.claimed == true' >/dev/null; check "an unheld epic can be claimed" $?
"$O" state claim --id a --owner agent-2 >/dev/null 2>&1; [ $? -eq 3 ]
check "a second agent is REFUSED (exit 3), not silently given the same card" $?
"$O" state claim --id a --owner agent-2 2>/dev/null | jq -e '.heldBy == "agent-1"' >/dev/null
check "the refusal names the current holder" $?
"$O" state claim --id a --owner agent-1 | jq -e '.claimed == true' >/dev/null
check "re-claiming your OWN lease succeeds (a resumed run keeps working)" $?
[ "$("$O" state list-claimable --state Planned | jq -c 'map(.id)')" = '["b"]' ]
check "list-claimable excludes a held epic" $?

# an EXPIRED lease returns the card to the pool — a crashed agent must not strand work
jq '.leaseUntil = "2020-01-01T00:00:00Z"' "$D/.orch/epics/a.json" > "$D/t" && mv "$D/t" "$D/.orch/epics/a.json"
[ "$("$O" state list-claimable --state Planned | jq -c 'map(.id)')" = '["a","b"]' ]
check "an EXPIRED lease returns the card to the pool (crashed agent recovery)" $?
"$O" state claim --id a --owner agent-2 | jq -e '.claimed == true' >/dev/null
check "…and another agent can then claim it" $?
"$O" state release --id a >/dev/null
jq -e '(has("leaseUntil") | not) and (has("assignee") | not)' "$D/.orch/epics/a.json" >/dev/null
check "release clears both the lease and the assignee" $?
"$O" state claim --id nope >/dev/null 2>&1; [ $? -ne 0 ]; check "claiming an unknown epic fails loudly" $?
rm -rf "$D"; unset CLAUDE_PROJECT_DIR

# --- adapters: the contract must not have shrunk ---
node -e "
const fs=require('fs');
const ops=['health','capabilities','push-epic','push-backlog','get-epic','list-epics','push-status',
           'pull-status','push-spec','get-spec','list-specs','push-plan','get-plan','push-session',
           'pull-session','push-digest'];
for (const f of ['pm-jira','pm-notion','pm-github-projects','pm-gitlab']) {
  const s=fs.readFileSync('$A/'+f+'.js','utf8');
  for (const o of ops) if(!s.includes(\"'\"+o+\"'\")) { console.error(f+' lost '+o); process.exit(1); }
}
" && check "all 16 contract ops survive in every adapter (grep-enforced elsewhere)" $? || check "all 16 contract ops survive in every adapter" 1

for f in pm-jira pm-notion pm-github-projects pm-gitlab; do
  grep -q "case 'list-initiatives'" "$A/$f.js"; check "$f implements list-initiatives" $?
  grep -q "hierarchy:" "$A/$f.js"; check "$f advertises its hierarchy support in capabilities" $?
done

# --- the three adapter bugs this work depended on ---
for f in pm-github-projects pm-gitlab; do
  grep -q "function warn(" "$A/$f.js"; check "$f defines warn() (it was referenced but absent)" $?
  grep -q "catch (e) { warn" "$A/$f.js"
  check "$f guards the payload parse — one bad fence no longer kills the listing" $?
  grep -q "arg('--assignee')" "$A/$f.js"
  check "$f honours --assignee (it was parsed by Jira/Notion and DROPPED here)" $?
  grep -q "leaseUntil" "$A/$f.js"; check "$f carries leaseUntil so a claim survives a round-trip" $?
  grep -q "pr: e.pr" "$A/$f.js"; check "$f pull-status reports pr (it was omitted entirely)" $?
done
grep -q "'parent', 'issuetype'" "$A/pm-jira.js"; check "pm-jira REQUESTS parent back (the link was write-only)" $?
grep -q 'labels in ("orch-epic","orch-child")' "$A/pm-jira.js"; check "pm-jira lists children, not just epics" $?
grep -q "e.level ?? 'epic') !== 'child'" "$A/pm-jira.js"
check "…but an un-flagged list-epics still excludes children (no behaviour change)" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
