# AGENTS — who does what, and how to orchestrate

## The escalation ladder: solo → subagent → workflow
1. **Solo** (main session): short task, shared context, iterative.
2. **Subagent**: the task produces volume (logs, research) you don't want
   in the main context, or requires restricted tools.
3. **Workflow**: massive fan-out — exhaustive review, multi-angle research,
   migration. Expensive — reserve for large tasks. (Workflows ship in the
   `workbench` and `orchestrator` plugins.)

## The agents (which plugin provides each)
| Agent | Plugin | Trigger | Cost |
|---|---|---|---|
| code-reviewer | core | Proactive after any significant change | € |
| debugger | core | Bug that resists the first diagnosis | € |
| architect | core | Structural decision → options + ADR draft | €€ (opus) |
| design-reviewer | core | Critique of a spec/plan/ADR before freeze | €€ (opus) |
| docs-writer | core | Docs drift, keeping CODEMAP/STACK consistent | ¢ (haiku) |
| security-auditor | workbench | Before sensitive merges; auth/data/payment code | €€ (opus) |
| test-runner | workbench | Tests to run/analyze — it reports, does not fix | € |
| researcher | workbench | External knowledge (libs, versions) — runs in background | € |
| refactorer | workbench | Mass mechanical change — in an isolated worktree | €€ (volume) |
| integration-checker | orchestrator | Overlapping epics merged → verify combined result | € |

_(Only the agents from your installed plugins are available. Agents are namespaced
by their plugin.)_

## The 3 anti-failure rules
1. **Parallel only if files are disjoint.** Read-only agents (reviewer, auditor,
   researcher) run in parallel safely. Writers: never together, except in isolated worktrees.
2. **Vague invocation is failure mode #1.** Always: exact paths + success criterion.
   "Fix the auth" ✗ — "Fix the OAuth redirect loop: login redirects to /login instead of
   /dashboard, see src/auth/callback.ts" ✓.
3. **Don't over-parallelize small tasks.** Coordination overhead costs more than the gain
   below ~3 independent subtasks.

## Agent memory
code-reviewer, security-auditor, debugger, architect and design-reviewer have
`memory: project` (`.claude/agent-memory/`, committed): they accumulate the project's
patterns and root causes. Ask them explicitly: "check your memory" / "save what you learned".

## Extension
An agent earns its own file after **3 identical delegations** with the same instructions.
A nightly session that solves something non-trivial should capitalize it into a reusable
skill or topic doc. No per-language agents (stack expertise lives in CLAUDE.md/CODEMAP).
