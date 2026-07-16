export const meta = {
  name: 'parallel-research',
  description: 'Multi-angle research (official docs, GitHub issues, comparisons, alternatives) then cited synthesis',
  whenToUse: 'Choice of lib/service/approach that will end up in an ADR. Pass the question via args.question.',
  phases: [{ title: 'Research' }, { title: 'Synthesis' }],
}

const question = (args && args.question) || null
if (!question) {
  return { error: 'Pass the question: Workflow({scriptPath, args: {question: "..."}}) ' }
}

const ANGLES = [
  `Official documentation and recent releases regarding: ${question}. Current versions, breaking changes, roadmap.`,
  `GitHub issues, bug trackers and known limitations regarding: ${question}. Real problems from users in production.`,
  `Recent comparisons and benchmarks regarding: ${question}. Criteria: performance, maintenance, community.`,
  `Credible alternatives to what is proposed in: ${question} — including "do nothing" or a simpler solution.`,
]

const findings = (
  await parallel(ANGLES.map((a, i) => () => agent(`${a} Every factual claim MUST carry its source URL.`, { label: `angle:${i + 1}`, phase: 'Research' })))
).filter(Boolean)

const synthesis = await agent(
  `Question: ${question}\n\nReports from 4 independent researchers:\n\n${findings.map((f, i) => `--- Report ${i + 1} ---\n${f}`).join('\n\n')}\n\nSynthesize: recommended answer first, trade-offs, points of disagreement between reports, consolidated sources. Format ready to feed an ADR (Context/Decision/Consequences).`,
  { label: 'synthesis', phase: 'Synthesis' }
)
return { synthesis }
