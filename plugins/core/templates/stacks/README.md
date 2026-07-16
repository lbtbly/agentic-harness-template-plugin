# Stack packs

Per-language code-standards packs that `/core:new-project` copies into place:

- `stacks/<lang>.md` → `.claude/rules/<lang>.md` (path-scoped standards for the
  chosen language). Also drop the matching linter/formatter config at the repo
  root so `format-on-edit.sh` (format + lint-fix, from the `formatting`
  plugin) activates.

These packs live in the `core` plugin's `templates/` and are read at
scaffold time via `${CLAUDE_PLUGIN_ROOT}`. Write lint/format error messages as
remediation instructions — a failing lint is a prompt to the next agent.
