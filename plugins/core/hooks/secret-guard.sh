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

SECRET_PAT='(^|[=/[:space:]'"'"'"])\.env(rc|\.[A-Za-z0-9_.-]+)?(['"'"'"[:space:]]|$|[/|;&])|\.pem(['"'"'"[:space:]]|$)|\.key(['"'"'"[:space:]]|$)|(^|[=/[:space:]'"'"'"])secrets(/|['"'"'"[:space:]]|$)'
if echo "$STRIPPED" | grep -qE "$SECRET_PAT"; then
  echo "BLOCKED by secret-guard: \"$TARGET\" touches a secret path. Secrets must never enter the context. Use environment variables (docs/SECURITY.md)." >&2
  # Record the attempt. NEVER the target — it is a secret path by definition.
  . "$(dirname "$0")/policy-lib.sh" 2>/dev/null && journal guard_block secret_guard '{"severity":"security"}'
  exit 2
fi
exit 0
