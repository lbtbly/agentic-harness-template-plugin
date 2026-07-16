# STACK — the catalog (Layer 2: stable)

> CONTRACT: the WHAT. The WHY of each choice lives in the ADRs (link next to
> each line when an ADR exists). Maintained by /workbench:db-migration, /core:new-project
> and by hand.

## Project layout (ADR-0012)
Monorepo: the control-plane (`.claude/`, `docs/`, `orchestrator/`, `tests/hooks/`) stays at
the repo root; product code lives under `apps/<name>/` (deployable apps) + `packages/<name>/`
(shared libs) as **npm workspaces**. Per-app formatter/linter configs; the format hook uses
the nearest one.

## Language & runtime
_(fill in via /core:new-project)_

## Structural libraries
| Lib | Role | ADR |
|---|---|---|

## Third-party services
| Service | Usage | Env vars | ADR |
|---|---|---|---|

## LLM per feature
| Feature | Model | Estimated cost | ADR |
|---|---|---|---|

## Deployment & monitoring
_(target, short procedure, dashboards)_
