#!/bin/bash
# The guard policed what Claude READS. It never policed what Claude EMITS, and on
# 2026-07-28 a probe written as ${VAR:+YES}${VAR:-NO} printed a live Slack token
# into a transcript — `:-` substitutes only when UNSET, so a variable that IS set
# expands normally. Two halves are pinned here: refusing to print a credential
# (PreToolUse), and noticing when one came back anyway (PostToolUse).
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
G="../plugins/core/hooks/secret-guard.sh"
E="../plugins/core/hooks/secret-egress.sh"

[ -f "$G" ] && bash -n "$G"; check "secret-guard parses" $?
[ -f "$E" ] && bash -n "$E"; check "secret-egress parses" $?
[ -x "$E" ]; check "secret-egress is executable" $?
jq -e '[.hooks.PostToolUse[].hooks[].command] | map(select(test("secret-egress"))) | length == 1' \
  ../plugins/core/hooks/hooks.json >/dev/null 2>&1
check "secret-egress is wired as a PostToolUse hook" $?

# --- INPUT half: a command that would print a credential ----------------------
g() { # g <BLOCK|ALLOW> <command> <label>
  local got rc
  printf '%s' "$2" | jq -Rn --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$G" >/dev/null 2>&1
  rc=$?; got=ALLOW; [ "$rc" -eq 2 ] && got=BLOCK
  [ "$got" = "$1" ]; check "$1 — $3" $?
}
g BLOCK 'echo "set: ${SLACK_BOT_TOKEN:+YES}${SLACK_BOT_TOKEN:-NO}"' 'the probe that leaked a live token'
g ALLOW 'echo "set: ${SLACK_BOT_TOKEN:+yes}"'                       ':+ is the one safe presence check'
g BLOCK 'echo $ANTHROPIC_API_KEY'                                   'bare expansion'
g BLOCK 'printf "%s" "${GITHUB_TOKEN:-none}"'                       'printf with a :- default'
g BLOCK 'env'                                                       'bare env dumps every credential'
g BLOCK 'env | grep GITHUB_TOKEN'                                   'piping env does not make it safe'
g ALLOW 'env | grep -c GITHUB_TOKEN'                                'a count cannot emit a value'
g ALLOW 'printenv PATH'                                             'a named, non-secret variable'
g ALLOW 'curl -H "Authorization: Bearer $SLACK_BOT_TOKEN" https://slack.com/api/auth.test'
g ALLOW 'git commit -m "document token handling"'                   'the word token in prose'

# --- OUTPUT half: a credential that came back anyway --------------------------
e() { # e <alarm|quiet> <payload> <label>
  local out got
  out=$(jq -cn --arg b "$2" '{tool_name:"Bash",tool_response:{stdout:$b}}' | bash "$E" 2>&1)
  got=alarm; [ -z "$out" ] && got=quiet
  [ "$got" = "$1" ]; check "$1 — $3" $?
  if [ "$1" = alarm ]; then
    printf '%s' "$out" | grep -qF -- "$2"; [ $? -ne 0 ]
    check "…and the value itself is NOT echoed back — $3" $?
  fi
}
e alarm 'leaked xoxb-1234567890-0987654321-AbCdEfGhIjKlMnOpQrStUvWx here' 'slack bot token in output'
e alarm 'ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789'                        'github pat in output'
e alarm 'AKIAIOSFODNN7EXAMPLE'                                            'aws access key in output'
e alarm '-----BEGIN RSA PRIVATE KEY-----'                                 'private key header (grep -- guard)'
e quiet 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0'                        'a commit sha is not a credential'
e quiet 'integrity sha512-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF'     'npm integrity hash'
e quiet 'the SLACK_BOT_TOKEN variable is documented in SECURITY.md'       'a variable NAME is not a value'
e quiet 'ALL SUITES GREEN 962 assertions'                                 'ordinary suite output'

# --- the detector must never block: a credential cannot be un-printed ---------
jq -cn '{tool_name:"Bash",tool_response:{stdout:"xoxb-1234567890-0987654321-AbCdEfGhIjKlMnOpQrStUvWx"}}' \
  | bash "$E" >/dev/null 2>&1
[ $? -eq 0 ]; check "detector is advisory: exits 0 even on a hit (rotation is the remedy)" $?
grep -qi "ROTATE" "$E"; check "…and says so — it tells you to rotate" $?

# --- the documented rule ------------------------------------------------------
S="../plugins/core/templates/docs/SECURITY.md"
grep -q 'VAR:+' "$S"; check "SECURITY.md documents the :+ rule" $?
grep -qi "LEAKS THE VALUE\|expands to the value" "$S"; check "…and names the :- trap explicitly" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
