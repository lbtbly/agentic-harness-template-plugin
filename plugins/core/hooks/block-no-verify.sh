#!/bin/bash
# Stops a hurried agent from bypassing git safety nets.
# POLICY (opt-in, default ON): git hygiene, not a security boundary. Disable per
# project via .claude/policy.json {"block_no_verify": false} or env
# CLAUDE_POLICY_BLOCK_NO_VERIFY=0.
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

source "$(dirname "$0")/policy-lib.sh"
policy_enabled block_no_verify || exit 0

if echo "$CMD" | grep -qE 'git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+commit[^|;&]*([[:space:]]--no-verify|[[:space:]]-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$))'; then
  echo "BLOCKED: git commit --no-verify is forbidden (git hooks exist for a reason)." >&2
  exit 2
fi
if echo "$CMD" | grep -qE 'git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+push[^|;&]*([[:space:]]--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$))' \
   && echo "$CMD" | grep -qE '(main|master)([[:space:]]|$)'; then
  echo "BLOCKED: push --force to main/master is forbidden. Use --force-with-lease on a branch." >&2
  exit 2
fi
exit 0
