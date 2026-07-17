#!/bin/bash
# Run-to-completion driver. Launch: /orchestrator:run.
# Source-able: functions are defined at top; `main` only runs when executed.
# Parallel build, serial merge: builders fan out in worktrees; this outer loop
# lands epics one at a time and is the only thing that touches main.
set -u
R="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# orch_bin — resolve the orch CLI at call time (ORCH_BIN overridable for tests).
orch_bin() { echo "${ORCH_BIN:-$R/orchestrator/bin/orch}"; }

# select_scope <all|first> [n] — prints selected epic ids in board order.
select_scope() {
  local mode="$1" n="${2:-0}"
  local ids; ids=$("$(orch_bin)" state list-epics 2>/dev/null | jq -r '.[].id')
  if [ "$mode" = "first" ]; then echo "$ids" | head -n "$n"; else echo "$ids"; fi
}

# partition_wave — reads epics JSON on stdin, prints ids whose footprints are
# pairwise disjoint (greedy, board order). Overlap = shared glob string.
partition_wave() {
  jq -r '
    reduce .[] as $e ({admitted:[], globs:[]};
      . as $acc
      | ($e.footprint // []) as $fp
      | if ($fp | any(. as $g | $acc.globs | index($g)))
        then .
        else .admitted += [$e.id] | .globs += $fp end)
    | .admitted[]'
}

# --- termination guards (each prints a decision token, returns 0) ---
guard_no_progress() { [ "$1" -ge "$2" ] && echo blocked || echo continue; }
guard_budget()     { [ "$2" -gt 0 ] && [ "$1" -ge "$2" ] && echo stop || echo continue; }
guard_wallclock()  { [ "$2" -gt 0 ] && [ "$1" -ge "$2" ] && echo stop || echo continue; }
guard_thrash()     { [ "$1" -eq 0 ] && echo stop || echo continue; }
# safety: settings tampered / plan-mode gone → abort the whole run. Resolves the
# project dir at CALL time so a mid-run swap is caught.
guard_safety() {
  local s="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/settings.json"
  [ -f "$s" ] && grep -q '"defaultMode"' "$s" 2>/dev/null && grep -q 'plan' "$s" 2>/dev/null && echo ok || echo abort
}

# --- usage-aware throttle: slow, then pause, BEFORE the wall ---
usage_pct() {
  if [ -n "${ORCH_USAGE_CMD:-}" ]; then eval "$ORCH_USAGE_CMD" 2>/dev/null | grep -oE '^[0-9]+$' | head -1 && return; fi
  if command -v ccusage >/dev/null 2>&1; then ccusage --json 2>/dev/null | jq -r '.percentUsed // -1' | grep -oE '^-?[0-9]+' | head -1 && return; fi
  echo -1
}
throttle_decision() {
  local p="$1"
  [ "$p" -lt 0 ] 2>/dev/null && { echo continue; return; }
  [ "$p" -ge "${ORCH_USAGE_PAUSE_PCT:-95}" ] && { echo pause; return; }
  [ "$p" -ge "${ORCH_USAGE_SLOW_PCT:-80}" ] && { echo slow; return; }
  echo continue
}
throttled_cap() {
  case "$(throttle_decision "$1")" in
    pause) echo 0 ;;
    slow) local h=$(( $2 / 2 )); [ "$h" -lt 1 ] && h=1; echo "$h" ;;
    *) echo "$2" ;;
  esac
}

# --- risk-gated serial merge queue ---
RISK_POLICY="${RISK_POLICY:-$R/orchestrator/risk-policy.json}"
# classify_risk <lines> <paths> — policy data decides; a sensitive-path hit or a
# big diff makes the epic high-risk regardless of anything else.
classify_risk() {
  local lines="$1" paths="$2" lo med
  lo=$(jq -r '.linesChanged.low' "$RISK_POLICY"); med=$(jq -r '.linesChanged.medium' "$RISK_POLICY")
  while IFS= read -r p; do [ -n "$p" ] || continue
    while IFS= read -r g; do case "$p" in ${g//\*\*/*}) echo high; return;; esac
    done < <(jq -r '.highRiskPaths[]' "$RISK_POLICY")
  done <<< "$paths"
  [ "$lines" -gt "$med" ] && { echo high; return; }
  [ "$lines" -gt "$lo" ]  && { echo medium; return; }
  echo low
}
may_automerge() { jq -e --arg r "$1" '.autoMergeRiskLevels | index($r)' "$RISK_POLICY" >/dev/null 2>&1; }
# compute_risk <id> — the DEFAULT risk signal: classify the epic's real diff
# (orch/<id> vs main) against the policy. Fails CLOSED: no policy, no branch,
# or an unreadable diff all classify as high.
compute_risk() {
  local id="$1" stat lines paths
  [ -f "$RISK_POLICY" ] || { echo high; return; }
  stat=$(git diff --numstat "main..orch/$id" 2>/dev/null) || { echo high; return; }
  [ -n "$stat" ] || { echo high; return; }
  lines=$(echo "$stat" | awk '{a+=$1; d+=$2} END {print a+d+0}')
  paths=$(echo "$stat" | awk '{print $3}')
  classify_risk "$lines" "$paths"
}
# merge_epic <id> <risk> <verdict-json> — the only function that moves main.
# done verdict + auto-mergeable risk + green suite after the merge, else revert.
merge_epic() {
  local id="$1" risk="$2" verdict="$3"
  [ "$(echo "$verdict" | jq -r '.done')" = "true" ] || { echo escalated; return; }
  may_automerge "$risk" || { echo escalated; return; }
  git checkout -q main || return 1
  git merge -q --no-ff "orch/$id" -m "merge orch/$id" || { git merge --abort 2>/dev/null; echo escalated; return; }
  if eval "${SUITE_CMD:-true}"; then echo merged; else git reset -q --hard HEAD~1; echo reverted; fi
}

# --- engine hooks (overridable via env so the loop is testable with fakes) ---
# Hardened headless invocations (R12): explicit turn caps, optional native cost
# cap, pinned MCP config (no stray user servers in an unattended run), and a
# schema-validated verdict. NEVER --bare — it skips OAuth reads and silently
# breaks the subscription-token lane (ADR-0019).
MODELS_JSON() { jq -c . "$R/orchestrator/models.config.json" 2>/dev/null || echo null; }
build_wave()  { if [ -n "${ORCH_BUILD_CMD:-}" ]; then eval "$ORCH_BUILD_CMD"; else
  claude -p "Run the nightly-orchestrator workflow with args {\"date\":\"$(date +%F)\",\"maxEpics\":${ORCH_MAX_CONCURRENT:-4},\"models\":$(MODELS_JSON)}." \
    --settings "$R/orchestrator/settings.orchestrator.json" ${ORCH_PLUGIN_DIR:+--plugin-dir "$ORCH_PLUGIN_DIR"} \
    --max-turns "${ORCH_MAX_TURNS:-80}" ${ORCH_MAX_BUDGET_USD:+--max-budget-usd "$ORCH_MAX_BUDGET_USD"} \
    --strict-mcp-config --mcp-config "$R/.mcp.json" \
    --output-format json >/dev/null 2>&1; fi; }
verify_epic() { if [ -n "${ORCH_VERIFY_CMD:-}" ]; then eval "$ORCH_VERIFY_CMD"; else
  claude -p "Run dod-verify for epic $1; return the verdict." \
    --output-format json --json-schema "$(cat "$R/orchestrator/verdict.schema.json")" \
    --max-turns "${ORCH_MAX_TURNS:-80}" ${ORCH_MAX_BUDGET_USD:+--max-budget-usd "$ORCH_MAX_BUDGET_USD"} \
    --strict-mcp-config --mcp-config "$R/.mcp.json" \
    2>/dev/null | jq -c '.structured_output // .result // .'; fi; }
# risk: computed per epic BEFORE any merge decision — from the real diff via
# compute_risk (which fails closed to high when the policy/diff is unreadable).
do_risk()     { if [ -n "${ORCH_RISK_CMD:-}" ]; then eval "$ORCH_RISK_CMD"; else compute_risk "$1"; fi; }
# merge: the risk-gated queue (merge_epic). Escalation is always the safe path.
do_merge()    { if [ -n "${ORCH_MERGE_CMD:-}" ]; then eval "$ORCH_MERGE_CMD"; else merge_epic "$1" "$2" "$3"; fi; }
# spend signal for the budget guard (tokens spent so far; -1/absent = unknown)
spent_tokens() { if [ -n "${ORCH_SPENT_CMD:-}" ]; then eval "$ORCH_SPENT_CMD" 2>/dev/null | grep -oE '^[0-9]+' | head -1; else echo 0; fi; }

# json_arr <items…> — serialize args as a JSON string array ([] when empty).
json_arr() { [ "$#" -eq 0 ] && { echo '[]'; return; }; printf '%s\n' "$@" | jq -R . | jq -sc .; }

run_loop() {
  local mode="$1" n="${2:-0}" k="${ORCH_NOPROGRESS_K:-3}"
  local selected merged=() escalated=() blocked=() stopped=null
  selected=$(select_scope "$mode" "$n")
  declare -A rounds
  while :; do
    [ "$(guard_safety)" = abort ] && { stopped='"SAFETY"'; break; }
    [ "$(guard_wallclock "$(date +%s)" "${ORCH_WALLCLOCK_DEADLINE:-0}")" = stop ] && { stopped='"WALLCLOCK"'; break; }
    [ "$(guard_budget "$(spent_tokens)" "${ORCH_BUDGET_TOKENS:-0}")" = stop ] && { stopped='"BUDGET"'; break; }
    local advanced=0 pending=0
    for id in $selected; do
      case " ${merged[*]} ${escalated[*]} ${blocked[*]} " in *" $id "*) continue;; esac
      pending=1
      build_wave >/dev/null 2>&1
      local v; v=$(verify_epic "$id")
      if [ "$(echo "$v" | jq -r '.done')" = true ]; then
        local risk res
        risk=$(do_risk "$id")
        res=$(do_merge "$id" "$risk" "$v")
        if [ "$res" = merged ]; then merged+=("$id"); advanced=1; else escalated+=("$id"); advanced=1; fi
      else
        rounds[$id]=$(( ${rounds[$id]:-0} + 1 )); advanced=1
        [ "$(guard_no_progress "${rounds[$id]}" "$k")" = blocked ] && { blocked+=("$id"); }
      fi
    done
    [ "$pending" = 0 ] && break
    [ "$(guard_thrash "$advanced")" = stop ] && { stopped='"THRASH"'; break; }
  done
  printf '{"merged":%s,"escalated":%s,"blocked":%s,"stopped_by":%s}\n' \
    "$(json_arr "${merged[@]}")" \
    "$(json_arr "${escalated[@]}")" \
    "$(json_arr "${blocked[@]}")" "$stopped"
}

main() { run_loop "${1:-all}" "${2:-0}"; }
[ "${BASH_SOURCE[0]}" = "$0" ] && main "$@"
