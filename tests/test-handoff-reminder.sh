#!/bin/bash
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
HOOK=../plugins/core/hooks/handoff-reminder.sh

TMP=$(mktemp -d); mkdir -p "$TMP/docs"
git -C "$TMP" init -q -b main
echo x > "$TMP/f.txt"; git -C "$TMP" add f.txt
git -C "$TMP" -c user.email=t@t -c user.name=t commit -qm init
export CLAUDE_PROJECT_DIR="$TMP"

# HANDOFF 25h old + dirty repo → reminder
printf "# HANDOFF\n" > "$TMP/docs/HANDOFF.md"
git -C "$TMP" add docs && git -C "$TMP" -c user.email=t@t -c user.name=t commit -qm handoff
OLD=$(date -v-25H "+%Y%m%d%H%M" 2>/dev/null || date -d "25 hours ago" "+%Y%m%d%H%M")
touch -t "$OLD" "$TMP/docs/HANDOFF.md"
echo dirty >> "$TMP/f.txt"
assert_stdout_contains "$HOOK" '{"stop_hook_active":false}' "/handoff" "reminds /handoff if stale + dirty"
assert_stdout_contains "$HOOK" '{"stop_hook_active":false}' '"decision"' "JSON output with decision block"

# Anti-loop safeguard
assert_stdout_empty "$HOOK" '{"stop_hook_active":true}' "silent if stop_hook_active"

# Fresh HANDOFF → silent
touch "$TMP/docs/HANDOFF.md"
assert_stdout_empty "$HOOK" '{"stop_hook_active":false}' "silent if HANDOFF is fresh"

# Clean repo → silent
OLD=$(date -v-25H "+%Y%m%d%H%M" 2>/dev/null || date -d "25 hours ago" "+%Y%m%d%H%M")
touch -t "$OLD" "$TMP/docs/HANDOFF.md"
git -C "$TMP" checkout -q -- f.txt
assert_stdout_empty "$HOOK" '{"stop_hook_active":false}' "silent if repo is clean"

# Untracked files only → reminder
echo new > "$TMP/brand-new.txt"
assert_stdout_contains "$HOOK" '{"stop_hook_active":false}' "/handoff" "reminds if only untracked files"
rm "$TMP/brand-new.txt"

# No HANDOFF.md → silent
rm "$TMP/docs/HANDOFF.md"
echo dirty2 >> "$TMP/f.txt"
assert_stdout_empty "$HOOK" '{"stop_hook_active":false}' "silent without HANDOFF.md"
# --- D1 stop-gate: policy-toggled blocking on dirty cleanState (default OFF) ---
mkdir -p "$TMP/.orch/sessions"
cat > "$TMP/.orch/sessions/main.json" <<'JSON'
{"branch":"main","cleanState":{"build":"fail","tests":"fail","debugArtifacts":["src/x.ts:12 — console.log"]}}
JSON
echo gate-dirty >> "$TMP/f.txt"
# gate OFF (default) → advisory only, never exit 2
echo '{"stop_hook_active":false}' | bash "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 2 ]; ok2=$?; if [ $ok2 -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — stop_gate off: dirty cleanState never blocks"; else FAIL=$((FAIL+1)); echo "  FAIL — stop_gate off: dirty cleanState never blocks"; fi
# gate ON + dirty cleanState → exit 2 (block)
echo '{"stop_hook_active":false}' | CLAUDE_POLICY_STOP_GATE=true bash "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ]; ok2=$?; if [ $ok2 -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — stop_gate on + dirty cleanState → exit 2"; else FAIL=$((FAIL+1)); echo "  FAIL — stop_gate on + dirty cleanState → exit 2 (got $rc)"; fi
# gate ON + clean cleanState → no block
cat > "$TMP/.orch/sessions/main.json" <<'JSON'
{"branch":"main","cleanState":{"build":"pass","tests":"pass","debugArtifacts":[]}}
JSON
echo '{"stop_hook_active":false}' | CLAUDE_POLICY_STOP_GATE=true bash "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 2 ]; ok2=$?; if [ $ok2 -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — stop_gate on + clean state → no block"; else FAIL=$((FAIL+1)); echo "  FAIL — stop_gate on + clean state → no block"; fi
# anti-loop: stop_hook_active always wins
echo '{"stop_hook_active":true}' | CLAUDE_POLICY_STOP_GATE=true bash "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; ok2=$?; if [ $ok2 -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — stop_gate respects stop_hook_active (anti-loop)"; else FAIL=$((FAIL+1)); echo "  FAIL — stop_gate respects stop_hook_active"; fi

unset CLAUDE_PROJECT_DIR; rm -rf "$TMP"
summary
