#!/bin/bash
# ADR structure: this repo keeps its own decision log (dogfooding what the
# plugin scaffolds), and every ADR number cited in shipped plugin files must
# resolve to a real docs/adr/ file — no dangling decision references.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
R=".."

[ -d "$R/docs/adr" ]; check "docs/adr exists" $?
[ -f "$R/docs/adr/0001-record-architecture-decisions.md" ]; check "ADR-0001 (record decisions) exists" $?
[ -f "$R/docs/adr/README.md" ]; check "docs/adr/README.md exists" $?

# every ADR cited in shipped plugin files resolves
miss=0
for n in $(grep -rho "ADR-00[0-9][0-9]" "$R/plugins" | sort -u | sed 's/ADR-//'); do
  ls "$R/docs/adr/$n-"*.md >/dev/null 2>&1 || { echo "         dangling citation: ADR-$n (no docs/adr/$n-*.md)"; miss=1; }
done
check "every ADR cited in plugins/ resolves to docs/adr/" $miss

# the five verified deviations are recorded as decisions
for topic in judge risk auth sandbox; do
  ls "$R/docs/adr/"*"$topic"*.md >/dev/null 2>&1; check "a deviation ADR covers '$topic'" $?
done
grep -rlq "gated" "$R/docs/adr/" --include="*flavor*"; check "a deviation ADR covers the default flavor" $?

# every ADR carries a Status line (the immutability hook keys on it)
bad=0
for f in "$R/docs/adr/"00*.md; do
  head -12 "$f" | grep -qiE '^Status[[:space:]]*:' || { echo "         no Status: $f"; bad=1; }
done
check "every ADR carries a Status line" $bad

# dangling ADR references inside docs/adr/ itself must be annotated as historical
miss=0
for n in $(grep -rho "ADR-00[0-9][0-9]" "$R/docs/adr" | sort -u | sed 's/ADR-//'); do
  ls "$R/docs/adr/$n-"*.md >/dev/null 2>&1 && continue
  # absent ADR: every file citing it must carry the historical annotation
  for f in $(grep -rl "ADR-$n" "$R/docs/adr" ); do
    grep -q "historical, unported" "$f" || { echo "         unannotated dangling ADR-$n in $f"; miss=1; }
  done
done
check "dangling ADR refs in docs/adr are annotated as historical" $miss

# DEVIATIONS.md stays the research log and points at the decisions
grep -q "docs/adr" "$R/docs/DEVIATIONS.md"; check "DEVIATIONS.md points to the ADRs" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
