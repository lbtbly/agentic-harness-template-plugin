#!/bin/bash
# Subsystem 4b — the double risk-gate's forge half: CODEOWNERS must cover every
# risk-policy highRiskPath, so a misclassified low-risk auto-merge still cannot
# land a sensitive path without a human.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
R=".."
RISK="$R/plugins/orchestrator/templates/orchestrator/risk-policy.json"
CO="$R/plugins/orchestrator/templates/.github/CODEOWNERS"

test -f "$CO"; check "CODEOWNERS template exists" $?
miss=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  grep -qF "$p" "$CO" || { echo "         highRiskPath not owned in CODEOWNERS: $p"; miss=1; }
done < <(jq -r '.highRiskPaths[]' "$RISK" 2>/dev/null)
check "every risk-policy highRiskPath appears in CODEOWNERS" $miss
grep -q "@" "$CO"; check "CODEOWNERS assigns at least one owner" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
