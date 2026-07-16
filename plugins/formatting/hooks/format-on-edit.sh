#!/bin/bash
# Formats the edited file with THE REPO'S formatter, then auto-fixes with the
# repo's linter, detected via the NEAREST config from the edited file up to the
# repo root — works for flat AND monorepo/apps-* layouts (ADR-0012). Agnostic:
# graceful no-op if nothing is detected. Never blocking.
INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FP" ] && [ -f "$FP" ] || exit 0
R="${CLAUDE_PROJECT_DIR:-.}"
case "$FP" in "$R"/*) ;; *) exit 0 ;; esac
[ -L "$FP" ] && exit 0
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null

# have_up <name...> — 0 if any name exists at/above the edited file within $R
# (nearest-config: apps/<name>/ config wins over a root one).
have_up() {
  local d; d=$(cd "$(dirname "$FP")" 2>/dev/null && pwd) || return 1
  while :; do
    local f; for f in "$@"; do [ -e "$d/$f" ] && return 0; done
    [ "$d" = "$R" ] && return 1
    local up; up=$(dirname "$d"); [ "$up" = "$d" ] && return 1; d="$up"
  done
}

case "$FP" in
  *.js|*.jsx|*.ts|*.tsx|*.json|*.css|*.scss|*.md|*.yaml|*.yml)
    if have_up .prettierrc .prettierrc.json prettier.config.js prettier.config.mjs \
       && command -v npx >/dev/null 2>&1; then
      npx --no-install prettier --write "$FP" >/dev/null 2>&1
    fi ;;
  *.py)
    if have_up pyproject.toml && command -v ruff >/dev/null 2>&1; then
      ruff format "$FP" >/dev/null 2>&1
    fi ;;
  *.go) command -v gofmt >/dev/null 2>&1 && gofmt -w "$FP" 2>/dev/null ;;
  *.rs) have_up Cargo.toml && command -v rustfmt >/dev/null 2>&1 && rustfmt "$FP" 2>/dev/null ;;
esac

# Linter auto-fix after formatting — same nearest-config guards, never blocking.
case "$FP" in
  *.js|*.jsx|*.ts|*.tsx)
    if have_up eslint.config.js eslint.config.mjs eslint.config.cjs .eslintrc.json .eslintrc.js .eslintrc.cjs \
       && command -v npx >/dev/null 2>&1; then
      npx --no-install eslint --fix "$FP" >/dev/null 2>&1
    fi ;;
  *.py)
    if have_up pyproject.toml && command -v ruff >/dev/null 2>&1; then
      ruff check --fix "$FP" >/dev/null 2>&1
    fi ;;
esac
exit 0
