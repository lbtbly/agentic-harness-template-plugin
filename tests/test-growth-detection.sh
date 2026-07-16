#!/bin/bash
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
HOOK=../plugins/core/hooks/growth-detection.sh

TMP=$(mktemp -d); mkdir -p "$TMP/docs"
export CLAUDE_PROJECT_DIR="$TMP"

echo 'const k = process.env.STRIPE_API_KEY' > "$TMP/pay.ts"
assert_exit 0 "$HOOK" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/pay.ts\"}}" "exit 0 on credential trigger"
grep -q "ACCESS.md" "$TMP/docs/SUGGESTIONS.md" && { PASS=$((PASS+1)); echo "  ok   — ACCESS.md suggestion written"; } || { FAIL=$((FAIL+1)); echo "  FAIL — ACCESS.md suggestion missing"; }

# Idempotence: re-running does not duplicate
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/pay.ts\"}}" | bash "$HOOK" >/dev/null 2>&1
N=$(grep -c "ACCESS.md" "$TMP/docs/SUGGESTIONS.md")
[ "$N" -eq 1 ] && { PASS=$((PASS+1)); echo "  ok   — idempotent"; } || { FAIL=$((FAIL+1)); echo "  FAIL — $N duplicates"; }

echo 'customer EMAIL and phone' > "$TMP/user.ts"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/user.ts\"}}" | bash "$HOOK" >/dev/null 2>&1
grep -q "GDPR" "$TMP/docs/SUGGESTIONS.md" && { PASS=$((PASS+1)); echo "  ok   — GDPR flag written"; } || { FAIL=$((FAIL+1)); echo "  FAIL — GDPR flag missing"; }

# docs/ guard: editing a docs/ file containing "email" must not add a new GDPR line
echo 'email phone data' > "$TMP/docs/x.md"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/docs/x.md\"}}" | bash "$HOOK" >/dev/null 2>&1
N2=$(grep -c "GDPR" "$TMP/docs/SUGGESTIONS.md")
[ "$N2" -eq 1 ] && { PASS=$((PASS+1)); echo "  ok   — docs/ guard idempotent (no GDPR duplicate)"; } || { FAIL=$((FAIL+1)); echo "  FAIL — $N2 GDPR lines (expected 1)"; }

# EDGE marker harvesting (ADR-0011 confidence gate)
echo 'if (!x) { /* EDGE: can x be null here? */ return }' > "$TMP/svc.ts"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/svc.ts\"}}" | bash "$HOOK" >/dev/null 2>&1
grep -q "Author-flagged edge case" "$TMP/docs/SUGGESTIONS.md" && { PASS=$((PASS+1)); echo "  ok   — EDGE marker flagged"; } || { FAIL=$((FAIL+1)); echo "  FAIL — EDGE marker not flagged"; }
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/svc.ts\"}}" | bash "$HOOK" >/dev/null 2>&1
NE=$(grep -c "Author-flagged edge case" "$TMP/docs/SUGGESTIONS.md")
[ "$NE" -eq 1 ] && { PASS=$((PASS+1)); echo "  ok   — EDGE idempotent"; } || { FAIL=$((FAIL+1)); echo "  FAIL — $NE EDGE duplicates"; }

# Out-of-repo guard: a file outside CLAUDE_PROJECT_DIR must never be flagged
# (an absolute out-of-repo path would leak a machine username into a committed file).
OUT=$(mktemp -d); echo 'const k = process.env.STRIPE_API_KEY' > "$OUT/scratch.ts"
BEFORE=$(wc -l < "$TMP/docs/SUGGESTIONS.md")
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$OUT/scratch.ts\"}}" | bash "$HOOK" >/dev/null 2>&1
AFTER=$(wc -l < "$TMP/docs/SUGGESTIONS.md")
[ "$BEFORE" -eq "$AFTER" ] && { PASS=$((PASS+1)); echo "  ok   — out-of-repo file not flagged"; } || { FAIL=$((FAIL+1)); echo "  FAIL — out-of-repo file was flagged"; }
rm -rf "$OUT"

unset CLAUDE_PROJECT_DIR; rm -rf "$TMP"

# Lazy mkdir: no docs/ created if no trigger
TMP2=$(mktemp -d)
export CLAUDE_PROJECT_DIR="$TMP2"
echo 'nothing' > "$TMP2/plain.ts"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP2/plain.ts\"}}" | bash "$HOOK" >/dev/null 2>&1
if [ ! -d "$TMP2/docs" ]; then PASS=$((PASS+1)); echo "  ok   — does not create docs/ without a trigger"
else FAIL=$((FAIL+1)); echo "  FAIL — docs/ created without a trigger"; fi

unset CLAUDE_PROJECT_DIR; rm -rf "$TMP2"

summary
