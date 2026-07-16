#!/bin/bash
# Subsystem 4a — risk-gated auto-merge: the policy file, the classifier, the
# merge queue's auto-revert, and the driver's default risk computation.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
R=".."
RISK="$R/plugins/orchestrator/templates/orchestrator/risk-policy.json"
DRIVER="$R/plugins/orchestrator/templates/orchestrator/runtime/run-to-done.sh"
[ -f "$RISK" ] || { echo "  FAIL — risk-policy.json missing"; echo "---"; echo "0 ok, 1 failure(s)"; exit 1; }
RISK_ABS=$(cd "$(dirname "$RISK")" && pwd)/$(basename "$RISK")

# --- the policy is data the operator owns; the loop only reads it ---
jq -e . "$RISK" >/dev/null 2>&1; check "risk-policy.json is valid JSON" $?
jq -e '.autoMergeRiskLevels | index("low")' "$RISK" >/dev/null 2>&1; check "autoMergeRiskLevels includes low" $?
jq -e '(.autoMergeRiskLevels | index("high")) == null' "$RISK" >/dev/null 2>&1; check "autoMergeRiskLevels excludes high" $?
jq -e '(.autoMergeRiskLevels | index("medium")) == null' "$RISK" >/dev/null 2>&1; check "autoMergeRiskLevels excludes medium" $?
jq -e '.requiredReviewByRisk.low == "judge-panel"' "$RISK" >/dev/null 2>&1; check "low risk → judge-panel review" $?
jq -e '.requiredReviewByRisk.high == "human-codeowners"' "$RISK" >/dev/null 2>&1; check "high risk → human-codeowners review" $?
jq -e '.securityAuditorRequiredFor | index("high")' "$RISK" >/dev/null 2>&1; check "high risk requires security-auditor" $?
jq -e '.highRiskPaths | length >= 4' "$RISK" >/dev/null 2>&1; check "highRiskPaths covers sensitive areas" $?
jq -e '.linesChanged.low < .linesChanged.medium' "$RISK" >/dev/null 2>&1; check "size thresholds are ordered" $?

export CLAUDE_PROJECT_DIR="$(mktemp -d)"; mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
echo '{"permissions":{"defaultMode":"plan"}}' > "$CLAUDE_PROJECT_DIR/.claude/settings.json"
source "$DRIVER"
export RISK_POLICY="$RISK_ABS"

# --- classify_risk <lines> <paths> ---
[ "$(classify_risk 10 'src/app.js')" = "low" ]; check "small non-sensitive → low" $?
[ "$(classify_risk 300 'src/app.js')" = "medium" ]; check "mid-size non-sensitive → medium" $?
[ "$(classify_risk 700 'src/app.js')" = "high" ]; check "big diff → high" $?
[ "$(classify_risk 10 'src/auth/login.js')" = "high" ]; check "auth path → high (size irrelevant)" $?
[ "$(classify_risk 10 'db/migrations/001.sql')" = "high" ]; check "migrations path → high" $?
[ "$(classify_risk 10 '.github/workflows/ci.yml')" = "high" ]; check "CI workflow path → high" $?
may_automerge low; check "low is auto-mergeable" $?
may_automerge medium && r=1 || r=0; [ "$r" = "0" ]; check "medium is NOT auto-mergeable" $?
may_automerge high && r=1 || r=0; [ "$r" = "0" ]; check "high is NOT auto-mergeable" $?

# --- merge_epic: verdict + risk gates, suite re-run, auto-revert on red ---
G=$(mktemp -d); ( cd "$G" && git init -q -b main && git config user.email t@t && git config user.name t \
  && echo ok > f && git add . && git commit -qm init )
export SUITE_CMD='grep -q ok f'
( cd "$G" && git checkout -qb orch/x && echo bad > f && git commit -qam "epic x" && git checkout -q main )
out=$(cd "$G" && merge_epic x low '{"epic":"x","done":true}')
[ "$out" = "reverted" ]; check "red post-merge suite → auto-revert (main stays green)" $?
( cd "$G" && grep -q ok f ); check "main still contains the good file after revert" $?

( cd "$G" && git checkout -qb orch/y && echo extra > g && git add g && git commit -qm "epic y" && git checkout -q main )
out=$(cd "$G" && merge_epic y low '{"epic":"y","done":true}')
[ "$out" = "merged" ]; check "green low-risk done epic → merged" $?
out=$(cd "$G" && merge_epic y high '{"epic":"y","done":true}')
[ "$out" = "escalated" ]; check "high risk → escalated even when done" $?
out=$(cd "$G" && merge_epic y low '{"epic":"y","done":false}')
[ "$out" = "escalated" ]; check "not-done verdict → never merged" $?
rm -rf "$G"

# --- compute_risk: the driver's DEFAULT risk signal, from the real git diff ---
G=$(mktemp -d); ( cd "$G" && git init -q -b main && git config user.email t@t && git config user.name t \
  && mkdir -p src/auth && echo base > src/app.js && echo a > src/auth/a.js && git add . && git commit -qm init )
( cd "$G" && git checkout -qb orch/small && echo tweak >> src/app.js && git commit -qam small && git checkout -q main )
( cd "$G" && git checkout -qb orch/authy && echo change >> src/auth/a.js && git commit -qam authy && git checkout -q main )
[ "$(cd "$G" && compute_risk small)" = "low" ]; check "compute_risk: small safe diff → low" $?
[ "$(cd "$G" && compute_risk authy)" = "high" ]; check "compute_risk: auth-touching diff → high" $?
[ "$(cd "$G" && RISK_POLICY=/nonexistent.json compute_risk small)" = "high" ]; check "compute_risk: missing policy → high (fail closed)" $?
[ "$(compute_risk nosuchbranch 2>/dev/null)" = "high" ]; check "compute_risk: unreadable diff → high (fail closed)" $?
rm -rf "$G"

# --- the loop's default risk hook IS compute_risk (no env override needed) ---
grep -q 'compute_risk' "$DRIVER" && grep -qE 'do_risk\(\).*compute_risk|compute_risk "\$1"' "$DRIVER"
check "driver default do_risk uses compute_risk" $?

rm -rf "$CLAUDE_PROJECT_DIR"; unset CLAUDE_PROJECT_DIR RISK_POLICY SUITE_CMD
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
