#!/bin/bash
# PostToolUse credential detector — the OUTPUT half of secret-guard.
#
# secret-guard.sh (PreToolUse) polices what Claude reads and what a command
# would print. It cannot see what a command actually RETURNED: a script that
# echoes a token, a `git diff` over a config file, a curl response carrying a
# key, a test fixture. This reads the result and says so.
#
# ADVISORY BY CONSTRUCTION. It never blocks and always exits 0 — a credential
# that already appeared in the transcript cannot be un-printed, and failing the
# tool call afterwards destroys work without recovering the secret. The only
# real remedy is rotation, so the message says exactly that.
#
# It NEVER echoes the match. It names the credential CLASS and nothing else;
# printing the value to explain that a value was printed would be absurd.
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -n "$TOOL" ] || exit 0

# The whole response as text — shapes differ per tool and a new one must not
# silently escape the scan.
BODY=$(printf '%s' "$INPUT" | jq -r '.tool_response // empty | if type=="string" then . else tojson end' 2>/dev/null)
[ -n "$BODY" ] || exit 0

# High-confidence issuer-prefixed patterns only. A generic "looks like entropy"
# rule would cry wolf on every hash and commit sha in the repo, and a detector
# that is usually wrong gets ignored exactly when it is right.
hit=""
# `--` is load-bearing: the private-key pattern starts with dashes and grep would
# read it as options, erroring on EVERY tool result instead of matching.
scan() { printf '%s' "$BODY" | grep -qE -- "$2" && hit="${hit:+$hit, }$1"; }
scan "slack"            'xox[baprs]-[A-Za-z0-9-]{10,}'
scan "slack-app"        'xapp-[0-9]-[A-Za-z0-9-]{10,}'
scan "anthropic"        'sk-ant-[A-Za-z0-9_-]{20,}'
scan "github-pat"       '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}'
scan "github-fine"      'github_pat_[A-Za-z0-9_]{40,}'
scan "gitlab-pat"       'glpat-[A-Za-z0-9_-]{15,}'
scan "aws-access-key"   'AKIA[0-9A-Z]{16}'
scan "google-api-key"   'AIza[0-9A-Za-z_-]{35}'
scan "openai"           'sk-[A-Za-z0-9]{40,}'
scan "private-key"      '-----BEGIN [A-Z ]*PRIVATE KEY-----'

[ -n "$hit" ] || exit 0

cat >&2 <<EOF
⚠ SECRET IN OUTPUT — a credential-shaped string appeared in the result of $TOOL.
  Class(es): $hit
  It is in the transcript now and cannot be redacted retroactively.
  ROTATE the affected credential; do not merely delete the message.
  Correct presence check: \${VAR:+yes} (docs/SECURITY.md).
EOF
# Record that it happened, never what it was — the class is the whole payload.
journal guard_block secret_egress_output \
  "$(jq -cn --arg t "$TOOL" --arg c "$hit" '{tool:$t,classes:$c,severity:"security"}' 2>/dev/null || echo '{}')"
exit 0
