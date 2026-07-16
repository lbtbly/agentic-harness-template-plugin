---
Status: Accepted
Date: 2026-07-02
---

# ADR-0009 — Accept the `settings.json` Bash-redirection gap as a documented limitation

## Context
`protect-paths.sh` blocks `Edit|Write` on `.claude/settings.json` (an agent must not
widen its own permissions). But the hook matches only file-tool events: a Bash
redirection (`jq … > .claude/settings.json`) is not intercepted. This gap predates the
modular refactor; the refactor *depends* on it (the `compose-settings.sh` assembler
regenerates `settings.json` via Bash). Options considered:

1. **Accept and document** the gap (status quo).
2. A Bash-matcher hook blocking redirections targeting `settings*.json`, with a one-shot
   `.claude/.composing` sentinel the composer creates and removes.

## Decision
Option 1 — accept and document. Rationale: option 2 is defeated by the same power it
tries to contain (an agent that can run Bash can recreate the sentinel, use `tee`, `dd`,
`python -c`, or a hundred other write paths); a pattern-blacklist over Bash is an arms
race, not a boundary. The real boundaries remain: `defaultMode: plan` +
`disableBypassPermissionsMode` (a human approves Bash calls in normal use), the sandbox
with default-deny egress for unattended runs, and human review of any PR that touches
`settings*.json`.

## Consequences
- `compose-settings.sh` works without ceremony; the gap is documented here and in
  `docs/SECURITY.md` rather than half-closed.
- The `Edit|Write` block stays valuable: it stops the *accidental* self-modification
  path (the common case), not a determined adversary — which no in-process hook can.
- If Claude Code ever ships kernel-level file protections for settings, revisit with a
  superseding ADR.
