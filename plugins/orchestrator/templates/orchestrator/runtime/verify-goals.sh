#!/usr/bin/env bash
# verify-goals — re-check everything the harness has ever finished (ADR-0028).
#
# A feature_list entry flips passes:false → true once and is terminal. Nothing
# ever looked at it again, so a silent regression stayed invisible until a human
# noticed. A goal you verify once is an assumption with a timestamp.
#
# Each goal is a SHELL PREDICATE: exit 0 means the invariant still holds. If a
# shell script cannot check it, it is not a goal — adjectives are not verifiable.
# Predicates must be cheap, deterministic and READ-ONLY; this runs daily.
#
# This DETECTS. It never fixes: a violation goes through the normal pipeline like
# any other work, because an auto-fix on a regression nobody has looked at is how
# a real bug gets papered over.
set -u
R="${CLAUDE_PROJECT_DIR:-$(pwd)}"
G="$R/.orch/goals"
LEDGER="$R/.orch/goal-ledger.tsv"
TIMEOUT="${ORCH_GOAL_TIMEOUT:-60}"
VIOLATIONS=0; CHECKED=0

[ -d "$G" ] || { echo "no standing goals yet ($G) — nothing to verify"; exit 0; }
mkdir -p "$(dirname "$LEDGER")"; touch "$LEDGER"

# field <file> <key> — read `key: value` from the goal's header
field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1; }

# `timeout` is GNU; macOS has neither it nor gtimeout by default. Fall back to a
# background job + poll rather than skipping the bound entirely — an unbounded
# predicate is exactly what turns a daily sentinel into a hung cron slot.
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT" bash -c "$1" >/dev/null 2>&1; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$TIMEOUT" bash -c "$1" >/dev/null 2>&1; return $?; fi
  bash -c "$1" >/dev/null 2>&1 & local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null; do
    [ "$i" -ge "$TIMEOUT" ] && { kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; }
    sleep 1; i=$((i+1))
  done
  wait "$pid"; return $?
}

for g in "$G"/*.md; do
  [ -f "$g" ] || continue
  name=$(basename "$g" .md)
  [ "$(field "$g" status)" = "retired" ] && continue
  pred=$(field "$g" predicate)
  if [ -z "$pred" ]; then
    echo "goal '$name' has no predicate — skipping (a goal without one cannot be verified)" >&2
    continue
  fi
  CHECKED=$((CHECKED+1))
  start=$(date +%s)
  run_bounded "cd '$R' && $pred"; rc=$?
  dur=$(( $(date +%s) - start ))
  if [ "$rc" -eq 0 ]; then
    res=pass
    sed -i.bak -e "s/^status:.*/status: satisfied/" -e "s/^last-pass:.*/last-pass: $(date -u +%F)/" "$g" && rm -f "$g.bak"
  else
    # A predicate that times out is a VIOLATION, not a skip. "Too slow to check"
    # and "no longer true" are indistinguishable from here, and treating a
    # timeout as a pass is how a sentinel goes quietly blind.
    res=FAIL; [ "$rc" -eq 124 ] && res=TIMEOUT
    VIOLATIONS=$((VIOLATIONS+1))
    sed -i.bak -e "s/^status:.*/status: VIOLATED/" "$g" && rm -f "$g.bak"
  fi
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" "$res" "$dur" >> "$LEDGER"
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "STANDING GOALS VIOLATED ($VIOLATIONS of $CHECKED):" >&2
  grep -l '^status: VIOLATED' "$G"/*.md 2>/dev/null | while read -r f; do
    echo "  - $(basename "$f" .md) — last passed $(field "$f" last-pass), on-violation: $(field "$f" on-violation)" >&2
  done
  exit 1
fi
echo "all $CHECKED standing goal(s) hold"
