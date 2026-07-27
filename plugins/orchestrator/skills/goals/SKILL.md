---
name: goals
description: "Graduates a merged epic's acceptance criteria into standing goals that are re-verified daily, so a finished feature cannot silently regress."
argument-hint: "[epic id | --verify | --retire <name>]"
disable-model-invocation: true
---

# /orchestrator:goals — finished work stays finished

A `feature_list` entry flips `passes:false → true` once and is terminal. Nothing ever looks at
it again, so a regression in something the harness shipped last month is invisible until a human
trips over it. **A goal you verify once is an assumption with a timestamp.**

This graduates finished work into invariants that keep being checked (ADR-0028).

## Graduating an epic (`$ARGUMENTS` = an epic id)

For each acceptance criterion in `.orch/epics/<id>/feature_list.json`, write
`.orch/goals/<name>.md`:

```
predicate: cd $REPO && npm test -- tests/auth 2>&1 | tail -1 | grep -q passing
born: 2026-07-27
source: epic auth-revamp
status: satisfied
last-pass: 2026-07-27
on-violation: wake me. Do not auto-fix.
retire-when: the auth module is deleted. Retirement is a human decision, logged.
```

**The predicate is the whole thing.** It must be a shell command where exit 0 means the
invariant holds, and it must be cheap, deterministic and read-only — this runs every day. If a
shell script cannot check it, it is not a goal; write the criterion differently or leave it out.
Adjectives are not verifiable. Non-code invariants work identically:
`find invoices/overdue -mtime +45 | wc -l | grep -qx 0`.

Not every criterion should graduate. Pick the ones whose silent failure would actually matter,
and say which ones you skipped and why. A `goals/` directory nobody trusts is worse than a small
one.

## Verifying (`--verify`, or the daily lane)

`bash orchestrator/runtime/verify-goals.sh` — exits non-zero if any invariant broke, appends
every result to `.orch/goal-ledger.tsv`, and flips the goal's `status` to `VIOLATED`.

A **timeout counts as a violation**, not a skip: "too slow to check" and "no longer true" are
indistinguishable from outside, and treating a timeout as a pass is how a sentinel goes quietly
blind. If a predicate times out, make it cheaper — do not raise the timeout.

## On a violation

Report the goal, its `last-pass` date, and what merged since (`git log --since=<date>`). **Do
not fix it here.** The fix goes through the normal pipeline like any other work; an auto-fix on
a regression nobody has looked at is how a real bug gets papered over. `on-violation` in the
goal file says what the operator wanted.

## Retiring

A goal that no longer applies is **retired, never deleted** — set `status: retired` with a note.
A flaky predicate is also retired ("needs a better predicate"), not quietly removed: the ledger
should still show it existed. Retirement is a human decision.

## Reading the ledger

```
awk -F'\t' '$3!="pass"{n[$2]++} END{for(g in n) print n[g], g}' .orch/goal-ledger.tsv | sort -rn
```
The top entry is either your flakiest predicate or your least stable subsystem. Both are worth
knowing; they are not the same problem and the ledger will not tell you which — go and look.
