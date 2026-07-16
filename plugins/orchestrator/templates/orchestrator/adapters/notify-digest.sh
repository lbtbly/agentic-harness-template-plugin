#!/bin/bash
# notify-digest.sh — deliver the morning digest to Slack and/or email at a
# user-chosen time (ADR-0008). Runs as its OWN scheduled job (separate from the
# night build); on CI it reads digests from the orch/state branch checkout.
# Sends a short "went well / needs attention" summary with the daily HTML file
# attached (email / Slack bot upload) or linked (Slack webhook).
#
# Config: orchestrator/notify.config.json  { channels, deliver_at, email_to, digest_url_base }
# Secrets (env NAMES only — never in the repo; docs/SECURITY.md):
#   Slack:  SLACK_WEBHOOK_URL   or  SLACK_BOT_TOKEN + SLACK_CHANNEL (channel ID)
#   Email:  SENDGRID_API_KEY    (or a mail/mailx with attachment support)
# NOTE (audit SEC-M1): delivery ships repo-derived content (epic titles, file
# paths, staging URLs) to external SaaS. VPN/data-residency teams: use an
# internal relay, or link-only webhook delivery — see docs/SECURITY.md.
# Thin + fail-soft: a delivery failure never breaks the loop (exit 0), it logs.
set -u
R="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CFG="$R/orchestrator/notify.config.json"
DIR="$R/docs/reports/nightly"

# Default: the NEWEST digest on disk (the build may have run 12:30 yesterday or
# resumed past midnight — "today's date" is wrong for both; audit L-I6).
DATE="${1:-}"
if [ -z "$DATE" ]; then
  NEWEST=$(ls -1 "$DIR"/[0-9]*.html 2>/dev/null | sort | tail -1)
  [ -n "$NEWEST" ] && DATE=$(basename "$NEWEST" .html)
fi
[ -n "$DATE" ] || { echo "notify-digest: no digest found in $DIR, skipping."; exit 0; }
HTML="$DIR/$DATE.html"
SUMMARY="$DIR/$DATE.summary.md"

[ -f "$CFG" ] || { echo "notify-digest: no config, skipping."; exit 0; }
[ -f "$HTML" ] || { echo "notify-digest: no digest for $DATE, skipping."; exit 0; }

channels=$(jq -r '.channels[]? // empty' "$CFG" 2>/dev/null)
email_to=$(jq -r '.email_to // empty' "$CFG" 2>/dev/null)
url_base=$(jq -r '.digest_url_base // empty' "$CFG" 2>/dev/null)
[ -n "$channels" ] || { echo "notify-digest: no channels enabled, skipping."; exit 0; }

if [ -f "$SUMMARY" ]; then BODY=$(cat "$SUMMARY"); else BODY="Nightly digest for $DATE is ready. Open the attached HTML for the full test sequence and per-PR risk flags."; fi
LINK="${url_base:+$url_base/$DATE.html}"

slack_ok() { jq -e '.ok == true' >/dev/null 2>&1; }

send_slack() {
  if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    # Webhook: summary text + link (webhooks cannot attach files).
    local text="*Nightly digest — $DATE*"$'\n'"$BODY"
    [ -n "$LINK" ] && text="$text"$'\n'"<$LINK|Open the full HTML digest>"
    jq -n --arg t "$text" '{text:$t}' | curl -sf -X POST -H 'Content-type: application/json' \
      -d @- "$SLACK_WEBHOOK_URL" >/dev/null && echo "notify-digest: posted to Slack." \
      || echo "notify-digest: Slack webhook failed (non-fatal)." >&2
  elif [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_CHANNEL:-}" ]; then
    # files.upload was retired by Slack in Nov 2025 (audit S-B2) — use the
    # two-step external upload, gating each step on {"ok":true} (Slack returns
    # HTTP 200 with ok:false on failure, so curl -f alone reports false success).
    local size up url fid resp
    size=$(wc -c < "$HTML" | tr -d ' ')
    up=$(curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
      --get --data-urlencode "filename=$DATE.html" --data-urlencode "length=$size" \
      https://slack.com/api/files.getUploadURLExternal)
    if ! echo "$up" | slack_ok; then
      echo "notify-digest: Slack getUploadURLExternal failed: $(echo "$up" | jq -r '.error // "unknown"') (non-fatal)." >&2; return
    fi
    url=$(echo "$up" | jq -r '.upload_url'); fid=$(echo "$up" | jq -r '.file_id')
    curl -s -X POST -F filename=@"$HTML" "$url" >/dev/null 2>&1
    resp=$(curl -s -X POST -H "Authorization: Bearer $SLACK_BOT_TOKEN" -H 'Content-type: application/json' \
      -d "$(jq -nc --arg fid "$fid" --arg t "$DATE.html" --arg ch "$SLACK_CHANNEL" \
             --arg c "Nightly digest — $DATE"$'\n'"$BODY" \
             '{files:[{id:$fid,title:$t}], channel_id:$ch, initial_comment:$c}')" \
      https://slack.com/api/files.completeUploadExternal)
    if echo "$resp" | slack_ok; then echo "notify-digest: uploaded digest to Slack."
    else echo "notify-digest: Slack completeUpload failed: $(echo "$resp" | jq -r '.error // "unknown"') (non-fatal)." >&2; fi
  else
    echo "notify-digest: Slack selected but no SLACK_WEBHOOK_URL / SLACK_BOT_TOKEN+SLACK_CHANNEL set (non-fatal)." >&2
  fi
}

send_email() {
  [ -n "$email_to" ] || { echo "notify-digest: email selected but email_to empty (non-fatal)." >&2; return; }
  local subject="Nightly digest — $DATE"
  if [ -n "${SENDGRID_API_KEY:-}" ]; then
    local B64F; B64F=$(mktemp)
    base64 < "$HTML" | tr -d '\n' > "$B64F"   # rawfile, not argv — big digests exceed ARG_MAX
    jq -n --arg to "$email_to" --arg subj "$subject" --arg body "$BODY" \
          --rawfile file "$B64F" --arg name "$DATE.html" '
      {personalizations:[{to:[{email:$to}]}],
       from:{email:"orchestrator@localhost"},
       subject:$subj,
       content:[{type:"text/plain",value:$body}],
       attachments:[{content:$file,type:"text/html",filename:$name,disposition:"attachment"}]}' \
      | curl -sf -X POST https://api.sendgrid.com/v3/mail/send \
        -H "Authorization: Bearer $SENDGRID_API_KEY" -H "Content-Type: application/json" -d @- >/dev/null \
      && echo "notify-digest: emailed via SendGrid." || echo "notify-digest: SendGrid send failed (non-fatal)." >&2
    rm -f "$B64F"
  elif command -v mail >/dev/null 2>&1; then
    # -A (attach) is GNU mailutils-only; BSD/macOS mail has none — fall back to link.
    if { printf '%s\n' "$BODY"; } | mail -s "$subject" -A "$HTML" "$email_to" 2>/dev/null; then
      echo "notify-digest: emailed via mail (with attachment)."
    else
      { printf '%s\n\n' "$BODY"; [ -n "$LINK" ] && printf 'Full digest: %s\n' "$LINK"; } \
        | mail -s "$subject" "$email_to" 2>/dev/null \
        && echo "notify-digest: emailed via mail (link only — no attachment support)." \
        || echo "notify-digest: mail send failed (non-fatal)." >&2
    fi
  else
    echo "notify-digest: email selected but neither SENDGRID_API_KEY nor 'mail' available (non-fatal)." >&2
  fi
}

for ch in $channels; do
  case "$ch" in
    slack) send_slack ;;
    email) send_email ;;
    *) echo "notify-digest: unknown channel '$ch' (skipped)." >&2 ;;
  esac
done
exit 0
