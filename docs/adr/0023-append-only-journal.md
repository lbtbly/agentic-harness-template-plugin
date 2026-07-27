---
Status: Accepted
Date: 2026-07-27
---

# ADR-0023 — An append-only journal of the harness's own mistakes

## Context

Every state artefact this harness writes is replace-semantics. `.orch/sessions/<branch>.json`
is overwritten on each push; `.orch/epics/<id>.json` is last-write-wins; the PreCompact
auto-snapshot in `docs/HANDOFF.md` is capped at one. `docs/SUGGESTIONS.md` is the single
append-only file, and its `grep -qF` idempotence guard actively *suppresses* repeats — which is
correct for a to-do list and exactly wrong for a frequency signal.

The consequence: the harness could not answer the one question that would improve it. When a
guard blocked the agent, the block was `stderr` plus `exit 2` and nothing else. When a command
failed, no hook was watching (`PostToolUse` matched `Edit|Write` only). When a human typed "no,
that's wrong", nothing recorded that a person had to intervene. When the model escalation retry
turned a red epic green — an error and its correction in the same variable scope — the pair was
`log()`'d to run stdout and discarded. There was no `UserPromptSubmit`, `SubagentStop` or
`SessionEnd` hook at all, and no path of any kind from an installed repo back to this one.

So each install repeated the previous install's mistakes, and the framework had no evidence
about which of its own rules were load-bearing and which were noise.

## Decision

One append-only event stream, `.orch/journal/<YYYY-MM-DD>.jsonl`, written by the **harness**
rather than by the agent. NDJSON, one event per line, `{ts, sid, kind, key, …}`. `sid` is
Claude Code's session id where available and the branch otherwise — enough to join an error to
the correction that followed it.

Producers: the six guard-block sites (through a shared `journal()` in `policy-lib.sh`, which all
six already funnel through), a widened `PostToolUse` observer on `Bash|Edit|Write|NotebookEdit`
reading `tool_response`, new `UserPromptSubmit`/`SubagentStop`/`SessionEnd` hooks, the formatter
(a rewrite means the agent produced non-conforming code — a real signal that was being destroyed
silently), and the nightly workflow's escalation and integration-revert paths.

Three properties are load-bearing:

- **It records classifications, never content.** The verb of a failed command, not the command
  line. The shape of a correction, not the user's words. The rule that fired, not the secret path
  that triggered it. Free text is where absolute paths, hostnames and credentials leak, and
  `RECOMMENDATIONS.md` R3 exists because exactly that was committed once.
- **It is advisory.** Every observer exits 0 and blocks nothing. `UserPromptSubmit` observers
  emit no stdout, because a `UserPromptSubmit` hook's stdout is injected into the model's context.
- **It is refusable.** It follows the standard `CLAUDE_POLICY_<KEY>` > `.claude/policy.json` >
  default chain under the `journal` key. It defaults ON — passive accretion is the whole point —
  but `{"journal": false}` writes nothing, and the guards still block either way.

Journal ops (`push-journal`, `pull-journal`) are **local-only** in `bin/orch` and never delegate
to a board adapter: this is the harness's own telemetry, not board data.

## Consequences

Fixed in passing: `bin/orch` delegated every op except `pull-feedback` to the board adapter, so
on any remote backend `import`, `push-suggestion`, `pull-suggestions` and `triage-suggestion`
reached an adapter that threw `unknown op` and exited 1. The whole suggestion lifecycle worked
on `backend: none` alone while `/core:triage-suggestions` claimed it "works the same either
way". Local-only ops are now an explicit list.

Deliberately **not** OpenTelemetry. `docs/DEVIATIONS.md` §7 rejected harness-emitted OTel spans
as breaking the zero-dependency posture; that still holds, and a JSONL file needs no collector.
The docs-only pointer in `SCHEDULED-AGENTS.md` stands for anyone who wants the full thing.

The export path (redaction, and carrying bundles back to the marketplace repo) is deliberately
separate and stricter — a journal safe to keep in your own repo is not automatically safe to
hand to someone else.
