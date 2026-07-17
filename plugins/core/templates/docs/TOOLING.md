# TOOLING — recommended add-ons (Layer 2)

Opt-in tooling around Claude Code. Nothing here is required; the template stays
dependency-free (pure-shell hooks + `jq`). Adopt what earns its place.

## MCP policy: CLI-first
**Prefer a CLI over an MCP server whenever one exists.** A CLI (`gh`, `aws`, `gcloud`,
`psql`, `kubectl`, …) costs ~zero context and runs under the same permission/sandbox
rules as any other command; an MCP server permanently adds its whole tool list to every
session's context and is another moving part to secure. Reach for MCP only when there is
no adequate CLI (or the CLI is far clumsier).

## MCP servers
`.mcp.json` ships empty (agnostic). When you do add a server, keep the discipline:
- **CLI-first** — see above; don't add an MCP server that duplicates a CLI you already have.
- **Start with 3-4 max** — every server's tool list consumes context.
- **Never a plaintext secret** — only `${VAR}` expansion (see `docs/SECURITY.md`).
- **Do NOT add a filesystem server** — Claude Code already has native file tools.

Community shortlist (copy-ready stubs live in `.mcp.json` under
`$examples_move_one_into_mcpServers_to_enable`). They are **inert**: Claude Code only
loads the `mcpServers` object, and `enableAllProjectMcpServers: false` means any server
still needs explicit per-user approval — so a stub does nothing until you move it into
`mcpServers` *and* approve it.

| Server | Why | Note |
|---|---|---|
| Context7 | Live, version-correct library docs → kills hallucinated APIs | free tier is rate-limited |
| GitHub MCP | Issues/PRs/CI from the session | needs `${GITHUB_TOKEN}` |
| Playwright | Real browser: navigate, click, screenshot, E2E | heavier; for frontend work |

## Cost & usage visibility
- **statusline**: `.claude/statusline.sh` (shipped) shows `branch · model · context%`
  via the `statusLine` setting. Pure shell, no dependency.
- **ccusage** (`npx ccusage`) — per-session/daily cost attribution from local
  session files, no API key. Recommended for teams tracking spend.
- **ccstatusline** — richer React/Ink statusline (cost, PR state, powerline). Opt-in
  replacement for `.claude/statusline.sh` if you want more than branch/model/context.

## Auto memory (coherence with the 3-layer model)
Claude Code keeps an automatic memory under `~/.claude/projects/<project>/memory/`.
It is personal and outside this repo, so it does not replace the committed layers:
- Durable, team-facing knowledge still belongs in **Layer 2** (`CODEMAP`, `STACK`, ADRs).
- Session state still belongs in **Layer 3** (`HANDOFF.md`).
- Treat auto memory as a scratchpad. It must never capture secret values — the same
  rule as everywhere (`docs/SECURITY.md`). Toggle/inspect it via `/memory`.

## Runtime toolchain (opt-in — `mise`)
Language-agnostic by default (only `jq` is required). For projects that need pinned
runtimes, `/core:new-project` can drop a `.mise.toml` ([mise](https://mise.jdx.dev)) that pins
node/python/go/rust per project and installs them with `mise install`. It keeps toolchains
**isolated and reinstallable**, which is especially handy inside git worktrees and sandboxes.
Template: `plugins/core/skills/new-project/templates/runtime/mise.toml`. Not added unless chosen.

## Sandbox / devcontainer (opt-in)
For higher-autonomy or untrusted-code runs, `/core:new-project` can drop a `.devcontainer/`
with a **default-deny egress firewall** (`init-firewall.sh`: allowlist only what the agent
needs, then self-verify the lockdown). This is the safe home for `auto`/bypass-style runs —
see the sandboxing note in `docs/SECURITY.md`. Template:
`plugins/core/skills/new-project/templates/devcontainer/`. Not added unless chosen.

## Evals (agent-output verification)
Tests are the primary success signal (non-negotiable rule 5). Beyond tests, for
non-testable criteria (style, architectural conformance) an LLM-as-judge pass or a
small eval suite (Braintrust, Inspect AI, DeepEval) is the community-standard
guardrail. Documentation pointer only — no framework is bundled.

## Published docs
If any docs/ content is published externally, add an `llms.txt` at the site
root (a machine-readable index of the published pages) so agents consuming
your product docs get the same curated entry point humans do.
