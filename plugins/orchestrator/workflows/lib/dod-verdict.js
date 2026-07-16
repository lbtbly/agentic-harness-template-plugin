// Pure DoD decision logic — no Workflow globals, no I/O, unit-testable with node.
// Judge panel: pass requires a strict majority AND zero blocking objections.
export function tallyJudges(votes) {
  const approve = votes.filter(v => v.verdict === 'approve').length
  const reject = votes.filter(v => v.verdict === 'reject').length
  const blocking = votes.filter(v => v.blocking).map(v => 'judge:' + v.lens)
  const majority = Math.floor(votes.length / 2) + 1
  const pass = votes.length > 0 && approve >= majority && blocking.length === 0
  return { approve, reject, pass, blocking }
}

// done is true only when all four stages pass and nothing is blocking; a blocking
// entry (a judge's hard objection) forces escalation regardless of the majority.
export function aggregateVerdict({ epic, stages, votes }) {
  const t = tallyJudges(votes)
  const judge = { pass: t.pass, tally: { approve: t.approve, reject: t.reject }, votes,
    reasons: t.blocking.length ? t.blocking.map(b => b + ' blocking dissent') : [] }
  const s = { ...stages, judge }
  const blocking = [...t.blocking]
  const reasons = []
  for (const [name, st] of Object.entries(s)) if (!st.pass) reasons.push(`${name} not passing`)
  const done = s.tests.pass && s.e2e.pass && s.acceptance.pass && judge.pass && blocking.length === 0
  return { epic, done, escalate: blocking.length > 0, stages: s, blocking, reasons }
}
