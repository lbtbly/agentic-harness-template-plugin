#!/bin/bash
# Subsystem 1a — the DoD contract: feature-list schema, example, and the
# validate-dod structural checker (the termination authority's shape enforcer).
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
R=".."
SCHEMA="$R/plugins/core/templates/orch/feature-list.schema.json"
EXAMPLE="$R/plugins/core/templates/orch/feature-list.example.json"
VDOD="$R/plugins/orchestrator/templates/orchestrator/bin/validate-dod"

command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; summary; exit $?; }

# --- schema: parses + keeps the anti-drift invariant ---
jq -e . "$SCHEMA" >/dev/null 2>&1; check "feature-list.schema.json is valid JSON" $?
jq -e '.properties.contract.const | test("unacceptable to remove or edit")' "$SCHEMA" >/dev/null 2>&1; check "anti-drift contract const preserved" $?
jq -e '.additionalProperties == false' "$SCHEMA" >/dev/null 2>&1; check "additionalProperties stays false" $?
jq -e '.properties.features.items.required | index("passes")' "$SCHEMA" >/dev/null 2>&1; check "every feature requires a passes flag" $?

# --- schema: DoD fields declared ---
jq -e '.properties.acceptanceCriteria.type == "array"' "$SCHEMA" >/dev/null 2>&1; check "acceptanceCriteria declared (array)" $?
jq -e '.properties.acceptanceCriteria.items.required | index("statement")' "$SCHEMA" >/dev/null 2>&1; check "acceptanceCriteria items require statement" $?
jq -e '.properties.testLevels.properties | has("unit") and has("integration") and has("e2e")' "$SCHEMA" >/dev/null 2>&1; check "testLevels declares unit/integration/e2e" $?
jq -e '.properties.epicTests.type == "array"' "$SCHEMA" >/dev/null 2>&1; check "epicTests declared (array)" $?
jq -e '.properties.designRefs.type == "array"' "$SCHEMA" >/dev/null 2>&1; check "designRefs declared (array)" $?
jq -e '.properties.features.items.properties.blindspots.type == "array"' "$SCHEMA" >/dev/null 2>&1; check "features declare blindspots (array)" $?
jq -e '(.required | index("acceptanceCriteria")) and (.required | index("testLevels"))' "$SCHEMA" >/dev/null 2>&1; check "acceptanceCriteria + testLevels are required" $?

# --- the shipped example is itself a valid contract ---
jq -e . "$EXAMPLE" >/dev/null 2>&1; check "feature-list.example.json is valid JSON" $?
jq -e --slurpfile s "$SCHEMA" '.contract == $s[0].properties.contract.const' "$EXAMPLE" >/dev/null 2>&1; check "example carries the exact contract const" $?
jq -e '[.features[] | .passes] | all(. == false)' "$EXAMPLE" >/dev/null 2>&1; check "example features all start passes:false" $?

# --- validate-dod: behavioral checks ---
[ -x "$VDOD" ]; check "validate-dod exists and is executable" $?

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GOOD_REC="$TMP/rec.json"; GOOD_FL="$TMP/fl.json"
cat > "$GOOD_REC" <<'JSON'
{ "id":"e1", "title":"Login", "initiative":"auth", "footprint":["src/auth/**"],
  "deps":[], "riskHints":{"paths":[],"linesEstimate":80},
  "dodPath":".orch/epics/e1/feature_list.json", "state":"Needs-plan" }
JSON
cat > "$GOOD_FL" <<'JSON'
{ "epic":"e1",
  "contract":"It is unacceptable to remove or edit tests/steps or to add/delete features. Only flip `passes` to true after a real end-to-end pass.",
  "acceptanceCriteria":[{"id":"ac1","statement":"user can log in","automated":true}],
  "testLevels":{"unit":true,"integration":true,"e2e":true},
  "epicTests":["tests/e1/login.test.ts"],
  "features":[{"id":"f1","description":"login","steps":["open /login","submit valid creds"],"expected":"redirected to dashboard","passes":false}] }
JSON

assert_cmd_exit 0 "valid record + feature_list → exit 0" bash "$VDOD" "$GOOD_REC" "$GOOD_FL"
assert_cmd_exit 2 "missing args → exit 2 (usage)" bash "$VDOD" "$GOOD_REC"

# edited contract const → reject
jq '.contract = "steps may be edited when needed"' "$GOOD_FL" > "$TMP/bad-contract.json"
assert_cmd_exit 1 "edited contract const → exit 1" bash "$VDOD" "$GOOD_REC" "$TMP/bad-contract.json"

# no features → reject
jq '.features = []' "$GOOD_FL" > "$TMP/no-features.json"
assert_cmd_exit 1 "empty features → exit 1" bash "$VDOD" "$GOOD_REC" "$TMP/no-features.json"

# feature without steps → reject
jq 'del(.features[0].steps)' "$GOOD_FL" > "$TMP/no-steps.json"
assert_cmd_exit 1 "feature missing steps → exit 1" bash "$VDOD" "$GOOD_REC" "$TMP/no-steps.json"

# feature with empty steps array → reject (steps must be a non-empty user journey)
jq '.features[0].steps = []' "$GOOD_FL" > "$TMP/empty-steps.json"
assert_cmd_exit 1 "feature with empty steps → exit 1" bash "$VDOD" "$GOOD_REC" "$TMP/empty-steps.json"

# missing acceptanceCriteria → reject
jq 'del(.acceptanceCriteria)' "$GOOD_FL" > "$TMP/no-ac.json"
assert_cmd_exit 1 "missing acceptanceCriteria → exit 1" bash "$VDOD" "$GOOD_REC" "$TMP/no-ac.json"

# incomplete testLevels → reject
jq 'del(.testLevels.e2e)' "$GOOD_FL" > "$TMP/no-e2e-level.json"
assert_cmd_exit 1 "testLevels missing e2e → exit 1" bash "$VDOD" "$GOOD_REC" "$TMP/no-e2e-level.json"

# passes not boolean → reject
jq '.features[0].passes = "false"' "$GOOD_FL" > "$TMP/passes-string.json"
assert_cmd_exit 1 "passes as string → exit 1" bash "$VDOD" "$GOOD_REC" "$TMP/passes-string.json"

# epic record missing footprint → reject
jq 'del(.footprint)' "$GOOD_REC" > "$TMP/rec-no-footprint.json"
assert_cmd_exit 1 "epic record missing footprint → exit 1" bash "$VDOD" "$TMP/rec-no-footprint.json" "$GOOD_FL"

# epic record with empty footprint → reject (drives wave partitioning; cannot be empty)
jq '.footprint = []' "$GOOD_REC" > "$TMP/rec-empty-footprint.json"
assert_cmd_exit 1 "epic record empty footprint → exit 1" bash "$VDOD" "$TMP/rec-empty-footprint.json" "$GOOD_FL"

# invalid JSON → reject
echo '{ nope' > "$TMP/invalid.json"
assert_cmd_exit 1 "invalid JSON feature_list → exit 1" bash "$VDOD" "$GOOD_REC" "$TMP/invalid.json"

summary
