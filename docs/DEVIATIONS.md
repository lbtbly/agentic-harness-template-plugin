# Deviations from the field manual (verified July 2026)

The field manual "The Overnight Harness" is the source of truth for this plugin's
architecture. Before building each subsystem, its design was checked against current
official and practitioner sources. Where a current source improves on or contradicts
the manual, this file records the deviation and why.

This file is the **research log** (sources, what changed, evidence). The decisions
themselves are recorded as immutable ADRs in [docs/adr/](adr/): §1 → ADR-0016
(decorrelated judge panel), §2 → ADR-0018 (gated flavor default), §4 → ADR-0019
(subscription auth lane), §5 → ADR-0020 (native sandbox + devcontainer); the
fail-closed risk fix discovered during subsystem 3–4 → ADR-0017. Inherited
architecture decisions cited by shipped skills (externalized state, phase split,
run-to-completion, …) are ported as ADR-0001/0007/0008/0009/0011/0012/0013/0015.

## 1. Judge panel: model diversity added (correlated-judges research)

**Manual says:** four-stage DoD verify ends with an independent judge panel — several
adversarial reviewers with distinct lenses; pass = majority AND no blocking objection.

**Current sources:** correlated-error research (arXiv 2605.29800 "Nine Judges, Two
Effective Votes") shows majority voting among same-family judges adds little — same-model
judges fail together, so a 3-vote panel of one model is ≈ one judge. Blocking dissent is
supported (arXiv 2606.07834); Anthropic's 2026 harness follow-up
(anthropic.com/engineering/harness-design-long-running-apps) uses a single strong
evaluator with hard per-criterion thresholds instead of a panel.

**Deviation:** `dod-verify.js` keeps lenses + strict majority + blocking dissent, and
additionally pins a **different model per lens** (`JUDGE_MODELS`) so votes are less
correlated. Zero-vote and tie tallies always fail (never pass by default).

## 2. Auto-merge stance: gated nightly documented as the default flavor

**Manual says:** two flavors — gated nightly and run-to-completion with risk-gated
auto-merge for low-risk epics.

**Current sources:** MSR 2026 mining study (arXiv 2605.22534): 61% of
"automation-authorized" agent merges still had a human review first; no first-party
Anthropic/OpenAI post recommends unattended auto-merge. The published recipe that does
exist ("The End of Code Review", arXiv 2606.13175) is exactly the manual's shape:
structured machine sign-off for low-risk, mandatory human sign-off on high-risk paths.

**Deviation:** none structural — but docs present the **gated flavor as the recommended
default** and run-to-completion as the opt-in for mature projects with a hardened DoD.
The manual's own "build the loops first, loosen the gates second" is now backed by data.

## 3. BMAD mapping: sharding is legacy terminology in BMAD v6

**Manual says:** the initiative → epic → feature hierarchy maps onto BMAD's
brief → PRD-epic → sharded story file, and "sharding" is BMAD's key move.

**Current sources:** BMad Method v6 (docs.bmad-method.org) no longer requires document
sharding (auto-scan replaced it; sharding survives as an optional how-to). The current
flow is 4 scale-adaptive phases (Analysis → Planning → Solutioning → Implementation)
with project Levels 0–4 deciding how much ceremony runs; the SM/QA/dev agents were
consolidated.

**Deviation:** the per-epic self-contained `feature_list.json` shard stays — it's
justified by parallel-writer isolation and context-completeness, not by BMAD citation.
Docs credit the insight to BMAD v4 and note v6's change. The planner adopts BMAD v6's
**scale-adaptive** idea: a small initiative becomes one epic without ceremony; only
oversized initiatives get full decomposition.

## 4. Headless auth: `--bare` vs subscription token, verified precedence

**Manual says:** subscription OAuth works headlessly; `claude setup-token` →
`CLAUDE_CODE_OAUTH_TOKEN` for CI; avoid `--bare` which ignores it; don't set
`ANTHROPIC_API_KEY` (it takes precedence).

**Current sources (code.claude.com/docs/en/authentication.md, headless.md):** all
confirmed — and sharpened: setup-token tokens now live 1 year; docs recommend `--bare`
for CI *when using an API key*, but `--bare` skips OAuth/keychain reads entirely, so a
subscription-token runner must NOT use `--bare`. Auth precedence (high→low): cloud
provider vars → ANTHROPIC_AUTH_TOKEN → ANTHROPIC_API_KEY → apiKeyHelper →
CLAUDE_CODE_OAUTH_TOKEN → stored login.

**Deviation:** runtime templates document both lanes explicitly and never combine
`--bare` with `CLAUDE_CODE_OAUTH_TOKEN`.

## 5. Sandboxing: native sandbox settings complement the devcontainer

**Manual says:** unattended runs require a devcontainer with a default-deny egress
firewall.

**Current sources (code.claude.com/docs/en/sandboxing.md):** Claude Code now ships an
OS-level sandbox (macOS Seatbelt / Linux bubblewrap) with filesystem write-scoping,
credential deny/mask, and a network allowlist — enforceable via
`sandbox.enabled + failIfUnavailable: true + allowUnsandboxedCommands: false`.

**Deviation:** the orchestrator's settings template enables the native sandbox in
addition to (not instead of) the devcontainer requirement; the devcontainer remains the
outer box for CI runners where the native sandbox may be unavailable.

## 6. Plugin API: manual's frontmatter and packaging confirmed current

`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`, `skills/<name>/SKILL.md`
(commands/ is legacy), `agents/*.md`, `hooks/hooks.json`, `${CLAUDE_PLUGIN_ROOT}`,
`${CLAUDE_PROJECT_DIR}` — all current. Agent frontmatter fields used here (`tools`,
`model`, `memory`, `skills`, `isolation: worktree`, `maxTurns`, `background`) are all
officially supported (code.claude.com/docs/en/sub-agents.md). `/reload-plugins` is still
required after install for hooks/agents/MCP (not for SKILL.md edits) — the manual's
"reload gotcha" stands.

## 7. Lecture audit (learn-harness-engineering 04–13, 2026-07-17)

The plugin was audited against walkinglabs.github.io/learn-harness-engineering
lectures 04–13. Verdicts: **equal or better** on 05 (continuity — orch state
snapshots + PreCompact auto-save beat manual protocols), 07 (overreach —
one-epic workers + footprint single-writer; WIP=1 applies per worker, worktree
parallelism is lecture 13's own primitive), 09 (premature victory — 4-stage
external DoD + decorrelated judges exceed 3-layer validation), 10 (E2E — browser
-as-user + rules-as-checks), 13 (loop engineering — all six primitives, richer
guards). **Adopted** from the remaining lectures: day-0 test harness in the
initializer (L06), verifier-owned `evidence` on the feature contract (L08),
harness-side per-phase metrics + VCR + OTel env documentation (L11 + L07),
clean-exit checklist in handoff (L12), rule since/expires metadata + doc-health
instruction audit (L04). **Explicitly not adopted**: global WIP=1 (worktree
parallelism + serial merge is strictly better), evaluator letter-grade rubrics
(majority + blocking dissent is stricter — ADR-0016), harness-emitted OTel
spans (breaks the zero-dependency posture; docs-only pointer instead).

## 8. `paths:`-scoped rules: verified convention, community-reported bugs (2026-07-17)

Stack packs rely on `.claude/rules/*.md` `paths:` frontmatter (officially supported).
Community trackers report open bugs (anthropics/claude-code #21858, #16299, #17204 —
rules ignored or loaded globally). Deviation: none — but /core:doc-health now carries
a manual canary check, and the documented fallback is folding the stack pack into the
always-loaded code-standards.md if the canary fails on a given CC version.
