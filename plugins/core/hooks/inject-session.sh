#!/bin/bash
# SessionStart: injects Layer 3 (session resume) from the state layer
# (ADR-0007). Fail-open chain — a slow/VPN-gated board must NEVER stall a
# session start:
#   1. .orch/sessions/<branch>.json   (none backend — pure local read)
#   2. orch state pull-session        (remote backend, timeout-wrapped)
#   3. .orch/cache/session-<branch>.json  (offline mirror of last push)
#   4. docs/HANDOFF.md                (legacy fallback)
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null
R="${CLAUDE_PROJECT_DIR:-.}"

BR=$(git -C "$R" branch --show-current 2>/dev/null); [ -n "$BR" ] || BR=detached
SLUG=$(printf '%s' "$BR" | tr '/' '-' | tr -c 'a-zA-Z0-9._-' '-')

render() { # render <session.json file>
  echo "## Session resume (state layer — orch state pull-session)"
  jq -r '
    def list(k; title): if (.[k] // []) | length > 0
      then "### \(title)\n" + ((.[k]) | map("- " + .) | join("\n")) else empty end;
    (if .branch then "Branch: \(.branch)" else empty end),
    (if .spec then "Spec: \(.spec)" else empty end),
    (if .status then "Status: \(.status)" else empty end),
    list("failedAttempts"; "Failed attempts (do not retry blindly)"),
    list("blockers"; "Blockers"),
    list("nextSteps"; "Next steps"),
    (if .testStatus then "Tests: \(.testStatus | tojson)" else empty end),
    (if .auto then "\n_Auto snapshot (pre-compaction): \(.auto | tojson)_" else empty end)
  ' "$1" 2>/dev/null
  echo ""
  echo "(If the work described is finished or obsolete, flag it and suggest /handoff.)"
}

# 1. none backend — direct local read
F="$R/.orch/sessions/$SLUG.json"
if [ -f "$F" ] && [ -s "$F" ]; then render "$F"; exit 0; fi

# 2. remote backend via orch, timeout-wrapped (never block startup)
ORCH="$R/orchestrator/bin/orch"
CFG="$R/orchestrator/state.config.json"
if [ -x "$ORCH" ] && [ -f "$CFG" ] && [ "$(jq -r '.backend // "none"' "$CFG" 2>/dev/null)" != "none" ]; then
  if command -v timeout >/dev/null 2>&1; then
    OUT=$(timeout 3 "$ORCH" state pull-session --branch "$BR" 2>/dev/null || true)
  elif command -v gtimeout >/dev/null 2>&1; then
    OUT=$(gtimeout 3 "$ORCH" state pull-session --branch "$BR" 2>/dev/null || true)
  elif command -v perl >/dev/null 2>&1; then
    # macOS has no timeout(1) — perl alarm is the portable stall guard
    OUT=$(perl -e 'alarm 3; exec @ARGV' "$ORCH" state pull-session --branch "$BR" 2>/dev/null || true)
  else
    OUT=$("$ORCH" state pull-session --branch "$BR" 2>/dev/null || true)
  fi
  if [ -n "$OUT" ] && [ "$OUT" != "{}" ]; then
    TMPF=$(mktemp); echo "$OUT" > "$TMPF"; render "$TMPF"; rm -f "$TMPF"; exit 0
  fi
fi

# 3. offline cache mirror
C="$R/.orch/cache/session-$SLUG.json"
if [ -f "$C" ] && [ -s "$C" ]; then render "$C"; exit 0; fi

# 4. legacy HANDOFF.md
H="$R/docs/HANDOFF.md"
if [ -f "$H" ]; then
  echo "## HANDOFF — session resume (docs/HANDOFF.md — legacy fallback)"
  cat "$H"
  echo ""
  echo "(If the work described is finished or obsolete, flag it and suggest /handoff.)"
fi
exit 0
