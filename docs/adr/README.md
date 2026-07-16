# ADRs — Architecture Decision Records

The WHY behind structural choices. Convention:

- Numbered (`NNNN-kebab-title.md`), chronological order.
- **Immutable once accepted** (the protect-paths hook enforces this): to
  change a decision, write a new ADR that supersedes the old one.
- `Status:` values: Proposed → Accepted | Rejected | Superseded by ADR-NNNN.
- When to write an ADR: structural lib choice, change in module boundaries,
  third-party service, LLM model, data strategy. The `architect` agent produces
  ADR drafts; /doc-health flags decisions made without an ADR.
- Each accepted ADR adds a line to the "Decided" section of the CHANGELOG.

> **Numbering note.** This repo inherited the load-bearing decisions of the working
> implementation it was distilled from; only the ADRs that shipped skills/hooks actually
> cite were carried over, keeping their original numbers (hence gaps: 0002–0006, 0010,
> 0014 were distribution-history decisions that no shipped file references). This repo's
> own decisions — the verified deviations of docs/DEVIATIONS.md — start at 0016.

## Index

Inherited (cited by shipped skills/hooks/templates):
- [0001 — Record architecture decisions](0001-record-architecture-decisions.md)
- [0007 — Externalized state via the `orch state` adapter contract](0007-externalized-state-orch-state.md)
- [0008 — Orchestrator as opt-in top module with pluggable runtimes](0008-orchestrator-top-module.md)
- [0009 — Accept the `settings.json` Bash-redirection gap](0009-settings-bash-redirection-hole.md)
- [0011 — Confidence-gated error handling + human-gated suggestion lifecycle](0011-human-gated-suggestion-lifecycle.md)
- [0012 — Monorepo project layout: control-plane at root, product code under `apps/*`](0012-monorepo-project-layout.md)
- [0013 — Plugin-only distribution](0013-plugin-only-distribution.md)
- [0015 — Autonomous run-to-completion with risk-gated auto-merge](0015-autonomous-run-to-completion.md)

This repo's own (the verified deviations — research log in [../DEVIATIONS.md](../DEVIATIONS.md)):
- [0016 — Decorrelated judge panel (distinct model per lens)](0016-decorrelated-judge-panel.md)
- [0017 — Risk classification fails closed to high](0017-risk-fails-closed.md)
- [0018 — The gated nightly flavor is the recommended default](0018-gated-flavor-default.md)
- [0019 — Subscription token is the primary headless auth lane](0019-subscription-auth-lane.md)
- [0020 — Native OS sandbox on top of the devcontainer](0020-native-sandbox-plus-devcontainer.md)
