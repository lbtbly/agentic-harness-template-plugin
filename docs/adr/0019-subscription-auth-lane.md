---
Status: Accepted
Date: 2026-07-16
---

# ADR-0019 — Subscription token is the primary headless auth lane

## Context
Unattended runs don't require a metered API key: `claude setup-token` issues a
~1-year `CLAUDE_CODE_OAUTH_TOKEN` usable in CI on a Pro/Max subscription.
Verified July 2026 (code.claude.com/docs/en/authentication.md): precedence is
cloud vars → ANTHROPIC_AUTH_TOKEN → ANTHROPIC_API_KEY → apiKeyHelper →
CLAUDE_CODE_OAUTH_TOKEN → stored login; and `--bare` skips OAuth/keychain reads
entirely, so it silently breaks the subscription lane.

## Decision
Every runtime template (github-actions.yml, gitlab-ci.yml, routines.md)
documents the subscription lane first, the metered `ANTHROPIC_API_KEY` lane as
the alternative (noting its precedence), and no actual `claude` invocation uses
`--bare` (enforced by `tests/test-plugin-manifests.sh`).

## Consequences
Overnight runs ride the subscription by default; a runner that sets both
credentials bills the API key — the templates say so out loud.
