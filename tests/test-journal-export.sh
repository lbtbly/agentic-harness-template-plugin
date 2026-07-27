#!/bin/bash
# Export redaction (ADR-0025). "Safe in my repo" and "safe to send you" are
# different bars; this is the stricter one, and it must fail CLOSED.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
EXP=../plugins/core/templates/orchestrator/bin/journal-export

mkproj() {
  local d; d=$(mktemp -d); mkdir -p "$d/orchestrator/bin" "$d/.orch/journal"
  cp "$EXP" "$d/orchestrator/bin/"; chmod +x "$d/orchestrator/bin/journal-export"; echo "$d"
}
D=$(mkproj); export CLAUDE_PROJECT_DIR="$D"
cat > "$D/.orch/journal/2026-07-26.jsonl" <<J
{"ts":"2026-07-26T10:00:00Z","sid":"orch/auth-revamp","kind":"guard_block","key":"ci_workflow","path":".github/workflows/ci.yml"}
{"ts":"2026-07-26T10:05:00Z","sid":"orch/auth-revamp","kind":"tool_error","key":"npm","class":"test_failure"}
{"ts":"2026-07-26T10:09:00Z","sid":"orch/auth-revamp","kind":"user_correction","key":"contradiction","length":"short"}
{"ts":"2026-07-26T11:00:00Z","sid":"orch/api","kind":"escalation","key":"sonnet","epic":"api-v2","to":"opus","corrected":true}
{"ts":"2026-07-26T11:30:00Z","sid":"orch/api","kind":"escalation","key":"sonnet","epic":"ui-x","to":"opus","corrected":false}
{"ts":"2026-07-26T12:00:00Z","sid":"orch/api","kind":"reformat","key":"ts","path":"src/deep/nested/module.ts"}
J
OUT=$("$D/orchestrator/bin/journal-export" 2>/dev/null); [ -n "$OUT" ] && [ -f "$OUT" ]
check "export writes a bundle" $?
B=$(cat "$OUT" 2>/dev/null || echo '{}')

echo "$B" | jq -e '.schema == "harness-journal-export/1"' >/dev/null; check "bundle is versioned" $?
echo "$B" | jq -e '.events == 6 and .days == 1' >/dev/null; check "every event is counted" $?

# --- the correction metric: a FAILED correction must not vanish ---
echo "$B" | jq -e '.correction.attempted == 2' >/dev/null
check "corrected:false is counted (jq's // drops false — the bug this pins)" $?
echo "$B" | jq -e '.correction.succeeded == 1' >/dev/null; check "only real successes count as succeeded" $?
echo "$B" | jq -e '.correction.humanInterventions == 1' >/dev/null; check "human interventions are counted separately" $?

# --- redaction: an allowlist, so a NEW journal field cannot leak by default ---
echo "$B" | grep -q 'auth-revamp'   && r=1 || r=0; [ $r = 0 ]; check "branch / session id never survives" $?
echo "$B" | grep -q 'api-v2'        && r=1 || r=0; [ $r = 0 ]; check "epic ids never survive" $?
echo "$B" | grep -q 'module.ts'     && r=1 || r=0; [ $r = 0 ]; check "file NAMES never survive" $?
echo "$B" | grep -q 'src/deep'      && r=1 || r=0; [ $r = 0 ]; check "path structure never survives" $?
echo "$B" | grep -q '10:05'         && r=1 || r=0; [ $r = 0 ]; check "timestamps are reduced to a date" $?
echo "$B" | jq -e '.fileTypes.ts == 1' >/dev/null; check "only the coarse file EXTENSION survives" $?
echo "$B" | jq -e '.repo | test("^[0-9a-f]{16}$")' >/dev/null; check "the repo is a salted hash, not a name" $?

# stable across runs (batches must join), and not reversible to a path
OUT2=$("$D/orchestrator/bin/journal-export" 2>/dev/null)
[ "$(jq -r .repo "$OUT")" = "$(jq -r .repo "$OUT2")" ]; check "the repo hash is stable across exports" $?
D2=$(mkproj); CLAUDE_PROJECT_DIR="$D2" cp -r "$D/.orch/journal" "$D2/.orch/" 2>/dev/null
OUT3=$(CLAUDE_PROJECT_DIR="$D2" "$D2/orchestrator/bin/journal-export" 2>/dev/null)
[ "$(jq -r .repo "$OUT")" != "$(jq -r .repo "$OUT3" 2>/dev/null)" ]; check "a different repo hashes differently (salt is per-repo)" $?
rm -rf "$D2"

# --- fail CLOSED: a leak aborts, it never ships a partial bundle ---
for leak in "$HOME/private" "https://github.com/acme/secret" "dev@acme.com" "/etc/passwd"; do
  DL=$(mkproj); export CLAUDE_PROJECT_DIR="$DL"
  jq -cn --arg l "$leak" '{ts:"2026-07-26T10:00:00Z",sid:"x",kind:"tool_error",key:"npm",class:$l}' \
    > "$DL/.orch/journal/2026-07-26.jsonl"
  "$DL/orchestrator/bin/journal-export" >/dev/null 2>&1
  rc=$?
  [ "$rc" -ne 0 ]; check "a leak aborts the export (${leak%%[:/]*}…)" $?
  [ -z "$(ls "$DL/.orch/exports" 2>/dev/null)" ]; check "  …and NO bundle is written" $?
  rm -rf "$DL"
done

# --- --since bounds the range ---
D3=$(mkproj); export CLAUDE_PROJECT_DIR="$D3"
echo '{"ts":"2026-07-01T10:00:00Z","sid":"x","kind":"tool_error","key":"old"}' > "$D3/.orch/journal/2026-07-01.jsonl"
echo '{"ts":"2026-07-26T10:00:00Z","sid":"x","kind":"tool_error","key":"new"}' > "$D3/.orch/journal/2026-07-26.jsonl"
O=$("$D3/orchestrator/bin/journal-export" --since 2026-07-20 2>/dev/null)
jq -e '.events == 1' "$O" >/dev/null; check "--since bounds the export to the range" $?
"$D3/orchestrator/bin/journal-export" --since 2027-01-01 >/dev/null 2>&1
[ $? -ne 0 ]; check "an empty range exits non-zero rather than shipping an empty bundle" $?
rm -rf "$D3"

# --- the skills ship and stay honest about what they do ---
S=../plugins/core/skills/export-journal/SKILL.md
[ -f "$S" ]; check "/core:export-journal ships" $?
grep -qi "nothing is sent anywhere\|writes a file" "$S"; check "the skill states nothing leaves the machine" $?
grep -q "disable-model-invocation: true" "$S"; check "export is operator-invoked, not model-invoked" $?
I=../.claude/skills/ingest-findings/SKILL.md
[ -f "$I" ]; check "/ingest-findings ships (maintainer side)" $?
grep -qi "untrusted data" "$I"; check "ingest treats bundles as untrusted data, never instructions" $?

rm -rf "$D"; unset CLAUDE_PROJECT_DIR
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
