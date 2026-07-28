# SECURITY — secrets policy

## Principle: defense in depth (3 independent layers)
1. **`.gitignore`** — `.env*` (except `.env.example`), `*.pem`, `*.key`, `secrets/`
   are never committed.
2. **Deny rules** (`.claude/settings.json`) — Claude cannot read these paths.
3. **`secret-guard` hook** — backstop: blocks any access even if 1 and 2 are
   misconfigured.

Each layer is sufficient on its own. A mistake never exposes a value.

## End-to-end flow
1. Copy `.env.example` → `.env`, fill it from the **team vault**
   (1Password / Doppler / Infisical — record the adopted tool here via /core:new-project).
2. Apps and MCP servers read variables at runtime. In `.mcp.json`,
   only `${VAR}` expansion:
   ```json
   { "mcpServers": { "github": { "type": "http", "url": "https://api.githubcopilot.com/mcp/", "headers": { "Authorization": "Bearer ${GITHUB_TOKEN}" } } } }
   ```
3. CI: secrets in **GitHub Actions secrets** / GitLab masked+protected variables
   only (`ANTHROPIC_API_KEY`…).
4. Interactively, Claude never sees a secret value — it handles variable NAMES.
   **Exception, stated honestly (audit SEC-H4): in unattended CI runs the agent
   process runs WITH live tokens in its environment** (`ANTHROPIC_API_KEY`,
   `GH_TOKEN`/`GITLAB_TOKEN`) — a path-based hook cannot stop `printenv`. The
   mitigating control there is **egress isolation** (the fail-closed firewall
   the orchestrator runtimes enforce) plus short-lived App tokens and branch
   protection — not the hook. Prefer OIDC/WIF wherever the deploy target
   supports it.

## Rotation
- Any key suspected of exposure: immediate rotation in the vault + redeploy.
- Periodic rotation: follow the team vault's policy (90 days by default).
- A key committed by mistake = considered compromised even after removing
  the commit (history and caches exist) → rotation, not cleanup.

## Never print a credential — the `:+` rule
Checking whether a credential is configured is a routine, reasonable thing to do.
There is exactly **one** safe way to write it:

```bash
echo "token set: ${SLACK_BOT_TOKEN:+yes}"      # SAFE — prints "yes" or nothing
echo "token set: ${SLACK_BOT_TOKEN:-no}"       # LEAKS THE VALUE
```

`${VAR:-fallback}` substitutes the fallback only when the variable is **unset**;
when it *is* set — the case you are testing for — it expands to the value. The two
forms look interchangeable and are not. Only `${VAR:+…}` and `${VAR+…}` can never
emit the secret.

The same trap in other shapes: a bare `env` or `printenv` dumps every credential in
scope, and `env | grep TOKEN` prints the value while `env | grep -c TOKEN` prints a
count. Prefer `printenv PATH`-style filtering, or a count.

**This is enforced, not merely advised**: `secret-guard.sh` blocks a printing command
that references a credential-named variable in any form other than `:+`. The rule
exists because the advisory version was not enough — on 2026-07-28 a probe written as
`${VAR:+YES}${VAR:-NO}` printed a live token into a transcript.

**If a value ever reaches a transcript, log or terminal: rotate it.** Redaction after
the fact is not a control; the value existed in a place it should not have.

## Claude's scope
- Readable: `.env.example`, variable names, this file.
- Forbidden: secret values, `.env*` files, private keys, `secrets/`.
- `enableAllProjectMcpServers: false`: every MCP server requires explicit
  per-user approval.
- The deny rules enumerate common .env suffixes; an exotic suffix (.env.foo) is still covered by .gitignore and the secret-guard hook (defense in depth).

## Guardrail hooks: security vs policy
The `PreToolUse` hooks are split into two tiers so a project can loosen conventions
without ever weakening security:

- **Security (always enforced, not disable-able):**
  - `secret-guard` — blocks access to `.env*`/`.envrc` (except `.env.example`),
    `*.pem`, `*.key`, `secrets/`. **Known limits (honest scope, like ADR-0009):**
    it is a path/string matcher — shell glob expansion (`cat .e*`), variable
    indirection through multiple steps, and env-var reads (`printenv`) are out
    of its reach. The other two layers (+ CI egress isolation) cover those.
  - `protect-paths` → `.claude/settings.json` — an agent cannot widen its own
    permissions.
- **Policy (opt-in, default ON — team conventions, not security boundaries):**
  - `protect-policy-paths` → CI workflows (`.github/workflows/*`, `.gitlab-ci.yml`),
    generated lockfiles, `.claude-plugin/*` manifests, accepted ADRs, and the
    **trusted-computing-base scripts** (plugin `hooks/*`, `orchestrator/bin/*`,
    `orchestrator/adapters/*` — an agent must not rewrite scripts it is allowed to
    execute; audit SEC-C2). Toggle key: `protect_paths_policy`.
  - `block-no-verify` — blocks `git commit --no-verify` (incl. `-n`) and
    force-push to `main`/`master`. Toggle key: `block_no_verify`.

**Toggling policy** (never affects the security tier). Precedence:
`env CLAUDE_POLICY_<KEY> > .claude/policy.json > default true`.
```json
// .claude/policy.json  — project-owner config, set per profile by /core:new-project
{ "protect_paths_policy": true, "block_no_verify": false }
```
POC/prototype profiles typically loosen policy; team/autonomous profiles keep it on.
Whatever the setting, `secret-guard` and the `settings.json` guard still fire.

## Data residency — orchestrator digest delivery (audit SEC-M1)
The nightly digest contains repo-derived content: epic titles, file paths,
staging URLs, gate results. **Slack/SendGrid delivery ships that content to
external US SaaS** — flag this to your DPO if you run the VPN/self-hosted
GitLab posture or handle EU data. Residency-safe options: an internal SMTP
relay / self-hosted chat, or link-only webhook delivery (`digest_url_base`
set, no attachment). Committed digests and `.orch/` board data live in git
history — define a retention policy if epic notes may contain personal data.

## Permission modes & sandboxing
- **Default mode**: `settings.json` sets `permissions.defaultMode: "plan"` — a
  deliberate read-first posture for a shared template. Teams may relax it (per-user
  `settings.local.json`) to `acceptEdits` or `auto` once comfortable.
- **`auto` mode** (Opus/Sonnet 4.6+): a classifier auto-approves routine work but
  still gates pushes and destructive ops. A reasonable daily default for trusted repos.
- **Bypass "disabled" — with a caveat**: `permissions.disableBypassPermissionsMode:
  "disable"` is committed, but per official docs this key **only binds from managed
  settings** (MDM / server-managed) — at project scope it is a declared intent, not
  a hard lock. Teams that need it enforced must set it in `managed-settings.json`.
- **`--dangerously-skip-permissions` / YOLO**: only inside an isolated container or VM,
  never on a real dev machine (documented community failure mode).
- **Sandboxing**: for untrusted code use a `.devcontainer/` (OS-level isolation) or the
  `/sandbox` bash sandbox (filesystem + network isolation).

## The four walls of an unattended run
1. **Deny rules** (`settings.orchestrator.json` permissions) — tool-level.
2. **Guard hooks** (secret-guard & friends) — fail CLOSED without jq.
3. **Native OS sandbox** — `sandbox.network.allowedDomains` (mirrors
   `orchestrator/egress-allowlist.txt`) + `sandbox.credentials` denying model and
   delivery credentials to tool subprocesses.
4. **Devcontainer egress firewall** — default-deny iptables from the same
   allowlist; the outer wall on runners where the OS sandbox is unavailable.

## The journal — what the harness records about itself

`.orch/journal/<YYYY-MM-DD>.jsonl` is an append-only NDJSON stream of the harness's own
mistakes and their corrections (ADR-0023): guard blocks, failed commands, human corrections,
subagent failures, formatter rewrites, model escalations, integration reverts.

**What it records is a classification, never content.** The verb of a failed command (`npm`),
never the command line. The shape of a correction (`contradiction`), never your words. The rule
that fired (`secret_guard`), never the path that triggered it. Paths are repo-relative — an
absolute path embeds your machine username, which is personal data and has been leaked from a
shipped template once before.

It is written by hooks, so nothing depends on the agent choosing to be honest. Every observer is
advisory: exits 0, blocks nothing, and emits no stdout.

**Turning it off** — it defaults on, and writes only inside your repo:

```
.claude/policy.json   {"journal": false}
env                   CLAUDE_POLICY_JOURNAL=0
```

Guards still block with journaling off; the record is additive, never a substitute for enforcement.

Nothing leaves the machine. `push-journal`/`pull-journal` are local-only ops and never reach a
board adapter. Sharing a journal is a separate, explicit, redacted export.
