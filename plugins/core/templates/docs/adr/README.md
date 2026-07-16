# ADRs — Architecture Decision Records

The WHY behind structural choices. Convention:

- Numbered (`NNNN-kebab-title.md`), chronological order.
- **Immutable once accepted** (the protect-paths hook enforces this): to change a
  decision, write a new ADR that supersedes the old one.
- `Status:` values: Proposed → Accepted | Rejected | Superseded by ADR-NNNN.
- When to write an ADR: structural lib choice, module boundary change, third-party
  service, LLM model, data strategy. The `architect` agent produces ADR drafts;
  `/core:doc-health` flags decisions made without an ADR.
- Each accepted ADR adds a line to the "Decided" section of the CHANGELOG.

> This project starts with only **0001** (which establishes the practice). Your own
> ADRs start at **0002**. The harness's own design decisions live in the
> `your-org/agentic-harness-template-plugin` repo, not here.

## Index
- [0001 — Record architecture decisions](0001-record-architecture-decisions.md)
