export const meta = {
  name: 'migrate',
  description: 'Mass mechanical migration: site discovery → transformation in isolated worktrees → verification',
  whenToUse: 'Refactor too large for a single context (internal API rename, pattern change). Pass args.instruction and args.discoverCmd.',
  phases: [
    { title: 'Discovery', detail: 'list the files to transform' },
    { title: 'Transformation', detail: 'one agent per batch, isolated worktree' },
    { title: 'Verification' },
  ],
}

const SITES = {
  type: 'object',
  properties: { files: { type: 'array', items: { type: 'string' } } },
  required: ['files'],
}

const instruction = (args && args.instruction) || null
if (!instruction) return { error: 'Pass args.instruction (the exact transformation) and ideally args.discoverCmd (a grep/glob discovery command).' }

const discovery = await agent(
  `Exhaustively list the files affected by this transformation: "${instruction}". ${args.discoverCmd ? `Suggested discovery command: ${args.discoverCmd}` : 'Use grep/glob.'} Return only the paths.`,
  { label: 'discovery', phase: 'Discovery', schema: SITES }
)
const files = (discovery && discovery.files) || []
log(`${files.length} file(s) to transform`)
if (files.length === 0) return { transformed: [], note: 'no sites found' }

// Batches of 10 files per agent, isolated worktrees (parallel writers)
const BATCH = 10
const batches = []
for (let i = 0; i < files.length; i += BATCH) batches.push(files.slice(i, i + BATCH))

const results = await parallel(
  batches.map((batch, i) => () =>
    agent(
      `Apply EXACTLY this transformation, file by file, with no opportunistic improvements: "${instruction}".\nFiles in this batch: ${batch.join(', ')}.\nAfter the transformation, run the available verification (tests/lint/compile) and report: modified files, verification result, anomalies.`,
      { label: `batch:${i + 1}`, phase: 'Transformation', isolation: 'worktree' }
    )
  )
)

const verification = await agent(
  `Here are the reports from the transformation agents for "${instruction}":\n${results.filter(Boolean).join('\n---\n')}\n\nSynthesize: batches OK, batches with anomalies, files to redo by hand, and the global verification command to run after merging the worktrees.`,
  { label: 'synthesis', phase: 'Verification' }
)
return { batches: batches.length, verification }
