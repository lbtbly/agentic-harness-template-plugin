---
name: watch
description: "Live view of a run-to-completion build — which epic, which agent, which tool, and why a wave failed. Read-only; renders the stream run-to-done.sh writes."
argument-hint: "[--replay | --errors | --date YYYY-MM-DD]"
---

# /orchestrator:watch

`/orchestrator:run` hands the build to `run-to-done.sh`, a bash loop that calls
`claude -p` once per wave. That is deliberate — the loop must survive being
killed and re-entered, which a chat session cannot — but it means the build is
**not** happening in this terminal. This is how you see it anyway.

The driver writes Claude Code's `stream-json` to `.orch/logs/run-<date>.jsonl`
as the run goes, and its stderr to `run-<date>.err`. Nothing is discarded.

## DO

1. **Render it**: `bash orchestrator/bin/watch` — follows today's log and prints
   the agent tree live. Variants: `--replay` (whole run, then exit), `--errors`
   (the stderr log), `--date <YYYY-MM-DD>` (an earlier run).
2. **Read the shape, not the volume.** Indentation *is* the agent tree: a line
   under `┌ subagent <type>` came from that subagent, matched on
   `parent_tool_use_id`. `▸` is a tool call, `✗` a failed one, `└` a subagent
   returning, `──` the session banner and the closing turns/cost/duration.
3. **When a wave failed**, go to `--errors` first. The exit code and the last
   stderr lines are the diagnosis; the epic's board note (`orch state
   list-epics`) only tells you *that* it escalated.
4. **Report what you see** in terms of the loop's own vocabulary — which epic,
   which phase, which gate — not a transcript dump. The log is the evidence,
   your summary is the answer.

## Notes

- **Read-only.** This skill never edits, never merges, never touches the board.
  If the run needs a decision, that decision is made through `/orch approve` or
  `/orch revise: <notes>` on the PR, not here.
- **A subagent cannot ask you anything mid-run.** Headless `claude -p` has no
  interactive channel, so uncertainty fails closed instead: the verifier
  defaults to reject, the epic lands in `Needs-review` or `Blocked` with a note,
  and it waits as a PR. Watching tells you it happened; it does not open a
  conversation.
- **`--forward-subagent-text` is what makes the tree a tree.** The driver probes
  for it and degrades to a flat stream on an older CLI (< v2.1.211) rather than
  failing every wave on an unknown flag. A flat view means an old CLI, not a
  broken run.
- **No log at all?** Either the run has not started, or the scaffold predates
  this feature — re-copy the runtime with
  `cp -R "${CLAUDE_PLUGIN_ROOT}/templates/orchestrator/." orchestrator/`.
- Logs are machine-local and self-ignoring (`.orch/logs/.gitignore`); they never
  reach a commit or the `orch/state` branch. `ORCH_STREAM=0` reverts the driver
  to whole-run JSON, still logged, never discarded.
