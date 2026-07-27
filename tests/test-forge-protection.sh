#!/bin/bash
# ADR-0032 — branch protection is a three-state, machine-readable property, and
# accepting an unprotectable forge is a MECHANISM (auto-merge off), not a warning.
# The failure this pins: a skill that can only say "stop", re-derives the same
# argument every run, and leaves the decision as prose in three documents.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."
EN="$R/plugins/orchestrator/skills/enable-orchestrator/SKILL.md"
RUN="$R/plugins/orchestrator/skills/run/SKILL.md"
POLICY="$R/plugins/orchestrator/templates/orchestrator/risk-policy.json"
DRIVER="$R/plugins/orchestrator/templates/orchestrator/runtime/run-to-done.sh"

[ -f "$R/docs/adr/0032-forge-protection-graduated.md" ]; check "ADR-0032 exists" $?

# --- the skill distinguishes unset from unsatisfiable ---
grep -qi "unsatisfiable" "$EN"; check "enable-orchestrator names the unsatisfiable case" $?
grep -q "404" "$EN"; check "absent-but-settable is detected by the forge's 404" $?
grep -q "403" "$EN"; check "unavailable-on-plan is detected by the forge's 403" $?
grep -q "unavailable-accepted" "$EN"; check "the acceptance value is named in the skill" $?
grep -qi "do \*\*not\*\* propose making a private repository public\|Do not propose making a private" "$EN"
check "making a private repo public is NOT offered as a remedy" $?
grep -qi "one-line pointer\|nowhere else" "$EN"; check "the decision is recorded once, not restated in prose" $?
grep -qi "read the field instead of re-deriving" "$EN"; check "later runs read the field, not re-derive the argument" $?

# --- the policy file carries the field, defaulting to required ---
if command -v jq >/dev/null 2>&1; then
  jq -e '.forgeProtection == "required"' "$POLICY" >/dev/null 2>&1
  check "risk-policy.json ships forgeProtection: required" $?
  jq -e 'has("$comment_forgeProtection")' "$POLICY" >/dev/null 2>&1
  check "the field documents its own two values in-file" $?
else
  echo "  skip — jq not available"
fi

# --- the mechanism: may_automerge is gated on protection, not on prose ---
if command -v jq >/dev/null 2>&1; then
  TMP=$(mktemp -d); export CLAUDE_PROJECT_DIR="$TMP"
  # a policy that WOULD auto-merge low risk, but on an unprotectable forge
  cat > "$TMP/policy.json" <<'JSON'
{ "linesChanged": { "low": 150, "medium": 600 }, "highRiskPaths": [],
  "forgeProtection": "unavailable-accepted", "autoMergeRiskLevels": ["low","medium"] }
JSON
  export RISK_POLICY="$TMP/policy.json"
  # shellcheck disable=SC1090
  source "$DRIVER"

  may_automerge low; [ $? -ne 0 ]; check "accepted-exposure: low risk does NOT auto-merge" $?
  may_automerge medium; [ $? -ne 0 ]; check "accepted-exposure: medium risk does NOT auto-merge" $?

  # the same policy on a protected forge behaves exactly as before
  jq '.forgeProtection = "required"' "$TMP/policy.json" > "$TMP/p2.json"
  RISK_POLICY="$TMP/p2.json" may_automerge low; check "protected forge: listed level still auto-merges" $?
  RISK_POLICY="$TMP/p2.json" may_automerge high; [ $? -ne 0 ]; check "protected forge: unlisted level still refused" $?

  # a policy written before the field existed must not silently gain auto-merge
  jq 'del(.forgeProtection)' "$TMP/policy.json" > "$TMP/p3.json"
  [ "$(RISK_POLICY="$TMP/p3.json" forge_protection)" = "required" ]
  check "missing field defaults to required (no silent behavior change)" $?
  rm -rf "$TMP"
fi

# --- run-to-completion states what it completes TO ---
grep -q "forgeProtection" "$RUN"; check "the run skill names the gate" $?
grep -qi "never to \`main\`\|never to .main." "$RUN"; check "run-to-completion completes to PRs where protection is impossible" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
