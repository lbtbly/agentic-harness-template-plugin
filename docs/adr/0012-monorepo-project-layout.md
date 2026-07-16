---
Status: Accepted
Date: 2026-07-06
---

# ADR-0012 — Monorepo project layout: control-plane at root, product code under `apps/*` + `packages/*`

## Context
A composed project has no convention for *where application code lives*. The template
ships a rich **control-plane** at the repo root — `.claude/`, `docs/`, `orchestrator/`,
`tests/hooks/` (plus `CLAUDE.md`, `CHANGELOG.md`, `.env.example`, `.mcp.json`,
`.gitignore`) — but says nothing about the product it is meant to build.

In testing this bit us: a scaffolded Next.js app landed **at the repo root** —
`app/`, `node_modules/`, `package.json`, `next.config.ts` intermixed with the
control-plane. Two problems follow:

- **It doesn't scale past one app.** A second front-end or a back-end service has
  nowhere to go without colliding names (`package.json`, `node_modules/`, framework
  configs) at the root.
- **It muddles two different things.** "The agent's operating environment" (the
  control-plane the template maintains) and "the product" (code the team ships)
  become indistinguishable — for humans reading the tree, for tooling that walks it,
  and for the orchestrator that partitions work by path.

This is a layout convention, not a change to any existing decision. It is orthogonal
to ADR-0006 (modular compose), which governs *control-plane composition* under
`.claude/`; this ADR governs *product-code placement* — a different axis.

## Decision
- **The control-plane stays at the repo root**, unchanged: `.claude/`, `docs/`,
  `orchestrator/`, `tests/hooks/`, `conception/` (if kept), and the root dotfiles /
  contract files (`CLAUDE.md`, `CHANGELOG.md`, `.env.example`, `.mcp.json`,
  `.gitignore`). This is the template's territory and the agent's operating
  environment.
- **Product code lives under two top-level trees**:
  - `apps/<name>/` — deployable applications (e.g. `apps/web`, `apps/api`).
  - `packages/<name>/` — shared libraries consumed by apps or other packages.
- **Managed as npm workspaces.** The root `package.json` declares
  `"workspaces": ["apps/*", "packages/*"]`. Each app/package is **self-contained**
  (its own `package.json`, framework configs, lint/format configs); dependencies
  hoist to a single root `node_modules`.
- **Single-app projects still use `apps/<name>/`** — never dump app files at the
  root. One app today is the common path to two apps tomorrow, and the
  control-plane/product split is worth keeping from the first commit.

## Consequences
- **`format-on-edit.sh` must become nearest-config-aware.** This is the key tooling
  change. Today the hook resolves the formatter/linter config from the repo root; with
  per-app configs under `apps/web/` (its own Prettier/ESLint/tsconfig), a root-only
  lookup never finds them and the hook **silently no-ops** on product code — the worst
  failure mode for a guardrail. The hook must walk **up** from the edited file to the
  nearest config and run that, falling back to root only when none is found.
- **Orchestrator footprint partitioning improves for free.** Footprints are already
  path-based (no code change needed); separate apps are naturally disjoint lanes, so
  `apps/web/**` and `apps/api/**` become clean, non-overlapping footprints and
  parallel work fans out along app boundaries.
- **`/new-project` and the docs become workspace-aware.** `/new-project` scaffolds /
  recommends apps into `apps/<name>/`, records the layout in `docs/CODEMAP.md` and
  `docs/STACK.md`, and CLAUDE.md's Commands become workspace-scoped
  (`npm -w apps/web run build`, etc.) rather than root-scoped.
- **Trade-off: slightly more ceremony for a trivial single-file project** — one
  nested directory and a workspace root for what could have been a lone file. Accepted:
  the control-plane/product separation pays for itself the moment a second app, a
  shared package, or an orchestrator lane appears, and it keeps the template's own
  files legible next to arbitrary product code.
- **No prior ADR is changed.** This adds a layout convention and does **not** amend or
  supersede any existing decision. It **complements ADR-0006**: modules govern how the
  control-plane under `.claude/` is composed; this ADR governs where product code sits.
  The two axes are independent and compose cleanly.
