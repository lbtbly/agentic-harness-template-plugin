#!/bin/bash
# PreCompact: the context is about to be compacted — mechanical save of the
# state via the state layer (ADR-0007), legacy HANDOFF.md as fallback.
# Covers the case the Stop hook does not see.
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# State-layer path: push a mechanical snapshot under .auto (dedup is server-side
# — push-session --auto keeps exactly one auto snapshot per branch).
if [ -x orchestrator/bin/orch ]; then
  BR=$(git branch --show-current 2>/dev/null); [ -n "$BR" ] || BR=detached
  DIRTY=$(git status --porcelain 2>/dev/null | head -20 | jq -R . | jq -sc . 2>/dev/null || echo '[]')
  jq -nc --arg br "$BR" --argjson dirty "$DIRTY" \
    '{branch: $br, dirty: $dirty, ts: (now | todate), note: "mechanical pre-compaction snapshot — run /handoff for a real handoff"}' \
    | orchestrator/bin/orch state push-session --auto >/dev/null 2>&1 && exit 0
fi

# Legacy fallback: append to HANDOFF.md
H="docs/HANDOFF.md"
[ -d docs ] || exit 0

# Cap noise: keep at most one auto snapshot. Strip previous auto-snapshot blocks
# (header .. mechanical-snapshot footer) before appending a fresh one, so a series
# of compactions can never bury a good HANDOFF under stale machine state.
if [ -f "$H" ]; then
  awk '
    /^## Auto snapshot \(pre-compaction\)/ { insnap=1; next }
    insnap && /^_Mechanical snapshot/       { insnap=0; next }
    insnap                                  { next }
    { print }
  ' "$H" > "$H.tmp" 2>/dev/null && mv "$H.tmp" "$H"
fi

{
  echo ""
  echo "## Auto snapshot (pre-compaction) — $(date '+%Y-%m-%d %H:%M')"
  echo "Branch: $(git branch --show-current 2>/dev/null || echo 'n/a')"
  DIRTY=$(git status --porcelain 2>/dev/null | head -20)
  [ -n "$DIRTY" ] && { echo "Files in progress:"; echo "$DIRTY"; }
  echo "_Mechanical snapshot — run /handoff for a real handoff._"
} >> "$H"
exit 0
