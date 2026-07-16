---
paths:
  - "**/*.py"
---
# Code standards — Python

- **Type hints** on public functions; run `mypy`/`pyright` if adopted (record in STACK.md).
- **Formatter + linter: ruff** (`ruff format` + `ruff check`; config in `pyproject.toml` drives
  `format-on-edit.sh`). Target the project's min Python version.
- Prefer `pathlib` over `os.path`; dataclasses/pydantic over ad-hoc dicts at boundaries.
- Errors: raise specific exceptions; never bare `except:`; no silent `pass` in handlers.
- No mutable default args; isolate I/O for testability.

_Baseline (all languages): `docs/CODE-STANDARDS.md`._
