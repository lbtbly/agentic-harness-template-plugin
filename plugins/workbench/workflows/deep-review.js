export const meta = {
  name: 'deep-review',
  description: 'Multi-dimensional review (bugs, security, perf, GDPR) with adversarial verification of every finding',
  whenToUse: 'Exhaustive review before an important merge. Expensive — not for a small diff.',
  phases: [
    { title: 'Review', detail: 'one dimension per agent, in parallel' },
    { title: 'Verify', detail: 'every finding verified adversarially' },
  ],
}

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: { title: { type: 'string' }, file: { type: 'string' }, detail: { type: 'string' }, severity: { type: 'string', enum: ['blocking', 'important', 'minor'] } },
        required: ['title', 'file', 'detail', 'severity'],
      },
    },
  },
  required: ['findings'],
}
const VERDICT = {
  type: 'object',
  properties: { isReal: { type: 'boolean' }, why: { type: 'string' } },
  required: ['isReal', 'why'],
}

const target = (args && args.target) || 'the current diff (git diff main...HEAD, otherwise git diff HEAD)'
const DIMENSIONS = [
  { key: 'bugs', prompt: `Find correctness bugs (logic, edge cases, state errors) in ${target}. Read docs/CODEMAP.md first.` },
  { key: 'security', prompt: `Security audit of ${target}: OWASP, hardcoded secrets, injections, input validation.` },
  { key: 'perf', prompt: `Performance issues in ${target}: N+1, allocations in loops, blocking I/O, accidental complexity.` },
  { key: 'gdpr', prompt: `Personal data in ${target}: non-minimized collection, personal data in logs, missing retention (GDPR).` },
]

const results = await pipeline(
  DIMENSIONS,
  (d) => agent(`${d.prompt} Return only precise, localized findings.`, { label: `review:${d.key}`, phase: 'Review', schema: FINDINGS }),
  (review, d) =>
    parallel(
      ((review && review.findings) || []).map((f) => () =>
        agent(
          `Adversarially verify this finding — try to REFUTE it by reading the actual code: "${f.title}" — ${f.detail} (${f.file}). When in doubt, isReal=false.`,
          { label: `verify:${d.key}`, phase: 'Verify', schema: VERDICT }
        ).then((v) => ({ ...f, dimension: d.key, verdict: v }))
      )
    )
)

const confirmed = results.filter(Boolean).flat().filter(Boolean).filter((f) => f.verdict && f.verdict.isReal)
log(`${confirmed.length} finding(s) confirmed after adversarial verification`)
return { confirmed }
