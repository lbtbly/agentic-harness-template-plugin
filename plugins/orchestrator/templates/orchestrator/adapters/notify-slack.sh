#!/bin/bash
# notify-slack.sh — per-project Slack notifications for the run loop.
#
#   bash orchestrator/adapters/notify-slack.sh <event> <text…>
#   echo "text" | bash orchestrator/adapters/notify-slack.sh <event>
#
# One channel per project: `cchar-<repo>`, created on first use. The channel is
# derived from the git toplevel (folder name outside a repo), lowercased and
# slugified — Slack rejects uppercase and most punctuation outright.
#
# ABSOLUTE RULES for this file:
#   * A notification may NEVER break a run. Every failure — no token, no network,
#     Slack 500, malformed reply — is non-fatal and exits 0. The loop's job is to
#     build software, not to talk about it.
#   * The token is never printed, never echoed back, and never written to a log.
#     Slack errors are surfaced by their `error` field only.
#
# Credentials, in precedence order (names only, never values):
#   $SLACK_BOT_TOKEN            — export it in your shell profile to cover every
#                                 project on the machine (recommended: one token,
#                                 one place to rotate)
#   ./.env  SLACK_BOT_TOKEN=…   — per-project override; parsed, never sourced,
#                                 because sourcing an env file executes it
#
# Scopes the token needs: chat:write, chat:write.public, channels:manage,
# channels:read.
#
# SANDBOX: `slack.com` must be uncommented in orchestrator/egress-allowlist.txt
# AND mirrored into settings.orchestrator.json + .devcontainer/init-firewall.sh,
# or every call fails closed. This script says so plainly when a call fails.
set -u

R="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
EVENT="${1:-note}"; shift 2>/dev/null || true
TEXT="$*"
[ -n "$TEXT" ] || TEXT=$(cat 2>/dev/null || true)
[ -n "$TEXT" ] || exit 0

say() { echo "notify-slack: $*" >&2; }

# --- token --------------------------------------------------------------------
token() {
  if [ -n "${SLACK_BOT_TOKEN:-}" ]; then printf '%s' "$SLACK_BOT_TOKEN"; return; fi
  # Parsed, not sourced: `. .env` would execute whatever is in the file.
  local f="$R/.env" v
  [ -f "$f" ] || return 1
  v=$(grep -m1 '^[[:space:]]*SLACK_BOT_TOKEN[[:space:]]*=' "$f" 2>/dev/null) || return 1
  v=${v#*=}
  v=$(printf '%s' "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}
TOKEN=$(token) || { exit 0; }   # not configured is the normal case, not an error

command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || {
  say "curl and jq are required — skipping."; exit 0; }

# --- channel name -------------------------------------------------------------
# Slack: lowercase letters, digits, hyphens, underscores; 80 chars max.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9_-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' \
    | cut -c1-80
}
project_channel() {
  [ -n "${ORCH_SLACK_CHANNEL:-}" ] && { printf '%s' "$(slugify "$ORCH_SLACK_CHANNEL")"; return; }
  local base
  base=$(git -C "$R" rev-parse --show-toplevel 2>/dev/null) || base="$R"
  # prefix first, then clamp, so a long repo name can never truncate the prefix away
  printf '%s' "$(slugify "${ORCH_SLACK_PREFIX:-cchar-}$(basename "$base")")"
}
CHANNEL=$(project_channel)
[ -n "$CHANNEL" ] || { say "could not derive a channel name — skipping."; exit 0; }

api() { # api <method> <json-body>
  curl -s --max-time 15 -X POST "https://slack.com/api/$1" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-type: application/json; charset=utf-8' \
    -d "$2" 2>/dev/null
}

# --- resolve the channel id, cached so a run does not re-list every notification -
CACHE="$R/.orch/cache/slack-channels.json"
mkdir -p "$(dirname "$CACHE")" 2>/dev/null || true
[ -f "$CACHE" ] || echo '{}' > "$CACHE" 2>/dev/null

cached_id() { jq -r --arg c "$CHANNEL" '.[$c] // empty' "$CACHE" 2>/dev/null; }
cache_id()  { local t; t=$(jq -c --arg c "$CHANNEL" --arg i "$1" '.[$c]=$i' "$CACHE" 2>/dev/null) \
              && printf '%s' "$t" > "$CACHE" 2>/dev/null || true; }

find_channel() { # paginate; a workspace can have more channels than one page
  local cursor="" resp id
  while :; do
    resp=$(curl -s --max-time 15 -G "https://slack.com/api/conversations.list" \
      -H "Authorization: Bearer $TOKEN" \
      --data-urlencode "types=public_channel" --data-urlencode "limit=200" \
      --data-urlencode "exclude_archived=true" --data-urlencode "cursor=$cursor" 2>/dev/null)
    [ -n "$resp" ] || return 1
    id=$(printf '%s' "$resp" | jq -r --arg c "$CHANNEL" '.channels[]? | select(.name==$c) | .id' 2>/dev/null | head -1)
    [ -n "$id" ] && { printf '%s' "$id"; return 0; }
    cursor=$(printf '%s' "$resp" | jq -r '.response_metadata.next_cursor // ""' 2>/dev/null)
    [ -n "$cursor" ] || return 1
  done
}

ID=$(cached_id)
if [ -z "$ID" ]; then
  ID=$(find_channel) || ID=""
  if [ -z "$ID" ]; then
    resp=$(api conversations.create "$(jq -nc --arg n "$CHANNEL" '{name:$n, is_private:false}')")
    ID=$(printf '%s' "$resp" | jq -r '.channel.id // empty' 2>/dev/null)
    if [ -z "$ID" ]; then
      # An EMPTY body is the sandbox signature (connection refused/blocked). jq
      # emits nothing for empty input, so `// "no response"` never fires — the
      # one diagnosis that matters most would be the one silently skipped.
      if [ -z "$resp" ]; then err="no response"
      else err=$(printf '%s' "$resp" | jq -r '.error // "no response"' 2>/dev/null); [ -n "$err" ] || err="no response"; fi
      case "$err" in
        name_taken) ID=$(find_channel) || ID="" ;;
        missing_scope|not_allowed_token_type)
          say "token lacks a scope (need chat:write, chat:write.public, channels:manage, channels:read)." ;;
        "no response")
          say "no reply from slack.com — if this run is sandboxed, uncomment slack.com in"
          say "orchestrator/egress-allowlist.txt and mirror it into settings.orchestrator.json"
          say "and .devcontainer/init-firewall.sh, or every call fails closed." ;;
        *) say "could not create #$CHANNEL: $err" ;;
      esac
    fi
  fi
  [ -n "$ID" ] && cache_id "$ID"
fi
[ -n "$ID" ] || exit 0

# --- post ---------------------------------------------------------------------
resp=$(api chat.postMessage "$(jq -nc --arg ch "$ID" --arg t "$TEXT" '{channel:$ch, text:$t, unfurl_links:false, unfurl_media:false}')")
if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null)" != "true" ]; then
  say "post to #$CHANNEL failed: $(printf '%s' "$resp" | jq -r '.error // "no response"' 2>/dev/null) (event=$EVENT)"
fi
exit 0
