---
name: setup
description: Scaffolds the chosen CI forge's workflow files (GitHub Actions and/or GitLab CI) from the ci plugin into the current project. Run after installing ci; /core:new-project recommends it when a forge was chosen.
---

# /ci:setup

Plugins can't write files at install, so this skill copies the CI templates from
`${CLAUDE_PLUGIN_ROOT}/templates/` into the project. The workflow paths are
policy-protected (`protect-policy-paths`), so write them via Bash with the user's OK.

1. **Ask which forge** (unless obvious from the project): `github` · `gitlab` · `both`.

2. **Scaffold**:
   - github → `mkdir -p .github/workflows && cp "${CLAUDE_PLUGIN_ROOT}/templates/github/"*.yml .github/workflows/`
     (`claude.yml` = PR assistant, `claude-review.yml` = auto-review). Tell the user to set
     ONE auth secret: `CLAUDE_CODE_OAUTH_TOKEN` (subscription, from `claude setup-token` —
     preferred, ADR-0019) or `ANTHROPIC_API_KEY` (metered; takes precedence if both are set).
   - gitlab → merge `${CLAUDE_PLUGIN_ROOT}/templates/gitlab/.gitlab-ci.yml` into the project's
     `.gitlab-ci.yml` (create it if absent). Tell the user to set ONE auth
     variable — `CLAUDE_CODE_OAUTH_TOKEN` (subscription, preferred) or `ANTHROPIC_API_KEY`
     (metered) — as **masked + protected** CI/CD variables.

3. **Do NOT** put a secret value in any file — only names. **Do NOT** enable the nightly
   orchestrator here (that is `/orchestrator:enable-orchestrator`, which installs
   its own scheduled runtime).

4. **Report** what was written and the exact secret/variable names the user must set in the
   forge UI, then propose a commit `ci: add <forge> workflows`.
