#!/bin/bash
# CI finding 2026-07-17: an unquoted ': ' inside a frontmatter value makes the
# WHOLE frontmatter unparseable — the skill loads with EMPTY metadata
# (description, disable-model-invocation… silently dropped). Lint every
# skill + agent frontmatter.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }

if python3 -c 'import yaml' 2>/dev/null; then
  # real YAML parse when available (GitHub runners preinstall PyYAML)
  bad=$(python3 - <<'PY'
import re, glob, yaml
bad=[]
for f in glob.glob('../plugins/*/skills/*/SKILL.md') + glob.glob('../plugins/*/agents/*.md'):
    s=open(f).read()
    m=re.match(r'^---\n(.*?)\n---\n', s, re.S)
    if not m: bad.append(f+" (no frontmatter)"); continue
    try:
        d=yaml.safe_load(m.group(1))
        if not isinstance(d, dict) or 'description' not in d: bad.append(f+" (no description after parse)")
    except Exception as e: bad.append(f+" ("+str(e).splitlines()[0]+")")
print("\n".join(bad))
PY
)
  [ -z "$bad" ]; check "every skill/agent frontmatter parses as YAML with a description" $?
  [ -n "$bad" ] && echo "$bad" | sed 's/^/         /'
else
  # heuristic fallback: unquoted single-line values must not contain ': '
  bad=0
  for f in ../plugins/*/skills/*/SKILL.md ../plugins/*/agents/*.md; do
    hit=$(awk '/^---$/{n++; next} n==1 && /^[a-z-]+: [^"'"'"' ].*: / {print FILENAME": "$0}' "$f")
    [ -n "$hit" ] && { echo "         $hit"; bad=1; }
  done
  [ "$bad" -eq 0 ]; check "no unquoted ': ' inside frontmatter values (heuristic; pyyaml gives the real parse)" $?
fi
echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
