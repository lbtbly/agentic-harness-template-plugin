---
paths:
  - "**/*.go"
---
# Code standards — Go

- **Formatter: gofmt** (drives `format-on-edit.sh`). **Linter: `go vet` + golangci-lint.**
- **Handle every error** — check `err`; wrap with `fmt.Errorf("...: %w", err)` for context; never `_ = err`.
- Accept interfaces, return structs; keep interfaces small and defined at the consumer.
- Use `context.Context` for cancellation/deadlines on I/O paths.
- No panics for expected errors; `defer` for cleanup.

_Baseline (all languages): `docs/CODE-STANDARDS.md`._
