---
Status: Accepted
Date: 2026-07-16
---

# ADR-0020 — Native OS sandbox on top of the devcontainer

## Context
Claude Code now ships an OS-level sandbox (macOS Seatbelt / Linux bubblewrap)
with filesystem write-scoping, credential deny/mask, and a network allowlist
(code.claude.com/docs/en/sandboxing.md). The manual's control was a
devcontainer with a default-deny egress firewall.

## Decision
`settings.orchestrator.json` enables the native sandbox
(`enabled: true, allowUnsandboxedCommands: false`) in ADDITION to the
devcontainer precondition — not instead of it. `failIfUnavailable` stays false
because the devcontainer is the outer wall on runners where the OS sandbox is
missing.

## Consequences
Two independent isolation layers for unattended runs; on CI the devcontainer
remains mandatory (enable-orchestrator precondition #4).
