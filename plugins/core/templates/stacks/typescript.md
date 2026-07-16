---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---
# Code standards — TypeScript / JS

- **`strict: true`** in tsconfig; no implicit `any`; prefer `unknown` over `any` at boundaries.
- **No floating promises** — `await` or explicitly `void`; handle rejections.
- **Formatter: Prettier** (config drives `format-on-edit.sh`). **Linter: ESLint** (typescript-eslint,
  `no-floating-promises`, `no-explicit-any`).
- Prefer `const`; narrow types at the boundary; avoid enums in favor of union literals.
- Errors: throw `Error` subclasses with context; never `throw` strings.

_Baseline (all languages): `docs/CODE-STANDARDS.md`._
