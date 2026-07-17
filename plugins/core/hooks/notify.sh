#!/bin/bash
# notify.sh: best-effort desktop/terminal alert when Claude needs attention.
# Wired to the Notification event (permission needed / idle). Never blocks —
# always exits 0. Silent in CI / non-interactive and when CLAUDE_NOTIFY_DISABLE
# is set. Add it to the Stop event too if you want turn-completion pings.
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null
command -v jq >/dev/null 2>&1 || { echo "notify: jq missing — advisory hook skipped" >&2; exit 0; }
INPUT=$(cat)
NTYPE=$(echo "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)
MSG=$(echo "$INPUT" | jq -r '.message // empty' 2>/dev/null)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Notification"' 2>/dev/null)

# Alert only for attention-worthy notifications; ignore transient/info types.
case "$NTYPE" in
  permission_prompt|idle_prompt|elicitation_dialog|"") : ;;
  *) exit 0 ;;
esac

# Escape hatch for tests / focus mode.
[ -n "$CLAUDE_NOTIFY_DISABLE" ] && exit 0

BODY="${MSG:-needs your attention}"
if command -v osascript >/dev/null 2>&1; then
  # Strip characters the shell would interpret inside the -e string
  # (double-quote, backtick, $, backslash) to avoid any command injection.
  SAFE_BODY=$(printf '%s' "$BODY" | tr -d '"`$\\')
  SAFE_EVENT=$(printf '%s' "$EVENT" | tr -d '"`$\\')
  osascript -e "display notification \"$SAFE_BODY\" with title \"Claude Code — $SAFE_EVENT\"" >/dev/null 2>&1
fi
printf '\a' > /dev/tty 2>/dev/null
exit 0
