#!/bin/bash
# The CI lane (ADR-0024): observation (pull-checks) + reaction (fix-ci.js).
# Before this the harness knew a PR was red and never why.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
ORCH_SRC=../plugins/core/templates/orchestrator/bin/orch
WF=../plugins/orchestrator/workflows/fix-ci.js
AG=../plugins/orchestrator/agents/ci-triage.md
SET=../plugins/orchestrator/templates/orchestrator/settings.orchestrator.json
RT=../plugins/orchestrator/templates/orchestrator/runtime/github-actions.yml

D=$(mktemp -d); mkdir -p "$D/orchestrator/bin" "$D/fakebin"
cp "$ORCH_SRC" "$D/orchestrator/bin/orch"; chmod +x "$D/orchestrator/bin/orch"
printf '{"backend":"none","forge":"github"}' > "$D/orchestrator/state.config.json"
cat > "$D/fakebin/gh" <<'GH'
#!/bin/bash
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
cat <<'J'
[{"number":7,"headRefName":"orch/auth","statusCheckRollup":[{"name":"tests","conclusion":"FAILURE","detailsUrl":"https://github.com/o/r/actions/runs/12345/job/999"}]},
 {"number":8,"headRefName":"orch/ui","statusCheckRollup":[{"name":"tests","conclusion":"","state":"PENDING","detailsUrl":""}]},
 {"number":9,"headRefName":"orch/api","statusCheckRollup":[{"name":"tests","conclusion":"SUCCESS","detailsUrl":""}]},
 {"number":10,"headRefName":"orch/none","statusCheckRollup":[]}]
J
elif [ "$1" = "run" ] && [ "$2" = "view" ]; then echo "FAIL src/auth.test.ts > rejects expired token"; fi
GH
chmod +x "$D/fakebin/gh"
export CLAUDE_PROJECT_DIR="$D" PATH="$D/fakebin:$PATH"
C=$("$D/orchestrator/bin/orch" state pull-checks)

echo "$C" | jq -e 'length == 4' >/dev/null; check "pull-checks reports every open PR" $?
echo "$C" | jq -e '.[] | select(.pr==7) | .status == "red"'     >/dev/null; check "a failing check is red" $?
echo "$C" | jq -e '.[] | select(.pr==8) | .status == "pending"' >/dev/null; check "an UNFINISHED check is pending, not green (the old bug)" $?
echo "$C" | jq -e '.[] | select(.pr==9) | .status == "green"'   >/dev/null; check "a passing check is green" $?
echo "$C" | jq -e '.[] | select(.pr==10) | .status == "none"'   >/dev/null; check "no checks configured is 'none', not green" $?
echo "$C" | jq -e '.[] | select(.pr==7) | .epicId == "auth"'    >/dev/null; check "epicId resolves from the orch/<id> branch" $?
echo "$C" | jq -e '.[] | select(.pr==7) | .failedJobs[0].logExcerpt | test("expired token")' >/dev/null
check "the FAILING JOB LOG is retrieved (the framework could never see this)" $?
echo "$C" | jq -e '.[] | select(.pr==9) | .failedJobs == []' >/dev/null; check "a green PR pulls no logs (no wasted API calls)" $?
"$D/orchestrator/bin/orch" state pull-checks --pr 7 | jq -e 'length == 1' >/dev/null; check "--pr scopes to one PR" $?
rm -rf "$D"; unset CLAUDE_PROJECT_DIR

# pull-feedback: the two fixed defects
grep -q 'def ci_state' "$ORCH_SRC"; check "pull-feedback shares the three-state CI classifier" $?
grep -q 'select(.signal != null or .checks == "red")' "$ORCH_SRC"
check "a red PR with NO operator signal is no longer dropped (the old bug)" $?
grep -qF 'green: (([$pr.statusCheckRollup' "$ORCH_SRC"; check "legacy 'green' kept for compatibility, now excluding pending" $?
! grep -q 'green:null' "$ORCH_SRC"; check "GitLab no longer hardcodes a null CI signal" $?

# permissions: read-only observation, no new landing power
jq -e '.permissions.allow | index("Bash(gh run view:*)")' "$SET" >/dev/null; check "gh run view is allowlisted (log reading)" $?
jq -e '.permissions.allow | index("Bash(gh pr checks:*)")' "$SET" >/dev/null; check "gh pr checks is allowlisted" $?
jq -e '(.permissions.allow | index("Bash(gh pr merge:*)")) == null' "$SET" >/dev/null
check "gh pr merge STILL denied to the builder (observation grants no landing power)" $?
jq -e '.permissions.deny | index("Bash(git push origin main:*)")' "$SET" >/dev/null; check "direct main push still denied" $?
grep -q 'actions: read' "$RT"; check "runtime workflow grants actions: read" $?

# the repair loop's structural limits
grep -q "NOT_FIXABLE" "$WF"; check "fix-ci separates fixable from escalate-only classes" $?
grep -qE "flake.*infra.*dependency|'flake', 'infra', 'dependency'" "$WF"; check "flake/infra/dependency escalate, never 'repaired'" $?
grep -q "MAX_ROUNDS" "$WF"; check "repair is bounded per PR" $?
grep -q "workflows" "$WF"; check "fix-ci states it cannot edit CI config" $?
grep -q "push-journal --kind ci_repair" "$WF"; check "every repair outcome is journalled with corrected:<bool>" $?
grep -q "pipeline(" "$WF"; check "PRs are pipelined, not barriered" $?
grep -q "agentType: 'ci-triage'" "$WF"; check "triage runs as the ci-triage agent" $?
grep -q "never weaken, skip or delete a test" "$WF" || grep -qi "never weaken" "$WF"
check "the repair prompt forbids weakening a test to go green" $?
grep -q "^name: ci-triage" "$AG" || grep -q "name: ci-triage" "$AG"; check "ci-triage agent ships" $?
grep -qi "you do not edit" "$AG"; check "ci-triage diagnoses only (matches debugger.md's contract)" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
