#!/bin/bash
# Subsystem 1b — the independent verifier's pure decision logic:
# judge tally (majority + blocking dissent) and the four-stage verdict.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."
LIB="$R/plugins/orchestrator/workflows/lib/dod-verdict.js"
PIPE="$R/plugins/orchestrator/workflows/dod-verify.js"

command -v node >/dev/null 2>&1 || { echo "  skip — node not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }

run_node() { node --input-type=module 2>/dev/null <<NODE
import { tallyJudges, aggregateVerdict } from '$(cd "$(dirname "$LIB")" && pwd)/$(basename "$LIB")';
$1
NODE
}

# --- tallyJudges: majority + blocking dissent ---
out=$(run_node 'const t=tallyJudges([{lens:"correctness",verdict:"approve",blocking:false},{lens:"pm",verdict:"approve",blocking:false},{lens:"design",verdict:"reject",blocking:false}]); console.log(t.pass, t.approve, t.blocking.length);')
[ "$out" = "true 2 0" ]; check "2-of-3 approve, no blocking → judge pass" $?

out=$(run_node 'const t=tallyJudges([{lens:"correctness",verdict:"reject",blocking:true},{lens:"pm",verdict:"approve",blocking:false},{lens:"design",verdict:"approve",blocking:false}]); console.log(t.pass, t.blocking.join(","));')
[ "$out" = "false judge:correctness" ]; check "blocking dissent overrides majority → judge fail" $?

out=$(run_node 'const t=tallyJudges([{lens:"a",verdict:"approve",blocking:false},{lens:"b",verdict:"reject",blocking:false},{lens:"c",verdict:"reject",blocking:false}]); console.log(t.pass);')
[ "$out" = "false" ]; check "1-of-3 approve → judge fail (strict majority)" $?

out=$(run_node 'const t=tallyJudges([{lens:"a",verdict:"approve",blocking:false},{lens:"b",verdict:"reject",blocking:false}]); console.log(t.pass);')
[ "$out" = "false" ]; check "1-of-2 tie → judge fail (majority is strict)" $?

out=$(run_node 'const t=tallyJudges([]); console.log(t.pass);')
[ "$out" = "false" ]; check "zero votes → judge fail (never pass by default)" $?

# --- aggregateVerdict: done requires all four stages + zero blocking ---
out=$(run_node 'const v=aggregateVerdict({epic:"e1",stages:{tests:{pass:true},e2e:{pass:true},acceptance:{pass:true}},votes:[{lens:"c",verdict:"approve",blocking:false},{lens:"p",verdict:"approve",blocking:false},{lens:"d",verdict:"approve",blocking:false}]}); console.log(v.done, v.escalate, v.blocking.length);')
[ "$out" = "true false 0" ]; check "all stages + judge pass → done=true escalate=false" $?

out=$(run_node 'const v=aggregateVerdict({epic:"e1",stages:{tests:{pass:false},e2e:{pass:true},acceptance:{pass:true}},votes:[{lens:"c",verdict:"approve",blocking:false},{lens:"p",verdict:"approve",blocking:false},{lens:"d",verdict:"approve",blocking:false}]}); console.log(v.done, v.reasons.join(","));')
[ "$out" = "false tests not passing" ]; check "a red stage → done=false with a reason" $?

out=$(run_node 'const v=aggregateVerdict({epic:"e1",stages:{tests:{pass:true},e2e:{pass:true},acceptance:{pass:true}},votes:[{lens:"c",verdict:"approve",blocking:false},{lens:"p",verdict:"approve",blocking:false},{lens:"d",verdict:"reject",blocking:true}]}); console.log(v.done, v.escalate, v.blocking.join(","));')
[ "$out" = "false true judge:d" ]; check "blocking judge → done=false escalate=true, blocking recorded" $?

# a blocking objection escalates even when every stage nominally passes and majority approves
out=$(run_node 'const v=aggregateVerdict({epic:"e1",stages:{tests:{pass:true},e2e:{pass:true},acceptance:{pass:true}},votes:[{lens:"c",verdict:"approve",blocking:true},{lens:"p",verdict:"approve",blocking:false},{lens:"d",verdict:"approve",blocking:false}]}); console.log(v.done, v.escalate);')
[ "$out" = "false true" ]; check "blocking approve-vote still forbids done (defense in depth)" $?

# the verdict shape the merge queue reads: epic/done/escalate/stages/blocking/reasons
out=$(run_node 'const v=aggregateVerdict({epic:"e1",stages:{tests:{pass:true},e2e:{pass:true},acceptance:{pass:true}},votes:[{lens:"c",verdict:"approve",blocking:false}]}); console.log(["epic","done","escalate","stages","blocking","reasons"].every(k=>k in v));')
[ "$out" = "true" ]; check "verdict carries epic/done/escalate/stages/blocking/reasons" $?

# --- pipeline module: parses, exports verifyDoD, keeps ≥3 distinct lenses ---
node --input-type=module -e "import('$(cd "$(dirname "$PIPE")" && pwd)/$(basename "$PIPE")').then(m=>process.exit(typeof m.verifyDoD==='function'?0:1)).catch(()=>process.exit(1))" 2>/dev/null
check "dod-verify.js exports verifyDoD()" $?
node --input-type=module -e "import('$(cd "$(dirname "$PIPE")" && pwd)/$(basename "$PIPE")').then(m=>process.exit(new Set(m.LENSES).size>=3?0:1)).catch(()=>process.exit(1))" 2>/dev/null
check "judge panel has ≥3 distinct lenses" $?

echo "---"
echo "$PASS ok, $FAIL failure(s)"
[ "$FAIL" -eq 0 ]
