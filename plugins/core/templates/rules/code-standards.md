# Code standards — baseline (always loaded)

<!-- No `paths:` frontmatter → loaded every session, like the contract. Keep it
     SHORT (context cost). Detail + stack-specific rules: docs/CODE-STANDARDS.md
     and .claude/rules/<lang>.md (added by /core:new-project). -->
<!-- Rule metadata (optional, recommended): a rule line may end with
     `(since: <why/when it was added>, expires: <condition to remove it>)`.
     Rules without an expiry accumulate forever — /core:doc-health's
     instruction audit flags stale/contradictory ones for triage. -->

- **Think first** — state assumptions, surface tradeoffs, ask before guessing; don't hide confusion.
- **Goal-driven** — define the success criterion up front, then loop until it verifies.
- **Match surrounding code** — naming, layout, idioms, comment density.
- **Small, single-purpose units**; names say intent; no dead or speculative code (YAGNI).
- **Handle errors by likelihood** — boundary/untrusted input: always validate (no silent catches); provably-impossible states: skip (YAGNI on error paths); uncertain: skip but leave a `// EDGE:` marker for human triage.
- **No secrets in code** — env/vault only, NAMES not values (`docs/SECURITY.md`).
- **Tests are the guardrail** — new behavior ships with a test; never weaken a test to pass.
- **Comment the *why***, not the *what*.
- **Simplest ≠ shortest/cleverest** — fewer concepts and branches, not fewer lines. Would a senior engineer call it overcomplicated? then simplify.
- **Surgical changes** — every changed line traces to the task; never rewrite what works; clean up only the mess your change made.
- **Early returns over nesting**; no new dependency without a strong, stated reason.
- **Conventional Commits**; focused diffs (the formatter runs on save).

Detail → `docs/CODE-STANDARDS.md`. Stack-specific rules → `.claude/rules/<lang>.md`.
