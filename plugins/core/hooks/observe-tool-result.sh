#!/bin/bash
# PostToolUse observer (POLICY, default ON — gated by the `journal` key).
# The richest error source in the whole harness is a Bash command that failed:
# a red suite, a type error, a broken build. Nothing observed it before this.
# Advisory only: never blocks, never edits, always exits 0.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null || exit 0
policy_enabled journal || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -n "$TOOL" ] || exit 0

# Claude Code reports failure differently per tool; accept every shape.
IS_ERR=$(printf '%s' "$INPUT" | jq -r '
  (.tool_response.is_error // .tool_response.isError //
   (if (.tool_response.interrupted // false) then true else false end) // false) | tostring' 2>/dev/null)
[ "$IS_ERR" = "true" ] || exit 0

case "$TOOL" in
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    # The FIRST WORD only — the verb is the signal ("npm", "pytest", "cargo").
    # Never the full command line: it carries paths, hostnames and flags, and
    # this file is meant to be exportable.
    VERB=$(printf '%s' "$CMD" | tr -s ' ' | cut -d' ' -f1 | sed 's|.*/||')
    # A classification, not the message. Free-text stderr is where secrets and
    # absolute paths leak, so it is deliberately never recorded.
    # Plain grep, not awk: BSD awk has no \< word boundary, and `exit` still runs
    # END — both silently produced garbage classes.
    OUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // .tool_response.stderr // ""' 2>/dev/null | tr 'A-Z' 'a-z')
    CLASS=unclassified
    for rule in \
      'command not found|no such file:missing_command' \
      'permission denied:permission_denied' \
      'type ?error|typecheck|tsc|mypy:type_error' \
      'test|spec|assert:test_failure' \
      'lint|eslint|ruff|clippy:lint_failure' \
      'conflict:merge_conflict'; do
      pat=${rule%:*}; name=${rule##*:}
      if printf '%s' "$OUT" | grep -qE "$pat"; then CLASS=$name; break; fi
    done
    journal tool_error "$VERB" "$(jq -cn --arg c "$CLASS" '{class:$c}')"
    ;;
  Edit|Write|NotebookEdit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    journal tool_error "$TOOL" "$(jq -cn --arg f "$(journal_relpath "$FP")" '{path:$f}')"
    ;;
  *)
    journal tool_error "$TOOL"
    ;;
esac
exit 0
