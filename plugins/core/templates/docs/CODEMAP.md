# CODEMAP — what the code does not say (Layer 2: stable)

> CONTRACT: only what an agent CANNOT guess by reading the code —
> the macro view (module boundaries, data flow) and cross-cutting gotchas.
> NO file-by-file (roles, imports, test locations: greppable, it would drift).
>
> **Path-scoped coupling rules live in `.claude/rules/`** (native, `paths:`
> frontmatter — loaded automatically when a matching file is read/edited).
> This file holds the big picture and the gotchas that aren't tied to one path.
> Maintenance: /core:codemap (after a refactor that changes module boundaries).

## Project layout (ADR-0012)
The Claude Code **control-plane stays at the repo root**: `.claude/`, `docs/`,
`orchestrator/`, `tests/hooks/`, `conception/`, and the root contract files. **Product
code lives under `apps/<name>/`** (deployable front-/back-ends) and **`packages/<name>/`**
(shared libs), as **npm workspaces**. Even a single app nests under `apps/` — never at the
repo root. Formatter/linter configs are per-app; the format hook finds the nearest one.

## Macro view
_(Filled by /core:new-project or /core:codemap: the 3-5 modules and how they depend on
each other. One paragraph or a small diagram — the map, not the territory.)_

## Cross-cutting gotchas
_(Non-obvious, project-wide traps. Path-specific rules go in `.claude/rules/`.)_
- _(example — replace via /core:new-project)_ All timestamps are stored UTC; the API
  layer is the only place that localizes.
