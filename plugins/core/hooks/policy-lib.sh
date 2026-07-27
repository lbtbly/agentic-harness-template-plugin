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

# --- the journal: an append-only event stream owned by the HARNESS ------------
# Every other .orch artefact is replace-semantics; this one is the only history.
# It exists so an installed repo can tell you what the agent got wrong and what
# fixed it. 12factor XI: logs are an event stream, not a file to be managed.
#
# journal <kind> <key> [json-object-of-extra-fields]
#   kind — guard_block | tool_error | user_correction | subagent_fail | reformat
#          | verdict_reject | merge_revert | escalation | correction
#   key  — the stable grouping label for that kind (rule name, tool name, …)
#
# NEVER writes a value: paths are made repo-relative, and nothing here reads
# file contents. Redaction for EXPORT is a separate, stricter pass.
# Off by default is wrong here (the whole point is passive accretion), so it
# follows the standard policy chain and defaults ENABLED — `journal: false` in
# .claude/policy.json or CLAUDE_POLICY_JOURNAL=0 turns it off.
journal() {
  policy_enabled journal || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # Resolve a REAL project root, never the bare CWD. A hook invoked without
  # CLAUDE_PROJECT_DIR would otherwise scatter .orch/journal/ into whatever
  # directory it happened to be run from — telemetry has no business writing
  # somewhere nobody asked for. No root, no journal.
  local root="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$root" ] || root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$root" ] && [ -d "$root" ] || return 0
  local dir="$root/.orch/journal"
  mkdir -p "$dir" 2>/dev/null || return 0
  # session id: Claude Code's when present, else the branch — enough to join an
  # error to the correction that followed it.
  local sid="${CLAUDE_SESSION_ID:-}"
  [ -n "$sid" ] || sid=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null) || sid=unknown
  [ -n "$sid" ] || sid=unknown
  # Assign the default separately: "${3:-\{\}}" keeps the backslashes and yields
  # invalid JSON, which jq rejects — silently, because of the || true below.
  local extra="${3:-}"
  case "$extra" in '') extra='{}' ;; esac
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --arg sid "$sid" \
         --arg kind "$1" \
         --arg key "$2" \
         --argjson extra "$extra" \
    '{ts:$ts, sid:$sid, kind:$kind, key:$key} + $extra' \
    >> "$dir/$(date -u +%F).jsonl" 2>/dev/null || true
  return 0
}

# journal_relpath <path> — repo-relative, or the basename when it is outside the
# repo. Absolute paths leak the machine username (see RECOMMENDATIONS R3, which
# exists because exactly that was committed once).
journal_relpath() {
  local root="${CLAUDE_PROJECT_DIR:-.}" p="$1"
  case "$p" in
    "$root"/*) printf '%s' "${p#"$root"/}" ;;
    /*)        printf '%s' "${p##*/}" ;;
    *)         printf '%s' "$p" ;;
  esac
}
