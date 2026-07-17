# Contributing — release discipline

## Version policy (distribution correctness, not cosmetics)
`version` in each `plugins/<name>/.claude-plugin/plugin.json` is the **update cache
key**: an unbumped version can leave installed users on stale cached content after
`/plugin update`. Therefore:

- **Any commit that changes files under `plugins/<name>/` bumps that plugin's version**
  (semver: fix → patch, feature/template change → minor, breaking contract → major).
- **Any release bumps `.claude-plugin/marketplace.json` `metadata.version`** and gets a
  git tag `v<version>`.
- CI enforces the plugin-dir↔bump rule (see `.github/workflows/ci.yml`).

## Release checklist
1. `bash tests/run-tests.sh` — all suites green.
2. Bump versions per the policy above; update `CHANGELOG.md` (Keep a Changelog).
3. `python3 tools/embed-files.py` — refresh the START_HERE payload; sync its prose if
   behavior changed.
4. `claude plugin validate` on each plugin + the marketplace root (CI also runs it).
5. Tag `v<marketplace version>`, push with tags.

## Deferred backlog (deliberate, with reasons)
- **Agent SDK port of the workflows** (external audit D3): spike `dod-verify` on the
  Claude Agent SDK in a dedicated round; MUST verify the subscription-token auth lane
  (ADR-0019) before adopting. Workflows are prompt-interpreted specs until then.
- **Setup-hook CI lane** (R21): evaluate `claude -p --init` Setup hooks for runner prep.
- **Guard-chain consolidation** (R22): measure PreToolUse latency first; only
  consolidate the 3 Edit|Write guards if timings justify it.
