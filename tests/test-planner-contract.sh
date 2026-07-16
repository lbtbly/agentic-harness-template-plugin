#!/bin/bash
# Subsystem 2 — the planner: validate-dod accepts the planner's full epic record
# (with designReview + riskHints), the planner/design-reviewer agents exist with
# the right separation of duties, and the plan skill wires them together.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
R=".."
VD="$R/plugins/orchestrator/templates/orchestrator/bin/validate-dod"
PLANNER="$R/plugins/orchestrator/agents/planner.md"
REVIEWER="$R/plugins/core/agents/design-reviewer.md"
PLAN_SKILL="$R/plugins/orchestrator/skills/plan/SKILL.md"

command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; summary; exit $?; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- a planner-emitted epic record (all fields from the epic-fields table) passes ---
cat > "$TMP/rec.json" <<'JSON'
{ "id":"e1","title":"Login","initiative":"auth","footprint":["apps/web/src/login/**"],
  "deps":[],"riskHints":{"paths":["apps/web/src/login"],"estLines":120},
  "state":"Planned","dodPath":".orch/epics/e1/feature_list.json",
  "designReview":{"verdict":"READY","at":"2026-07-15T00:00:00Z"} }
JSON
cat > "$TMP/fl.json" <<'JSON'
{ "epic":"e1","contract":"It is unacceptable to remove or edit tests/steps or to add/delete features. Only flip `passes` to true after a real end-to-end pass.",
  "acceptanceCriteria":[{"id":"ac1","statement":"user can log in with valid creds","automated":true}],
  "testLevels":{"unit":true,"integration":true,"e2e":true},
  "epicTests":["tests/e1/login.test.ts"],"designRefs":[],
  "features":[{"id":"f1","description":"login","steps":["open /login","submit valid creds"],"expected":"redirected to dashboard","passes":false}] }
JSON
assert_cmd_exit 0 "planner-shaped epic record + DoD → validate-dod exit 0" bash "$VD" "$TMP/rec.json" "$TMP/fl.json"

# --- planner agent: exists, correctly scoped ---
[ -f "$PLANNER" ]; check "planner agent exists" $?
grep -q "^name: planner" "$PLANNER" 2>/dev/null; check "planner agent frontmatter name" $?
grep -q "feature_list.json" "$PLANNER" 2>/dev/null; check "planner authors the feature_list DoD" $?
grep -q "footprint" "$PLANNER" 2>/dev/null; check "planner emits a footprint per epic" $?
grep -qi "never write[s]* product code\|never writes product code" "$PLANNER" 2>/dev/null; check "planner never writes product code" $?
grep -qi "not self-approve\|never grade.*own\|do not self-approve" "$PLANNER" 2>/dev/null; check "planner never grades its own output" $?

# --- design-reviewer agent: the independent DoD gate ---
[ -f "$REVIEWER" ]; check "design-reviewer agent exists" $?
grep -q "^name: design-reviewer" "$REVIEWER" 2>/dev/null; check "design-reviewer frontmatter name" $?
grep -q "READY-WITH-FIXES" "$REVIEWER" 2>/dev/null; check "design-reviewer verdict vocabulary (READY / READY-WITH-FIXES / NEEDS-REWORK)" $?
grep -q "NEEDS-REWORK" "$REVIEWER" 2>/dev/null; check "design-reviewer can reject (NEEDS-REWORK)" $?
grep -qi "NEVER edit" "$REVIEWER" 2>/dev/null; check "design-reviewer never edits — reports only" $?

# --- plan skill: decompose → validate → independent review → persist ---
[ -f "$PLAN_SKILL" ]; check "plan skill exists" $?
grep -q "/orchestrator:plan" "$PLAN_SKILL" 2>/dev/null; check "plan skill is namespaced /orchestrator:plan" $?
grep -q "validate-dod" "$PLAN_SKILL" 2>/dev/null; check "plan skill runs validate-dod" $?
grep -q "design-reviewer" "$PLAN_SKILL" 2>/dev/null; check "plan skill dispatches the independent design-reviewer" $?
grep -q "push-epic" "$PLAN_SKILL" 2>/dev/null; check "plan skill persists via orch state push-epic" $?
grep -q "designReview" "$PLAN_SKILL" 2>/dev/null; check "plan skill records the designReview verdict on the epic" $?
grep -qi "independent of the planner\|no self-grading" "$PLAN_SKILL" 2>/dev/null; check "plan skill states reviewer ≠ planner (no self-grading)" $?
grep -qi "human escalation\|escalat" "$PLAN_SKILL" 2>/dev/null; check "plan skill escalates un-completable DoDs to a human" $?

summary
