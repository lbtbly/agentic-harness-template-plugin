---
Status: Accepted
Date: 2026-07-17
---

# ADR-0022 — Claude-Code-native by design (no AGENTS.md interoperability)

## Context
The 2026 baseline for agentic coding environments treats AGENTS.md as the
canonical cross-tool instruction file (Linux Foundation governance, read by
Codex/Copilot/Cursor and 30+ agents), with CLAUDE.md as a symlink or @import.
This marketplace ships a single CLAUDE.md and no AGENTS.md — a consequence
inherited from the reference implementation's decision (its ADR-0005) whose
rationale was never ported here, leaving the deviation undocumented (flagged
by the 2026-07-17 market audit, AUDIT.md D1/D10).

## Decision
Stay Claude-Code-native, deliberately. The product's edge is not the
instruction file — it is the ENFORCEMENT and AUTONOMY layer: PreToolUse guard
hooks, policy toggles, permission profiles, plan-mode defaults, worktree
subagents, the orchestrator loop. None of that is expressible in the portable
AGENTS.md subset; a cross-tool file would carry the prose while every gate it
relies on silently vanished on other tools — a worse failure mode than honest
vendor specificity. One canonical CLAUDE.md, no duplicate per-tool files, no
symlink.

## Consequences
- Projects scaffolded by /core:new-project are first-class only under Claude
  Code; other agents see no instruction file. Teams needing multi-tool support
  should NOT adopt the autonomous profile of this harness.
- Revisit when a portable enforcement standard (hooks-equivalent) exists —
  the trigger to supersede this ADR, not a reason to pre-emptively split files.
- README states the position ("Claude Code native, by design").
