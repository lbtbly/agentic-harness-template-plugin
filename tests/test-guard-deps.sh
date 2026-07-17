#!/bin/bash
# R6 — dependency integrity: security guards FAIL CLOSED without jq (exit 2);
# advisory hooks fail open (exit 0) with a logged note.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
H="../plugins/core/hooks"

# a PATH with core utils but no jq
NOJQ=$(mktemp -d)
for t in bash sh grep sed cat ls head tail dirname mktemp awk tr date git wc find sort uniq; do
  p=$(command -v $t 2>/dev/null) && ln -s "$p" "$NOJQ/$t" 2>/dev/null
done
if PATH="$NOJQ" command -v jq >/dev/null 2>&1; then
  echo "  skip — cannot construct a jq-less PATH"; echo "---"; echo "0 ok, 0 failure(s)"; rm -rf "$NOJQ"; exit 0
fi

J='{"tool_name":"Read","tool_input":{"file_path":"/p/.env"}}'
for g in secret-guard protect-paths block-no-verify protect-policy-paths; do
  echo "$J" | PATH="$NOJQ" bash "$H/$g.sh" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ]; check "guard $g without jq → exit 2 (fail closed)" $?
done
for a in growth-detection handoff-reminder notify session-context; do
  echo "$J" | PATH="$NOJQ" bash "$H/$a.sh" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ]; check "advisory $a without jq → exit 0 (fail open)" $?
done
echo "$J" | PATH="$NOJQ" bash "../plugins/formatting/hooks/format-on-edit.sh" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; check "format-on-edit without jq → exit 0 (advisory)" $?
rm -rf "$NOJQ"
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
