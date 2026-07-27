#!/bin/bash
# UserPromptSubmit + SubagentStop observer (POLICY, default ON via `journal`).
#
# The half of the story the harness could never see: a human typing "no, that's
# wrong" is the ground truth that the agent made a mistake, and it is the only
# signal that distinguishes "the agent recovered on its own" from "a person had
# to intervene". Both are corrections; only one is cheap.
#
# Records a CLASSIFICATION of the prompt, never the prompt itself — user text is
# the most sensitive thing in the session and this file is meant to be exported.
# Advisory only: never blocks, always exits 0, and emits no stdout (stdout from a
# UserPromptSubmit hook is injected into the model's context).
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
. "$(dirname "$0")/policy-lib.sh" 2>/dev/null || exit 0
policy_enabled journal || exit 0

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)

if [ "$EVENT" = "SubagentStop" ]; then
  journal subagent_fail "$(printf '%s' "$INPUT" | jq -r '.agent_type // .subagent_type // "unknown"' 2>/dev/null)"
  exit 0
fi

P=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null | tr 'A-Z' 'a-z')
[ -n "$P" ] || exit 0

# Only correction-shaped prompts are recorded. An ordinary instruction is not a
# signal about the harness and has no business in an exportable log.
# Plain grep with explicit boundaries, not awk: BSD awk has no \< and its `exit`
# still runs END, so the awk version silently classified everything wrongly.
# Padding with spaces lets [^a-z] stand in for a word boundary portably.
PAD=" $(printf '%s' "$P" | tr -c 'a-z0-9' ' ') "
KIND=''
for rule in \
  'you (broke|missed|forgot)|still (broken|failing):regression_report' \
  'revert|undo|roll ?back:revert_request' \
  'no|nope|wrong|incorrect|not what:contradiction' \
  'actually|instead|rather than:redirect' \
  'again|retry:retry_request'; do
  pat=${rule%:*}; name=${rule##*:}
  if printf '%s' "$PAD" | grep -qE "[^a-z0-9](${pat})[^a-z0-9]"; then KIND=$name; break; fi
done
[ -n "$KIND" ] || exit 0

# Bucketed length only — a proxy for how much re-explaining the harness forced.
LEN=${#P}
if   [ "$LEN" -lt 80 ];  then BUCKET=short
elif [ "$LEN" -lt 400 ]; then BUCKET=medium
else                          BUCKET=long
fi
journal user_correction "$KIND" "$(jq -cn --arg b "$BUCKET" '{length:$b}')"
exit 0
