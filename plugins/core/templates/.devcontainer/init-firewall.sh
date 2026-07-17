#!/bin/bash
# Default-deny egress firewall for the devcontainer (opt-in isolation for
# higher-autonomy / untrusted-code runs). Allowlist only what the agent needs,
# then verify the lockdown actually holds. Requires NET_ADMIN (see devcontainer.json).
# Adapt the allowlist to your stack; this is a starting point, not a guarantee.
set -euo pipefail

# Allowlisted egress hosts (extend deliberately — every entry widens the blast radius).
# Single source of truth: orchestrator/egress-allowlist.txt (also feeds the native
# sandbox's allowedDomains — parity-tested). The literal default below matches it
# for scaffolds where the orchestrator payload isn't installed yet.
ALLOW_HOSTS="api.anthropic.com github.com api.github.com codeload.github.com registry.npmjs.org pypi.org files.pythonhosted.org"
ALLOWLIST_FILE="${ORCH_EGRESS_ALLOWLIST:-${CLAUDE_PROJECT_DIR:-$(pwd)}/orchestrator/egress-allowlist.txt}"
[ -f "$ALLOWLIST_FILE" ] && ALLOW_HOSTS=$(grep -v "^#" "$ALLOWLIST_FILE" | tr "\n" " ")

# FAIL CLOSED (audit SEC-C1): unattended runs must not proceed without confirmed
# containment. Set ORCH_FIREWALL_OPTIONAL=1 only for interactive/dev use.
fail() { echo "FIREWALL FATAL: $1" >&2; [ "${ORCH_FIREWALL_OPTIONAL:-0}" = "1" ] && exit 0 || exit 1; }

command -v iptables >/dev/null 2>&1 || fail "iptables missing — cannot establish egress lockdown"

iptables -F OUTPUT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT   # DNS
for h in $ALLOW_HOSTS; do
  for ip in $(getent ahosts "$h" | awk '{print $1}' | sort -u); do
    iptables -A OUTPUT -d "$ip" -j ACCEPT
  done
done
iptables -P OUTPUT DROP   # default deny

# Verify: an off-list host must fail (fatal if it doesn't), an on-list host must succeed.
if curl -sf --max-time 5 https://example.com >/dev/null 2>&1; then
  fail "egress to example.com succeeded — lockdown is NOT effective"
fi
curl -sf --max-time 5 https://api.github.com >/dev/null 2>&1 || echo "FIREWALL WARNING: api.github.com unreachable — allowlist may be too tight." >&2
echo "Firewall initialized and VERIFIED (default-deny egress; allowlist: $ALLOW_HOSTS)."
