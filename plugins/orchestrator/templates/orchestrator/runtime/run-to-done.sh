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

# --- engine hooks (overridable via env so the loop is testable with fakes) ---
build_wave()  { if [ -n "${ORCH_BUILD_CMD:-}" ]; then eval "$ORCH_BUILD_CMD"; else
  claude -p "Run the nightly-orchestrator workflow with args {\"date\":\"$(date +%F)\",\"maxEpics\":${ORCH_MAX_CONCURRENT:-4}}." \
    --settings "$R/orchestrator/settings.orchestrator.json" ${ORCH_PLUGIN_DIR:+--plugin-dir "$ORCH_PLUGIN_DIR"} --output-format json >/dev/null 2>&1; fi; }
verify_epic() { if [ -n "${ORCH_VERIFY_CMD:-}" ]; then eval "$ORCH_VERIFY_CMD"; else
  claude -p "Run dod-verify for epic $1; output only the verdict JSON." --output-format json 2>/dev/null | jq -c '.result // .'; fi; }
# risk: computed per epic BEFORE any merge decision. Default is HIGH — nothing
# auto-merges until a real classifier (risk-policy.json) says otherwise.
do_risk()     { if [ -n "${ORCH_RISK_CMD:-}" ]; then eval "$ORCH_RISK_CMD"; else echo high; fi; }
# merge: default ESCALATE. The risk-gated merge queue (subsystem: auto-merge)
# overrides this with merge_epic; escalation is always the safe fallback.
do_merge()    { if [ -n "${ORCH_MERGE_CMD:-}" ]; then eval "$ORCH_MERGE_CMD"; else echo escalated; fi; }
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
