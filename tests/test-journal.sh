#!/bin/bash
# The append-only journal: the ONLY history the harness keeps. Every other
# .orch artefact is replace-semantics, so this is what an installed repo can
# hand back to say what the agent got wrong and what fixed it.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
H=../plugins/core/hooks
ORCH_SRC=../plugins/core/templates/orchestrator/bin/orch

newproj() { local d; d=$(mktemp -d); mkdir -p "$d/.claude"; echo '{}' > "$d/.claude/settings.json"; echo "$d"; }
jfile()   { echo "$1/.orch/journal/$(date -u +%F).jsonl"; }
events()  { cat "$(jfile "$1")" 2>/dev/null | jq -s '.'; }

# --- guard blocks are recorded (they were pure stderr before) ---
D=$(newproj); export CLAUDE_PROJECT_DIR="$D"
echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$D"'/.github/workflows/ci.yml"}}' | bash "$H/protect-policy-paths.sh" >/dev/null 2>&1
echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$D"'/package-lock.json"}}'        | bash "$H/protect-policy-paths.sh" >/dev/null 2>&1
echo '{"tool_name":"Edit","tool_input":{"file_path":"/p/.claude/settings.json"}}'         | bash "$H/protect-paths.sh"        >/dev/null 2>&1
echo '{"tool_name":"Read","tool_input":{"file_path":"/p/.env"}}'                          | bash "$H/secret-guard.sh"         >/dev/null 2>&1
echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}'        | bash "$H/block-no-verify.sh"      >/dev/null 2>&1
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'       | bash "$H/block-no-verify.sh"      >/dev/null 2>&1
E=$(events "$D")
[ "$(echo "$E" | jq 'length')" = "6" ]; check "all six guard-block sites journal (was: stderr only)" $?
echo "$E" | jq -e 'all(.kind == "guard_block")' >/dev/null; check "every guard event is kind=guard_block" $?
for k in ci_workflow lockfile self_elevation secret_guard no_verify_commit force_push_main; do
  echo "$E" | jq -e --arg k "$k" 'any(.key == $k)' >/dev/null; check "rule '$k' is identified by key" $?
done
echo "$E" | jq -e 'all(has("ts") and has("sid"))' >/dev/null; check "every event carries ts + sid (joinable to its correction)" $?

# --- it must never record a secret or an absolute path ---
echo "$E" | jq -e 'all((.path // "") | startswith("/") | not)' >/dev/null; check "no absolute path is ever written (RECOMMENDATIONS R3)" $?
! grep -q "$HOME" "$(jfile "$D")"; check "no \$HOME fragment leaks into the journal" $?
! echo "$E" | jq -e 'any(.key == "secret_guard" and has("path"))' >/dev/null
check "secret-guard records the ATTEMPT, never the secret path it blocked" $?
rm -rf "$D"

# --- blocking still happens: journaling is additive, never a substitute ---
D=$(newproj); export CLAUDE_PROJECT_DIR="$D"
echo '{"tool_name":"Edit","tool_input":{"file_path":"/p/.claude/settings.json"}}' | bash "$H/protect-paths.sh" >/dev/null 2>&1
[ $? -ne 0 ]; check "protect-paths still exits non-zero (the block is unchanged)" $?
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/p/package-lock.json"}}' | bash "$H/protect-policy-paths.sh" 2>&1 >/dev/null)
echo "$out" | grep -q "generated lockfile"; check "the human-readable reason still reaches Claude on stderr" $?
rm -rf "$D"

# --- opt-out honoured (it writes to the user's repo; it must be refusable) ---
D=$(newproj); export CLAUDE_PROJECT_DIR="$D" CLAUDE_POLICY_JOURNAL=0
echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' | bash "$H/block-no-verify.sh" >/dev/null 2>&1
[ ! -f "$(jfile "$D")" ]; check "CLAUDE_POLICY_JOURNAL=0 writes nothing at all" $?
[ $? -eq 0 ] && echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' | bash "$H/block-no-verify.sh" >/dev/null 2>&1
[ $? -ne 0 ]; check "the block still fires with journaling off (never a security trade)" $?
unset CLAUDE_POLICY_JOURNAL
D2=$(newproj); export CLAUDE_PROJECT_DIR="$D2"
echo '{"journal": false}' > "$D2/.claude/policy.json"
echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' | bash "$H/block-no-verify.sh" >/dev/null 2>&1
[ ! -f "$(jfile "$D2")" ]; check "policy.json {\"journal\": false} writes nothing" $?
rm -rf "$D" "$D2"

# --- it must never write into an arbitrary CWD ---
# A hook invoked without CLAUDE_PROJECT_DIR used to journal into `.`, which is how
# the repo's own tests/ directory acquired a .orch/journal during development.
D=$(newproj); unset CLAUDE_PROJECT_DIR
OUT=$(mktemp -d); ( cd "$OUT" && echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' \
  | bash "$OLDPWD/$H/block-no-verify.sh" >/dev/null 2>&1 )
[ ! -d "$OUT/.orch" ]; check "no CLAUDE_PROJECT_DIR and no git repo → writes NOTHING (not into the CWD)" $?
rm -rf "$OUT" "$D"

# --- tool failures: the richest error source, previously unobserved ---
D=$(newproj); export CLAUDE_PROJECT_DIR="$D"
fire() { echo "$1" | bash "$H/observe-tool-result.sh" >/dev/null 2>&1; }
fire '{"tool_name":"Bash","tool_input":{"command":"npm test -- --watch=false"},"tool_response":{"is_error":true,"stdout":"3 tests failed"}}'
fire '{"tool_name":"Bash","tool_input":{"command":"/usr/local/bin/tsc --noEmit"},"tool_response":{"is_error":true,"stdout":"error TS2345: type error"}}'
fire '{"tool_name":"Bash","tool_input":{"command":"ruff check ."},"tool_response":{"is_error":true,"stdout":"lint: E501"}}'
fire '{"tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_response":{"is_error":false,"stdout":"hi"}}'
E=$(events "$D")
[ "$(echo "$E" | jq 'length')" = "3" ]; check "a SUCCESSFUL tool call is not recorded (failures only)" $?
echo "$E" | jq -e 'any(.key == "npm" and .class == "test_failure")' >/dev/null; check "a failing Bash command records verb + classification" $?
echo "$E" | jq -e 'any(.key == "tsc" and .class == "type_error")' >/dev/null; check "an absolute-path binary is recorded by basename only" $?
echo "$E" | jq -e 'any(.class == "lint_failure")' >/dev/null; check "a lint failure is classified" $?
echo "$E" | jq -e 'all(has("command") | not)' >/dev/null; check "the full command line is NEVER stored (only the verb)" $?
! grep -q 'watch=false' "$(jfile "$D")"; check "command flags do not leak into the journal" $?
rm -rf "$D"

# --- human corrections: the ground truth that the agent was wrong ---
D=$(newproj); export CLAUDE_PROJECT_DIR="$D"
prompt() { printf '{"hook_event_name":"UserPromptSubmit","prompt":%s}' "$(jq -Rn --arg p "$1" '$p')" | bash "$H/observe-correction.sh" >/dev/null 2>&1; }
prompt "no, that's wrong — the auth check runs before the redirect"
prompt "revert that change please"
prompt "you broke the login flow, still failing"
prompt "add a health endpoint to the api"
E=$(events "$D")
[ "$(echo "$E" | jq 'length')" = "3" ]; check "an ordinary instruction is not recorded (corrections only)" $?
echo "$E" | jq -e 'any(.key == "contradiction")' >/dev/null; check "a contradiction is classified" $?
echo "$E" | jq -e 'any(.key == "revert_request")' >/dev/null; check "a revert request is classified" $?
echo "$E" | jq -e 'any(.key == "regression_report")' >/dev/null; check "a regression report is classified" $?
! grep -qi 'auth check\|login flow' "$(jfile "$D")"; check "the user's actual words are NEVER stored" $?
echo "$E" | jq -e 'all(.length | IN("short","medium","long"))' >/dev/null; check "only a bucketed length is kept" $?
# a UserPromptSubmit hook's stdout is injected into the model's context
out=$(printf '{"hook_event_name":"UserPromptSubmit","prompt":"no thats wrong"}' | bash "$H/observe-correction.sh" 2>/dev/null)
[ -z "$out" ]; check "the observer emits NO stdout (it must not pollute the prompt)" $?
printf '{"hook_event_name":"SubagentStop","agent_type":"code-reviewer"}' | bash "$H/observe-correction.sh" >/dev/null 2>&1
events "$D" | jq -e 'any(.kind == "subagent_fail" and .key == "code-reviewer")' >/dev/null; check "a subagent stop is recorded by agent type" $?
rm -rf "$D"

# --- session end: a self-contained summary of the session ---
D=$(newproj); export CLAUDE_PROJECT_DIR="$D"
echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' | bash "$H/block-no-verify.sh" >/dev/null 2>&1
printf '{"hook_event_name":"SessionEnd","reason":"clear"}' | bash "$H/session-end.sh" >/dev/null 2>&1
events "$D" | jq -e 'any(.kind == "session_end" and .key == "clear" and .guardBlocks >= 1)' >/dev/null
check "session end summarises the session's own guard blocks" $?
events "$D" | jq -e 'any(.kind == "session_end" and has("dirtyTree"))' >/dev/null
check "session end records whether the tree was left clean (lecture 12)" $?
rm -rf "$D"

# --- the formatter's silent rewrites are a real signal, not noise ---
D=$(newproj); export CLAUDE_PROJECT_DIR="$D"
mkdir -p "$D/src"; printf 'x = 1\n' > "$D/src/a.py"
echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$D"'/src/a.py"}}' | bash ../plugins/formatting/hooks/format-on-edit.sh >/dev/null 2>&1
[ ! -f "$(jfile "$D")" ]; check "a file the formatter did not change is not recorded" $?
rm -rf "$D"

# --- orch state ops ---
D=$(newproj); mkdir -p "$D/orchestrator/bin"; cp "$ORCH_SRC" "$D/orchestrator/bin/orch"; chmod +x "$D/orchestrator/bin/orch"
export CLAUDE_PROJECT_DIR="$D"
printf '{"backend":"none","forge":"none"}' > "$D/orchestrator/state.config.json"
"$D/orchestrator/bin/orch" state push-journal --kind correction --key agent_retry --extra '{"of":"npm"}' >/dev/null
"$D/orchestrator/bin/orch" state pull-journal | jq -e 'any(.kind=="correction" and .of=="npm")' >/dev/null
check "orch state push-journal / pull-journal round-trips" $?
"$D/orchestrator/bin/orch" state push-journal --kind x --key y --extra 'nope' >/dev/null 2>&1
[ $? -ne 0 ]; check "push-journal rejects a non-JSON --extra" $?
# local-only ops must never be handed to a board adapter
printf '{"backend":"jira","forge":"github"}' > "$D/orchestrator/state.config.json"
for op in pull-journal pull-suggestions; do
  "$D/orchestrator/bin/orch" state $op >/dev/null 2>&1
  check "$op stays local on a remote backend (was: 'unknown op', exit 1)" $?
done
"$D/orchestrator/bin/orch" state list-epics >/dev/null 2>&1
[ $? -ne 0 ]; check "a genuine board op still delegates to the adapter" $?
rm -rf "$D"

unset CLAUDE_PROJECT_DIR
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
