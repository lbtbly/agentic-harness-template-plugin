#!/usr/bin/env bash
# Run-to-completion driver. Launch: /orchestrator:run.
# Source-able: functions are defined at top; `main` only runs when executed.
# Parallel build, serial merge: builders fan out in worktrees; this outer loop
# lands epics one at a time and is the only thing that touches main.
# BASH 3.2 CLEAN (stock macOS /bin/bash): no `declare -A` (bash 4+), no array
# expansion under `set -u` (safe only from bash 4.4). `env bash` prefers a newer
# bash when one is on PATH; nothing here requires it.
set -u
R="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# --- run log ------------------------------------------------------------------
# Everything the engine emits lands here. It used to go to /dev/null, which also
# threw away the REASON a wave failed: an escalation with no diagnosis, and no
# way to see which agent did what. `orchestrator/bin/watch` renders this live.
# Self-ignoring, because the CI runtimes force-add .orch to the orch/state branch
# and machine-local logs must never become commits.
ORCH_LOG_DIR="${ORCH_LOG_DIR:-$R/.orch/logs}"
mkdir -p "$ORCH_LOG_DIR" 2>/dev/null || true
[ -f "$ORCH_LOG_DIR/.gitignore" ] || printf '*\n!.gitignore\n' > "$ORCH_LOG_DIR/.gitignore" 2>/dev/null || true
ORCH_RUN_LOG="${ORCH_RUN_LOG:-$ORCH_LOG_DIR/run-$(date +%F).jsonl}"
ORCH_ERR_LOG="${ORCH_ERR_LOG:-$ORCH_LOG_DIR/run-$(date +%F).err}"

# stream_flags — stream-json so the run is observable while it runs, not after.
# --forward-subagent-text (CLI v2.1.211+) is what makes subagent messages carry
# parent_tool_use_id, i.e. what turns a blob into an agent tree. Probed, never
# assumed: passing an unknown flag would fail EVERY wave on an older CLI.
ORCH_STREAM="${ORCH_STREAM:-1}"
stream_flags() {
  [ "$ORCH_STREAM" = "1" ] || { echo "--output-format json"; return; }
  local f="--output-format stream-json --verbose"
  case "$(claude -p --help 2>/dev/null)" in
    *--forward-subagent-text*) f="$f --forward-subagent-text" ;;
  esac
  echo "$f"
}

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

# --- bash-3.2 state containers ------------------------------------------------
# Epic ids are slug-safe words (they are branch names and file slugs), so a
# space-delimited string IS the set and "<id>=<n>" tokens ARE the counter map.
# No associative arrays, no empty-array expansion, no forks.
set_has()    { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }
set_add()    { if set_has "$1" "$2"; then printf '%s' "$1"; else printf '%s' "${1:+$1 }$2"; fi; }
rounds_get() { local t; for t in $1; do case "$t" in "$2="*) printf '%s' "${t#*=}"; return ;; esac; done; printf '0'; }
rounds_set() { local out='' t; for t in $1; do case "$t" in "$2="*) ;; *) out="${out:+$out }$t" ;; esac; done
               printf '%s' "${out:+$out }$2=$3"; }
rounds_json() { [ -n "$1" ] || { echo '{}'; return; }
                printf '%s\n' $1 | jq -R 'split("=") | {(.[0]): (.[1]|tonumber)}' | jq -sc 'add // {}'; }

# --- the board is the source of truth (git + forge idempotence, ADR-0007) -----
board_json() { "$(orch_bin)" state list-epics 2>/dev/null || echo '[]'; }
epic_field() { printf '%s' "$1" | jq -r --arg i "$2" --arg f "$3" \
                 '[.[] | select(.id==$i) | .[$f] // empty] | first // ""' 2>/dev/null; }
# attempts=<n> is the SAME durable marker nightly-orchestrator.js writes and
# run-with-limits.sh reads. One convention, one parser, no new field.
epic_attempts() { printf '%s' "$1" | jq -r --arg i "$2" '
    [ .[] | select(.id==$i) | (.note // "")
      | select(test("attempts=[0-9]+")) | capture("attempts=(?<n>[0-9]+)").n ]
    | first // "0"' 2>/dev/null || printf '0'; }
# epic_class — what the BOARD already says. A killed run re-enters here and
# reconstructs merged/escalated/blocked instead of rebuilding settled work.
# Paused maps to skip: run-with-limits.sh owns pause bookkeeping, not this loop.
epic_class() {
  case "$(epic_field "$1" "$2" state)" in
    Merged)                echo merged ;;
    Blocked)               echo blocked ;;
    Needs-review|Approved) echo escalated ;;
    Cancelled|Paused)      echo skip ;;
    *)                     echo pending ;;
  esac
}
board_subset() { printf '%s' "$1" | jq -c --arg ids " $2 " \
                   '[.[] | .id as $i | select($ids | contains(" " + $i + " "))]'; }
# deps_ready <board> <candidates-sp> <landed-sp> — TOPOLOGICAL admission. An epic
# is admissible when every dep it declares has landed (merged this run, or
# already Merged on the board). A dep naming no board record is ignored so a
# planner typo cannot deadlock a night; every other unmet dep gates — fail
# closed, same ethos as compute_risk.
deps_ready() {
  printf '%s' "$1" | jq -r --arg cand " $2 " --arg landed " $3 " '
    ([.[] | .id]) as $known
    | ([.[] | select(.state == "Merged") | .id]) as $onboard
    | .[]
    | .id as $eid
    | select($cand | contains(" " + $eid + " "))
    | select([ (.deps // [])[] as $d
               | select($known | index($d))
               | select((($landed | contains(" " + $d + " ")) or ($onboard | index($d))) | not)
               | $d ]
             | length == 0)
    | $eid' 2>/dev/null
}
# push_status — the DURABLE round counter. The note is one argv element; never
# ${3:+--note "$3"}, which word-splits a multi-word note into stray args.
push_status() {
  if [ -n "${ORCH_STATUS_CMD:-}" ]; then eval "$ORCH_STATUS_CMD"; return; fi
  if [ -n "${3:-}" ]; then "$(orch_bin)" state push-status --id "$1" --state "$2" --note "$3" >/dev/null 2>&1 || true
  else                    "$(orch_bin)" state push-status --id "$1" --state "$2"              >/dev/null 2>&1 || true; fi
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
# forge_protection — ADR-0032. Missing field → `required` (fails closed for policies
# written before the field existed: they keep today's behavior only if the forge really
# does protect main, which enable-orchestrator verified).
forge_protection() { jq -r '.forgeProtection // "required"' "$RISK_POLICY" 2>/dev/null || echo required; }
# may_automerge <risk> — the risk level must be listed AND the forge must actually be
# able to refuse a bad push. Where protection is unavailable and the operator accepted
# that exposure, auto-merge is off at the mechanism: editing autoMergeRiskLevels cannot
# re-arm it, because the guard is not in that list.
may_automerge() {
  [ "$(forge_protection)" = "required" ] || return 1
  jq -e --arg r "$1" '.autoMergeRiskLevels | index($r)' "$RISK_POLICY" >/dev/null 2>&1
}

# --- graduated autonomy (ADR-0026) -------------------------------------------
# Risk says how bad it would be to get this wrong. Trust says how often we have
# actually got this KIND of thing right. Auto-merge needs both: a low-risk epic
# in a class the harness has never landed cleanly is still not something to
# merge unattended. Absent ledger → every class is `watch` → nothing auto-merges,
# which is the correct default for a fresh install.
TRUST_BIN="${TRUST_BIN:-$R/orchestrator/bin/trust}"
epic_class_key() { # epic_class_key <board-json> <id>
  local fp cx
  fp=$(printf '%s' "$1" | jq -c --arg i "$2" '[.[] | select(.id==$i) | .footprint // []] | first // []' 2>/dev/null || echo '[]')
  cx=$(epic_field "$1" "$2" complexity); [ -n "$cx" ] || cx=medium
  "$TRUST_BIN" class "$fp" "$cx" 2>/dev/null || echo "unknown/medium"
}
trust_tier()   { [ -x "$TRUST_BIN" ] || { echo watch; return; }; "$TRUST_BIN" tier "$1" 2>/dev/null || echo watch; }
trust_record() { [ -x "$TRUST_BIN" ] || return 0; "$TRUST_BIN" record "$1" "$2" >/dev/null 2>&1 || true; }
do_trust_tier()   { if [ -n "${ORCH_TRUST_TIER_CMD:-}" ]; then eval "$ORCH_TRUST_TIER_CMD"; else trust_tier "$1"; fi; }
do_trust_record() { if [ -n "${ORCH_TRUST_RECORD_CMD:-}" ]; then eval "$ORCH_TRUST_RECORD_CMD"; else trust_record "$1" "$2"; fi; }
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

# --- landing: the forge merges, never this script -----------------------------
# ADR-0015: main is protected — direct push rejected, merges via PR only, the
# token cannot bypass. merge_epic's local merge is therefore the run-local
# integration PROOF (clean merge + green suite, serial, so epic n+1 is verified
# against everything landed before it). publish_epic is the REQUEST to land it:
# `--auto` leaves branch protection + required checks + CODEOWNERS as the enforcer.
publish_epic() {
  local id="$1" fg
  git push -q origin "orch/$id" 2>/dev/null || return 1
  fg=$(jq -r '.forge // "none"' "$R/orchestrator/state.config.json" 2>/dev/null || echo none)
  case "$fg" in
    github) command -v gh >/dev/null 2>&1 || return 1
            gh pr view "orch/$id" >/dev/null 2>&1 || gh pr create --head "orch/$id" --base main --fill >/dev/null 2>&1
            gh pr merge "orch/$id" --auto --squash >/dev/null 2>&1 ;;
    gitlab) command -v glab >/dev/null 2>&1 || return 1
            glab mr view "orch/$id" >/dev/null 2>&1 || glab mr create --source-branch "orch/$id" --target-branch main --fill >/dev/null 2>&1
            glab mr merge "orch/$id" --when-pipeline-succeeds --yes >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}
do_publish() { if [ -n "${ORCH_PUBLISH_CMD:-}" ]; then eval "$ORCH_PUBLISH_CMD"; else publish_epic "$1"; fi; }

# sync_main — re-enter from origin. compute_risk diffs main..orch/<id>, so main
# must reflect reality before anything is measured. Scoped with `git -C "$R"` so
# sourcing this driver in a test can never touch the caller's checkout.
# --ff-only: a re-entered run whose local main still carries un-landed proof
# merges is left alone (the board already records those epics as Merged).
sync_main() {
  git -C "$R" rev-parse --git-dir >/dev/null 2>&1 || return 0
  [ -z "$(git -C "$R" status --porcelain 2>/dev/null)" ] || return 0
  git -C "$R" remote get-url origin >/dev/null 2>&1 || return 0
  git -C "$R" fetch -q origin main 2>/dev/null || return 0
  git -C "$R" checkout -q main 2>/dev/null && git -C "$R" merge -q --ff-only origin/main 2>/dev/null
  return 0
}
do_sync() { if [ -n "${ORCH_SYNC_CMD:-}" ]; then eval "$ORCH_SYNC_CMD"; else sync_main; fi; }

# --- engine hooks (overridable via env so the loop is testable with fakes) ---
# Hardened headless invocations (R12): explicit turn caps, optional native cost
# cap, pinned MCP config (no stray user servers in an unattended run), and a
# schema-validated verdict. NEVER --bare — it skips OAuth reads and silently
# breaks the subscription-token lane (ADR-0019).
MODELS_JSON() { jq -c . "$R/orchestrator/models.config.json" 2>/dev/null || echo null; }
# build_wave [epic-ids…] — ONE call per ROUND, scoped to the admitted wave.
# maxEpics is the THROTTLED cap the loop exports before calling.
build_wave()  { if [ -n "${ORCH_BUILD_CMD:-}" ]; then eval "$ORCH_BUILD_CMD"; else
  local rc
  # Appended, never piped: a pipe would hand $? to tee and hide a failed wave.
  claude -p "Run the nightly-orchestrator workflow with args {\"date\":\"$(date +%F)\",\"epics\":$(json_arr "$@"),\"maxEpics\":${ORCH_MAX_CONCURRENT:-4},\"models\":$(MODELS_JSON)}." \
    --settings "$R/orchestrator/settings.orchestrator.json" ${ORCH_PLUGIN_DIR:+--plugin-dir "$ORCH_PLUGIN_DIR"} \
    --max-turns "${ORCH_MAX_TURNS:-80}" ${ORCH_MAX_BUDGET_USD:+--max-budget-usd "$ORCH_MAX_BUDGET_USD"} \
    --strict-mcp-config --mcp-config "$R/.mcp.json" \
    $(stream_flags) >>"$ORCH_RUN_LOG" 2>>"$ORCH_ERR_LOG"
  rc=$?
  # A failed wave must say why. Silent failure is what made escalations
  # undiagnosable: the epic came back Blocked and the reason was in /dev/null.
  [ "$rc" -eq 0 ] || { echo "build wave FAILED (exit $rc) — last lines of $ORCH_ERR_LOG:" >&2
                       tail -5 "$ORCH_ERR_LOG" >&2; }
  return $rc; fi; }
verify_epic() { if [ -n "${ORCH_VERIFY_CMD:-}" ]; then eval "$ORCH_VERIFY_CMD"; else
  claude -p "Run dod-verify for epic $1; return the verdict.
You did not build this. Verify against the feature list like a USER, not like CI.
Before reporting, audit each claim against a tool result from this session and report
only what you can point to evidence for. Default to reject if uncertain." \
    --output-format json --json-schema "$(cat "$R/orchestrator/verdict.schema.json")" \
    --max-turns "${ORCH_MAX_TURNS:-80}" ${ORCH_MAX_BUDGET_USD:+--max-budget-usd "$ORCH_MAX_BUDGET_USD"} \
    --strict-mcp-config --mcp-config "$R/.mcp.json" \
    2>>"$ORCH_ERR_LOG" | jq -c '.structured_output // .result // .'; fi; }
# risk: computed per epic BEFORE any merge decision — from the real diff via
# compute_risk (which fails closed to high when the policy/diff is unreadable).
do_risk()     { if [ -n "${ORCH_RISK_CMD:-}" ]; then eval "$ORCH_RISK_CMD"; else compute_risk "$1"; fi; }
# merge: the risk-gated queue (merge_epic). Escalation is always the safe path.
do_merge()    { if [ -n "${ORCH_MERGE_CMD:-}" ]; then eval "$ORCH_MERGE_CMD"; else merge_epic "$1" "$2" "$3"; fi; }
# spend signal for the budget guard. Mirrors usage_pct: explicit seam → ccusage
# → -1 (UNKNOWN). It must never fake a 0 — that silently disables guard_budget.
spent_tokens() {
  if [ -n "${ORCH_SPENT_CMD:-}" ]; then eval "$ORCH_SPENT_CMD" 2>/dev/null | grep -oE '^-?[0-9]+' | head -1 && return; fi
  if command -v ccusage >/dev/null 2>&1; then ccusage --json 2>/dev/null | jq -r '.tokensUsed // -1' | grep -oE '^-?[0-9]+' | head -1 && return; fi
  echo -1
}

# json_arr <items…> — serialize args as a JSON string array ([] when empty).
json_arr() { [ "$#" -eq 0 ] && { echo '[]'; return; }; printf '%s\n' "$@" | jq -R . | jq -sc .; }

run_loop() {
  local mode="$1" n="${2:-0}" k="${ORCH_NOPROGRESS_K:-3}"
  local scope board id
  local merged='' escalated='' blocked='' rounds='' stopped=null

  do_sync
  scope=$(select_scope "$mode" "$n" | tr '\n' ' ')

  # --- STATE RECONSTRUCTION ---------------------------------------------------
  # Seed every container from the board. A killed run re-enters here and picks up
  # where it stopped: it never rebuilds a settled epic and never loses a counter.
  board=$(board_json)
  for id in $scope; do
    case "$(epic_class "$board" "$id")" in
      merged)    merged=$(set_add "$merged" "$id") ;;
      escalated) escalated=$(set_add "$escalated" "$id") ;;
      blocked)   blocked=$(set_add "$blocked" "$id") ;;
    esac
    rounds=$(rounds_set "$rounds" "$id" "$(epic_attempts "$board" "$id")")
  done

  # An inert budget guard must be LOUD, never silent.
  if [ "${ORCH_BUDGET_TOKENS:-0}" -gt 0 ] && [ "$(spent_tokens)" -lt 0 ]; then
    echo "run-to-done: budget guard INERT — ORCH_BUDGET_TOKENS is set but there is no spend signal (set ORCH_SPENT_CMD or install ccusage)" >&2
  fi

  while :; do
    [ "$(guard_safety)" = abort ] && { stopped='"SAFETY"'; break; }
    [ "$(guard_wallclock "$(date +%s)" "${ORCH_WALLCLOCK_DEADLINE:-0}")" = stop ] && { stopped='"WALLCLOCK"'; break; }
    [ "$(guard_budget "$(spent_tokens)" "${ORCH_BUDGET_TOKENS:-0}")" = stop ] && { stopped='"BUDGET"'; break; }

    board=$(board_json)   # re-read every round: the board may have moved under us

    # pending = in scope, not settled here, not settled on the board. The board
    # can only ADD to the settled sets (monotone) — it never un-settles one.
    local pending=''
    for id in $scope; do
      set_has "$merged $escalated $blocked" "$id" && continue
      case "$(epic_class "$board" "$id")" in
        merged)    merged=$(set_add "$merged" "$id");       continue ;;
        escalated) escalated=$(set_add "$escalated" "$id"); continue ;;
        blocked)   blocked=$(set_add "$blocked" "$id");     continue ;;
        skip)      continue ;;
      esac
      pending=$(set_add "$pending" "$id")
    done
    [ -n "$pending" ] || break            # scope drained — the normal exit

    # --- usage throttle: it now actually reaches the loop ---
    local cap; cap=$(throttled_cap "$(usage_pct)" "${ORCH_MAX_CONCURRENT:-4}")
    [ "$cap" -le 0 ] && { stopped='"USAGE"'; break; }   # pause: stop clean, the
                                                       # retry lane re-enters

    # --- admission: deps-topological FIRST, then footprint-disjoint, then cap ---
    local ready wave
    ready=$(deps_ready "$board" "$pending" "$merged" | tr '\n' ' ')
    wave=''
    [ -n "$ready" ] && wave=$(board_subset "$board" "$ready" | partition_wave 2>/dev/null | head -n "$cap" | tr '\n' ' ')
    # nothing admissible while work remains = a dependency cycle, or a dep that
    # escalated instead of landing. Deadlock, not thrash — its own stop token.
    [ -n "$wave" ] || { stopped='"DEPS"'; break; }

    # --- ONE build_wave per ROUND, scoped to the wave, at the throttled cap ----
    # stdout → the run log (keeps a chatty ORCH_BUILD_CMD out of the summary
    # JSON this loop prints); stderr flows through, so a failed wave is seen.
    ( export ORCH_MAX_CONCURRENT="$cap"; build_wave $wave ) >>"$ORCH_RUN_LOG"

    local advanced=0 v risk res r st blk cls tier
    for id in $wave; do
      v=$(verify_epic "$id")
      # An unparseable verdict means the engine produced NOTHING for this epic
      # (crashed / out of turns / rate-walled). No attributable work, so it must
      # NOT consume a no-progress round — and a whole wave of these is exactly
      # the busy-spin guard_thrash exists to catch.
      printf '%s' "$v" | jq -e 'type=="object" and has("done")' >/dev/null 2>&1 || continue
      advanced=$((advanced+1))

      if [ "$(printf '%s' "$v" | jq -r '.done')" = true ]; then
        risk=$(do_risk "$id")
        # Trust gate BEFORE the merge attempt: a class that has not earned `auto`
        # produces a reviewed PR, not a landing. The DoD still passed — this is
        # about whether we have seen enough of this KIND of work to stop looking.
        cls=$(epic_class_key "$board" "$id"); tier=$(do_trust_tier "$cls")
        if [ "$tier" != auto ]; then
          escalated=$(set_add "$escalated" "$id")
          do_trust_record "$cls" pass
          push_status "$id" Needs-review "verified, but class '$cls' is tier=$tier — review required (risk=$risk)"
          continue
        fi
        res=$(do_merge "$id" "$risk" "$v")
        case "$res" in
          merged)
            merged=$(set_add "$merged" "$id")
            do_trust_record "$cls" pass
            do_publish "$id" || echo "run-to-done: $id proved green locally but could not be published to the forge — it will NOT land; check the remote/PR" >&2
            push_status "$id" Merged "landed by run-to-done (risk=$risk)"
            ;;
          reverted)
            # Merged cleanly but the post-merge suite went red: NOT done. Back to
            # the rework lane with the round consumed — never silently escalated.
            r=$(( $(rounds_get "$rounds" "$id") + 1 )); rounds=$(rounds_set "$rounds" "$id" "$r")
            do_trust_record "$cls" fail   # green in isolation, red after merging: a miss
            st=Planned; [ -n "$(epic_field "$board" "$id" pr)" ] && st=Changes-requested
            if [ "$(guard_no_progress "$r" "$k")" = blocked ]; then
              blocked=$(set_add "$blocked" "$id")
              push_status "$id" Blocked "attempts=$r blocked: post-merge suite red — needs human triage"
            else
              push_status "$id" "$st" "attempts=$r post-merge suite red, merge reverted"
            fi
            ;;
          *)  # escalated: high risk, not auto-mergeable, or a dirty merge
            escalated=$(set_add "$escalated" "$id")
            push_status "$id" Needs-review "escalated by run-to-done (risk=$risk) — awaiting /orch approve"
            ;;
        esac
      else
        r=$(( $(rounds_get "$rounds" "$id") + 1 )); rounds=$(rounds_set "$rounds" "$id" "$r")
        do_trust_record "$(epic_class_key "$board" "$id")" fail
        blk=$(printf '%s' "$v" | jq -r '[(.blocking // [])[] | tostring] | join(", ")' 2>/dev/null)
        st=Planned; [ -n "$(epic_field "$board" "$id" pr)" ] && st=Changes-requested
        if [ "$(guard_no_progress "$r" "$k")" = blocked ]; then
          blocked=$(set_add "$blocked" "$id")
          push_status "$id" Blocked "attempts=$r blocked: ${blk:-no progress} — needs human triage"
        else
          # DURABLE: the next re-entry reads attempts=$r back out of this note.
          push_status "$id" "$st" "attempts=$r ${blk:-}"
        fi
      fi
    done

    # REACHABLE: advanced stays 0 exactly when the whole wave returned no usable
    # verdict — the engine did nothing and the loop would otherwise busy-spin.
    [ "$(guard_thrash "$advanced")" = stop ] && { stopped='"THRASH"'; break; }
  done

  # word-splitting is intentional: ids are slug-safe words (bash-3.2 containers).
  printf '{"merged":%s,"escalated":%s,"blocked":%s,"rounds":%s,"stopped_by":%s}\n' \
    "$(json_arr $merged)" "$(json_arr $escalated)" "$(json_arr $blocked)" \
    "$(rounds_json "$rounds")" "$stopped"
}

main() { run_loop "${1:-all}" "${2:-0}"; }
# ${BASH_SOURCE[0]:-} — unguarded, this is unbound under `set -u` when the file is
# sourced from a non-bash shell, which is the same bug class as the rest of this file.
[ "${BASH_SOURCE[0]:-}" = "$0" ] && main "$@"
