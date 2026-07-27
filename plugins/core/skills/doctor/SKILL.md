---
name: doctor
description: "Reports the harness's own context cost — CLAUDE.md size, hook injections, skill sizes, MCP schemas — and what to cut. Read-only."
context: fork
agent: Explore
disallowed-tools: Edit, Write
---

# /core:doctor — what the harness costs you before you type a word

Every turn pre-charges you for the CLAUDE.md, the hooks that inject on every prompt, the skills
whose descriptions sit in the listing, and the tool schemas of every connected MCP server.
Productive tokens are what is left. This framework ships all four, so it is responsible for a
share of that bill and should be able to say how much.

Report, do not fix. **Modify nothing.**

## Measure

1. **CLAUDE.md** — `wc -w` on the project and user files. Over ~1,200 words combined is a
   standing tax on every single turn. Note which sections are things Claude could learn by
   looking at the repo, and which are genuine gotchas — only the second kind earns its place.
2. **Hook injections** — every `SessionStart` and `UserPromptSubmit` hook, and roughly what each
   emits. A hook whose purpose you cannot state in one sentence is costing more than it returns.
   The observe-* hooks in this framework emit *nothing* to context by design; confirm that.
3. **Skills** — `SKILL.md` size per skill, and description length (the description is in the
   listing on every turn; the body is not). Flag skills over ~2,000 words that could use
   progressive disclosure — a short entry file that points at detail files loaded on demand.
4. **MCP servers** — every server in `.mcp.json` under `mcpServers`, since each ships its whole
   tool schema on every request. `TOOLING.md` is CLI-first for exactly this reason.
5. **Rules** — `.claude/rules/*.md`, and whether `paths:` scoping is actually working (the
   canary in `/core:doc-health`). An always-loaded rule file is CLAUDE.md by another name.

## Say what to cut

Rank by cost × how rarely it is relevant. Be specific: name the file and the lines.

Two findings are worth calling out explicitly when you see them:

- **Conflicting instructions.** "Leave documentation as appropriate" next to "DO NOT add
  comments" costs more than either alone — the model has to reconcile them before it can act.
  Contradictions are more expensive than verbosity.
- **Over-constraint.** Rules written for older models can now make output *worse*. Anthropic
  removed over 80% of Claude Code's own system prompt for the Claude 5 generation with no
  measurable loss on their coding evals. If default behaviour is already correct without a rule,
  the rule is a cost with no benefit. Prefer stating intent over enumerating cases, and prefer a
  pointer to an example in the repo over a description of the convention.

## Do not

Do not propose deleting a *security* rule to save tokens. The guard hooks, the secret rules and
the test-integrity rule are not context overhead; they are the point. Cost-cutting stops at the
safety boundary.
