#!/bin/bash
# Stop: the safety net against "I close the terminal and forget".
# If HANDOFF.md > 24h old AND there are uncommitted changes → ask Claude to
# remind the user about /handoff. stop_hook_active prevents the infinite loop.
INPUT=$(cat)
[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
# Freshness source: newest state-layer session record (ADR-0007), else legacy HANDOFF.md
H=$(ls -t .orch/sessions/*.json 2>/dev/null | head -1)
[ -n "$H" ] || H="docs/HANDOFF.md"
[ -f "$H" ] || exit 0
[ -n "$(git status --porcelain 2>/dev/null)" ] || exit 0

MTIME=$(stat -c %Y "$H" 2>/dev/null || stat -f %m "$H" 2>/dev/null) || exit 0
AGE=$(( $(date +%s) - MTIME ))
if [ "$AGE" -gt 86400 ]; then
  jq -n '{decision:"block", reason:"HANDOFF.md is more than 24h old and there are uncommitted git changes. Briefly remind the user to run /handoff before leaving (do not run it yourself, do nothing else)."}'
fi
exit 0
