# CLAUDE.md — project contract (always loaded)

<!-- SECURITY & NON-NEGOTIABLES FIRST (lost-in-the-middle: the constraints that
     must never be missed go at the very top, before anything else). -->

## Non-negotiable rules
1. **Secrets**: never read/write `.env*` (except `.env.example`), `*.pem`, `*.key`,
   `secrets/`. Handle variable NAMES, never values. Details: `docs/SECURITY.md`.
2. **Tests are the guardrail**: never delete or weaken a test to make it pass — fix
   the code, or flag the test explicitly. For orchestrated work the per-epic
   `feature_list.json` is the contract: **it is unacceptable to remove or edit its
   tests/steps — only flip a `passes` field to `true`, and only after a real
   end-to-end pass.**
3. **ADR before structural change**: consult `docs/adr/`; if the decision is new,
   draft an ADR (`architect` agent). An accepted ADR is never modified — it is superseded.
4. **Simplicity**: ruthless YAGNI. Flag unjustified complexity; no abstraction before
   the 2nd real usage.

## Project
_(placeholder — set at /core:new-project: name, one-paragraph purpose, current phase)_

## Commands
- Build: _(fill in)_
- Test: `bash tests/run-tests.sh` (scaffolded smoke + epic tests; add the app suite here)
- Lint/format: _(fill in — also picked up by formatting's format-on-edit hook)_

## Verification loop
Define the success criterion up front as a verifiable goal, then loop to it. After a
series of changes: run typecheck + tests + lint and fix until green. For anything with a
runtime surface, **verify like a user** — drive the app end-to-end (browser automation),
not only unit tests. Never declare "done" without showing the verification output. Fix the
root cause, not the symptom.

## 3-layer memory
- **Layer 1 (this file)**: conventions, pointers. Short — every detail lives elsewhere.
- **Layer 2 (reference)**: `.claude/rules/` (path-scoped coupling rules),
  `docs/CODEMAP.md` (macro view + gotchas), `docs/STACK.md` (the WHAT), `docs/adr/` (the WHY).
- **Layer 3 (session)**: `orchestrator/bin/orch state` (state layer; `.orch/` files when
  the backend is `none`). Injected at startup, written by `/core:handoff`.

## Workflow
- Think before coding: state assumptions, surface tradeoffs, ask before guessing.
- Plan mode for anything touching >2 files or with an uncertain approach; skip for trivial fixes.
- Reviews go to the fresh-context `code-reviewer` agent (correctness + requirements
  deviations); style is the format hook's job.
- A recurring mistake becomes a rule line in `.claude/rules/code-standards.md`.

## Repository etiquette
- Commits: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`).
- Never `--no-verify` (a hook blocks it). Commit/push only when asked.
- Branch naming: _(fill in)_

## End of session
Run `/core:handoff` before leaving (the Stop hook reminds you): session push +
changelog fragment + status propagation.

## Installed plugins
_(filled at /core:new-project — the confirmed set (with their
`/plugin install …@harness` commands, ending in `/reload-plugins` —
skills stay `Unknown command` until reload). e.g. core,
formatting, orchestrator. Each plugin's skills are namespaced
`/<plugin>:<skill>`.)_

## Where things live
| Need | Go to |
|---|---|
| Why a choice was made | `docs/adr/` |
| Coupling rules (path-scoped) | `.claude/rules/` |
| Macro view, cross-cutting gotchas | `docs/CODEMAP.md` |
| Stack, services, env var names | `docs/STACK.md` + `.env.example` |
| Session state, next steps | `orch state pull-session` (`none`: `.orch/sessions/`) |
| Product code (apps, shared libs) | `apps/<name>/` + `packages/<name>/` (npm workspaces) |
| Turn on autonomous mode | install `orchestrator`, then `/orchestrator:enable-orchestrator` |
