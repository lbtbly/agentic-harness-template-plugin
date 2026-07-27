---
name: new-project
description: "Scaffolds or upgrades a project from the core templates: questionnaire, contracts, state layer, day-0 tests, then prints the install commands. Use at adoption or to upgrade."
disable-model-invocation: true
---

# /core:new-project (scaffolder)

Stands up a new project by **copying from `${CLAUDE_PLUGIN_ROOT}/templates/` into the
current directory** and personalizing it. Plugins cannot write files at install, so this
skill is the initializer that does it once (ADR-0013/0014). It does **not** mutate the
plugin and it does **not** park/compose anything — optional capabilities are added later by
*installing the matching plugin*.

0. **Execution context** (before anything):
   - Run this **in the target project directory** (empty or an existing repo you want to
     adopt the harness). It writes files into the cwd; it never touches the plugin.
   - **Existing scaffold → upgrade mode.** If scaffold markers are present (`CLAUDE.md`
     AND `orchestrator/bin/orch`), this is a re-init over a live project: switch to
     **adopt/upgrade mode** — add files the templates gained since, and for every file
     that already exists, DIFF template vs project and **propose** each change;
     **never overwrite a personalized file** (CLAUDE.md, docs/*, settings, configs are
     the user's). Skip the questionnaire items already answered (read them back from
     the scaffold) and re-confirm only what upgrade needs. Everything still lands on a
     safety branch as one reviewable commit.
   - **Dry run = plan mode.** To preview without changing anything, run under plan mode.
   - Create a **safety branch** first (e.g. `chore/init-project`) so initialization is one
     reviewable, revertible commit.
   - Under the default `plan` permission mode every Bash/Write prompts — switch to
     normal/acceptEdits for a real run, or approve each step.
   - **Project layout (ADR-0012)**: the control-plane (`.claude/`, `docs/`, `orchestrator/`,
     `tests/`, root contract files) stays at root; **product code goes under `apps/<name>/`**
     + `packages/<name>/` as npm workspaces — never scaffold an app at the repo root. Record
     the layout in CODEMAP/STACK and make CLAUDE.md Commands workspace-aware.
   - `T="${CLAUDE_PLUGIN_ROOT}/templates"` — the scaffold source for every copy below.
   - **Preflight (R6/R18)**: `command -v jq git` must both succeed — the guard hooks
     and state layer need them (guards FAIL CLOSED without jq, by design). Platform:
     macOS / Linux / WSL2; native Windows unsupported (POSIX shell hooks) — say so
     and stop rather than scaffolding a broken environment.

1. **Questionnaire.** Ask **fixed-option** items with `AskUserQuestion` (**≤4 options
   each**; nested follow-up when a real choice has >4 branches). Ask **free-text** items as
   plain conversational prompts — never as picker options.

   **Free-text (ask directly):**
   - **project name + one-sentence purpose** — ask first; don't proceed without the purpose
     (it seeds CLAUDE.md, README, STACK.md);
   - runtime versions (node/python/…) if runtime pinning is on; planned service names.

   **Fixed-option (`AskUserQuestion`, ≤4 each):**
   - **profile** — `poc` · `solo` · `team` · `autonomous`. If `solo`, follow up: `minimal`
     (= `solo-small`) vs `fuller` (= `solo-big`). Drives the pre-ticked plugin checklist
     (step 8) and guardrail strictness.
   - **state backend** (ADR-0007) — `none` (default: local sharded `.orch/`, zero-dep) ·
     `github-projects` · `gitlab` · `other remote` (follow-up: `jira`/`notion`/`linear`/
     `trello`). Recommend `none` for poc/solo; remote backends need node + a token env var
     and degrade to cache-reads offline — say so.
     **jira/notion follow-up**: create a **new board from the template**, or **adopt an
     existing board** (ask the user to paste its URL — a Notion database link or a Jira
     project/board link). **Jira always needs a URL** — the connector cannot create
     projects, so a "new" Jira board means a project the user just created in the UI;
     board-setup then asks fresh-vs-lived-in and adapts accordingly. Record the choice +
     URL; `/core:board-setup` (step 3) executes it — adopted boards are AUDITED against
     the template and gaps are fixed automatically or via a hand-off guide, per the
     user's choice there.
   - **main stack** — `Node/TS` · `Python` · `Go` · `Rust` (auto-"Other" gets no stack pack).
     "Node/TS" maps to the `typescript.md` pack.
   - **team vault** — `none (local .env)` · `1Password` · `Doppler` · `Infisical`.
   - **CI forge** — `github` · `gitlab` · `both` · `none` (pre-ticks `ci` in step 8
     and picks which forge files its setup scaffolds).
   - **runtime pinning?** yes/no (yes → fill `.mise.toml`).
   - **isolated devcontainer?** yes/no (auto-yes if profile is `autonomous`, since the
     orchestrator needs the egress-firewalled sandbox).

   (There is **no** `distribution` axis and **no** module add/remove step anymore — plugin
   selection replaces both, in step 8.)

2. **Scaffold the contract & config** — copy from `$T` and personalize:
   - `cp "$T/CLAUDE.md" ./CLAUDE.md` — the trimmed contract (≤150 lines, security-top). Keep
     it that shape; push detail to topic docs.
   - `cp -R "$T/docs/." ./docs/` — CODEMAP, STACK, SECURITY, CODE-STANDARDS, AGENT-ROSTER,
     SUGGESTIONS, and `adr/` (README + 0001 only). (README.md for the project: author fresh
     from the purpose; don't ship the plugin's own README.)
   - `mkdir -p .claude/rules && cp "$T/rules/code-standards.md" .claude/rules/code-standards.md`.
   - `cp "$T/settings.json" .claude/settings.json` and `cp "$T/statusline.sh" .claude/statusline.sh`
     (chmod +x). The scaffolded `settings.json` carries **only** permissions + plan-mode +
     MCP gating + statusline — **hooks come from the installed plugins**, not this file.
   - `cp "$T/.env.example" ./.env.example`; devcontainer chosen → `cp -R "$T/.devcontainer" .`;
     runtime pinning → `cp "$T/.mise.toml" .` and **uncomment + set** the asked versions.
   - `cp "$T/.mcp.json" ./.mcp.json`. For the **autonomous** profile, move the `playwright`
     server from the examples block into `mcpServers` — the nightly loop verifies features
     by driving the app in a real browser, so the browser MCP must be available.
   - Write `.claude/policy.json` — security/policy toggles only (per profile: poc relaxes
     `block_no_verify`/`protect_paths_policy` less strictly; team/autonomous keep them ON).
     No `module_*` keys — plugin install/uninstall is the gate.

3. **State backend & the `orchestrator/` state layer** (always scaffolded — the session
   hooks + `/core:handoff` depend on `orch`):
   - `mkdir -p orchestrator/bin orchestrator/adapters`
   - `cp "$T/orchestrator/bin/orch" orchestrator/bin/orch` (chmod +x);
     `cp "$T/orchestrator/state.config.json" orchestrator/state.config.json`.
   - **Keep only the chosen backend's adapter**: `none` → copy no `pm-*.js`;
     `<backend>` → `cp "$T/orchestrator/adapters/pm-<backend>.js" orchestrator/adapters/`.
   - **Record the CI forge** (from the questionnaire) in `orchestrator/state.config.json`'s
     `forge` field — it is the source `pull-feedback` reads PR signals from, independent of
     the board backend. `forge: none` only if no forge was chosen (the loop then cannot be
     driven until one is set).
   - **jira / notion**: after scaffolding, run `/core:board-setup` — it provisions the
     board (database/project) with the 12-state epic lifecycle and wires it into
     `state.config.json`. Mention it in the final summary alongside the plugin installs.
   - `none` → `mkdir -p .orch/{sessions,specs,epics,plans,digest}` + a `.gitkeep` in each;
     gitignore `.orch/cache/`. remote → record the backend in `docs/STACK.md`, add the token
     env var NAME to `.env.example` (never a value), set it in `state.config.json`.

3b. **Test harness (day-0 green suite — the initializer must ship a verifiable
   framework + one passing example test)**: `cp -R "$T/tests" ./tests` (run-tests.sh +
   smoke.test.sh, chmod +x), run `bash tests/run-tests.sh` and require GREEN before the
   first commit. Record the command in CLAUDE.md Commands. This is also what
   /orchestrator:enable-orchestrator's "green test suite" precondition checks on day 0 —
   epics add their own `tests/*.test.sh` (test-first) next to the smoke test.

4. **Anti-drift feature-list contract** (autonomy guardrail — CLAUDE.md rule 2):
   `mkdir -p .orch/epics` and `cp "$T/orch/feature-list.schema.json" .orch/feature-list.schema.json`.
   Point CLAUDE.md rule 2 at it. Each epic the orchestrator builds gets its own
   `.orch/epics/<id>/feature_list.json` (validated against the schema; `passes:false`;
   only the `passes` field is ever mutated). `$T/orch/feature-list.example.json` shows the shape.

5. **Code standards (stack pack)**: `cp "$T/stacks/<lang>.md" .claude/rules/<lang>.md`, then
   **author** the matching formatter/linter config at the repo root using the **exact
   filenames `format-on-edit.sh` detects** (else the hook no-ops): TS/JS → `.prettierrc` +
   `eslint.config.mjs`; **Python → `pyproject.toml` with `[tool.ruff]`** (not `ruff.toml`);
   Rust → `Cargo.toml` + rustfmt; Go → gofmt. Write lint error messages as **remediation
   instructions** (a failing lint is a prompt to the next agent). Record commands in
   `docs/STACK.md` **and** CLAUDE.md Commands.

6. **Personalize & de-template** — replace every `_(fill in / placeholder)_`:
   - CLAUDE.md (Project, Commands, branch naming), README, STACK.md (language/libs/vault +
     chosen backend), SECURITY.md (vault name), `.env.example`, CODEMAP.md (drop the example).
   - **Reset `.claude/agent-memory/`** to empty `MEMORY.md` indexes if the plugin seeded any
     (the review agents' memory must start blank for this project).
   - CHANGELOG.md → empty Keep-a-Changelog skeleton.

7. **ADRs**: keep the mechanism (`architect` agent, immutability hook, `docs/adr/README.md`).
   The scaffolded `adr/` has only 0001 + README; the project's own ADRs start at **0002**.

8. **Optional-plugin selection (the replacement for module composition).** Read
   `$T/profiles.json` for the chosen profile's recommended list and present an
   `AskUserQuestion` **multi-select checklist** of the four optional plugins
   (`formatting`, `orchestrator`, `ci`, `workbench`),
   **pre-ticked** from that list (and pre-tick `ci` iff a forge was chosen). A skill
   cannot install plugins, so after the user confirms, **print the exact commands** for the
   confirmed set (ending with `/reload-plugins` — a freshly installed plugin's skills are
   `Unknown command` until the session reloads) and record the whole block in CLAUDE.md's
   "Installed plugins":
   ```
   /plugin marketplace add lbtbly/agentic-harness-template-plugin
   /plugin install core@harness
   /plugin install formatting@harness      # if ticked
   /plugin install orchestrator@harness    # if ticked
   /plugin install ci@harness              # if ticked
   /plugin install workbench@harness       # if ticked
   /reload-plugins                                               # REQUIRED: skills are inert until reload
   ```
   Then name the **post-install setup skills** to run: `ci` → `/ci:setup`
   (scaffolds the chosen forge's workflow files); `orchestrator` →
   `/orchestrator:enable-orchestrator` (scaffolds the runtime + host scheduler).

9. **Verify & commit**: `jq .` valid on `.claude/settings.json`, `.claude/policy.json`,
   `orchestrator/state.config.json`, `.orch/feature-list.schema.json`; `none` backend →
   `.orch/` skeleton with `.gitkeep`s; CLAUDE.md ≤150 lines with security at the top; no doc
   references a file you didn't scaffold. Propose the first commit
   `chore: initialize from core`, and in the summary repeat the plugin-install +
   setup-skill commands from step 8.

Do not: hand-edit `.claude/settings.json` permissions to widen them (protect-paths blocks
it); write a secret value anywhere; scaffold an app at the repo root. Per-project tuning
happens through `.claude/rules/`, `.claude/policy.json`, and *which plugins are installed* —
never by editing plugin hooks/agents.
