# Suggestions (growth-detection)

Triaged by /core:doc-health. Checked = handled. Beyond 20 unhandled entries,
/core:doc-health proposes a batch triage (promotions to CODEMAP/ADR/RUNBOOK).

<!-- 2026-07-02 purge #2: the entries recorded during template development were
     meta-noise — the detector firing on the template's OWN files, which
     legitimately mention credential NAMES and GDPR wording (docs about the
     detector). They also recorded ABSOLUTE paths embedding the machine
     username (personal data); the hook now records repo-relative paths.
     Real product findings will accumulate below once the template hosts a
     real project. -->
- [ ] 2026-07-06 🔍 Author-flagged edge case (EDGE:) → validate error handling via /core:triage-suggestions — `apps/web/src/checkout.ts`
