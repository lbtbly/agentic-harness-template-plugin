---
Status: Accepted
Date: 2026-07-27
---

# ADR-0028 — Finished work graduates into an invariant

## Context

The DoD contract is deliberately one-way: a `feature_list` entry may only move
`passes: false → true`, and only after a real end-to-end pass. That is the right rule for
preventing an agent from unmarking inconvenient work, and it has a consequence nobody had
addressed — **`true` is terminal and nothing ever looks again.**

So the harness could tell you a feature passed on the night it was built, and nothing more. A
regression introduced three weeks later in an unrelated epic stayed invisible until a human
tripped over it. Across a long autonomous run, that is precisely the failure the harness exists
to prevent: work that was verified once, drifting, silently, while the loop keeps reporting
green on new work.

## Decision

A merged epic's acceptance criteria **graduate** into standing goals under `.orch/goals/`, each
carrying a shell predicate where exit 0 means the invariant still holds. A daily lane
(`verify-goals.sh`) re-runs every predicate and appends the result to `.orch/goal-ledger.tsv`.

Four properties carry the weight:

**The predicate is the goal.** If a shell script cannot check it, it is not a goal. Adjectives
are not verifiable, and a "goal" that needs a human to judge it is a review item, not an
invariant. This also keeps non-code work in scope — `find invoices/overdue -mtime +45 | wc -l |
grep -qx 0` is as valid as a test command.

**A timeout is a violation, not a skip.** "Too slow to check" and "no longer true" are
indistinguishable from outside the predicate. Treating a timeout as a pass is how a sentinel goes
quietly blind, which is worse than not having one — it produces false confidence. If a predicate
times out, the answer is a cheaper predicate, not a longer timeout. (The bound itself falls back
to a poll loop where `timeout`/`gtimeout` are absent, which is stock macOS — an unbounded
predicate would otherwise hang a daily cron slot.)

**It detects; it never fixes.** A violation goes through the normal pipeline like any other
work. An auto-fix on a regression nobody has looked at is how a real bug gets papered over, and
the whole point of the sentinel is that a human learns something broke.

**Goals are retired, never deleted** — including flaky ones, which are quarantined with "needs a
better predicate". The ledger should still show that the invariant once existed. Retirement is a
human decision.

## Consequences

Not every acceptance criterion should graduate; the skill says so explicitly and asks for the
skipped ones to be named. A `goals/` directory nobody trusts is worse than a small one, and the
temptation is to graduate everything on the night it passes.

The goal ledger becomes a second input to the compost loop alongside the journal and the trust
ledger. A goal that keeps flapping is either a bad predicate or a genuinely unstable subsystem —
the ledger cannot distinguish them, and the skill says so rather than pretending to.

This is the piece that makes a long autonomous run trustworthy over weeks rather than over a
night: the loop's own past output is continuously re-verified, so "done" stops being a claim
about one evening.
