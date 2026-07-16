#!/bin/bash
# SECURITY (never disabled, CORE): an agent must not widen its own permissions.
# Guards the project's .claude/settings.json (permissions + plan-mode). The POLICY
# half of the old combined hook lives in protect-policy-paths.sh. Known limit: Bash
# redirections are not intercepted — accepted and documented in ADR-0009.
INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FP" ] && exit 0

case "$FP" in
  */.claude/settings.json|.claude/settings.json)
    echo "BLOCKED: $FP is the team contract — an agent cannot widen its own permissions. Modify settings.local.json or go through a human PR." >&2; exit 2;;
esac
exit 0
