#!/bin/bash
# Subsystem 4d — no self-elevation (SECURITY, never toggled off): an agent
# cannot edit the file that defines its own permissions.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
HOOK=../plugins/core/hooks/protect-paths.sh

assert_exit 2 "$HOOK" '{"tool_name":"Write","tool_input":{"file_path":"/p/.claude/settings.json"}}' "blocks settings.json (self-elevation)"
assert_exit 0 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/src/index.ts"}}' "allows normal code"
assert_exit 0 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/.claude/settings.local.json"}}' "allows settings.local.json"

# Security is immune to every policy toggle
export CLAUDE_POLICY_PROTECT_PATHS_POLICY=0
assert_exit 2 "$HOOK" '{"tool_name":"Write","tool_input":{"file_path":"/p/.claude/settings.json"}}' "settings.json stays blocked with policy off (security)"
unset CLAUDE_POLICY_PROTECT_PATHS_POLICY
summary
