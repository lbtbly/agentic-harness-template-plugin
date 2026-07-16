---
name: project-conventions
description: Project conventions — preloaded into code-reviewer, architect and docs-writer via the skills field. Do not invoke directly.
disable-model-invocation: true
---

# Project conventions

- **Coupling rules and gotchas**: docs/CODEMAP.md — sections tagged by
  glob; any edit within a tagged scope respects its constraints.
- **Stack and services**: docs/STACK.md. **Decisions**: docs/adr/ (immutable
  once accepted — they get superseded).
- **Simplicity**: ruthless YAGNI; no abstraction before the 2nd real usage;
  unjustified complexity is a defect to flag.
- **Secrets**: variable names only, never values (docs/SECURITY.md).
- **Docs**: CODEMAP without file-by-file; CHANGELOG = Keep a Changelog + Decided;
  ROADMAP = dynamic; conception/ = frozen.
