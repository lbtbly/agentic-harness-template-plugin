---
name: doc-health
description: Health report on the documentation + state layer — with no modifications at all. Run weekly or before a work phase.
---

# /core:doc-health — STRICTLY READ-ONLY

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
8. **Changelog fragments piling up?** `changelog.d/*.md` count > 15 → propose
   an assemble/release.

Format: ✅ / ⚠️ / ❌ per check, then prioritized recommended actions.
FORBIDDEN: modifying any file. This skill diagnoses (DDPC) — the human confirms.
