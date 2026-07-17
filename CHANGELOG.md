# Changelog

All notable changes to the harness marketplace. Format: Keep a Changelog; versions are
the marketplace `metadata.version` (per-plugin versions in each plugin.json).

## [Unreleased]

## [1.4.1] — 2026-07-17
### Fixed
- CI's first run caught three real bugs: 7 skill frontmatters were unparseable
  (unquoted colons from the 1.4.0 description rewrites — they loaded with EMPTY
  metadata at runtime, silently dropping disable-model-invocation); the
  parallel-merge test lacked git identity on CI runners; the START_HERE embed
  payload was platform-dependent (unsorted walk order). New frontmatter-lint
  suite prevents the first class permanently.

## [1.4.0] — 2026-07-17
### Security
- Guard hooks FAIL CLOSED when jq is missing (they silently disabled themselves);
  explicit timeouts on every hook (guards 10s vs the 600s default); sandbox
  credential walls + egress allowlist parity (native sandbox ↔ devcontainer
  firewall, single source); pinned MCP server list for unattended runs.
### Added
- LICENSE (MIT); CI on the marketplace itself (tests, plugin validate, embed
  drift, version discipline); CONTRIBUTING release policy; manifest discovery
  metadata + core dependency declarations; keychain-backed userConfig
  (board_token, plugin_repo_url); policy-gated Stop gate (default OFF); model
  ladder externalized to models.config.json; verdict.schema.json for
  schema-validated headless verify; argument-hints + listing-budget skill
  descriptions; forked read-only doc-health/codemap.
### Fixed
- Personal path scrubbed from a shipped template; authenticated parameterized
  runner clone (private marketplaces); six stale references; refactorer agent
  least-privilege tools; ADR-0016 decorrelation wording corrected.

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
