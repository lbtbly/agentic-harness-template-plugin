#!/bin/bash
# POLICY file-edit guardrails (core plugin, opt-in, default ON):
# CI workflows, generated lockfiles, plugin/marketplace manifests, accepted
# ADRs — team conventions, not security boundaries. The SECURITY half
# (settings*.json self-elevation) lives in protect-paths.sh (CORE).
# Disable per project: .claude/policy.json {"protect_paths_policy": false}
#   or env CLAUDE_POLICY_PROTECT_PATHS_POLICY=0.
INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FP" ] && exit 0

source "$(dirname "$0")/policy-lib.sh"
policy_enabled protect_paths_policy || exit 0

case "$FP" in
  */plugins/*/templates/*|plugins/*/templates/*)
    ;;  # scaffold sources are templates, not live TCB — editable in the dev repo
  */.github/workflows/*|.github/workflows/*|.gitlab-ci.yml|*/.gitlab-ci.yml)
    echo "BLOCKED: $FP — CI changes go through a human. (policy: protect_paths_policy)" >&2; exit 2;;
  *package-lock.json|*yarn.lock|*pnpm-lock.yaml|*Cargo.lock|*poetry.lock|*uv.lock)
    echo "BLOCKED: $FP is a generated lockfile — use the package manager. (policy: protect_paths_policy)" >&2; exit 2;;
  */.claude-plugin/*|.claude-plugin/*)
    echo "BLOCKED: $FP is a distribution manifest (plugin/marketplace) — bump the version and change it through a human PR. (policy: protect_paths_policy)" >&2; exit 2;;
  */plugins/*/hooks/*|plugins/*/hooks/*|*/orchestrator/bin/*|orchestrator/bin/*|*/orchestrator/adapters/*|orchestrator/adapters/*)
    # Trusted computing base: guardrail hooks + allow-listed executables. An
    # agent must not rewrite scripts it is permitted to run (audit SEC-C2).
    echo "BLOCKED: $FP is a guardrail/allow-listed script — changes go through a human PR. (policy: protect_paths_policy)" >&2; exit 2;;
esac

if echo "$FP" | grep -q 'docs/adr/' && [ -f "$FP" ] && head -10 "$FP" | grep -qiE '^Status[[:space:]]*:[[:space:]]*Accept'; then
  echo "BLOCKED: $FP is an accepted ADR, hence immutable. Create a new ADR that supersedes it. (policy: protect_paths_policy)" >&2
  exit 2
fi
exit 0
