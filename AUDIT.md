# AUDIT — harness marketplace vs. 2026 agentic-coding baseline

Audited 2026-07-17 against the supplied rubric (Surface A = plugin, 30%; Surface B =
generated environment, 70%). Read-only audit; evidence is path:line or verified absence.

## Executive summary

Overall: **AT PAR, with ABOVE pockets and one structural BELOW.** The generated
environment beats baseline on enforcement (D3), verification (D4) and security (D9) —
hooks, independent verifier, fail-closed defaults. It is BELOW market on cross-tool
interoperability: no `AGENTS.md` canonical file (D1/D10), a deliberate-in-spirit but
**undocumented-in-this-repo** Claude-native lock. Top risks: (1) the missing canonical
instruction file, (2) 14/15 skills lack model-invocation control on side-effectful
workflows, (3) re-running the initializer over a modified project has no defined
non-clobber behavior.

## Inventory (Phase 1)

| Component | Type | Surface | Purpose |
|---|---|---|---|
| `.claude-plugin/marketplace.json` (v1.2.0) | manifest | A | 5-plugin marketplace |
| `plugins/*/.claude-plugin/plugin.json` ×5 | manifests | A | core 1.2.0, others 1.0.0 |
| core: 8 skills, 5 agents, 10 hook cmds (`hooks/hooks.json`) | skills/agents/hooks | A→B | scaffolder, handoff, board-setup, guards |
| orchestrator: 5 skills, 2 agents, 2 workflows | — | A→B | enable/kickoff/plan/run, dod-verify, nightly |
| workbench: 1 skill, 4 agents, 3 workflows; formatting: 1 hook; ci: 1 skill | — | A→B | |
| core/templates → **generated tree (Surface B)** | templates | B | verified in the 2026-07-16 field test (`~/harness-trial`) |

**Generated tree** (trace: `new-project/SKILL.md:57-118` + field-test verification):
`CLAUDE.md` (73-line template; 86 rendered), `README.md` (authored), `.claude/settings.json`
+ `policy.json` + `rules/{code-standards,<stack>}.md` + `statusline.sh`, `.mcp.json`
(playwright for autonomous), `.env.example`, `.devcontainer/{devcontainer.json,init-firewall.sh}`,
`docs/{CODEMAP,STACK,SECURITY,CODE-STANDARDS,AGENT-ROSTER,SUGGESTIONS,SCHEDULED-AGENTS,TOOLING,adr/}`,
`orchestrator/{bin/orch,state.config.json[,adapters/pm-*.js]}`, `.orch/` skeleton +
`feature-list.schema.json`, `tests/{run-tests.sh,smoke.test.sh}`, stack lint configs.
Enable-orchestrator overlays `orchestrator/{risk-policy,settings.orchestrator,bin/validate-dod,adapters,runtime,digest-template,notify.config}`.

**Always-loaded context cost (measured):** `CLAUDE.md` 3,766 B + `rules/code-standards.md`
1,895 B ≈ **5.7 KB ≈ ~1.4k tokens**. Stack packs are `paths:`-scoped (on-demand;
`templates/stacks/typescript.md:1-3`). Hooks are exec-only (no context payload). Session
injection adds one <80-line snapshot (`handoff/SKILL.md` lean rule).

## Scorecard (Phase 2)

| Dim | Surface | Verdict | One-line evidence |
|---|---|---|---|
| D1 instruction file | B | **BELOW** | No `AGENTS.md` anywhere — absent (checked: `find . -name AGENTS.md`; `grep -rl AGENTS.md plugins/ docs/ README.md` → none). File itself is strong (73 lines, command-first, security-top). |
| D2 on-demand skills | B | **AT PAR** | 15 skills on demand; but `disable-model-invocation` on only 1/15 (`project-conventions/SKILL.md`) — side-effectful workflows uncontrolled. |
| D3 enforcement | B | **ABOVE** | 4 guard hooks + policy-lib + protected paths incl. lockfiles/CI/ADRs (`core/hooks/protect-policy-paths.sh`), deny rules (`templates/settings.json`: 17 deny), format-on-edit plugin. Deduction: Stop hook reminds, never gates (`handoff-reminder.sh:2-4`). |
| D4 verification | B | **ABOVE** | Day-0 harness (`templates/tests/run-tests.sh` + `smoke.test.sh`), evidence-based completion (`feature-list.schema.json:69-72`), independent verifier + decorrelated judges (`dod-verify.js:8-11`) — the rubric's "bonus" is core here. |
| D5 spec-driven | B | **AT PAR** | Full explore→spec→tasks flow (`core/skills/spec/SKILL.md`), plan-mode default — but `conception/` is write-once by design (`spec/SKILL.md:16,25`); rubric caps static specs at PAR. Per-epic `feature_list.json` is living (re-authored on revise, `plan/SKILL.md:14`) — epic level only. |
| D6 docs architecture | B | **AT PAR** | ADRs immutable **by hook** (`protect-policy-paths.sh:29-32`), changelog.d fragments (`handoff/SKILL.md:27-29`), doc-health ritual. Doc-updates-in-DoD are convention, not hook/CI-gated; `llms.txt` absent (checked: `find . -name llms.txt`, `grep -rn llms.txt plugins/`); no KB publication pipeline. |
| D7 improvement loop | B | **AT PAR** | Review-to-rule ritual documented (`templates/CLAUDE.md:46`), growth-detection hook → SUGGESTIONS → human triage, rule pruning audit (`doc-health/SKILL.md` check 8). Missing: automated capture of PR-review comments into rules (kickoff folds revise notes into plans, not rules — `kickoff/SKILL.md:42`). |
| D8 context hygiene | B | **ABOVE** | ~1.4k tokens measured at start; path-scoped stack rules; delegation guidance (fresh-context reviewer, `templates/CLAUDE.md:44-45`); PreCompact auto-save hook (`core/hooks/precompact-save-state.sh`). |
| D9 security | B | **ABOVE** | `defaultMode: plan` + bypass disabled (`templates/settings.json`), 3-wall secret-guard, egress firewall + native sandbox (`settings.orchestrator.json`), trifecta warning shipped (`enable-orchestrator/SKILL.md:56-58`), no secret values (grep `sk-ant-|ghp_` → none). |
| D10 interop & distribution | A+B | **BELOW** | Vendor-locked to Claude Code with no canonical cross-tool file and **no ADR documenting the lock** (docs/adr/ gaps 0002–0006 were deliberately not ported). Distribution half is fine: standard anatomy, versioned, `.mcp.json` declared, adapter-update path in ADR-0021; but `new-project` re-run over a modified project has no defined merge/skip behavior (only a safety-branch mitigation, `new-project/SKILL.md:18`). |

**Surface A note:** anatomy matches the standard exactly (manifest-only `.claude-plugin/`,
skills/agents/hooks at plugin root); install docs bake in the reload gotcha (`README.md:16`).
One credibility nit: README says "317+ assertions" — the suite now runs 24 files / ~390
assertions; stale but under-claiming, low risk.

## Gap backlog (Phase 3)

**P0 — BELOW on buyer-checked dimensions**
1. **Ship AGENTS.md as the canonical file** (D1/D10, Surface B): new-project writes
   `AGENTS.md` and makes `CLAUDE.md` a pointer/symlink (or vice-versa with an `@import`),
   zero duplicated content. Files: `plugins/core/templates/CLAUDE.md` (rename/pointer),
   `plugins/core/skills/new-project/SKILL.md` step 2, `tests/test-plugin-manifests.sh`. **S**
2. **Document or reverse the vendor lock** (D10, Surface A): author ADR-0022 (Claude-native
   positioning: hooks/skills/agents are CC-only by design; AGENTS.md carries the portable
   subset) — the reference repo had this decision (its ADR-0003/0005); this repo shipped
   the consequence without the rationale. Files: `docs/adr/0022-*.md`, `docs/adr/README.md`. **S**
3. **Optional Stop-gate** (D3, Surface B): a policy-toggled mode where the Stop hook blocks
   (exit 2) when `cleanState` shows failing build/tests or debug artifacts, default stays
   advisory. Files: `plugins/core/hooks/handoff-reminder.sh`, `.claude/policy.json` key,
   `tests/test-handoff-reminder.sh`. **M**

**P1 — blocking AT PAR elsewhere**
4. `disable-model-invocation: true` on all side-effectful skills (D2): new-project,
   board-setup, enable/disable-orchestrator, kickoff, run, ci:setup, db-migration,
   triage-suggestions. Files: those SKILL.md frontmatters + a test asserting coverage. **S**
5. **Defined re-init behavior** (D10): new-project detects an existing scaffold and enters
   adopt/upgrade mode (diff-and-propose, never overwrite personalized files). Files:
   `new-project/SKILL.md` step 0/2. **M**
6. README test-count freshness + a stated policy ("counts are minimums") (Surface A). **S**

**P2 — differentiators (ABOVE)**
7. Review-comment→rule capture (D7): kickoff step that classifies each `/orch revise` note
   as plan-fix vs *missing context* and proposes the rule line. Files: `kickoff/SKILL.md`. **S/M**
8. Living-spec mechanic (D5): a `/core:spec --revise` path that regenerates the spec +
   tasks from changed requirements with a superseding entry, keeping the frozen trail. **M**
9. Docs publication pipeline (D6): optional skill mapping docs/ pages → Notion/Confluence
   via MCP with human review; plus `llms.txt` template for published docs. **L**

## Quick wins (under a day)
Items 1, 2, 4, 6 above — all S. Combined they flip D1 to AT PAR (arguably ABOVE given the
file quality), remove the D2 deduction, and close the Surface-A credibility nits.

## Open questions (product decisions, not fixes)
- **Vendor-neutral vs Claude-native**: AGENTS.md-canonical unlocks Codex/Copilot/Cursor
  users for the *instructions*, but hooks/enforcement (the plugin's real edge) remain
  CC-only. Position as "portable contract, CC-native enforcement"?
- **Stop-gate default**: advisory (current) vs blocking — blocking matches the rubric's
  baseline but fights the field-tested UX (the Stop hook as reminder was deliberate).
- **Bundle a KB publication pipeline** (P2-9) or keep the zero-dependency posture and
  leave it to a future plugin?

*Re-read pass done: every claim above traces to a cited path:line, a measured number, or a
recorded absence check.*

---
## Remediation addendum (2026-07-17, post-audit)
Closed: P0-2 (ADR-0022 documents the Claude-native position; README states it),
P1-4 (`disable-model-invocation: true` on all 9 side-effectful skills, test-enforced),
P1-5 (new-project upgrade mode — diff-and-propose, never overwrite),
P1-6 (README counts freshened), P2-7 (kickoff review→rule capture, human-approved)
+ the llms.txt pointer in TOOLING.md. Deliberately open: P0-1 (AGENTS.md — rejected
by ADR-0022), P0-3 (Stop-gate — pending product decision), P2-8/9 (deferred).
