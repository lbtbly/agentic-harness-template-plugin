#!/bin/bash
# Subsystem 4e — git hygiene (POLICY, default ON, per-project toggle):
# no --no-verify, no force-push to main.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
HOOK=../plugins/core/hooks/block-no-verify.sh

assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git commit -m x --no-verify"}}' "blocks --no-verify"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git commit -n -m x"}}' "blocks git commit -n (short no-verify)"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git commit -an -m x"}}' "blocks git commit -an"
assert_exit 0 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git commit -m fix"}}' "allows plain git commit -m"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "blocks push --force main"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' "blocks push -f main"
assert_exit 0 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin feature/x"}}' "allows force-with-lease on a branch"
assert_exit 0 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix\""}}' "allows normal commit"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git -C /tmp commit -m x --no-verify"}}' "blocks --no-verify with git -C"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git -c user.name=x push --force origin main"}}' "blocks force push with git -c"

# --- Policy opt-out (git hygiene is policy, not security) ---
export CLAUDE_POLICY_BLOCK_NO_VERIFY=0
assert_exit 0 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git commit -m x --no-verify"}}' "--no-verify allowed when policy disabled"
assert_exit 0 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' "force-push allowed when policy disabled"
unset CLAUDE_POLICY_BLOCK_NO_VERIFY
summary
