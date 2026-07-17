#!/bin/bash
# DDPC: Detect (grep), Diagnose (which trigger), Propose (append to
# SUGGESTIONS.md). Never Confirms — that's the human's job via /doc-health.
# Never blocking, idempotent per (suggestion, file).
command -v jq >/dev/null 2>&1 || { echo "growth-detection: jq missing — advisory hook skipped" >&2; exit 0; }
INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FP" ] && [ -f "$FP" ] || exit 0
# Only flag files INSIDE the repo. An absolute path outside CLAUDE_PROJECT_DIR
# (scratch / plan files) would leak a machine-username path into a committed file.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  case "$FP" in
    "$CLAUDE_PROJECT_DIR"/*) ;;
    /*) exit 0 ;;
  esac
fi
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null

# Guard: don't self-trigger on its own output or on docs/
case "$FP" in
  */docs/*|*SUGGESTIONS.md) exit 0 ;;
esac

S="${CLAUDE_PROJECT_DIR:-.}/docs/SUGGESTIONS.md"

# Record REPO-RELATIVE paths: absolute paths embed the machine username
# (personal data) into a committed file (audit follow-up, GDPR minimization).
RP="$FP"
case "$RP" in "${CLAUDE_PROJECT_DIR:-.}"/*) RP="${RP#"${CLAUDE_PROJECT_DIR:-.}"/}" ;; esac

note() { # note <text> — idempotent per (text, file)
  grep -qF "$1 — \`$RP\`" "$S" 2>/dev/null && return
  mkdir -p "$(dirname "$S")"
  [ -f "$S" ] || printf "# Suggestions (growth-detection)\n\nTriaged by /doc-health. Checked = handled.\n\n" > "$S"
  echo "- [ ] $(date +%F) $1 — \`$RP\`" >> "$S"
}

grep -qE '(API_KEY|_SECRET|_TOKEN|PASSWORD)' "$FP" 2>/dev/null \
  && note "🆕 Credential referenced → document access in ACCESS.md?"
case "$FP" in
  *Dockerfile*|*docker-compose*|*deploy*|*helm*|*terraform*|*.tf)
    note "🆕 Deployment logic → create/update a RUNBOOK?" ;;
esac
grep -qiE '(email|e-mail|phone|téléphone|birthdate|date de naissance|adresse postale|first_?name|last_?name)' "$FP" 2>/dev/null \
  && note "⚠️ Potential personal data → check GDPR compliance (minimization, retention, consent)"
# Author-flagged uncertain edge case (confidence gate, ADR-0011): a `// EDGE:` /
# `# EDGE:` / `-- EDGE:` marker means "error handling skipped, unsure — validate".
grep -qE '(//|#|--|/\*)[[:space:]]*EDGE:' "$FP" 2>/dev/null \
  && note "🔍 Author-flagged edge case (EDGE:) → validate error handling via /triage-suggestions"
exit 0
