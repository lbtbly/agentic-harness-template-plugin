---
name: codemap
description: Updates docs/CODEMAP.md (macro view, coupling rules, gotchas) and detects coupling violations. Run after a refactor that changes module boundaries.
context: fork
agent: general-purpose
---

# /core:codemap

> Runs FORKED (general-purpose agent — it must keep Write for the CODEMAP
> update); the survey detail stays out of the main context.

1. **Check violations**: for each coupling rule in `.claude/rules/*.md`
   (its `paths:` frontmatter = the scope), grep the imports/references within
   that scope and cross-check against the rule. List each violation: file:line,
   rule violated.
2. **Detect drift**: `paths:` globs that no longer match anything, rules citing
   modules that no longer exist → propose the fix.
3. **Update** (with confirmation): coupling rules in `.claude/rules/`
   (one file per bounded context) and, in `docs/CODEMAP.md`, the macro view +
   cross-cutting gotchas discovered during the session (pull "Failed attempts"
   from `orchestrator/bin/orch state pull-session` — legacy: docs/HANDOFF.md —
   and SUGGESTIONS).

STRICT CONTRACT: NEVER generate file-by-file content (a file's role, its
imports, its tests — derivable by grep, it would drift). Only what the
code does not say: coupling, intent, gotchas.
