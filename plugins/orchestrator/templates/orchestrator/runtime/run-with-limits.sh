#!/bin/bash
# Usage-limit resilience wrapper (WS5 / ADR-0008). Runs Phase B headless and
# survives limits by CLASS:
#   - 429 rate limits: claude -p auto-retries with backoff (respects
#     retry-after) — prefer the CLI over the raw Agent SDK, which crashes on 429.
#   - HARD stops (billing_error / weekly-subscription reset / daily run caps):
#     do NOT sleep in-process — checkpoint (state: Paused, note: paused-until)
#     and exit 0; the RUNTIME's retry schedule re-fires and resumes.
# Lanes (audit L-B1): ORCH_LANE=nightly always builds; ORCH_LANE=retry builds
# ONLY if it just restored an expired pause — otherwise it exits without
# spending a token. Unset = nightly (single-schedule setups).
# Budget (audit L-I1): ORCH_BUDGET_TOKENS is passed to the workflow as a hard cap.
# git + forge are the idempotent source of truth: a killed run is always safe
# to re-enter — the workflow reconciles from reality (no session-file resume).
set -u
R="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ORCH="$R/orchestrator/bin/orch"
DATE=$(date +%F)
PAUSE_HOURS_DEFAULT="${ORCH_PAUSE_HOURS:-6}"
LANE="${ORCH_LANE:-nightly}"

# --- pause bookkeeping -------------------------------------------------------
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PAUSED_JSON=$("$ORCH" state list-epics --state Paused 2>/dev/null || echo '[]')
ACTIVE_PAUSES=$(echo "$PAUSED_JSON" | jq -r --arg now "$NOW" \
  '[.[] | select((.note // "") | test("paused-until ")) |
    select(((.note | capture("paused-until (?<t>[0-9TZ:.-]+)").t) // "1970") > $now)] | length' 2>/dev/null || echo 0)
case "$ACTIVE_PAUSES" in ''|*[!0-9]*) ACTIVE_PAUSES=0 ;; esac

if [ "$ACTIVE_PAUSES" -gt 0 ]; then
  echo "still paused on a usage limit ($ACTIVE_PAUSES epic(s)) — waiting for reset; exiting cleanly."
  exit 0
fi

# expired pauses → restore to the state they were paused FROM (Planned or
# Changes-requested, encoded in the note). RESUMED tracks whether the retry
# lane has any right to run.
RESUMED=0
EXPIRED_IDS=$(echo "$PAUSED_JSON" | jq -r '.[].id // empty' 2>/dev/null)
for id in $EXPIRED_IDS; do
  note=$(echo "$PAUSED_JSON" | jq -r --arg i "$id" '[.[] | select(.id == $i)][0].note // ""')
  from=$(printf '%s' "$note" | sed -n 's/.*from=\([A-Za-z-]*\).*/\1/p'); [ -n "$from" ] || from=Planned
  "$ORCH" state push-status --id "$id" --state "$from" >/dev/null 2>&1 && RESUMED=1
done

if [ "$LANE" = "retry" ] && [ "$RESUMED" -eq 0 ]; then
  echo "retry lane: no expired pause to resume — exiting without running (audit L-B1)."
  exit 0
fi

# --- run Phase B (workflow) headless ---
# The nightly-orchestrator workflow ships in the orchestrator PLUGIN,
# not the project. On a CI runner the plugin is not part of the checkout, so the
# runtime templates fetch it and set ORCH_PLUGIN_DIR to the plugin dir; we pass
# it via --plugin-dir so `claude -p` can resolve the workflow. (Interactive/local
# runs where the plugin is already installed can leave ORCH_PLUGIN_DIR unset.)
PLUGIN_ARGS=()
[ -n "${ORCH_PLUGIN_DIR:-}" ] && PLUGIN_ARGS=(--plugin-dir "$ORCH_PLUGIN_DIR")
MODELS_JSON=$(jq -c . "$R/orchestrator/models.config.json" 2>/dev/null || echo null)
# Hardened flags (R12): turn cap + optional native USD cap + pinned MCP config.
# NEVER --bare here (ADR-0019: it breaks the subscription-token lane).
OUT=$(claude -p "Run the nightly-orchestrator workflow with args {\"date\":\"$DATE\",\"maxEpics\":${ORCH_MAX_EPICS:-4},\"budgetTokens\":${ORCH_BUDGET_TOKENS:-null},\"models\":$MODELS_JSON}." \
  --settings "$R/orchestrator/settings.orchestrator.json" \
  "${PLUGIN_ARGS[@]}" \
  --max-turns "${ORCH_MAX_TURNS:-200}" ${ORCH_MAX_BUDGET_USD:+--max-budget-usd "$ORCH_MAX_BUDGET_USD"} \
  --strict-mcp-config --mcp-config "$R/.mcp.json" \
  --output-format json 2>&1)
STATUS=$?
[ $STATUS -eq 0 ] && { echo "$OUT" | jq -r '.result // "done"' 2>/dev/null || echo done; exit 0; }

# --- classify the failure ---
if echo "$OUT" | grep -qiE 'billing_error|spend limit|usage limit|weekly limit|run cap'; then
  # HARD stop: parse a reset timestamp — ISO or the CLI's epoch form ("…|1751234567")
  RESET=$(echo "$OUT" | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z' | head -1)
  if [ -z "$RESET" ]; then
    EPOCH=$(echo "$OUT" | grep -oE '\|1[0-9]{9}' | head -1 | tr -d '|')
    if [ -n "$EPOCH" ]; then
      RESET=$(date -u -r "$EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
           || date -u -d "@$EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    fi
  fi
  [ -n "$RESET" ] || RESET=$(date -u -v+"${PAUSE_HOURS_DEFAULT}"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                          || date -u -d "+${PAUSE_HOURS_DEFAULT} hours" +%Y-%m-%dT%H:%M:%SZ)
  echo "usage limit hit — pausing until $RESET (the retry schedule resumes automatically)."
  # Pause the not-yet-built work (Planned = new, Changes-requested = rework,
  # In-progress = was mid-build when the limit hit — audit L-B6),
  # recording the origin state so expiry restores it faithfully.
  for st in Planned Changes-requested In-progress; do
    "$ORCH" state list-epics --state "$st" 2>/dev/null | jq -r '.[].id // empty' | while read -r id; do
      [ -n "$id" ] && "$ORCH" state push-status --id "$id" --state Paused --note "paused-until $RESET from=$st (usage limit)" >/dev/null
    done
  done
  exit 0   # clean stop — partial work is already on orch/* branches + PRs
fi
if echo "$OUT" | grep -qE '429|rate_limit'; then
  echo "residual 429 after CLI retries — transient; the retry schedule will re-enter." >&2
  exit 0
fi
echo "$OUT" | tail -5 >&2
exit 1
