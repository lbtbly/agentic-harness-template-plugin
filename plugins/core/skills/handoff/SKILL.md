---
name: handoff
description: Pushes the session resume snapshot to the state layer (orch state push-session) — status, failed attempts, blockers, next steps — from git + tests + context. Run at the end of a session — the Stop hook reminds you.
---

# /core:handoff

1. **Collect**: `git branch --show-current`, `git status --porcelain`,
   `git log --oneline -5`; if a test suite exists and is fast,
   run it for the real status.
2. **Push the session** (Layer 3 = perishable, no history — ADR-0007). Build the
   snapshot JSON and push it:
   ```bash
   orchestrator/bin/orch state push-session << 'EOF'
   { "branch": "<branch>", "spec": "<spec-id or null>",
     "status": "<where things stand, factual>",
     "failedAttempts": ["<tried WITHOUT success this session and why — the most
                         valuable section, never empty if any leads failed>"],
     "blockers": ["..."], "nextSteps": ["<numbered, actionable without context>"],
     "testStatus": {"ran": true, "passed": 0, "failed": 0} }
   EOF
   ```
   `none` backend → this writes `.orch/sessions/<branch>.json` (one file per
   branch: parallel worktrees never clobber each other). Remote backend → board
   + local cache. **Legacy fallback** (state layer not installed): overwrite
   `docs/HANDOFF.md` with the same sections.
3. **CHANGELOG**: write a fragment in `changelog.d/` for what was shipped this
   session (Added/Fixed/Decided) — propose, the user confirms.
4. **Status**: propagate epic/task state changes via
   `orch state push-status --id <epic> --state <state>` (read-time aggregation
   replaces the old ROADMAP table; legacy fallback: `docs/ROADMAP.md`).

Guardrails: do not commit; do not invent status (when in doubt, write
"unverified"); the snapshot stays lean (< 80 lines rendered) — the previous
auto snapshot is replaced automatically by the push.
