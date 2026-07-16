#!/bin/bash
# SessionStart: orients Claude without burning turns on discovery.
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
echo "## Session context (auto-injected)"
echo "Branch: $(git branch --show-current 2>/dev/null | grep . || echo 'detached')"
echo "### Last 5 commits"
git log --oneline -5 2>/dev/null
DIRTY=$(git status --porcelain 2>/dev/null | head -20)
[ -n "$DIRTY" ] && { echo "### Uncommitted modified files"; echo "$DIRTY"; }
echo "### Detected stack"
[ -f package.json ] && echo "- Node ($(jq -r '.name + " " + (.version // "")' package.json 2>/dev/null))"
[ -f pyproject.toml ] && echo "- Python (pyproject.toml)"
[ -f Cargo.toml ] && echo "- Rust (Cargo.toml)"
[ -f go.mod ] && echo "- Go (go.mod)"
exit 0
