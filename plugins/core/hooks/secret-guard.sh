#!/bin/bash
# Layer 3 of defense in depth: blocks any access to secret paths,
# even if .gitignore or the settings.json deny-rules are misconfigured.
# Exit 2 = hard block, the stderr message is shown to Claude.
# R6: a guard that cannot parse its input must BLOCK, not silently allow.
command -v jq >/dev/null 2>&1 || { echo "BLOCKED: secret-guard cannot run — jq is missing (install jq; see docs/SECURITY.md)" >&2; exit 2; }
INPUT=$(cat)
TARGET=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // empty')
[ -z "$TARGET" ] && exit 0

# Whitelist: .env.example is the only readable "secret-like" file.
# Tolerated bootstrap case: `cp .env.example .env` (exposes no values).
if echo "$TARGET" | grep -qE '^cp[[:space:]]+(\./)?\.env\.example[[:space:]]+(\./)?\.env$'; then exit 0; fi
STRIPPED=$(echo "$TARGET" | sed 's/\.env\.example//g')

# --- EGRESS: a command that would PRINT a credential ---------------------------
# The guard policed only what Claude READS. It never policed what Claude EMITS,
# and on 2026-07-28 a probe meant to answer "is the token set?" printed a live
# Slack token into a transcript:
#     ${VAR:+yes}  -> "yes"        SAFE: the + forms never expand the value
#     ${VAR:-no}   -> THE VALUE    TRAP: :- substitutes only when UNSET, so a
#                                  variable that IS set expands normally
# Only the + forms are provably safe, so anything else inside a printing command
# is blocked. Passing a credential to curl is untouched: the offence is printing
# it, not using it.
SECRET_VAR='[A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|API_KEY|APIKEY|PRIVATE_KEY)[A-Za-z0-9_]*'
if printf '%s' "$TARGET" | grep -qE '(^|[;&|]|[[:space:]])(echo|printf)[[:space:]]'; then
  LEFT=$(printf '%s' "$TARGET" | sed -E "s/\\$\{$SECRET_VAR:?\+[^}]*\}//g")
  if printf '%s' "$LEFT" | grep -qE "\\$\{?$SECRET_VAR"; then
    echo "BLOCKED by secret-guard: this command would PRINT a credential-named variable." >&2
    echo "Use \${VAR:+yes} - it reports presence without ever expanding the value." >&2
    echo "\${VAR:-fallback} expands to the VALUE when the variable is set (docs/SECURITY.md)." >&2
    . "$(dirname "$0")/policy-lib.sh" 2>/dev/null && journal guard_block secret_egress '{"severity":"security"}'
    exit 2
  fi
fi
# `env` / `printenv` dumps every credential in scope. Piping it does not help --
# `env | grep TOKEN` prints the value. Only sinks that structurally CANNOT emit a
# value are allowed through: a count or a quiet test. Same principle as ${VAR:+}.
if printf '%s' "$TARGET" | grep -qE '(^|[;&|][[:space:]]*)(env|printenv)[[:space:]]*($|[;&|])' \
   && ! printf '%s' "$TARGET" | grep -qE '(env|printenv)[[:space:]]*\|[[:space:]]*(grep[[:space:]]+-[a-z]*[qc]|wc[[:space:]]+-l)'; then
  echo "BLOCKED by secret-guard: a bare \`env\`/\`printenv\` dumps every credential in scope." >&2
  echo "Filter it: printenv PATH, or env | grep -c SOMETHING (docs/SECURITY.md)." >&2
  . "$(dirname "$0")/policy-lib.sh" 2>/dev/null && journal guard_block secret_egress '{"severity":"security"}'
  exit 2
fi

SECRET_PAT='(^|[=/[:space:]'"'"'"])\.env(rc|\.[A-Za-z0-9_.-]+)?(['"'"'"[:space:]]|$|[/|;&])|\.pem(['"'"'"[:space:]]|$)|\.key(['"'"'"[:space:]]|$)|(^|[=/[:space:]'"'"'"])secrets(/|['"'"'"[:space:]]|$)'
if echo "$STRIPPED" | grep -qE "$SECRET_PAT"; then
  echo "BLOCKED by secret-guard: \"$TARGET\" touches a secret path. Secrets must never enter the context. Use environment variables (docs/SECURITY.md)." >&2
  # Record the attempt. NEVER the target — it is a secret path by definition.
  . "$(dirname "$0")/policy-lib.sh" 2>/dev/null && journal guard_block secret_guard '{"severity":"security"}'
  exit 2
fi
exit 0
