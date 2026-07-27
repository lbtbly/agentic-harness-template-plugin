#!/bin/bash
# BOARD_SETUP.html — the step-by-step provisioning guide. It is hand-written
# prose that no other check validates, and it makes factual claims about the
# adapters. This pins the claims that would silently rot.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
G="../BOARD_SETUP.html"; SH="../START_HERE.html"; A="../plugins/core/templates/orchestrator/adapters"
[ -f "$G" ]; check "the guide ships" $?

# --- discoverable, and a round trip ---
grep -q 'href="BOARD_SETUP.html"' "$SH"; check "START_HERE links to the guide" $?
[ "$(grep -c 'href="BOARD_SETUP.html"' "$SH")" -ge 2 ]; check "…from both the nav and the board section" $?
grep -q 'href="START_HERE.html"' "$G"; check "the guide links back" $?

# --- self-contained: it is opened via file://, so nothing may be remote ---
! grep -qE '<(script|link)[^>]+(src|href)="https?://' "$G"
check "no remote script/stylesheet (must work from file://)" $?
grep -q '<style>' "$G"; check "styles are inlined" $?
# it has no file-db payload, so a data-file element would render clickable and do nothing
! grep -qE '<(span|code)[^>]*data-file=' "$G"
check "no dead file-viewer chips (this page has no payload)" $?

# --- all three backends, each with the steps that cannot be automated ---
for b in Linear Notion Jira; do
  grep -q ">$b</h2>" "$G"; check "covers $b" $?
done
grep -qi 'Issue statuses' "$G"; check "Linear: names the issue-statuses settings path" $?
grep -qi 'Add connections' "$G"; check "Notion: names the sharing step (the #1 404 cause)" $?
grep -qi 'Both. Not just' "$G"; check "Notion: warns BOTH databases must be shared" $?
grep -q 'Parent epic' "$G" && grep -q 'Sub-tasks' "$G"
check "Notion: documents the self-relation and its synced inverse" $?
grep -q "DUAL 'Epics' 'epics'" "$G"; check "Notion: names both sides of the relation in the DDL" $?
grep -qi 'auto-generated inverse' "$G"; check "Notion: warns about the unnamed-inverse trap" $?
grep -q 'initiativesDataSourceId' "$G"; check "Notion: documents the second data source id" $?
grep -q '"Type" SELECT' "$G"; check "Notion: documents the Epic/Task type marker" $?
grep -qi 'unscoped' "$G"; check "Jira: warns about scoped vs unscoped tokens" $?

# --- factual claims that must track the code ---------------------------------
# Linear's stock states. If this list changes, the guide's default map is wrong.
for s in Backlog Todo "In Progress" Done Canceled; do
  grep -qF "$s" "$G"; check "Linear stock state documented: $s" $?
done
grep -qi 'no .In Review. by default\|There is no' "$G"
check "Linear: flags that In Review is NOT a default state" $?
# the sample stateMap must only target states a stock team actually has
python3 - "$G" <<'PY'
import re,sys,json
s=open(sys.argv[1]).read()
m=re.search(r'"stateMap":\s*\{(.*?)\}', s, re.S)
assert m, "no stateMap sample in the guide"
txt=m.group(1).replace('&quot;','"')
targets=set(re.findall(r':\s*"([^"]+)"', txt))
stock={"Backlog","Todo","In Progress","Done","Canceled"}
bad=targets-stock
sys.exit(1 if bad else 0)
PY
check "the sample stateMap targets ONLY states a stock Linear team has" $?

# env var names must match what the adapters actually read
for pair in "pm-linear.js:LINEAR_API_KEY" "pm-notion.js:NOTION_TOKEN" "pm-jira.js:JIRA_BASE_URL" "pm-jira.js:JIRA_EMAIL" "pm-jira.js:JIRA_API_TOKEN"; do
  f=${pair%%:*}; v=${pair##*:}
  grep -q "$v" "$A/$f" && grep -q "$v" "$G"
  check "env var documented and read by the adapter: $v" $?
done
# config keys the guide tells people to write
grep -q '"teamKey"' "$G" && grep -q 'teamKey' "$A/pm-linear.js"; check "linear.teamKey matches the adapter" $?
grep -q '"databaseId"' "$G" && grep -q 'databaseId' "$A/pm-notion.js"; check "notion.databaseId (legacy) matches the adapter" $?
grep -q 'dataSourceId' "$G" && grep -q 'dataSourceId' "$A/pm-notion.js"; check "notion.dataSourceId matches the adapter" $?
grep -q 'initiativesDataSourceId' "$A/pm-notion.js"; check "notion.initiativesDataSourceId is read by the adapter" $?
grep -q '"projectKey"' "$G" && grep -q 'projectKey' "$A/pm-jira.js"; check "jira.projectKey matches the adapter" $?

# --- the egress step: the failure it prevents is silent, so it must be here ---
grep -q 'api.linear.app' "$G" && grep -q 'api.notion.com' "$G"
check "documents the egress hosts (a missing one fails closed MID-RUN)" $?
grep -q 'egress-allowlist' "$G"; check "…and names the file to edit" $?

# --- the 12 lifecycle states, in full ---
for s in Suggested Backlog Needs-plan Planned In-progress Needs-review Changes-requested Approved Merged Blocked Paused Cancelled; do
  grep -qF "$s" "$G" || { echo "         missing lifecycle state: $s"; miss=1; }
done
[ -z "${miss:-}" ]; check "all 12 lifecycle states appear in the guide" $?

# --- the split the design rests on ---
grep -qi 'approvals are read from the forge\|never from the board' "$G"
check "states that approvals come from the forge, never the board" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
