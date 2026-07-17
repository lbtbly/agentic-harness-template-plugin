---
name: triage-suggestions
description: "Human-gated triage of machine-generated suggestions: accept promotes to a Backlog epic, reject cancels. Use when the Suggested queue has items — the night loop never touches them."
disable-model-invocation: true
---

# /core:triage-suggestions

Reviews the **Suggested** queue and, per the human's call, promotes each item to a
`Backlog` ticket or cancels it. This is the **Confirm** step of DDPC — the machine
proposed (via `// EDGE:` markers, growth-detection, or the orchestrator); the human
decides here. `/core:doc-health` only *reports* the queue; this skill is the one that *acts*.

Backend-adaptive substrate (ADR-0011): with a remote board, suggestions live in its
`Suggested` column; with the `none` backend, in `docs/SUGGESTIONS.md`. This skill talks to
the `orch state` contract, so it works the same either way.

## Steps

1. **List** the open suggestions: `orch state pull-suggestions` (JSON: `{id, text, …}`
   per unchecked/Suggested item). If empty, say so and stop.
2. **Present** them to the human in a compact list. For each, offer a recommendation
   (e.g. `// EDGE:` flags usually deserve a quick "is this reachable?" judgment) but do
   **not** decide — surface the tradeoff.
3. **Per the human's decision**, call once per item:
   - accept → `orch state triage-suggestion --id <id> --decision accepted [--note "..."]`
     — marks it handled and creates a `Backlog` ticket (via `push-epic`) that enters the
     normal flow.
   - reject → `orch state triage-suggestion --id <id> --decision rejected [--note "why"]`
     — marks it `Cancelled`; no ticket is created.
   Re-run `pull-suggestions` between rounds if ids shifted (the `none` substrate numbers
   the remaining unchecked lines).
4. **Report** what was accepted (with the new epic ids) and rejected. Accepted tickets are
   now visible via `orch state pull-status` (state `Backlog`).

## Guardrails

- **Never auto-decide.** Every accept/reject is the human's; the skill only executes the
  chosen transition. Uncertain items stay in the queue.
- **The autonomous loop never sees `Suggested`** — it pulls only `Backlog`/`Planned`/
  `Changes-requested` (ADR-0011 loop-safety invariant). Acceptance is what lets a
  suggestion become buildable.
- Do not edit `docs/SUGGESTIONS.md` by hand — go through `orch state triage-suggestion`
  so the board/file and the epic store stay consistent.

Propose commit when done: `chore: triage suggestions (N accepted, M cancelled)`.
