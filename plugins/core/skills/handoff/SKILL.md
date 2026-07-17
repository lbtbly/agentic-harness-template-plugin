---
name: handoff
description: Pushes the session resume snapshot to the state layer (orch state push-session) — status, failed attempts, blockers, next steps — from git + tests + context. Run at the end of a session — the Stop hook reminds you.
---

# /core:handoff

1. **Collect**: `git branch --show-current`, `git status --porcelain`,
   `git log --oneline -5`; if a test suite exists and is fast,
   run it for the real status.
1b. **Clean-exit check (advisory, recorded — never silently dropped)**: scan the
   session's diff for left-behind noise before snapshotting:
   `git diff HEAD --unified=0 | grep -nE "console\.log|debugger|print\(.*#.*debug|TODO(?![(:].*[)])|^\+\s*//.*(commented.out|XXX)"`
   (adapt per stack). Build `cleanState`: `{ "build": <pass|fail|not-run>,
   "tests": <pass|fail|not-run>, "debugArtifacts": ["file:line — what", …] }` —
   findings are reported in the snapshot and to the user; fixing them now is
   preferred, but this check never blocks the handoff (the Stop hook stays a
   reminder, not a gate).

2. **Push the session** (Layer 3 = perishable, no history — ADR-0007). Build the
   snapshot JSON and push it:
   ```bash
   orchestrator/bin/orch state push-session << 'EOF'
   { "branch": "<branch>", "spec": "<spec-id or null>",
     "cleanState": { "build": "pass", "tests": "pass", "debugArtifacts": [] },
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
