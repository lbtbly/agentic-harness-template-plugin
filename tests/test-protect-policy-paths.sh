#!/bin/bash
# Subsystem 4f — policy paths (POLICY, default ON): CI files, lockfiles,
# distribution manifests, guardrail scripts (TCB), accepted ADRs.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
HOOK=../plugins/core/hooks/protect-policy-paths.sh

assert_exit 2 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/.github/workflows/ci.yml"}}' "blocks CI workflows"
assert_exit 2 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/package-lock.json"}}' "blocks npm lockfile"
assert_exit 2 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/.claude-plugin/plugin.json"}}' "blocks plugin manifest"
assert_exit 2 "$HOOK" '{"tool_name":"Write","tool_input":{"file_path":"/p/.claude-plugin/marketplace.json"}}' "blocks marketplace manifest"
assert_exit 2 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/.gitlab-ci.yml"}}' "blocks GitLab CI"
assert_exit 0 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/src/index.ts"}}' "allows normal code"

# Policy toggle off → everything allowed
export CLAUDE_POLICY_PROTECT_PATHS_POLICY=0
assert_exit 0 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/.github/workflows/ci.yml"}}' "CI allowed when policy disabled"
assert_exit 0 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/package-lock.json"}}' "lockfile allowed when policy disabled"
unset CLAUDE_POLICY_PROTECT_PATHS_POLICY

# Trusted computing base: an agent must not rewrite its own referee
assert_exit 2 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/plugins/core/hooks/secret-guard.sh"}}' "blocks plugin guardrail hooks"
assert_exit 2 "$HOOK" '{"tool_name":"Write","tool_input":{"file_path":"/p/orchestrator/bin/orch"}}' "blocks the allow-listed orch CLI"
assert_exit 2 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/orchestrator/adapters/deploy.sh"}}' "blocks the allow-listed deploy adapter"
assert_exit 0 "$HOOK" '{"tool_name":"Write","tool_input":{"file_path":"/p/plugins/core/templates/orchestrator/adapters/deploy.sh"}}' "allows scaffold templates (not live TCB)"

# Accepted ADR = immutable; supersede instead
TMP=$(mktemp -d); mkdir -p "$TMP/docs/adr"
printf -- "---\nStatus: Accepted\n---\n# ADR-0001\n" > "$TMP/docs/adr/0001-test.md"
assert_exit 2 "$HOOK" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/docs/adr/0001-test.md\"}}" "blocks accepted ADR"
printf -- "---\nStatus: Proposed\n---\n# ADR-0002\n" > "$TMP/docs/adr/0002-test.md"
assert_exit 0 "$HOOK" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/docs/adr/0002-test.md\"}}" "allows proposed ADR"
rm -rf "$TMP"
summary
