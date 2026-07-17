# Changelog

All notable changes to the harness marketplace. Format: Keep a Changelog; versions are
the marketplace `metadata.version` (per-plugin versions in each plugin.json).

## [Unreleased]

## [1.3.0] — 2026-07-17
### Added
- Market-audit remediation: ADR-0022 (Claude-Code-native by design), upgrade mode in
  new-project, review→rule capture in kickoff, `disable-model-invocation` on all
  side-effectful skills.
### Fixed
- README test-count freshness.

## [1.2.0] — 2026-07-17
### Added
- Lecture-audit round: day-0 test harness scaffolding, verifier-owned `evidence` on the
  feature contract, per-phase run metrics + VCR in the digest, clean-exit checklist in
  handoff, rule `since:/expires:` metadata + doc-health instruction audit.

## [1.1.0] — 2026-07-16
### Added
- Native Jira semantics (ADR-0021): Epic issue type, parent links, statusMap
  transitions with label fallback; board-setup MCP-first lane; assignee + complexity
  on board cards; per-day report folders with screenshots; terracotta digest palette.

## [1.0.0] — 2026-07-16
### Added
- Initial marketplace: core / formatting / orchestrator / ci / workbench; DoD contract
  + independent verifier; planner; run-to-completion driver + guards; risk-gated
  auto-merge + safety wiring; field-test protocol.
