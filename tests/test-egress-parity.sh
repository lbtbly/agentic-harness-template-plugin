#!/bin/bash
# R13 — one egress allowlist, two enforcers: the devcontainer firewall and the
# native sandbox must derive from the same list (like CODEOWNERS↔risk-policy).
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
AL="../plugins/orchestrator/templates/orchestrator/egress-allowlist.txt"
SET="../plugins/orchestrator/templates/orchestrator/settings.orchestrator.json"
FW="../plugins/core/templates/.devcontainer/init-firewall.sh"

[ -f "$AL" ]; check "egress-allowlist.txt ships (single source of truth)" $?
miss=0
while IFS= read -r d; do
  case "$d" in ""|\#*) continue;; esac
  jq -e --arg d "$d" '.sandbox.network.allowedDomains | index($d)' "$SET" >/dev/null 2>&1 || { echo "         not in sandbox allowedDomains: $d"; miss=1; }
  grep -q "$d" "$FW" || { echo "         not in firewall ALLOW_HOSTS: $d"; miss=1; }
done < "$AL"
check "every allowlist domain present in BOTH sandbox settings and firewall" $miss
grep -q "egress-allowlist" "$FW"; check "firewall documents/reads the shared allowlist" $?
jq -e '.enabledMcpjsonServers == ["playwright"]' "$SET" >/dev/null 2>&1; check "granular MCP enable list (playwright only)" $?
jq -e '.enableAllProjectMcpServers' "$SET" >/dev/null 2>&1 && r=1 || r=0; [ "$r" = 0 ]; check "broad enableAllProjectMcpServers removed" $?
jq -e '[.sandbox.credentials.envVars[] | select(.name=="ANTHROPIC_API_KEY" and .mode=="deny")] | length == 1' "$SET" >/dev/null 2>&1
check "model credentials denied to tool subprocesses" $?
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
