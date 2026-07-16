---
name: spec
description: Spec-first workflow — turn a rough idea into a reviewed spec + task checklist in conception/ before any code. Use before starting a non-trivial feature.
---

# /core:spec

1. **Clarify** (AskUserQuestion): one round on the essentials — goal & who it's
   for, in-scope vs **out-of-scope**, constraints, and acceptance criteria (how
   we'll know it's done). Don't guess: a vague spec is the #1 agent failure mode.
2. **Write the spec**: `conception/YYYY-MM-DD-<topic>-design.md`, following the
   existing design-doc shape (context, goals, decisions, scope, acceptance
   criteria). A structural choice → draft an ADR (`architect` agent), don't bury
   it in the spec.
3. **Derive tasks**: a checklist of small, verifiable steps. For a large effort
   this becomes the frozen plan (`conception/tasks.md` — never rewritten; status
   lives in `docs/ROADMAP.md`).
4. **Design review** (if the `design-reviewer` agent is composed): offer a critique
   pass before freezing — boundaries, YAGNI, missing failure modes, consistency
   with accepted ADRs. Blocking findings go back to step 2.
5. **Confirm**: explicit sign-off on the spec before any code. Plan the test for
   each acceptance criterion — tests are the guardrail (non-negotiable rule 5).

GUARDRAILS: the spec is human-curated, never auto-bloated (machine-generated
context measurably hurts agents). `conception/` is frozen — supersede, don't
rewrite. Keep it lean; link to Layer 2 rather than duplicating it.
