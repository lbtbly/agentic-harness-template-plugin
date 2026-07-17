---
Status: Accepted
Date: 2026-07-15
---

# ADR-0013 — Plugin-only distribution (supersedes ADR-0002)

> ADR-0002 / ADR-0014: historical, unported — decisions of the reference
> implementation this repo was distilled from; see docs/adr/README.md.

## Context
ADR-0002 chose **dual distribution**: a copy-the-tree standalone kit *and* an additive
plugin manifest. In practice the standalone path is the source of the exact problem the
harness playbook warns against — *"the harness (configs, lints, prompts) should be a
versioned, importable package, not per-project folklore."* A copied tree forks the harness:
every project drifts, and every fix has to be re-copied and re-diffed by hand. Maintaining
two surfaces in sync (compose-in-place *and* logically-gated plugin) also doubled the
composition machinery.

Since ADR-0002, two facts settled the question:
1. A plugin makes the harness a single versioned dependency many projects import and upgrade
   in place — the distribution model the playbook argues for.
2. Plugins **cannot scaffold at install** (no install hook); files reach a project only via a
   skill the user runs. So the standalone "copy then mutate in place" model and the plugin
   model cannot share one code path anyway.

## Decision
Distribute the harness **as plugins only**. Retire the standalone copy-the-tree path and the
dual-distribution framing of ADR-0002.
- The repo becomes a **plugin marketplace**: `.claude-plugin/marketplace.json` lists the
  plugins; each plugin has its own `.claude-plugin/plugin.json`.
- Skills are **always namespaced** (`/core:handoff`, `/orchestrator:kickoff`).
  The unnamespaced form disappears.
- Scaffolding a project is an explicit **skill the user runs** (`/core:new-project`),
  not a copied tree — see ADR-0014 for the decomposition and the scaffold-via-skill mechanism.
- `.claude-plugin/*` remains a protected distribution artifact (protect-policy-paths); the
  marketplace/plugin versions are bumped on release.

## Consequences
- One distribution surface. Fixes ship as a plugin version bump; adopters `/plugin update`.
- No `distribution` axis in `/new-project`; no `rm -rf .claude-plugin` standalone path.
- The development repo keeps a **dogfood-only** `.claude/settings.json` that points at the
  in-repo plugin hooks, so contributors get the guardrails without installing.
- Headless/CI runs must ensure the needed plugins are available on the runner
  (`--plugin-dir` / marketplace install) — called out in the orchestrator runtime templates.
- ADR-0002 is superseded.
