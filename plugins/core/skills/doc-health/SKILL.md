---
name: doc-health
description: Health report on the documentation + state layer — with no modifications at all. Run weekly or before a work phase.
context: fork
agent: Explore
disallowed-tools: Edit, Write
---

# /core:doc-health — STRICTLY READ-ONLY

> Runs FORKED in the read-only `Explore` agent (context: fork): the audit detail
> never pollutes the main context, and Write/Edit are mechanically denied —
> the prose rule below is now enforced.

Produce a report (in the conversation, or in docs/reports/ if requested):

1. **State backend healthy?** `orchestrator/bin/orch state health` — reachable,
   auth OK? (`none` backend: `.orch/` skeleton present?)
2. **Session stale?** `orch state pull-session` — newest session record > 24h
   old with uncommitted git changes? (legacy: `docs/HANDOFF.md` mtime)
3. **Decisions without an ADR?** `git log --oneline -30`: any structural
   changes (new lib in the manifests, new service, module boundaries)
   without a matching ADR?
4. **Pending lessons?** Unchecked entries in docs/SUGGESTIONS.md;
   if > 20, propose a batch triage.
5. **Rules / CODEMAP drifted?** For each file in `.claude/rules/`: does its
   `paths:` frontmatter still match real files? Do the coupling rules (and the
   CODEMAP macro view) cite modules that no longer exist?
6. **Specs never finished?** `orch state list-specs` + `list-epics`: specs with
   no epic movement for 14 days (legacy: conception/*.md untouched).
7. **Status consistent?** `orch state pull-status`: "In-progress" epics with no
   movement (ts) for 14 days.
8. **Instruction audit** (rules are dependencies — remove unused ones): for
   each rule in CLAUDE.md's hard constraints and `.claude/rules/*.md`, flag:
   (a) rules whose `expires:` condition is met; (b) rules with no `since:`/
   `expires:` metadata added > 90 days ago (candidates for triage, not
   auto-removal); (c) pairs that contradict each other or an accepted ADR.
   Report only — removal goes through a human (rule 5 of DDPC).
9. **`paths:` canary** (community-reported bugs on path-scoped rules): confirm a
   stack rule (e.g. `.claude/rules/typescript.md`) is loaded ONLY when editing
   matching paths — if it loads globally or never, note it: the fallback is
   folding the pack into `code-standards.md` until the CC bug is fixed.
10. **Changelog fragments piling up?** `changelog.d/*.md` count > 15 → propose
   an assemble/release.

Format: ✅ / ⚠️ / ❌ per check, then prioritized recommended actions.
FORBIDDEN: modifying any file. This skill diagnoses (DDPC) — the human confirms.
