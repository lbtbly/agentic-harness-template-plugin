---
Status: Accepted
Date: 2026-07-06
---

# ADR-0011 — Confidence-gated error handling + human-gated suggestion lifecycle (amends ADR-0007)

## Context
Two of our own rules pull in opposite directions. Karpathy's "don't handle edge
cases that won't occur" argues against speculative error paths (YAGNI applies to
`try/catch` too); CLAUDE.md's non-negotiable rule says "validate untrusted input
at the boundary" and "no silent catches." Left unreconciled, an LLM writing code
will either over-armor internal helpers with dead defensive branches, or — worse —
silently drop a handler it *judged* unnecessary, making an unreviewable
correctness call on the human's behalf.

Separately, the `none` backend already accretes machine-generated findings:
`growth-detection.sh` harvests into `docs/SUGGESTIONS.md`. These have no defined
lifecycle — nothing says how a suggestion becomes real work, who decides, or how
the autonomous nightly loop must treat un-triaged items. Without a contract, a
suggestion is either lost in a file nobody reads, or (dangerously) picked up and
acted on by the loop as if it were approved backlog.

## Decision
- **A three-way confidence gate governs every error-handling decision:**
  - *Provably-impossible internal state* → skip handling. YAGNI applies to error
    paths; a dead branch is complexity, not safety.
  - *Boundary / untrusted input* (HTTP, files, env, CLI args) → **ALWAYS handle**.
    Unchanged non-negotiable; the gate never relaxes this.
  - *Uncertain* ("might not occur, but I can't prove it") → skip the handling to
    keep the code simple, **but leave an inline `// EDGE:` marker** naming the
    unproven assumption. The judgment is surfaced for **human** triage, never
    silently made by the LLM. This is DDPC: Detect, Diagnose, Propose, Confirm —
    the machine proposes, the human confirms.
- **A human-gated suggestion lifecycle is added to the `orch state` contract**
  (three new ops, backend-adaptive): `push-suggestion`, `pull-suggestions`,
  `triage-suggestion`.
  - *Substrate is backend-appropriate, one contract:* with a **remote** backend
    (github-projects/gitlab/…) suggestions live in that board's "Suggested"
    column/label; with the **`none`** backend they live in the local
    `docs/SUGGESTIONS.md` queue (the existing growth-detection file).
  - *Lifecycle states* (string literals, no code enum):
    `Suggested → Accepted → Backlog | Rejected → Cancelled`. An **Accepted**
    suggestion becomes a normal `Backlog` ticket via the existing `push-epic`
    path and enters the standard flow; a **Rejected** one is `Cancelled`
    (terminal).
  - *Producers:* `// EDGE:` markers (harvested by `growth-detection.sh` into
    SUGGESTIONS.md), other growth-detection findings, and orchestrator/agent ideas.
  - *Triage is human-only:* a new **mutating** `/triage-suggestions` skill;
    `/doc-health` stays strictly read-only.
- **Loop-safety invariant (explicit):** the autonomous nightly loop only ever
  pulls `Backlog`/`Planned`/`Changes-requested` — **NEVER `Suggested`**. It is
  structurally incapable of acting on an un-triaged suggestion.
- **State ≠ feedback (ADR-0007) is preserved, explicitly:** suggestion
  accept/reject is *backlog triage on the board/in the file*, not code-review
  feedback — there is no PR yet — so it correctly lives on the board/in the file
  and does **not** violate ADR-0007's rule that PR-approval signals come only
  from the forge (`gh`/`glab`). The two must not be conflated.

## Consequences
- The LLM never silently drops error handling: an uncertain call becomes a
  visible `// EDGE:` marker that flows into the triage queue instead of vanishing.
- Simple code stays simple — provably-dead branches are not written, boundary
  validation is never skipped, and the middle case is deferred to a human rather
  than guessed.
- Suggestions are visible where the team already works (their board, or the file
  for `none`), under one contract with backend-appropriate storage.
- The autonomous loop stays safe by construction: the pull filter excludes
  `Suggested`, so no un-triaged item can be actioned.
- **Deferred (YAGNI):** the remote-adapter implementation of the three ops is
  **not** built until a project actually runs a remote backend for suggestions.
  The stubs list the ops but reject with exit 64 ("command line usage error");
  the ADR defines the contract now, implementation follows real need — mirroring
  ADR-0007's stub-until-needed posture for jira/notion/linear/trello.
- The new lifecycle states are **string literals, not a code enum**; they are
  documented here and in `orchestrator/README.md` rather than by editing the
  frozen `conception/` design doc (frozen-plan rule: supersede, don't rewrite).
- **Amends ADR-0007** by extending the `orch state` contract with the three
  suggestion ops. Per the immutability convention, ADR-0007 is left intact as a
  historical record and is not edited.
