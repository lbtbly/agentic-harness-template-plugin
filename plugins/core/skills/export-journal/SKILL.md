---
name: export-journal
description: "Turns the harness journal into a redacted bundle you can carry back to the marketplace repo. Use before reporting harness problems upstream."
argument-hint: "[--since YYYY-MM-DD]"
disable-model-invocation: true
---

# /core:export-journal — hand the framework evidence about itself

The harness records its own mistakes in `.orch/journal/<date>.jsonl` (ADR-0023): guard blocks,
failing commands, human corrections, model escalations, integration reverts, formatter rewrites.
This skill turns that into one bundle that is safe to share, so the framework can be fixed with
evidence instead of recollection.

**Nothing is sent anywhere.** It writes a file. Moving it is your decision.

## DO

1. Run the exporter:
   `bash orchestrator/bin/journal-export $ARGUMENTS`
   It prints the path it wrote (`.orch/exports/<repo-hash>-<date>.json`).

2. **Show the bundle to the operator in full before doing anything else with it.** It is small
   and they are the only person who can judge whether it is fine to share. Do not summarise it
   in place of showing it.

3. Read the ranking back to them: which of the harness's rules fired most, whether corrections
   succeeded, and how often a human had to intervene. That last number is the honest measure of
   how autonomous the run actually was.

## What is in it, and what is deliberately not

Kept: event counts by kind and key, failure classes, whether a correction succeeded, coarse file
extensions, and a salted repo hash so several exports from the same repo can be joined.

Never present: timestamps below a date, session or branch names, epic ids, PR numbers, job
names, log excerpts, commands, your prompts, file names, repo name, URLs. Paths survive only as
`{depth, ext}` — a repo-relative path is still your architecture.

The exporter **verifies its own redaction and refuses to write** if a `$HOME` fragment, an
absolute path, an `@`, or a URL survives. That check is the feature; if it ever fires, report it
rather than working around it.

## Reading it

`correction.attempted` vs `correction.succeeded` is the number to look at: it says how often the
harness noticed it was wrong and fixed itself. `correction.humanInterventions` is the
complement — how often it needed you. A `byKey` entry that dominates is usually not a discipline
problem but a missing rule: the harness enforced something after the fact that it never taught
up front.

## Opting out entirely

If the journal should not exist in this repo at all: `.claude/policy.json` `{"journal": false}`,
or `CLAUDE_POLICY_JOURNAL=0`. Guards still block; only the record stops.
