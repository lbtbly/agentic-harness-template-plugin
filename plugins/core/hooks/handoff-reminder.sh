#!/bin/bash
# Stop: the safety net against "I close the terminal and forget".
# If HANDOFF.md > 24h old AND there are uncommitted changes → ask Claude to
# remind the user about /handoff. stop_hook_active prevents the infinite loop.
command -v jq >/dev/null 2>&1 || { echo "handoff-reminder: jq missing — advisory hook skipped" >&2; exit 0; }
INPUT=$(cat)
[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# D1 stop-gate (policy `stop_gate`, DEFAULT OFF — advisory reminder is the norm):
# when explicitly enabled, a session snapshot whose cleanState reports failing
# build/tests or leftover debug artifacts BLOCKS the stop (exit 2). Anti-loop:
# the stop_hook_active check above always wins; the runtime also caps repeats.
GATE="${CLAUDE_POLICY_STOP_GATE:-}"
[ -z "$GATE" ] && GATE=$(jq -r '.stop_gate // false' .claude/policy.json 2>/dev/null)
if [ "$GATE" = "true" ] || [ "$GATE" = "1" ]; then
  SNAP=$(ls -t .orch/sessions/*.json 2>/dev/null | head -1)
  if [ -n "$SNAP" ]; then
    DIRTY=$(jq -r '([.cleanState.build, .cleanState.tests] | map(select(. == "fail")) | length) + ((.cleanState.debugArtifacts // []) | if length > 0 then 1 else 0 end)' "$SNAP" 2>/dev/null)
    if [ "${DIRTY:-0}" -gt 0 ] 2>/dev/null; then
      echo "STOP GATE: the session snapshot reports failing build/tests or debug artifacts — fix them or run /core:handoff to record the state honestly before stopping (policy stop_gate; set stop_gate:false to disable)." >&2
      exit 2
    fi
  fi
fi
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
