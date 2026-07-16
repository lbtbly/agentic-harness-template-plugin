#!/bin/bash
# statusline.sh: compact status line — branch · model · context%.
# Reads the statusline JSON on stdin. Branch is derived from git (it is not in
# the statusline payload). Pure shell + jq, no npm dependency — see
# docs/TOOLING.md for richer opt-in alternatives (ccstatusline, ccusage).
INPUT=$(cat)
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // .model.id // "?"' 2>/dev/null)
CTX=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)

BRANCH=$(git -C "${DIR:-.}" branch --show-current 2>/dev/null)

OUT="$MODEL"
[ -n "$BRANCH" ] && OUT="⎇ ${BRANCH} · ${OUT}"
[ -n "$CTX" ] && OUT="${OUT} · ctx ${CTX%.*}%"
printf '%s' "$OUT"
