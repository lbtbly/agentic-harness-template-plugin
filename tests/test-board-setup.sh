#!/bin/bash
# Board provisioning: the /core:board-setup skill creates the board + epic
# lifecycle in Notion or Jira, and the pm-notion / pm-jira adapters actually
# drive what it creates (no more contract stubs).
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."
SK="$R/plugins/core/skills/board-setup/SKILL.md"
NP="$R/plugins/core/skills/new-project/SKILL.md"
NOTION="$R/plugins/core/templates/orchestrator/adapters/pm-notion.js"
JIRA="$R/plugins/core/templates/orchestrator/adapters/pm-jira.js"

# --- the skill: exists, namespaced, both backends, the full lifecycle ---
[ -f "$SK" ]; check "board-setup skill exists" $?
grep -q "/core:board-setup" "$SK"; check "skill is namespaced /core:board-setup" $?
grep -qi "notion" "$SK" && grep -qi "jira" "$SK"; check "skill covers Notion AND Jira" $?
miss=0
for st in Suggested Backlog Needs-plan Planned In-progress Needs-review Changes-requested Approved Merged Blocked Paused Cancelled; do
  grep -q "$st" "$SK" || { echo "         lifecycle state missing from skill: $st"; miss=1; }
done
check "skill provisions all 12 lifecycle states" $miss
grep -q "state.config.json" "$SK"; check "skill records the board in state.config.json" $?
grep -qi "never.*value\|NAMES only\|name only" "$SK"; check "skill handles token NAMES, never values" $?
grep -q "orch state health" "$SK"; check "skill verifies with orch state health" $?
grep -qi "MCP-first\|MCP connector" "$SK"; check "skill offers the credential-free MCP lane first" $?
grep -qi "only.*enable-orchestrator\|defer.*token" "$SK"; check "skill defers tokens to unattended-loop enablement" $?
grep -qi "forge.*never\|never.*board.*feedback\|feedback.*forge" "$SK"; check "skill restates: feedback comes from the forge, never the board" $?
grep -q "Assigned to" "$SK"; check "board carries an Assigned to property (worker on the card)" $?
grep -qi "Complexity" "$SK"; check "board carries a Complexity estimate (drives model choice)" $?
grep -q "created_time" "$SK" && grep -q "last_edited_time" "$SK"; check "board carries Created/Edited timestamps" $?
grep -qi "option order\|same order as the lifecycle\|column order" "$SK"; check "skill enforces lifecycle column order (not alphabetical)" $?
grep -q "Assigned to" "$NOTION"; check "pm-notion maps Assigned to" $?
grep -q "Complexity" "$NOTION"; check "pm-notion maps Complexity" $?
grep -q "orch-complexity-" "$JIRA"; check "pm-jira labels complexity" $?
grep -q -- "--assignee" "$R/plugins/core/templates/orchestrator/bin/orch"; check "orch push-status supports --assignee" $?

# --- new-project: create-from-template vs adopt-existing ---
grep -q "board-setup" "$NP"; check "new-project points jira/notion backends at /core:board-setup" $?
grep -qi "existing board" "$NP"; check "new-project asks: new board from template OR an existing board (URL)" $?

# --- adopting an existing board: audit -> auto-fix or DIY guide ---
grep -qi "existing board" "$SK"; check "board-setup can adopt an existing board by URL" $?
grep -qi "audit" "$SK"; check "adopted boards are AUDITED against the template contract" $?
grep -qi "missing" "$SK" && grep -qi "gap" "$SK"; check "audit reports missing columns/properties as gaps" $?
grep -qi "automatically.*or\|update the board automatically" "$SK"; check "user chooses: fix automatically or do it themselves" $?
grep -qi "guide" "$SK"; check "DIY path gets a precise update guide" $?
grep -qi "ADDITIVE\|never delete.*propert\|never remove.*propert" "$SK"; check "auto-fix is additive-only (never deletes existing properties/options)" $?

# --- Jira caveat: the connector cannot create projects; fresh vs lived-in fork ---
grep -qi "cannot create.*project" "$SK"; check "skill states the Jira connector cannot create projects (user provides the URL)" $?
grep -qi "freshly created\|created just for\|dedicated to this" "$SK"; check "skill asks: fresh dedicated project, or existing one with real work" $?
grep -qi "statuses" "$SK" && grep -qi "issue type" "$SK"; check "fresh Jira projects get full adaptation (statuses, issue types, columns)" $?
grep -qi "never modif.*schema\|never touch.*schema\|schema.*belongs to the team" "$SK"; check "existing Jira projects: schema untouched, labels-only coexistence" $?

# --- adapters: implemented (no stub exit 64), correct op surface ---
command -v node >/dev/null 2>&1 || { echo "  skip — node not available for adapter checks"; echo "---"; echo "$PASS ok, $FAIL failure(s)"; exit 0; }
for A in "$NOTION" "$JIRA"; do
  name=$(basename "$A" .js)
  node --check "$A" 2>/dev/null; check "$name parses (node --check)" $?
  ! grep -q "not implemented yet" "$A"; check "$name is no longer a contract stub" $?
  miss=0
  for opname in health capabilities push-epic push-backlog get-epic list-epics push-status pull-status push-spec get-spec list-specs push-plan get-plan push-session pull-session push-digest; do
    grep -q "'$opname'" "$A" || { echo "         $name missing op: $opname"; miss=1; }
  done
  check "$name covers the full orch state op surface" $?
  grep -q "cache(" "$A"; check "$name mirrors pushes to .orch/cache (fail-open reads)" $?
  grep -qi "never echo" "$A"; check "$name never echoes tokens on error" $?
done

# --- missing credentials fail loud, clean, and value-free ---
TMP=$(mktemp -d); export CLAUDE_PROJECT_DIR="$TMP"; mkdir -p "$TMP/.orch/cache"
outn=$(env -u NOTION_TOKEN node "$NOTION" health 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$outn" | grep -q "NOTION_TOKEN"; check "pm-notion health without NOTION_TOKEN → non-zero + names the env var" $?
outj=$(env -u JIRA_API_TOKEN -u JIRA_BASE_URL node "$JIRA" health 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$outj" | grep -qE "JIRA_API_TOKEN|JIRA_BASE_URL"; check "pm-jira health without credentials → non-zero + names the env vars" $?
unset CLAUDE_PROJECT_DIR; rm -rf "$TMP"

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
