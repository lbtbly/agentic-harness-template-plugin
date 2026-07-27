#!/bin/bash
# SECURITY (never disabled, CORE): an agent must not widen its own permissions.
# Guards the project's .claude/settings.json (permissions + plan-mode). The POLICY
# half of the old combined hook lives in protect-policy-paths.sh. Known limit: Bash
# redirections are not intercepted — accepted and documented in ADR-0009.
# R6: a guard that cannot parse its input must BLOCK, not silently allow.
command -v jq >/dev/null 2>&1 || { echo "BLOCKED: protect-paths cannot run — jq is missing (install jq; see docs/SECURITY.md)" >&2; exit 2; }
INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FP" ] && exit 0

case "$FP" in
  */.claude/settings.json|.claude/settings.json)
    echo "BLOCKED: $FP is the team contract — an agent cannot widen its own permissions. Modify settings.local.json or go through a human PR." >&2
    # A self-elevation attempt is the single most valuable journal entry there is.
    . "$(dirname "$0")/policy-lib.sh" 2>/dev/null && journal guard_block self_elevation '{"severity":"security"}'
    exit 2;;
esac
exit 0
