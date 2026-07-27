---
Status: Accepted
Date: 2026-07-27
---

# ADR-0025 — Carrying findings back to the framework, by allowlist

## Context

ADR-0023 gave each install an append-only record of the harness's own mistakes. That record is
only worth keeping if it can improve the *next* install, and there was no path of any kind from
an installed repo back to the marketplace repo — every data path ran outward. `RECOMMENDATIONS.md`,
the file that drives each round of framework changes, was written from recollection and one
external audit.

The obvious design — ship the journal upstream — is wrong. A journal that is safe to keep in
your own repo is not automatically safe to hand to someone else. Repo-relative paths are still
your architecture. Branch names carry initiative names. Epic ids carry product plans.

## Decision

A separate, stricter export pass producing `.orch/exports/<repo-hash>-<date>.json`, and **no
transport at all**. The exporter writes a file; moving it is the operator's decision. No network
call, no upstream identity in the installed repo, nothing to consent to.

Three choices carry the weight:

**Redaction by allowlist, not deny-list.** Only known-safe fields survive the projection. A
field added to the journal later cannot leak by default — it is simply absent until someone adds
it deliberately. A deny-list would have to be maintained forever and would fail silently the
first time it was not.

**The redaction verifies itself, and fails closed.** After projection, the bundle is checked for
a `$HOME` fragment, an absolute path, an `@`, and a URL. Any hit aborts and writes nothing. A
redaction pass that is never checked is one that silently regresses; this repo already shipped a
template containing a machine username once (`RECOMMENDATIONS.md` R3), which is precisely that
failure. Paths survive only as `{depth, ext}`.

**The repo is a salted hash.** Same repo hashes the same across exports so batches join into a
time series; the salt is per-repo, generated locally, and never leaves — so the id does not
reverse to a path and two repos never collide.

On the receiving side, `/ingest-findings` ranks by **how many distinct repos** hit a thing
rather than by raw count, so one pathological loop cannot dominate, and refuses to call anything
seen in fewer than two repos a framework problem. Bundles are treated as untrusted data: read as
JSON, never executed, and any directive-shaped text inside them is ignored.

## Consequences

The metric the whole thing exists for is `correction.attempted` vs `correction.succeeded`:
how often the harness noticed it was wrong and fixed itself, against
`correction.humanInterventions`, how often it needed a person. That is the honest measure of how
autonomous a run actually was, and it is now measurable rather than asserted.

A bug this surfaced immediately: jq's `//` operator treats `false` as null, so `corrected: false`
— a *failed* correction, the most interesting event in the set — vanished from the projection and
the success rate read 100%. Booleans need `has()`, not `//`. Pinned by a test.

Acting on findings in this repo still goes through a human PR, because
`protect-policy-paths.sh` blocks agent edits to `.claude-plugin/*` and `plugins/*/hooks/*`. That
is deliberate: a framework that rewrote its own guardrails from field telemetry is exactly the
thing the guardrails exist to prevent.
