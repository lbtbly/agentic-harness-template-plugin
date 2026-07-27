---
Status: Accepted
Date: 2026-07-27
---

# ADR-0031 — Third-party design plugins via project settings, gated to UI projects

## Context

The harness had no frontend design surface: nothing prevented AI-slop UI, no visual
direction mechanism, no design review beyond the spec-level `design-reviewer` agent. Two
external Claude Code plugins cover the gap and complement each other:

- **impeccable** (`pbakaus/impeccable`) — design *quality*: the `/impeccable` skill
  (23 commands), 4 agents, and self-contained hooks (PostToolUse detector pass on the
  touched file, Stop deep pass over the session's UI files, ~60 deterministic anti-pattern
  rules). Hooks need Node ≥ 22 and degrade to a one-time notice without it.
- **styles-library** (`lbtbly/styles-library`) — design *direction*: 18 reusable style
  briefs and a `style-picker` skill that auto-triggers when UI work starts with no fixed
  direction, proposing a primary + alternate with rationale.

The composition question: vendor them, add them as marketplace entries, depend on them
from a plugin manifest, or declare them in scaffolded project settings?

## Decision

Projects scaffolded by `/core:new-project` that answer **web UI** to the new UI-surface
question get `templates/settings-design.json` deep-merged (jq, additive-only) into their
`.claude/settings.json`: both marketplaces under `extraKnownMarketplaces` with
`autoUpdate: true`, both plugins under `enabledPlugins`. Claude Code then prompts anyone
who trusts the repo to install them, and refreshes them in the background (third-party
marketplaces default auto-update off; the flag opts in). Backend-only projects get
nothing.

The heavier model-driven commands are wired as a CLAUDE.md workflow rule ("`/impeccable
audit` before a UI feature is done, `/impeccable polish` before shipping; direction comes
from the styles-library brief in DESIGN.md"), **not** as a harness hook — impeccable's own
Stop deep pass already covers detector-level slop for free, and a per-Stop audit would be
slow and expensive.

The harness does **not**: vendor either plugin, add them as marketplace entries (the
marketplace stays at 5), declare cross-marketplace manifest dependencies, or wire them
into the orchestrator DoD judge lenses (deliberately deferred).

`lbtbly/styles-library` stays **private** by owner choice: the declaration still ships;
install succeeds only with GitHub access to the repo and fails gracefully elsewhere. The
scaffolder's printed guidance says so.

## Consequences

- Setup, trigger and update are all delegated to native Claude Code mechanisms: the trust
  prompt installs, the plugins' own hooks/skill descriptions trigger, `autoUpdate` keeps
  them current. The only coupling is two keys in a scaffolded settings file.
- Updates propagate only when the upstream plugin bumps its `version` (the update cache
  key) — for styles-library that discipline is on its owner.
- The base `templates/settings.json` stays byte-stable (permissions-only): upgrade mode
  offers the design block as one additive proposal instead of diffing every provisioned
  project.
- Revisit if: a UI axis lands in `profiles.json`, the orchestrator DoD gains a design
  lens that should call `/impeccable audit` as evidence, or styles-library goes public.
