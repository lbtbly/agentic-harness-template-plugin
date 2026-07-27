---
name: The Overnight Harness
description: Matte graphite instrument panel on a dotted canvas — a bench you inspect, not a brochure you scroll.
colors:
  bg: "#0B0B0B"
  surface: "#1C1C1C"
  raised: "#262626"
  ink: "#FAFAFA"
  muted: "#8C8C8C"
  line: "#333333"
  accent: "#3FBF52"
  accent-ink: "#052A0C"
  accent-text: "#3FBF52"
  warn: "#E0A32E"
  negative: "#E0503F"
  negative-text: "#E86A5A"
  code-bg: "#151515"
  dot: "rgba(255,255,255,.10)"
  light-bg: "#F3F3F1"
  light-surface: "#FFFFFF"
  light-raised: "#EAEAE8"
  light-ink: "#0B0B0B"
  light-muted: "#5F5F5C"
  light-line: "#D9D9D5"
  light-accent-text: "#1B6B28"
  light-warn: "#8A5E00"
  light-negative: "#B03325"
  light-code-bg: "#15150F"
  light-dot: "rgba(0,0,0,.13)"
typography:
  display:
    fontFamily: "Inter, 'General Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "clamp(30px, 4.6vw, 50px)"
    fontWeight: 500
    lineHeight: 1.06
    letterSpacing: "-.03em"
  headline:
    fontFamily: "{typography.display.fontFamily}"
    fontSize: "20px"
    fontWeight: 500
    lineHeight: "26px"
    letterSpacing: "-.01em"
  title:
    fontFamily: "{typography.display.fontFamily}"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "-.01em"
  body:
    fontFamily: "{typography.display.fontFamily}"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.65
  body-dense:
    fontFamily: "{typography.display.fontFamily}"
    fontSize: "13.5px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "'JetBrains Mono', ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace"
    fontSize: "10px"
    fontWeight: 500
    lineHeight: 1.4
    letterSpacing: ".06em"
  figure:
    fontFamily: "{typography.display.fontFamily}"
    fontSize: "22px"
    fontWeight: 500
    lineHeight: 1.1
    letterSpacing: "-.02em"
    fontVariation: "tabular-nums"
  code:
    fontFamily: "{typography.label.fontFamily}"
    fontSize: "12.5px"
    fontWeight: 400
    lineHeight: 1.7
rounded:
  xs: "4px"
  sm: "6px"
  md: "8px"
  lg: "10px"
spacing:
  hair: "6px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "22px"
  section: "52px"
components:
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    rounded: "{rounded.lg}"
    padding: "16px"
  callout:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    rounded: "{rounded.lg}"
  callout-header:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.muted}"
    typography: "{typography.label}"
    padding: "6px 14px"
  chip:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.muted}"
    rounded: "{rounded.sm}"
    padding: "2px 8px"
    typography: "{typography.label}"
  chip-live:
    textColor: "{colors.accent-text}"
  chip-human:
    textColor: "{colors.warn}"
  chip-escalation:
    textColor: "{colors.negative-text}"
  button-ghost:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.muted}"
    rounded: "{rounded.md}"
    padding: "7px 10px"
    typography: "{typography.label}"
  button-ghost-hover:
    textColor: "{colors.ink}"
  nav-link:
    textColor: "{colors.muted}"
    rounded: "{rounded.sm}"
    padding: "6px 10px"
    size: "12.5px"
  nav-link-active:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
  file-chip:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.muted}"
    rounded: "{rounded.sm}"
    padding: "3px 8px"
    typography: "{typography.label}"
  figure-cell:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    padding: "13px 16px"
  lifecycle-node:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    rounded: "{rounded.lg}"
    padding: "10px 12px"
    width: "150px"
  code-block:
    backgroundColor: "{colors.code-bg}"
    textColor: "#E6E6E6"
    rounded: "{rounded.lg}"
    padding: "14px 16px"
    typography: "{typography.code}"
---

# Design System: The Overnight Harness

## Overview

**Creative North Star: "The Dark Bench"**

This is a bench you inspect, not a brochure you scroll. Two long documents — `START_HERE.html` and `BOARD_SETUP.html` — are laid out like instrument panels sitting on an infinite dotted work surface: near-black ground, matte graphite cards, hairline rules, and machine-facing strings set in mono so a config key never has to pretend to be prose. Nothing is lit from within. Nothing glows. The reader is a skeptic evaluating whether an autonomous agent can be trusted with their repo, and the visual register has to match the product's own voice: exact, unshowy, willing to state its own limits.

The palette is almost entirely neutral, and that is load-bearing rather than austere. Because the ground is graphite and the type is grey-on-black, the single green (#3FBF52) reads as an instrument light: it means *live signal* — a merge, a happy exit, a feedback edge that actually loops. Amber means a human moment. Red means a gate or a hazard. Those three chromatic slots are the entire color vocabulary; everything else is a neutral step. Density is deliberately high — many small true facts, packed at a 13.5–15px reading size — because the reader is technical and already warm.

The world explicitly refuses the dark-SaaS landing page: no gradient hero, no neon-on-black gloss, no frosted glass, no `backdrop-filter`, no colored glow behind a call to action. Depth comes from one tonal ladder (`--bg` → `--surface` → `--raised`) plus one tight shadow, not from light. The system ships in both light and dark, driven by a `data-theme` attribute on `<html>` with the dark theme as default, because the pages are opened from a local clone and must respect the machine they land on.

**Key Characteristics:**
- Near-black canvas under a 24px radial dot lattice, at 10% white (dark) / 13% black (light)
- One rationed green for live signal; amber for human moments; red for gates
- 1px `--line` hairlines everywhere; corners are 6/8/10px, never pill-shaped
- Mono for every machine-facing string — paths, env vars, states, counts, micro-labels
- One tight shadow (`0 2px 8px rgb(0 0 0 / .5)`), no second elevation on the page body
- A 3% fractal-noise grain overlay to kill banding on the near-black ground; never above 3%
- Fully inline and self-contained: no remote font, stylesheet, script or image, ever

## Colors

A near-monochrome graphite ramp carrying exactly three signal hues, each with one job.

### Primary
- **Signal Green** (`{colors.accent}`): the only saturated color allowed to mean *good*. It fills status dots on happy-path nodes, strokes the "merge / exit" node in the SVG schemas, dashes the live feedback edge, sets the brand mark's center dot, marks the active nav link's left rule, and tints the `p-auto` / `p-core` chip borders. It is never a background fill for a large surface and never a gradient stop.
- **Signal Green (Type)** (`{colors.accent-text}`): the same value in dark, but darkened to `{colors.light-accent-text}` in light because #3FBF52 measures ~2.3:1 on white and cannot set type there. Used for links, `.callout.ok` labels, and accent chip text.

### Secondary
- **Human Amber** (`{colors.warn}`): every place a person must act — `you` lane nodes, `p-gated` / `p-you` chips, warning callout labels, the "human gate" legend swatch. Darkened to `{colors.light-warn}` in light for the same contrast reason.

### Tertiary
- **Gate Red** (`{colors.negative}`): borders, status dots and SVG wires on safety and risk gates only. It never sets type.
- **Gate Red (Type)** (`{colors.negative-text}`): the type-only lift. `{colors.negative}` measures 3.88:1 on `--raised`, under AA for a 10px chip label, so any red *text* — `p-esc` chips, danger callout labels, `.gotcha b` — uses this lighter value instead. In light theme both collapse to `{colors.light-negative}`.

### Neutral
- **Pitch Ground** (`{colors.bg}`): the page canvas and the inside of every schema frame.
- **Graphite Surface** (`{colors.surface}`): cards, callouts, tables, the nav rail, the drawer, lifecycle nodes.
- **Raised Graphite** (`{colors.raised}`): one step up — chip and button fills, table headers, callout header strips, inline `code`, row hover.
- **Paper Ink** (`{colors.ink}`): primary type and the emphasized half of the display headline.
- **Bench Grey** (`{colors.muted}`): body copy inside cards, all mono micro-labels, idle status dots, idle SVG wires. The most-used color in the system.
- **Hairline** (`{colors.line}`): every border, divider, table rule and group box, always 1px.
- **Terminal Ground** (`{colors.code-bg}`): code blocks and the file viewer only — one notch off the page ground so a block of source reads as a different material.
- **Lattice Dot** (`{colors.dot}`): the 24px dot grid.

### Named Rules

**The Rationed Green Rule.** Green means *live signal* — merged, verified, the loop closing. If an element is not reporting a live positive state, it does not get the accent. A page where green appears more than a handful of times has stopped meaning anything.

**The Three Slots Rule.** Green, amber, red. That is the whole chromatic vocabulary; no fourth hue is introduced for any reason, and no hue is introduced by the light theme.

**The Type-Only Lift Rule.** `{colors.negative}` is for borders, dots and wires; `{colors.negative-text}` is for glyphs. Never swap them — the pinned red fails AA at label sizes, and the lifted red is wrong on a 1px stroke.

**The Same Family Rule.** The light theme is the same neutral ramp inverted, not a second palette. Only `--accent-text`, `--warn` and `--negative` shift value, and only to clear contrast on white.

## Typography

**Display / Body Font:** Inter, with General Sans, then the system UI stack
**Label / Mono Font:** JetBrains Mono, with ui-monospace and the platform mono stack
Both are declared as stacks and neither is loaded — no `@font-face`, no remote fetch. The pages render on whatever the machine has.

**Character:** A neutral grotesque doing all the reading, and a mono doing all the machine-talking. The split is semantic, not decorative: if a string is something you would type into a terminal or find in a config file, it is mono; if a human wrote it as a sentence, it is sans.

### Hierarchy
- **Display** (500, `clamp(30px, 4.6vw, 50px)`, 1.06, `-.03em`): exactly one per page, the `<h1>` in the hero, capped at 17ch. On `START_HERE` it is set in `--muted` with the second clause lifted to `--ink`; on `BOARD_SETUP` the second clause is lifted to `--accent-text`.
- **Headline** (500, 20px/26px): every section `<h2>`. This is the working ceiling for the whole document below the hero.
- **Title** (500, 14px): card `<h3>`, step `<h4>`, schema frame titles. An occasional 18px `<h3>` marks a sub-heading inside a long section.
- **Body** (400, 15px, 1.65, max 78ch): the reading size for prose; `.lead` uses the same size in `--muted` at 74ch.
- **Body Dense** (400, 13.5px, 1.55): card and step copy, where density beats comfort.
- **Label** (500, 10px, `.06em`, uppercase, mono): eyebrows, callout header strips, table headers, nav group headers, legends, footers. Always paired with a 6px status dot in the eyebrow and callout cases.
- **Figure** (500, 22px, tabular-nums): the four hero statistics only. Sans, because it is a number a human reads, sitting inside a mono cell.

### Named Rules

**The Twenty-Pixel Ceiling Rule.** Below the hero, nothing exceeds 20px. The one `<h1>` per page is the entire exception; there is no second large moment anywhere on either document.

**The Mono-Is-Machine Rule.** Mono marks machine-facing strings and micro-labels only. Micro-labels are mono at 10px with `.06em` tracking — never tracked uppercase sans, which is the generic-dashboard tell this world refuses.

**The Reading Body Rule.** Body copy is 15px in `--ink`, not the 12px `--muted` of a node canvas. These are documents that must be read end to end, and the reading size is the deviation that makes that honest.

## Layout

A two-column shell: a 268px sticky inspector rail (`--nav-w`) against a fluid main column, both sitting on the dotted canvas at `z-index: 2` so the grain overlay never covers content. The rail is full-height, independently scrolling, and separated by a single hairline; it carries the brand mark, mono group headers, nav links, and the theme toggle at its foot.

Main padding is `clamp(20px, 4vw, 56px)` horizontally with 80px of tail. Sections are separated by 52px of top padding and a 16px `scroll-margin-top` so anchor jumps do not bury a heading. Prose is capped at 78ch, leads at 74ch, hero tagline at 62ch, hero headline at 17ch — measure is enforced by character count, not container width.

The spacing rhythm is tight and even: 6 / 8 / 12 / 16 / 22 for internal spacing, 52 between sections, 64 before the footer. Card grids are 2-up or 3-up at a 12px gutter. The statistics strip is a 1px-gap grid over a `--line` background, so the gutters *are* the hairlines.

One breakpoint at **960px**: the shell collapses to a single column, the rail becomes a static top band with a bottom hairline instead of a right one, all multi-column grids go 1-up, and the statistics strip drops to two columns (`START_HERE`) or stacks (`BOARD_SETUP`). There is no other breakpoint; the schema frames scroll horizontally rather than reflow.

## Elevation & Depth

Depth is tonal first, shadow second. Three neutral steps — `--bg` under `--surface` under `--raised` — carry almost all layering, with a 1px `--line` hairline drawing the edge of every step. Surfaces are matte: there is no gradient fill, no inner glow, no glass, no `backdrop-filter` anywhere in either page, and the modal scrim is a flat 60% black rather than a blur.

A single 3% fractal-noise overlay is fixed over the whole viewport (2% in light) purely to break banding on the near-black ground.

### Shadow Vocabulary
- **Bench shadow** (`box-shadow: 0 2px 8px rgb(0 0 0 / .5)`; light: `0 1px 3px rgb(0 0 0 / .10)`): the default lift for anything that reads as a physical object on the bench — cards, callouts, lifecycle nodes, schema frames, the hero principle line. Tight and low; it separates, it does not float.
- **Drawer shadow** (`box-shadow: 0 8px 32px rgb(0 0 0 / .7)`; light: `0 8px 28px rgb(0 0 0 / .16)`): reserved for the one element that leaves the page plane — the slide-in file viewer.

### Named Rules

**The Two Shadows Rule.** There are exactly two shadows. Anything on the page uses the bench shadow or none; only the overlay drawer uses the far shadow. No hover shadow, no focus shadow, no colored shadow.

**The No-Light Rule.** Nothing in this world emits light. Glow, gradient fills, glass and backdrop blur are all absent from the build and stay absent — depth is tone plus a hairline.

## Shapes

A soft-cornered rectangle language on a strict four-step radius scale: 4px for inline `code`, 6px for chips, nav links and the brand mark, 8px for buttons and small schema nodes, 10px for every card, callout, table frame, code block, lifecycle node and schema frame. Nothing is a pill and nothing is a circle except the 6–8px status dots, which are the only fully round elements in the system.

Every surface is bordered: a 1px `--line` stroke is the default, and tinted variants are mixed rather than saturated — `color-mix(in srgb, var(--accent) 40%, var(--line))` for a live chip, 45% for an SVG node stroke. A border never jumps straight to the raw signal color.

In the SVG schemas the geometry is orthogonal by construction: 2px wires run in horizontal and vertical runs with rounded joins and a solid triangular head, group boxes are 4/4 dashed rectangles, and the live feedback edge is the accent on a 5/4 dash. There are no bezier curves, because the topology is a labelled swimlane diagram rather than a free-placed node canvas.

## Components

### Buttons
Ghost only. There is no filled or accented button anywhere in either page.
- **Shape:** gently rounded (8px)
- **Ghost:** `--raised` fill, 1px `--line` border, `--muted` mono label at 10.5–11px, `7px 10px` padding. Used for the theme toggle, the schema expand control, and the drawer close.
- **Hover:** text lifts `--muted` → `--ink`. Nothing else moves; no shadow, no translate, no background change.

### Chips
- **Style:** `--raised` fill, 1px `--line` border, 6px radius, 10px mono-weight label with `.04em` tracking, `2px 8px` padding. Outlined and tinted — never a saturated filled pill.
- **State:** the semantic variants change *text color and border tint only*: live/automatic in accent, human-gated in amber, escalation in the lifted red, model and neutral tags in plain `--ink`. Border tint is always a 40% `color-mix` with `--line`.

### Cards
- **Corner Style:** 10px
- **Background:** `--surface` on the dotted canvas
- **Shadow Strategy:** bench shadow (see Elevation)
- **Border:** 1px `--line`
- **Internal Padding:** 16px
- **Anatomy:** a 14px title preceded by an 8px status dot (`.ic`), then 13.5px `--muted` body. The dot is a status indicator, not a pictogram — this system uses monoline geometry or nothing, never an emoji or a filled icon glyph.

### Navigation
The sticky rail. Links are 12.5px `--muted` at 6px/10px padding with a transparent 2px left rule; hover fills `--raised` and lifts text to `--ink`; the active link keeps that fill and turns its left rule accent green. Group headers are 10px uppercase mono in `--muted`. Below 960px the rail becomes a static top band.

### Tables
Wrapped in a 10px rounded, 1px bordered `--surface` frame with horizontal overflow and a 540px minimum width. Headers are sticky, `--raised`, 10px uppercase mono in `--muted`. Rows are separated by hairlines, hover fills `--raised`, and the last row drops its rule so the frame closes cleanly.

### Callouts (signature)
The system's aside, built from the schema's own node anatomy rather than a left accent bar: a `--raised` header strip closed by a bottom hairline, carrying a 6px status dot and a 10px uppercase mono label, above a 14px `--muted` body on `--surface`. Semantic variants (`ok`, `warn`, `danger`) recolor the label and its dot only — the strip, the border and the body never take a signal color.

### Lifecycle Nodes (signature)
The 12 states render as a horizontally scrolling row of 150px cards: an 11.5px mono state name preceded by a status dot, an 11.5px `--muted` description, and an owner line pinned to the bottom above a hairline. The dot carries the whole semantic load — grey machine, amber human, red rework, green done.

### Schema Frames (signature)
The SVG diagrams sit in a 10px frame whose interior repeats the page's own dot lattice, with a `--surface` header (title, mono hint, expand button) and a `--surface` mono legend footer. Nodes are `--surface` rects with a 1px stroke tinted by role and a 3.5r status dot in the header position; node labels are 12px sans, sublabels 10px mono; lane titles are 9.5px mono at 1.2px tracking. Hover strokes a node in `--ink`. The frame expands to a fixed full-viewport overlay in place.

### File Chips and Inspector Drawer (signature, `START_HERE` only)
Any element carrying `data-file` / `data-dir` is clickable: inline `code` gets an accent-mixed bottom rule and turns `--accent-text` on hover; standalone chips are mono at 10.5px in a `--raised` capsule whose leading dot goes accent on hover (square-cornered for a directory, round for a file). Clicking opens a right-side drawer at `min(760px, 94vw)` over a flat 60% black scrim — 120ms slide, no blur — with a mono breadcrumb head, a mono meta strip, and source on `--code-bg` with 10.5px line numbers in `#5A5A5A`.

## Do's and Don'ts

### Do:
- **Do** keep everything inline and self-contained. Both pages open from a local clone over `file://`; no remote font, stylesheet, script, image or analytics may ever be added.
- **Do** ship both themes. Every new token needs a light value in the `:root[data-theme="light"]` block, and the pre-paint theme script must stay in `<head>` so there is no flash.
- **Do** ration the green to live signal, and keep amber for human moments and red for gates.
- **Do** use `{colors.negative-text}` for red glyphs and `{colors.negative}` for red borders, dots and wires.
- **Do** set every machine-facing string in mono — paths, env vars, config keys, state names, counts, micro-labels.
- **Do** build depth from the `--bg` → `--surface` → `--raised` ladder plus a 1px `--line` hairline, and reach for the bench shadow only when something should read as an object.
- **Do** hold the radius scale at 4 / 6 / 8 / 10px and border every surface at exactly 1px.
- **Do** re-run `tools/embed-files.py` after any edit to `START_HERE.html` — CI fails on payload drift.
- **Do** preserve `START_HERE`'s `data-file` chips, its slide-in file viewer, and its links to `BOARD_SETUP`.
- **Do** leave `BOARD_SETUP` free of any `data-file` attribute, and leave its ~50 pinned factual claims verbatim — `tests/test-board-guide.sh` asserts them.

### Don't:
- **Don't** add a glow, a gradient fill, a glass panel or a `backdrop-filter`. The scrim is dimmed, never blurred.
- **Don't** introduce a fourth hue, a second accent, or a hue in the light ramp.
- **Don't** exceed 20px anywhere below the hero, and don't add a second display-scale moment to a page.
- **Don't** raise the grain overlay above 3%.
- **Don't** add a third shadow, a hover shadow, or a colored shadow.
- **Don't** use a saturated filled pill for a chip, or a filled/accented button — buttons are ghost, chips are outlined and tinted.
- **Don't** put a pictogram, emoji or icon-font glyph where a status dot belongs; monoline geometry or nothing.
- **Don't** mark an aside with a left accent bar — callouts use the header-strip node anatomy.
- **Don't** set micro-labels in tracked uppercase sans; they are mono.
- **Don't** re-route the schema wires as beziers; orthogonal runs with solid triangular heads are the diagram language.
