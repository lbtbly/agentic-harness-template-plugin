#!/bin/bash
# Subsystem 4c — secrets stay secret: layer 3 of defense in depth (gitignore +
# deny rules + this hook). Names, never values.
cd "$(dirname "$0")" || exit 1
source ./helpers.sh
HOOK=../plugins/core/hooks/secret-guard.sh

assert_exit 2 "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/p/.env"}}' "blocks Read .env"
assert_exit 2 "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/p/.env.production"}}' "blocks Read .env.production"
assert_exit 0 "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/p/.env.example"}}' "allows .env.example"
assert_exit 2 "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/p/certs/server.pem"}}' "blocks .pem"
assert_exit 2 "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/p/keys/deploy.key"}}' "blocks .key"
assert_exit 2 "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/p/secrets/db.json"}}' "blocks secrets/"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' "blocks cat .env"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"grep KEY .env.local | head"}}' "blocks pipe on .env.local"
assert_exit 0 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"cp .env.example .env"}}' "allows bootstrap cp .env.example .env"
assert_exit 0 "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/p/src/environment.ts"}}' "allows normal code with env in the name"
assert_exit 2 "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"/p/.env"}}' "blocks Edit .env"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"cat secrets/db.json"}}' "blocks relative secrets/"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"cat \".env\""}}' "blocks .env in double quotes"
assert_exit 2 "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"cat '\''.env'\''"}}' "blocks .env in single quotes"
assert_exit 0 "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/p/docs/secrets-management.md"}}' "allows secrets- in a file name"
summary
