// Preload for pm-linear tests: replaces global fetch with a scripted Linear
// GraphQL double. Scenario JSON comes from $MOCK_SCENARIO_FILE; every request is
// appended to $MOCK_LOG as one JSON line so the test can assert on the wire.
//
// Linear is GraphQL, so routing is by OPERATION rather than by path: the mock
// picks the first field name it recognises in the query text. It also answers
// 200-with-errors when the scenario asks for it, because that is how GraphQL
// reports failure and the adapter has to handle it.
'use strict';
const fs = require('node:fs');
const SCEN = JSON.parse(fs.readFileSync(process.env.MOCK_SCENARIO_FILE, 'utf8'));
const LOG = process.env.MOCK_LOG;

function record(entry) { fs.appendFileSync(LOG, JSON.stringify(entry) + '\n'); }
function reply(status, obj) {
  return { ok: status < 300, status, statusText: String(status), json: async () => obj };
}
// Which root field is this document asking for? Order matters: `issues` appears
// inside several queries, so the more specific operations are matched first.
function opOf(q) {
  for (const name of ['issueCreate', 'issueUpdate', 'issueLabelCreate', 'commentCreate',
                      'teams', 'projects', 'issues']) {
    if (new RegExp(`[{\\s]${name}\\s*[({]`).test(q)) return name;
  }
  return 'unknown';
}

globalThis.fetch = async (url, opts = {}) => {
  const body = JSON.parse(opts.body || '{}');
  const q = body.query || '';
  const name = opOf(q);
  record({ url: String(url), auth: (opts.headers || {}).Authorization, op: name, variables: body.variables || {} });

  if (SCEN.errors) return reply(200, { errors: SCEN.errors });

  switch (name) {
    case 'teams':
      return reply(200, { data: { teams: { nodes: SCEN.teams || [] } } });
    case 'projects':
      return reply(200, { data: { projects: { nodes: SCEN.projects || [] } } });
    case 'issues': {
      // `[spec] x` lookups and epic lookups share the root field; the scenario
      // can answer them separately.
      const t = (body.variables || {}).t || '';
      if (String(t).startsWith('[spec]')) return reply(200, { data: { issues: { nodes: SCEN.specIssues || [] } } });
      const nodes = SCEN.issues || [];
      const hit = String(t).startsWith('[') ? nodes.filter((n) => (n.title || '').startsWith(t)) : nodes;
      return reply(200, { data: { issues: { nodes: hit, pageInfo: { hasNextPage: false, endCursor: null } } } });
    }
    case 'issueCreate':
      return reply(200, { data: { issueCreate: { success: true, issue: { id: SCEN.createdId || 'iss_1', identifier: 'ENG-1' } } } });
    case 'issueUpdate':
      return reply(200, { data: { issueUpdate: { success: true } } });
    case 'issueLabelCreate':
      return reply(200, { data: { issueLabelCreate: { success: true, issueLabel: { id: 'lbl_new', name: (body.variables.i || {}).name } } } });
    case 'commentCreate':
      return reply(200, { data: { commentCreate: { success: true } } });
    default:
      return reply(200, { errors: [{ message: 'no mock route for operation: ' + name }] });
  }
};
