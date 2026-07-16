#!/bin/bash
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
HOOK=../plugins/formatting/hooks/format-on-edit.sh

assert_exit 0 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/nonexistent/foo.xyz"}}' "no-op on unknown extension"
assert_exit 0 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/nonexistent/foo.ts"}}' "no-op if file missing"
assert_exit 0 "$HOOK" '{"tool_name":"Edit","tool_input":{}}' "no-op if no file_path"
TMP=$(mktemp -d); echo 'const x=1' > "$TMP/a.ts"
export CLAUDE_PROJECT_DIR="$TMP"
assert_exit 0 "$HOOK" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP/a.ts\"}}" "no-op if no formatter configured"
unset CLAUDE_PROJECT_DIR
rm -rf "$TMP"

# Containment + symlink: uses a fake npx that rewrites any .ts file
# to prove the guard prevents formatting outside the project and via symlink
TMP2=$(mktemp -d); OUTSIDE=$(mktemp -d)
echo '{}' > "$TMP2/.prettierrc"
printf 'const  y=2' > "$OUTSIDE/b.ts"
# Fake npx: rewrites any *.ts argument it receives
mkdir -p "$TMP2/fakebin"
cat > "$TMP2/fakebin/npx" << 'FAKEEOF'
#!/bin/bash
for arg; do case "$arg" in *.ts|*.js|*.jsx|*.tsx) printf 'FORMATTED' > "$arg" ;; esac; done
FAKEEOF
chmod +x "$TMP2/fakebin/npx"
export CLAUDE_PROJECT_DIR="$TMP2"

assert_exit 0 "$HOOK" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$OUTSIDE/b.ts\"}}" "does not touch a file outside the project"
CONTENT=$(PATH="$TMP2/fakebin:$PATH" bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$OUTSIDE/b.ts\"}}' | CLAUDE_PROJECT_DIR='$TMP2' bash '$HOOK'" >/dev/null 2>&1; cat "$OUTSIDE/b.ts")
if [ "$CONTENT" = "const  y=2" ]; then PASS=$((PASS+1)); echo "  ok   — outside-project file content unchanged"
else FAIL=$((FAIL+1)); echo "  FAIL — outside-project file content modified: $CONTENT"; fi

# Symlink: the hook must not follow symlinks
printf 'const  z=3' > "$OUTSIDE/c.ts"
ln -s "$OUTSIDE/c.ts" "$TMP2/link.ts"
SYMCONTENT=$(PATH="$TMP2/fakebin:$PATH" bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP2/link.ts\"}}' | CLAUDE_PROJECT_DIR='$TMP2' bash '$HOOK'" >/dev/null 2>&1; cat "$OUTSIDE/c.ts")
if [ "$SYMCONTENT" = "const  z=3" ]; then PASS=$((PASS+1)); echo "  ok   — symlink target unchanged"
else FAIL=$((FAIL+1)); echo "  FAIL — symlink target modified: $SYMCONTENT"; fi

unset CLAUDE_PROJECT_DIR
rm -rf "$TMP2" "$OUTSIDE"

# Positive path: formatter detected → project file gets formatted
TMP3=$(mktemp -d)
echo '{}' > "$TMP3/.prettierrc"
printf 'const  x=1' > "$TMP3/in.ts"
mkdir -p "$TMP3/fakebin"
cat > "$TMP3/fakebin/npx" << 'FAKEEOF2'
#!/bin/bash
for arg; do case "$arg" in *.ts|*.js|*.jsx|*.tsx) printf 'FORMATTED' > "$arg" ;; esac; done
FAKEEOF2
chmod +x "$TMP3/fakebin/npx"
PATH="$TMP3/fakebin:$PATH" bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP3/in.ts\"}}' | CLAUDE_PROJECT_DIR='$TMP3' bash '$HOOK'" >/dev/null 2>&1
FMTCONTENT=$(cat "$TMP3/in.ts")
if [ "$FMTCONTENT" = "FORMATTED" ]; then PASS=$((PASS+1)); echo "  ok   — formats a project file when a formatter is detected"
else FAIL=$((FAIL+1)); echo "  FAIL — formats a project file when a formatter is detected (content: $FMTCONTENT)"; fi
rm -rf "$TMP3"

# Lint auto-fix path: eslint config present (no prettier) → eslint --fix runs
TMP4=$(mktemp -d)
echo '{}' > "$TMP4/.eslintrc.json"
printf 'var  a=1' > "$TMP4/lint.ts"
mkdir -p "$TMP4/fakebin"
cat > "$TMP4/fakebin/npx" << 'FAKEEOF3'
#!/bin/bash
tool=""; for arg; do case "$arg" in eslint) tool=eslint ;; prettier) tool=prettier ;; esac; done
[ "$tool" = "eslint" ] || exit 0
for arg; do case "$arg" in *.ts|*.js|*.jsx|*.tsx) printf 'LINTFIXED' > "$arg" ;; esac; done
FAKEEOF3
chmod +x "$TMP4/fakebin/npx"
PATH="$TMP4/fakebin:$PATH" bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP4/lint.ts\"}}' | CLAUDE_PROJECT_DIR='$TMP4' bash '$HOOK'" >/dev/null 2>&1
LINTCONTENT=$(cat "$TMP4/lint.ts")
if [ "$LINTCONTENT" = "LINTFIXED" ]; then PASS=$((PASS+1)); echo "  ok   — lint-fixes a project file when an eslint config is detected"
else FAIL=$((FAIL+1)); echo "  FAIL — lint-fixes when eslint config detected (content: $LINTCONTENT)"; fi
rm -rf "$TMP4"

# No lint config → file untouched by the lint step (clean no-op)
TMP5=$(mktemp -d)
printf 'var  b=2' > "$TMP5/nolint.ts"
mkdir -p "$TMP5/fakebin"
cp /dev/null "$TMP5/fakebin/npx" 2>/dev/null
cat > "$TMP5/fakebin/npx" << 'FAKEEOF4'
#!/bin/bash
for arg; do case "$arg" in *.ts|*.js|*.jsx|*.tsx) printf 'TOUCHED' > "$arg" ;; esac; done
FAKEEOF4
chmod +x "$TMP5/fakebin/npx"
PATH="$TMP5/fakebin:$PATH" bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP5/nolint.ts\"}}' | CLAUDE_PROJECT_DIR='$TMP5' bash '$HOOK'" >/dev/null 2>&1
NOLINTCONTENT=$(cat "$TMP5/nolint.ts")
if [ "$NOLINTCONTENT" = "var  b=2" ]; then PASS=$((PASS+1)); echo "  ok   — no-op when no formatter/linter config present"
else FAIL=$((FAIL+1)); echo "  FAIL — file modified with no config present: $NOLINTCONTENT"; fi
rm -rf "$TMP5"

# Monorepo (ADR-0012): config in a subfolder (apps/<name>/), edited file deeper.
# The old root-only guard would NOT find it; nearest-config detection must.
TMP6=$(mktemp -d)
mkdir -p "$TMP6/apps/web/app"
echo '{}' > "$TMP6/apps/web/.prettierrc"        # config in the app subfolder, NOT repo root
printf 'const  q=1' > "$TMP6/apps/web/app/page.ts"
mkdir -p "$TMP6/fakebin"
cat > "$TMP6/fakebin/npx" << 'FAKEEOF6'
#!/bin/bash
for arg; do case "$arg" in *.ts|*.js|*.jsx|*.tsx) printf 'FORMATTED' > "$arg" ;; esac; done
FAKEEOF6
chmod +x "$TMP6/fakebin/npx"
PATH="$TMP6/fakebin:$PATH" bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMP6/apps/web/app/page.ts\"}}' | CLAUDE_PROJECT_DIR='$TMP6' bash '$HOOK'" >/dev/null 2>&1
MONO=$(cat "$TMP6/apps/web/app/page.ts")
if [ "$MONO" = "FORMATTED" ]; then PASS=$((PASS+1)); echo "  ok   — nearest-config: formats via a subfolder config (monorepo, ADR-0012)"
else FAIL=$((FAIL+1)); echo "  FAIL — nearest-config not found in subfolder (content: $MONO)"; fi
rm -rf "$TMP6"

summary
