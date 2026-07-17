export const meta = {
  name: 'dod-verify',
  description: 'Definition-of-done verification: tests(all levels)+E2E(browser)+acceptance+independent judge panel → verdict',
  phases: [{ title: 'Verify' }],
}
import { aggregateVerdict } from './lib/dod-verdict.js'

export const LENSES = ['correctness', 'pm', 'design']
// Decorrelated panel: same-model judges fail together (majority ≈ one judge), so each
// lens is pinned to a model. Keep ≥2 distinct models across the panel when tuning.
export const JUDGE_MODELS = { correctness: 'opus', pm: 'sonnet', design: 'opus' }
export const JUDGE_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['verdict', 'blocking', 'note'],
  properties: {
    verdict: { enum: ['approve', 'reject'] },
    blocking: { type: 'boolean', description: 'true = a defect serious enough to forbid merge regardless of the vote tally' },
    note: { type: 'string' },
  },
}
const STAGE_SCHEMA = {
  type: 'object', additionalProperties: true, required: ['pass', 'reasons'],
  properties: { pass: { type: 'boolean' }, reasons: { type: 'array', items: { type: 'string' } } },
}

export async function verifyDoD(epic) {
  phase('Verify')
  const fl = `.orch/epics/${epic}/feature_list.json`

  // Stage 1 — tests at every required level + epic tests + typecheck/lint.
  const tests = await agent(
    `Run the project's checks for epic ${epic}. Read ${fl} → testLevels + epicTests.
     Run typecheck + lint, and the unit/integration/e2e suites that testLevels marks required,
     plus every path in epicTests. NEVER weaken or skip a test to make it pass.
     Return {pass, levels:{unit,integration,e2e}, epicTests:boolean, reasons:[...]}: pass only if
     every required level AND every epic test is green and typecheck+lint are clean.`,
    { label: `dod:tests:${epic}`, schema: { ...STAGE_SCHEMA, properties: { ...STAGE_SCHEMA.properties, levels: { type: 'object' }, epicTests: { type: 'boolean' } } } })

  // Stage 2 — functional E2E as a user (browser). Honours the anti-drift contract.
  const e2e = await agent(
    `Verify epic ${epic} like a USER, not like CI. Read ${fl}. For EACH feature, drive its
     "steps" in a REAL browser (Playwright/Claude-in-Chrome MCP) and observe whether "expected"
     holds. Flip "passes" false→true ONLY on a real pass — never edit steps or add/remove features.
     A surface the browser can't see → leave passes:false and record it in "blindspots".
     When a feature has a UI surface, screenshot the observed "expected" state into
     docs/reports/nightly/<date>/shots/${epic}/<feature-id>.png and record that path (or the
     command output ref for non-UI features) in the feature's "evidence" field as you flip
     passes — the VERIFIER owns the proof; a passes:true without evidence gets flagged.
     Return {pass, features:[{id,passes,blindspot,screenshot}], reasons:[...]}: pass only if every
     feature passes or is an acknowledged blindspot.`,
    { label: `dod:e2e:${epic}`, schema: { ...STAGE_SCHEMA, properties: { ...STAGE_SCHEMA.properties, features: { type: 'array' } } } })

  // Stage 3 — acceptance-criteria assertions.
  const acceptance = await agent(
    `Check epic ${epic}'s acceptanceCriteria from ${fl}. For each criterion, assert it against the
     built result (run the automated:true ones as assertions; evaluate the rest from observable behavior).
     Return {pass, criteria:[{id,met}], reasons:[...]}: pass only if every criterion is met.`,
    { label: `dod:acceptance:${epic}`, schema: { ...STAGE_SCHEMA, properties: { ...STAGE_SCHEMA.properties, criteria: { type: 'array' } } } })

  // Stage 4 — independent adversarial judge panel (builder ≠ judge; one per lens, in parallel).
  const votes = (await parallel(LENSES.map(lens => () =>
    agent(
      `You are an INDEPENDENT ${lens} judge for epic ${epic}. You did NOT build it. Adversarially
       assess the diff + the approved plan/spec + ${fl}${lens === 'design' ? ' + designRefs (compare the built UI to the reference screenshots)' : ''}.
       Lens: ${lens === 'correctness' ? 'does it correctly implement the spec, with real edge handling'
              : lens === 'pm' ? 'does it deliver the acceptanceCriteria value the initiative intended'
              : 'does the UI match the design references and behave well'}.
       Default to reject if uncertain. Set blocking:true only for a defect serious enough to forbid merge.`,
      { label: `dod:judge:${lens}:${epic}`, phase: 'Verify', schema: JUDGE_SCHEMA, model: JUDGE_MODELS[lens] })
      .then(v => ({ lens, ...v }))
  ))).filter(Boolean)

  return aggregateVerdict({ epic, stages: { tests, e2e, acceptance }, votes })
}
