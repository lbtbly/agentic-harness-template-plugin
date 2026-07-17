#!/bin/bash
# Subsystem 4g — the activation/driver skills keep the human gates and the
# safety wiring: six preconditions, plan gate, per-PR signals, CODEOWNERS,
# never auto-merge non-low, board preserved on disable.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."
EN="$R/plugins/orchestrator/skills/enable-orchestrator/SKILL.md"
DIS="$R/plugins/orchestrator/skills/disable-orchestrator/SKILL.md"
KICK="$R/plugins/orchestrator/skills/kickoff/SKILL.md"
RUN="$R/plugins/orchestrator/skills/run/SKILL.md"
SEC="$R/plugins/workbench/agents/security-auditor.md"
IC="$R/plugins/orchestrator/agents/integration-checker.md"
SET="$R/plugins/orchestrator/templates/orchestrator/settings.orchestrator.json"

# --- enable-orchestrator: verifies, doesn't trust ---
[ -f "$EN" ]; check "enable-orchestrator skill exists" $?
grep -qi "green test suite" "$EN"; check "precondition: green test suite" $?
grep -qi "staging" "$EN"; check "precondition: staging deploy command" $?
grep -qi "devcontainer\|sandbox" "$EN"; check "precondition: sandbox devcontainer" $?
grep -qi "branch protection" "$EN"; check "precondition: branch protection on main" $?
grep -qi "cannot bypass" "$EN"; check "branch protection: token cannot bypass" $?
grep -q "branches/main/protection" "$EN"; check "branch protection VERIFIED via the forge API" $?
grep -qi "forge is mandatory\|forge.*mandatory" "$EN"; check "precondition: a forge is mandatory to run the loop" $?
grep -qi "autonomous" "$EN"; check "precondition: autonomous profile" $?
grep -qi "dry.run" "$EN"; check "finishes with a dry run (no merge, no deploy)" $?
grep -qi "never ask for or write a value\|never.*secret value" "$EN"; check "secrets: names only, never values" $?
grep -q "CODEOWNERS" "$EN"; check "run-to-completion setup installs CODEOWNERS" $?
grep -qi "auto-merge without the per-PR operator OK" "$EN"; check "gated flavor: no auto-merge without per-PR OK" $?

# --- kickoff: the daily driver keeps merges observable and per-PR ---
[ -f "$KICK" ]; check "kickoff skill exists" $?
grep -q "pull-feedback" "$KICK"; check "kickoff reads signals from the forge" $?
grep -qi "risk check (mandatory\|risk gate" "$KICK"; check "kickoff risk-checks before any merge" $?
grep -qi "security-auditor" "$KICK"; check "high-risk PR needs a security-auditor pass" $?
grep -qi "reverted immediately\|revert" "$KICK"; check "red merge is reverted" $?
grep -qi "never bulk" "$KICK"; check "one signal per PR, never bulk" $?
grep -qi "approve it live\|approve each new plan\|approval here" "$KICK"; check "plan gate: human approves plans at kickoff" $?
grep -qi "missing context" "$KICK"; check "kickoff classifies revise notes: plan defect vs missing context" $?
grep -qi "rule line\|propose.*rule" "$KICK"; check "missing-context notes become proposed rule lines (human-approved)" $?

# --- run: scope confirmation + guards + no unsafe merges ---
[ -f "$RUN" ]; check "run skill exists" $?
grep -qi "list the selected epic" "$RUN"; check "run confirms the named epics (scope-at-launch gate)" $?
grep -q "run-to-done.sh" "$RUN"; check "run launches the driver" $?
grep -qi "never.*auto-merge a non-low risk\|never: bypass" "$RUN"; check "run never auto-merges non-low risk" $?
grep -qi "weaken a test" "$RUN"; check "run never weakens a test" $?

# --- disable: the board outlives the loop ---
[ -f "$DIS" ]; check "disable-orchestrator skill exists" $?
grep -qi "preserved\|preserve" "$DIS"; check "disable preserves the board and its data" $?

# --- the second gate's agents exist ---
[ -f "$SEC" ]; check "security-auditor agent exists" $?
grep -q "^name: security-auditor" "$SEC"; check "security-auditor frontmatter name" $?
grep -qi "never modif" "$SEC"; check "security-auditor reports, never modifies" $?
[ -f "$IC" ]; check "integration-checker agent exists" $?
grep -q "^name: integration-checker" "$IC"; check "integration-checker frontmatter name" $?
grep -qi "NEVER modify code and NEVER merge\|never merge" "$IC"; check "integration-checker never merges" $?

# --- the loop's own permission profile ---
command -v jq >/dev/null 2>&1 || { echo "---"; echo "$PASS ok, $FAIL failure(s)"; exit 0; }
[ -f "$SET" ] && jq -e . "$SET" >/dev/null 2>&1; check "settings.orchestrator.json exists and is valid JSON" $?
jq -e '.permissions.deny | length > 0' "$SET" >/dev/null 2>&1; check "orchestrator profile carries deny rules" $?
jq -e '[.permissions.deny[] | select(test("push.*main|main.*push"; "i"))] | length > 0' "$SET" >/dev/null 2>&1; check "orchestrator profile denies pushing main" $?
jq -e '.sandbox.enabled == true' "$SET" >/dev/null 2>&1; check "native sandbox enabled for unattended runs (DEVIATIONS §5)" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
