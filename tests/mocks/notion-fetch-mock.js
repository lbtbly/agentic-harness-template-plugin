// Preload for pm-notion tests: replaces global fetch with a scripted Notion
// REST double (API 2025-09-03+, data sources). Scenario JSON comes from
// $MOCK_SCENARIO_FILE; every request is appended to $MOCK_LOG as one JSON line
// so the test can assert on the wire.
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
  const p = u.pathname.replace(/^\/v1/, '');
  const method = (opts.method || 'GET').toUpperCase();
  let body = null;
  try { body = opts.body ? JSON.parse(opts.body) : null; } catch { /* keep null */ }
  record({ method, path: p, version: (opts.headers || {})['Notion-Version'], body });

  // legacy config path: GET /databases/{id} → the database's data sources
  let m = p.match(/^\/databases\/([^/]+)$/);
  if (m && method === 'GET') {
    if (SCEN.databaseMissing) return reply(404, { message: 'Could not find database' });
    return reply(200, { id: m[1], data_sources: SCEN.dataSources || [{ id: 'ds_epics', name: 'Epics' }] });
  }

  // GET /data_sources/{id} → schema
  m = p.match(/^\/data_sources\/([^/]+)$/);
  if (m && method === 'GET') {
    const which = m[1];
    if (which === (SCEN.initId || 'ds_inits')) {
      if (SCEN.initsUnreachable) return reply(404, { message: 'Could not find data source' });
      return reply(200, { id: which, title: [{ plain_text: 'Initiatives' }], properties: SCEN.initProps || {} });
    }
    return reply(200, { id: which, title: [{ plain_text: 'Epics' }], properties: SCEN.props || {} });
  }

  // POST /data_sources/{id}/query
  m = p.match(/^\/data_sources\/([^/]+)\/query$/);
  if (m && method === 'POST') {
    const which = m[1];
    const isInit = which === (SCEN.initId || 'ds_inits');
    let results = isInit ? (SCEN.initPages || []) : (SCEN.pages || []);
    const sw = body && body.filter && body.filter.title && body.filter.title.starts_with;
    if (sw) {
      results = results.filter((pg) => {
        const t = Object.values(pg.properties || {}).find((v) => v && v.type === 'title');
        return ((t && t.title) || []).map((x) => x.plain_text).join('').startsWith(sw);
      });
    }
    return reply(200, { results, has_more: false, next_cursor: null });
  }

  if (p === '/pages' && method === 'POST') return reply(200, { id: SCEN.createdId || 'page_new' });
  if (/^\/pages\/[^/]+$/.test(p) && method === 'PATCH') return reply(200, {});
  if (/^\/blocks\/[^/]+\/children$/.test(p) && method === 'GET') {
    const id = p.split('/')[2];
    return reply(200, { results: (SCEN.blocks || {})[id] || [] });
  }
  if (/^\/blocks\/[^/]+\/children$/.test(p) && method === 'PATCH') return reply(200, {});
  if (/^\/blocks\/[^/]+$/.test(p) && method === 'PATCH') return reply(200, {});

  return reply(404, { message: 'no mock route: ' + method + ' ' + p });
};
