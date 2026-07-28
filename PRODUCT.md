# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

**Primary — a developer deciding whether to adopt the harness.** They have found the
repo or been sent it, they already use Claude Code, and they are trying to answer one
question: *can I trust this thing to write code while I am asleep?* They are skeptical
by default and read the safety story before the feature list.

**Secondary — the same person after installing.** They come back to `START_HERE.html`
for the mental model (what runs when, what gates what) and to `BOARD_SETUP.html` to
provision an external board. That second visit is a task, not a decision.

`START_HERE.html` serves both, **evaluation first**: it must earn the install, then
keep working as the reference. `BOARD_SETUP.html` serves only the task.

## Product Purpose

Run a coding agent unattended overnight on Claude Code, packaged as a plugin
marketplace. It exists because the hard problem in autonomous coding is not generating
code — it is **knowing when the work is actually done**. Success is a developer waking
up to reviewable PRs they can trust, with a digest explaining what happened and what
needs attention.

## Positioning

**Gated autonomy.** The human-in-the-loop invariants survive every mode and are not
configuration: a plan is approved live before anything builds, merges to `main` need a
per-PR operator OK (never bulk), the committed `settings.json` keeps plan mode and
disables bypass, and the loop runs under its own profile inside a sandbox. Autonomy is
*earned per class of work* through a trust ledger rather than switched on (ADR-0026).

**Claude Code native by design.** The edge is the enforcement layer — hooks, permission
profiles, the loop — which only Claude Code runs. There is deliberately no AGENTS.md
interop (ADR-0022), and distribution is plugin-only (ADR-0013).

## Operating Context

- macOS / Linux / WSL2. Native Windows is unsupported: the hooks and state CLI are
  POSIX shell + `jq`.
- Both pages are opened **from a local clone over `file://`**. The reader is already
  warm — they have cloned or installed. Nothing may depend on a network fetch, and
  there is no server, no build step and no analytics.
- The daily ritual the product is designed around: review overnight PRs → approve or
  revise per PR → `/orchestrator:kickoff` in the morning → the build fires on its own
  schedule → next morning's digest is waiting.

## Capabilities and Constraints

- **Five plugins** at v1.8.0 — `core` (scaffolder, guard hooks, state layer, review
  agents), `orchestrator` (the overnight loop), `workbench`, `formatting`, `ci`.
- **Four runtimes** for the loop: `local` (on the operator's own machine, no stored
  credentials), `routines`, `github-actions`, `gitlab-ci`.
- **State backends**: `none` (local `.orch/`), github-projects, gitlab, jira, notion,
  linear — the last three with native semantics. Trello is a stub. The board outlives
  the loop; PR feedback always comes from the forge, never the board.
- **12 lifecycle states**: Suggested, Backlog, Needs-plan, Planned, In-progress,
  Needs-review, Changes-requested, Approved, Merged, Blocked, Paused, Cancelled.
- **26 ADRs** carry the decisions; an accepted ADR is immutable and superseded rather
  than edited.
- **962 test assertions** across 39 suites, plus four CI gates (suite, plugin manifest
  validation, START_HERE payload drift, version discipline).
- `START_HERE.html` embeds every shipped source file as a JSON payload so the reader can
  browse the repo offline; `tools/embed-files.py` regenerates it and CI fails on drift.
- `BOARD_SETUP.html` makes ~50 factual claims that `tests/test-board-guide.sh` pins to
  the adapters — env var names, config keys, Notion DDL, Linear's stock states, the
  egress hosts. They must survive verbatim.

## Brand Commitments

- The product is **The Overnight Harness**. The repo name
  (`agentic-harness-template-plugin`) is not the product name.
- Derived from a field manual of the same name; every subsystem was verified against
  the July 2026 state of the art before implementation, with deviations recorded in
  `docs/DEVIATIONS.md`.
- Voice: exact, unshowy, willing to state its own limits. The documentation habitually
  names what does *not* work and why — "honest note" sections, recorded exposures,
  explicit non-goals. That candour is the personality; marketing gloss would read as a
  lie about a product whose whole pitch is trustworthiness.

## Evidence on Hand

Real and citable, all verifiable in the repo: 26 ADRs, 962 test assertions across 39
suites, the CI workflow, `docs/DEVIATIONS.md`, the plugin manifests, the 12 lifecycle
states, the four runtimes and six state backends.

**Absent — must not be invented:** there are no users, no adoption or download numbers,
no testimonials, no case studies, no benchmarks, no press, no pricing, no uptime or
performance figures, and no security audit by a third party. No logos beyond the
project's own. If a surface needs social proof, it does not get to have any.

## Product Principles

1. **Trust is the product.** Every claim on a surface must be checkable in the repo;
   an unverifiable boast costs more than the space it fills.
2. **State the limits out loud.** Recorded exposures, unsupported platforms and known
   gaps belong on the page, not in a footnote — that candour is what makes the safety
   claims believable.
3. **The gates are the story.** What the harness refuses to do unattended matters more
   than what it can do.
4. **Density over decoration.** The reader is technical and already warm; many small
   true facts beat a few large gestures.
5. **Offline and self-contained, always.** A page that needs the network is a page that
   fails at the moment someone is evaluating it on a plane.

## Accessibility & Inclusion

No product-specific standard has been established. Two requirements are structural
rather than aspirational: both pages must work in **light and dark**, and both must be
fully usable with no network access.
