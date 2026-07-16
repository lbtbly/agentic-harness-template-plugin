#!/bin/bash
# deploy.sh — thin hook to the product's OWN staging deploy (filled at
# /orchestrator:enable-orchestrator). Receives the branch to deploy as $1
# (default: orch/integration). MUST print the staging URL(s)/routes on stdout —
# the digest links them in the human test sequence.
# Credentials: OIDC/WIF or the runner's secret store — never in this file
# (docs/SECURITY.md).
set -eu
BRANCH="${1:-orch/integration}"

echo "deploy.sh is the unconfigured template — /orchestrator:enable-orchestrator fills this in." >&2
echo "Wanted: deploy branch '$BRANCH' to staging and print its URL." >&2
exit 64
