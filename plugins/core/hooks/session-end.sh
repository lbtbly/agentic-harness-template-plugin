#!/bin/bash
# SessionEnd observer (POLICY, default ON via `journal`).
# Closes the session's journal with a summary line, so a reader can tell a
# session that ended clean from one that ended with work still red — without
# replaying every event. Advisory only: never blocks, always exits 0.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null || exit 0
policy_enabled journal || exit 0

R="${CLAUDE_PROJECT_DIR:-.}"
REASON=$(printf '%s' "$INPUT" | jq -r '.reason // "unknown"' 2>/dev/null)

# Count this session's own events, so the summary is self-contained.
TODAY="$R/.orch/journal/$(date -u +%F).jsonl"
SID="${CLAUDE_SESSION_ID:-}"
[ -n "$SID" ] || SID=$(git -C "$R" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -n "$SID" ] || SID=unknown
BLOCKS=0; ERRORS=0; CORRECTIONS=0
if [ -f "$TODAY" ]; then
  BLOCKS=$(jq -rs --arg s "$SID" '[.[] | select(.sid==$s and .kind=="guard_block")] | length' "$TODAY" 2>/dev/null || echo 0)
  ERRORS=$(jq -rs --arg s "$SID" '[.[] | select(.sid==$s and .kind=="tool_error")] | length' "$TODAY" 2>/dev/null || echo 0)
  CORRECTIONS=$(jq -rs --arg s "$SID" '[.[] | select(.sid==$s and .kind=="user_correction")] | length' "$TODAY" 2>/dev/null || echo 0)
fi

# Dirty tree at session end = the clean-state rule was not met (harness lecture 12).
DIRTY=false
[ -n "$(git -C "$R" status --porcelain 2>/dev/null)" ] && DIRTY=true

journal session_end "$REASON" "$(jq -cn \
  --argjson b "${BLOCKS:-0}" --argjson e "${ERRORS:-0}" --argjson c "${CORRECTIONS:-0}" \
  --argjson d "$DIRTY" \
  '{guardBlocks:$b, toolErrors:$e, userCorrections:$c, dirtyTree:$d}')"
exit 0
