// Preload for pm-jira tests: replaces global fetch with a scripted Jira REST
// double. Scenario JSON comes from $MOCK_SCENARIO_FILE; every request is
// appended to $MOCK_LOG as one JSON line so the test can assert on the wire.
'use strict';
const fs = require('node:fs');
const SCEN = JSON.parse(fs.readFileSync(process.env.MOCK_SCENARIO_FILE, 'utf8'));
const LOG = process.env.MOCK_LOG;

function record(entry) { fs.appendFileSync(LOG, JSON.stringify(entry) + '\n'); }
function reply(status, obj) {
  return { ok: status < 300, status, statusText: String(status), json: async () => obj };
}

globalThis.fetch = async (url, opts = {}) => {
  const u = new URL(url);
  const method = (opts.method || 'GET').toUpperCase();
  let body = null;
  try { body = opts.body ? JSON.parse(opts.body) : null; } catch { /* keep null */ }
  record({ method, path: u.pathname, body });
  const p = u.pathname;

  if (method === 'GET' && /\/project\/[^/]+\/statuses$/.test(p)) {
    return reply(200, SCEN.projectStatuses || []);
  }
  if (method === 'GET' && /\/project\//.test(p)) return reply(200, { name: 'Mock Project' });
  if (method === 'POST' && p.endsWith('/search')) return reply(200, SCEN.search || { issues: [], total: 0 });
  if (method === 'GET' && /\/transitions$/.test(p)) return reply(200, { transitions: SCEN.transitions || [] });
  if (method === 'POST' && /\/transitions$/.test(p)) return reply(204, {});
  if (method === 'POST' && p.endsWith('/issue')) return reply(201, { key: SCEN.createdKey || 'MOCK-1' });
  if (method === 'PUT' && /\/issue\//.test(p)) return reply(204, {});
  if (method === 'POST' && /\/comment$/.test(p)) return reply(201, {});
  return reply(404, { errorMessages: ['no mock route: ' + method + ' ' + p] });
};
