#!/bin/bash
# Repo hygiene (external audit R1/R3/R4/R5): license consistency, personal-data
# denylist, stale references, and no hardcoded distribution URLs in runtimes.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."

# R1 — declared license ⇒ LICENSE file at root
if grep -l '"license"' "$R"/plugins/*/.claude-plugin/plugin.json >/dev/null 2>&1; then
  [ -f "$R/LICENSE" ]; check "license declared in manifests ⇒ LICENSE exists at root" $?
  grep -qi "MIT" "$R/LICENSE" 2>/dev/null; check "LICENSE matches the declared SPDX (MIT)" $?
fi

# R3 — personal-string denylist in shipped plugin content (author field exempt:
# .claude-plugin manifests carry the author name legitimately)
leaks=$(grep -rn "lambertbouley\|/private/tmp\|claude-code-template-env" "$R/plugins" \
  | grep -v "/.claude-plugin/" | grep -v "Binary" || true)
[ -z "$leaks" ]; check "no personal paths/usernames in shipped templates (denylist)" $?
[ -n "$leaks" ] && echo "$leaks" | sed 's/^/         /' | head -5

# R4 — runtime templates carry no hardcoded distribution URL; both lanes parameterized
# Org-AGNOSTIC on purpose: the original check named one org, so it silently stopped
# guarding anything the moment the repo moved. Any hardcoded forge URL fails.
! grep -qnE "(github|gitlab)\.com/[A-Za-z0-9_.-]+/agentic-harness-template-plugin" \
    "$R/plugins/orchestrator/templates/orchestrator/runtime/github-actions.yml"
check "github-actions runtime: no hardcoded plugin-repo URL (any org)" $?
grep -q "ORCH_PLUGIN_REPO_URL" "$R/plugins/orchestrator/templates/orchestrator/runtime/github-actions.yml"
check "github-actions runtime: parameterized ORCH_PLUGIN_REPO_URL" $?
grep -qi "ORCH_PLUGIN_REPO_TOKEN\|private.*token" "$R/plugins/orchestrator/templates/orchestrator/runtime/github-actions.yml"
check "github-actions runtime: documents the auth token for private marketplaces" $?
grep -q "ORCH_PLUGIN_REPO_URL\|ORCH_PLUGIN_MARKETPLACE_URL" "$R/plugins/orchestrator/skills/enable-orchestrator/SKILL.md"
check "enable-orchestrator asks/records the plugin repo location" $?

# R5 — staleness greps
! grep -q "last four are stubs" "$R/plugins/core/templates/orchestrator/state.config.json"
check "state.config comment reflects implemented jira/notion adapters" $?
! grep -q "new-project/templates" "$R/plugins/core/templates/docs/TOOLING.md"
check "TOOLING.md cites real template paths" $?
! grep -q "claude-code-template.git" "$R/plugins/orchestrator/templates/orchestrator/runtime/gitlab-ci.yml"
check "gitlab runtime example URL updated (no pre-rename project)" $?
[ ! -f "$R/plugins/workbench/templates/docs/TOOLING.md" ] && [ ! -f "$R/plugins/workbench/templates/docs/SCHEDULED-AGENTS.md" ]
check "workbench doc dupes removed (core is canonical)" $?

# --- bash 3.2 portability (README claims macOS; stock /bin/bash there is 3.2.57) ---
# Two constructs silently break every shipped shell script under `set -u`:
#   declare -A          — bash 4.0+
#   "${arr[@]}" (empty) — unbound-variable error before bash 4.4; the portable
#                         form is ${arr[@]+"${arr[@]}"}
BAD_DECL=''; BAD_EXP=''
for f in $(grep -rl 'set -u' --include='*.sh' "$R/plugins" 2>/dev/null); do
  grep -v '^[[:space:]]*#' "$f" | grep -q 'declare -A' && BAD_DECL="$BAD_DECL $f"
  # strip the SAFE alternate form first, then look for what's left
  grep -v '^[[:space:]]*#' "$f" \
    | sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\+"\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}"\}//g' \
    | grep -qE '"\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}"' && BAD_EXP="$BAD_EXP $f"
done
[ -z "$BAD_DECL" ]; check "no shipped 'set -u' script uses declare -A (bash 4+):${BAD_DECL:- none}" $?
[ -z "$BAD_EXP" ]; check "no shipped 'set -u' script expands a bare \"\${arr[@]}\":${BAD_EXP:- none}" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
