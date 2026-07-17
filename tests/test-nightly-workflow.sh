#!/bin/bash
# Subsystem 3d — the scheduled build workflow (nightly-orchestrator.js):
# parses, guards its inputs, and keeps the load-bearing invariants in its prompts.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
W="../plugins/orchestrator/workflows/nightly-orchestrator.js"
[ -f "$W" ] || { echo "  FAIL — workflow missing at $W"; echo "---"; echo "0 ok, 1 failure(s)"; exit 1; }
WABS=$(cd "$(dirname "$W")" && pwd)/$(basename "$W")

command -v node >/dev/null 2>&1 || { echo "  skip — node not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }

# the runtime wraps the script body in an async function (top-level return is
# legal there) — replicate that wrap: strip `export `, construct an AsyncFunction
# (syntax check), then call it with empty args and expect the args.date guard
node -e "
const src = require('fs').readFileSync('$WABS', 'utf8').replace(/^export /gm, '');
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
let fn;
try { fn = new AsyncFunction('args','phase','agent','parallel','log','budget','workflow', src) }
catch (e) { console.error('syntax:', e.message); process.exit(1) }
fn({}).then(() => process.exit(1)).catch(e => process.exit(/args\.date/.test(e.message) ? 0 : 1))
" 2>/dev/null
check "workflow body is valid (runtime wrap); refuses to run without args.date" $?

# meta declares the eight phases of the night
for p in Reconcile Build Blocked-check Integrate Consistency Deploy Gardening Digest; do
  grep -q "title: '$p'" "$W"; check "meta declares phase $p" $?
done

# load-bearing invariants stay in the worker contract
grep -q "isolation: 'worktree'" "$W"; check "workers build in isolated worktrees" $?
grep -q "NEVER push to main" "$W"; check "worker contract: never push to main" $?
grep -qi "UNACCEPTABLE to remove or edit steps" "$W"; check "anti-drift contract embedded in the worker prompt" $?
grep -q "BLOCK_AFTER_ATTEMPTS" "$W"; check "non-progress backstop present" $?
grep -q "blindspots" "$W"; check "blindspots surfaced, never auto-passed" $?
grep -qi "record.*complexity\|complexity.*from the epic record\|epic record.s complexity" "$W"; check "reconcile prefers the planner-recorded complexity" $?
grep -q -- "--assignee" "$W"; check "workers set/clear the assignee on the card" $?
grep -q "capRemaining" "$W"; check "hard budget cap enforced per epic" $?
grep -q "push-digest" "$W"; check "digest pushed to the state layer" $?
grep -q "phaseMetrics" "$W"; check "per-phase metrics collected by the harness (not the agent)" $?
grep -q "phases: phaseMetrics" "$W"; check "run summary returns the phases array" $?
grep -qi "VCR" "$W"; check "digest surfaces the verified/activated ratio (VCR)" $?
grep -qi "screenshot" "$W"; check "workers capture screenshots of what was built (when relevant)" $?
grep -q '"evidence"' "$W"; check "flipping passes records evidence (the proof rides the contract)" $?
grep -q 'docs/reports/nightly/${today}/index.html' "$W"; check "digest written to the per-day folder (index.html)" $?
grep -q 'shots/' "$W"; check "screenshots collected under the day folder's shots/" $?
# serial integration: merges happen one at a time in a for-loop, not parallel()
grep -q "for (const r of results" "$W"; check "integration is serialized (merge queue)" $?
# consistency gate fails closed: a crashed checker must not open the deploy gate
grep -q "consistency?.pass === true" "$W"; check "deploy gate fails closed without a consistency pass" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
