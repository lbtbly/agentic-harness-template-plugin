#!/bin/bash
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
HOOK=../plugins/core/hooks/notify.sh

# Never fire real desktop notifications during tests.
export CLAUDE_NOTIFY_DISABLE=1

# The contract: notify never blocks — always exit 0, whatever the payload.
assert_exit 0 "$HOOK" '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"needs permission"}' "exit 0 on permission prompt"
assert_exit 0 "$HOOK" '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"waiting"}' "exit 0 on idle prompt"
assert_exit 0 "$HOOK" '{"hook_event_name":"Notification","notification_type":"auth_success"}' "exit 0 on ignored type"
assert_exit 0 "$HOOK" '{}' "exit 0 on empty object"
assert_exit 0 "$HOOK" '' "exit 0 on empty stdin"

unset CLAUDE_NOTIFY_DISABLE
summary
