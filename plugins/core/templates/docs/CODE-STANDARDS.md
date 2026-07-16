# CODE-STANDARDS — how we write code here (Layer 2: reference)

> The **cross-language baseline** below is always in force. Stack/language-specific
> rules are added by `/core:new-project` as `.claude/rules/<lang>.md` (path-scoped) plus a
> linter/formatter wired into `format-on-edit.sh`. The lean, always-loaded summary
> lives in `.claude/rules/code-standards.md`; this file is the detailed reference.

## Cross-language baseline (every project, every language)

### Readability & structure
- **Match the surrounding code** — naming, file layout, comment density, idioms. Consistency beats personal preference.
- **Names say intent** — no `data`, `tmp`, `x` for things that have a real meaning. Functions are verbs, values are nouns.
- **Small, single-purpose units** — a function does one thing; a file has one responsibility. If you can't summarize it in a sentence, split it.
- **No dead code** — delete it, don't comment it out (git remembers). No speculative abstractions (YAGNI): no indirection before the 2nd real use.

### Correctness & safety
- **Handle errors by likelihood — the confidence gate (ADR-0011):**
  - **Boundary / untrusted input** (HTTP, files, env, CLI) — *always* validate where it enters, not deep inside; no silent catches, no ignored return codes. Fail loud and early. *(Non-negotiable — never relaxed.)*
  - **Provably-impossible internal state** — don't add speculative handling; YAGNI applies to error paths too.
  - **Uncertain** ("might not occur, can't prove it") — keep the code simple (skip the handling) **but** leave an inline `// EDGE:` marker. It's harvested into the suggestion queue for **human** triage — never silently decide it "won't happen." See `/core:triage-suggestions`.
- **No secrets in code** — values come from the environment/vault; code handles variable NAMES only (see `docs/SECURITY.md`).
- **Deterministic by default** — isolate time, randomness, and I/O so logic is testable.

### Tests are the guardrail
- New behavior ships with a test; a bug fix ships with the test that would have caught it.
- **Never weaken or delete a test to make it pass** — fix the code, or flag the test explicitly (non-negotiable rule).
- Prefer fast, isolated tests; reserve slow/integration tests for real integration risk.

### Comments & docs
- Comment the **why**, not the **what** — the code says what. Note non-obvious constraints, invariants, and gotchas.
- Public/exported surfaces get a one-line doc-comment describing contract + failure modes.

### Commits & change hygiene
- **Conventional Commits** (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`, `refactor:`, `test:`). One logical change per commit.
- Keep diffs focused — no drive-by reformatting mixed with logic changes (the formatter runs on save via `format-on-edit.sh`).

## Examples (before/after)

**Simplicity — no speculative machinery.**
- ✗ A `RetryPolicy` class with pluggable backoff for a script that calls one endpoint once.
- ✓ Call it; handle the one failure that can happen (network error) at the boundary.

**Surgical — every changed line traces to the task.**
- ✗ Fix the bug *and* reformat the file, rename unrelated vars, "tidy" an adjacent function.
- ✓ Change only the buggy branch; leave the rest — including its style — untouched.

**Think first — surface the fork instead of guessing.**
- ✗ Requirement says "cache the results" → silently wire in Redis.
- ✓ "Cache in-memory per-process, or shared across instances? Assuming in-memory unless you need cross-instance." Then build.

**Confidence gate — the uncertain edge case.**
- ✗ `// this can never be null` then dereference it (an LLM guess about what "won't occur").
- ✓ `if (!x) { /* EDGE: can x be null here? assumed no — validate */ return }` — code stays simple, judgment goes to human triage.

## Stack-specific layers (filled by `/core:new-project`)
When the stack is chosen, `/core:new-project` adds the matching pack. Representative defaults:

| Stack | Formatter | Linter / rules | Path-scoped rule file |
|---|---|---|---|
| TypeScript / JS | Prettier | ESLint (strict, no-floating-promises), `strict: true` | `.claude/rules/typescript.md` |
| Python | ruff format | ruff (+ type hints, `mypy`/`pyright` if adopted) | `.claude/rules/python.md` |
| Go | gofmt | `go vet`, golangci-lint | `.claude/rules/go.md` |
| Rust | rustfmt | clippy (deny warnings) | `.claude/rules/rust.md` |

Each pack: (1) drops the linter/formatter config, (2) wires the formatter into
`format-on-edit.sh`, (3) adds a short `.claude/rules/<lang>.md` with the language's
non-obvious conventions, and (4) optionally adds a lint step to the chosen CI.

> _(This table is the menu; `/core:new-project` records the actual choices in `docs/STACK.md`.)_
