#!/bin/bash
# Subsystem 3a — the state layer (none backend): contract roundtrips + the
# property the whole design exists for — parallel branches never merge-conflict.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; summary; exit $?; }

SRC="../plugins/core/templates/orchestrator/bin/orch"
[ -f "$SRC" ] || { echo "  FAIL — orch CLI template missing at $SRC"; echo "---"; echo "0 ok, 1 failure(s)"; exit 1; }

TMP=$(mktemp -d)
mkdir -p "$TMP/orchestrator/bin"
cp "$SRC" "$TMP/orchestrator/bin/orch"; chmod +x "$TMP/orchestrator/bin/orch"
printf '{"backend":"none","forge":"none"}' > "$TMP/orchestrator/state.config.json"
git -C "$TMP" init -q -b main
git -C "$TMP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export CLAUDE_PROJECT_DIR="$TMP"
O="$TMP/orchestrator/bin/orch"

ok() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }

# health + capabilities
"$O" state health | jq -e '.ok == true and .backend == "none"' >/dev/null; ok "health ok (none)" $?

# session roundtrip
echo '{"status":"3/5 green","nextSteps":["DLQ"],"failedAttempts":["unique-constraint deadlocks"]}' | "$O" state push-session >/dev/null
"$O" state pull-session --branch main | jq -e '.status == "3/5 green" and .branch == "main"' >/dev/null; ok "session push/pull roundtrip" $?

# auto snapshot merges under .auto without clobbering
echo '{"note":"mech"}' | "$O" state push-session --auto >/dev/null
"$O" state pull-session --branch main | jq -e '.status == "3/5 green" and .auto.note == "mech"' >/dev/null; ok "auto snapshot preserves curated session" $?

# spec + plan roundtrip
echo "# Spec X" | "$O" state push-spec --id SPEC-1 >/dev/null
[ "$("$O" state get-spec --id SPEC-1)" = "# Spec X" ]; ok "spec push/get roundtrip" $?
"$O" state list-specs | jq -e 'index("SPEC-1") != null' >/dev/null; ok "list-specs sees it" $?
echo "plan body" | "$O" state push-plan --epic E-1 >/dev/null
[ "$("$O" state get-plan --epic E-1)" = "plan body" ]; ok "plan push/get roundtrip" $?

# epics + status: read-time aggregation
echo '{"id":"E-1","title":"Alpha","state":"Planned"}' | "$O" state push-epic >/dev/null
echo '[{"id":"E-2","title":"Beta","state":"Backlog"}]' | "$O" state push-backlog >/dev/null
"$O" state list-epics --state Planned | jq -e 'length == 1 and .[0].id == "E-1"' >/dev/null; ok "list-epics filters by state" $?
"$O" state push-status --id E-2 --state In-progress --note "building" >/dev/null
"$O" state pull-status | jq -e '[.[] | select(.id=="E-2")][0].state == "In-progress"' >/dev/null; ok "push-status → pull-status aggregates on read" $?

# digest: the caller sends the COMPLETE daily file — storing replaces
echo "<h1>run1</h1>" | "$O" state push-digest --date 2026-07-02 >/dev/null
printf "<h1>run1</h1><h2>run2</h2>" | "$O" state push-digest --date 2026-07-02 >/dev/null
[ "$(grep -c '<h1>run1</h1>' "$TMP/.orch/digest/2026-07-02.html")" -eq 1 ] && grep -q run2 "$TMP/.orch/digest/2026-07-02.html"; ok "push-digest stores the complete file (no duplicate docs)" $?
"$O" state push-digest --date '../evil' < /dev/null 2>/dev/null && ok "push-digest rejects a non-date --date" 1 || ok "push-digest rejects a non-date --date" 0

# corrupt epic file must not blank the board
echo 'not json' > "$TMP/.orch/epics/corrupt.json"
"$O" state pull-status 2>/dev/null | jq -e '[.[] | select(.id=="E-1")] | length == 1' >/dev/null; ok "corrupt epic file skipped, board survives" $?
rm -f "$TMP/.orch/epics/corrupt.json"

# slug collisions: feat/a-b and feat-a/b must not share a file
[ "$("$O" state push-session <<< '{"branch":"feat/a-b"}' | jq -r .id)" != "$("$O" state push-session <<< '{"branch":"feat-a/b"}' | jq -r .id)" ]; ok "slug is collision-resistant" $?

# push-status --pr persists the PR↔epic link
"$O" state push-status --id E-1 --state Needs-review --pr 42 >/dev/null
"$O" state get-epic --id E-1 | jq -e '.pr == 42' >/dev/null; ok "push-status --pr persists the PR link" $?

# feedback: forge=none → empty array, no error
[ "$("$O" state pull-feedback)" = "[]" ]; ok "pull-feedback without forge → []" $?

# suggestion lifecycle: none substrate = docs/SUGGESTIONS.md; accept → Backlog epic
"$O" state push-suggestion --text "Guard null user" --file "src/x.ts" >/dev/null
"$O" state push-suggestion --text "Retry flaky call" >/dev/null
"$O" state pull-suggestions | jq -e 'length == 2 and .[0].id == "1"' >/dev/null; ok "pull-suggestions lists pushed items with ids" $?
"$O" state triage-suggestion --id 1 --decision accepted >/dev/null
"$O" state pull-status | jq -e '[.[] | select(.state=="Backlog" and (.id|startswith("sug-")))] | length == 1' >/dev/null; ok "triage accept → Backlog epic" $?
"$O" state triage-suggestion --id 1 --decision rejected >/dev/null
"$O" state pull-suggestions | jq -e 'length == 0' >/dev/null; ok "triage reject drains queue" $?
[ "$("$O" state pull-status | jq '[.[] | select(.id|startswith("sug-"))] | length')" -eq 1 ]; ok "reject creates no epic (only the accepted one)" $?

# THE core property: two branches push state in parallel → merge with ZERO conflicts
git -C "$TMP" add -A; git -C "$TMP" -c user.email=t@t -c user.name=t commit -qm "state base"
git -C "$TMP" checkout -qb feat/a
echo '{"status":"work A"}' | "$O" state push-session >/dev/null
"$O" state push-status --id E-1 --state In-progress >/dev/null
git -C "$TMP" add -A; git -C "$TMP" -c user.email=t@t -c user.name=t commit -qm "A state"
git -C "$TMP" checkout -q main
git -C "$TMP" checkout -qb feat/b
echo '{"status":"work B"}' | "$O" state push-session >/dev/null
"$O" state push-status --id E-2 --state Needs-review >/dev/null
git -C "$TMP" add -A; git -C "$TMP" -c user.email=t@t -c user.name=t commit -qm "B state"
git -C "$TMP" checkout -q main
git -C "$TMP" merge -q --no-edit feat/a >/dev/null 2>&1
git -C "$TMP" merge -q --no-edit feat/b >/dev/null 2>&1; ok "parallel branches merge with zero conflicts (sharded state)" $?
[ -f "$TMP/.orch/sessions/feat-s-a.json" ] && [ -f "$TMP/.orch/sessions/feat-s-b.json" ]; ok "one session file per branch after merge" $?

unset CLAUDE_PROJECT_DIR; rm -rf "$TMP"
summary
