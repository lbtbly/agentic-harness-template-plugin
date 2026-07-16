#!/bin/bash
# Shared helper for the guardrail split (security vs policy).
# policy_enabled <key> — returns 0 (enabled) or 1 (disabled).
# Opt-in POLICY rules default to ENABLED (backward compatible). SECURITY rules
# never call this — they are always enforced.
# Precedence: env CLAUDE_POLICY_<KEY_UPPERCASE> > .claude/policy.json[<key>] > true.
#   e.g. key "block_no_verify" → env CLAUDE_POLICY_BLOCK_NO_VERIFY.
#   Truthy = anything except "0" or "false".
policy_enabled() {
  local key="$1"
  local up envvar envval
  up=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
  envvar="CLAUDE_POLICY_${up}"
  envval="${!envvar}"
  if [ -n "$envval" ]; then
    [ "$envval" != "0" ] && [ "$envval" != "false" ]
    return
  fi
  local pf="${CLAUDE_PROJECT_DIR:-.}/.claude/policy.json"
  if [ -f "$pf" ] && command -v jq >/dev/null 2>&1; then
    local v
    v=$(jq -r --arg k "$key" 'if has($k) then .[$k] else empty end' "$pf" 2>/dev/null)
    if [ -n "$v" ]; then
      [ "$v" != "false" ] && [ "$v" != "0" ]
      return
    fi
  fi
  return 0
}
