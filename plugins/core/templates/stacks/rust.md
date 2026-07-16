---
paths:
  - "**/*.rs"
---
# Code standards — Rust

- **Formatter: rustfmt** (drives `format-on-edit.sh`). **Linter: clippy** (`cargo clippy -- -D warnings`).
- Prefer `Result`/`?` over `unwrap()`/`expect()` outside tests and provably-infallible paths.
- Model errors with an enum (`thiserror`); avoid `panic!` for recoverable conditions.
- Keep `unsafe` rare, localized, and commented with its invariant.
- Borrow over clone; make illegal states unrepresentable via the type system.

_Baseline (all languages): `docs/CODE-STANDARDS.md`._
