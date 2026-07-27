#!/bin/bash
# POLICY file-edit guardrails (core plugin, opt-in, default ON):
# CI workflows, generated lockfiles, plugin/marketplace manifests, accepted
# ADRs — team conventions, not security boundaries. The SECURITY half
# (settings*.json self-elevation) lives in protect-paths.sh (CORE).
# Disable per project: .claude/policy.json {"protect_paths_policy": false}
#   or env CLAUDE_POLICY_PROTECT_PATHS_POLICY=0.
# R6: a guard that cannot parse its input must BLOCK, not silently allow.
command -v jq >/dev/null 2>&1 || { echo "BLOCKED: protect-policy-paths cannot run — jq is missing (install jq; see docs/SECURITY.md)" >&2; exit 2; }
INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FP" ] && exit 0

source "$(dirname "$0")/policy-lib.sh"
policy_enabled protect_paths_policy || exit 0

# jblock <rule> — the single exit path: tell Claude why, and record the attempt.
# A rule that fires repeatedly across installs is a rule the harness should have
# taught up front instead of enforcing after the fact.
MSG_ci_workflow="— CI changes go through a human"
MSG_lockfile="is a generated lockfile — use the package manager"
MSG_dist_manifest="is a distribution manifest (plugin/marketplace) — bump the version and change it through a human PR"
MSG_trusted_computing_base="is a guardrail/allow-listed script — changes go through a human PR"
MSG_accepted_adr="is an accepted ADR, hence immutable. Create a new ADR that supersedes it"
jblock() {
  local var="MSG_$1"                       # ${!var}: bash 3.2-safe indirection
  echo "BLOCKED: $FP ${!var}. (policy: protect_paths_policy)" >&2
  journal guard_block "$1" "$(jq -cn --arg f "$(journal_relpath "$FP")" '{path:$f}' 2>/dev/null || echo '{}')"
}

case "$FP" in
  */plugins/*/templates/*|plugins/*/templates/*)
    ;;  # scaffold sources are templates, not live TCB — editable in the dev repo
  */.github/workflows/*|.github/workflows/*|.gitlab-ci.yml|*/.gitlab-ci.yml)
    jblock ci_workflow; exit 2;;
  *package-lock.json|*yarn.lock|*pnpm-lock.yaml|*Cargo.lock|*poetry.lock|*uv.lock)
    jblock lockfile; exit 2;;
  */.claude-plugin/*|.claude-plugin/*)
    jblock dist_manifest; exit 2;;
  */plugins/*/hooks/*|plugins/*/hooks/*|*/orchestrator/bin/*|orchestrator/bin/*|*/orchestrator/adapters/*|orchestrator/adapters/*)
    # Trusted computing base: guardrail hooks + allow-listed executables. An
    # agent must not rewrite scripts it is permitted to run (audit SEC-C2).
    jblock trusted_computing_base; exit 2;;
esac

if echo "$FP" | grep -q 'docs/adr/' && [ -f "$FP" ] && head -10 "$FP" | grep -qiE '^Status[[:space:]]*:[[:space:]]*Accept'; then
  jblock accepted_adr
  exit 2
fi
exit 0
