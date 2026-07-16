#!/usr/bin/env node
// pm-jira — state backend on a Jira project (created/adopted by /core:board-setup).
// Auth env NAMES (values live in the vault, never in the repo):
// JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN; project key from
// state.config.json → { jira: { projectKey } } (or JIRA_PROJECT_KEY).
// Mapping: epic → issue — summary "[id] title", labels orch-epic +
// orch-state-<State> (lifecycle tracked as labels: team-managed workflow/status
// creation is not reliably scriptable, so the adapter never depends on Jira
// statuses; board columns can mirror via quick filters), FULL epic record JSON
// in the description as a code block. spec → issue labeled orch-spec.
// session/plan/digest → cache-only (perishable; plan also lands as an issue
// comment for the human trail). Every push mirrors to .orch/cache/ so reads
// fail open offline. Feedback is NOT here — the orch CLI pulls it from the
// forge. Headless uses REST-via-token (MCP oauth is fragile in cron — ADR-0007).
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const R = process.env.CLAUDE_PROJECT_DIR || path.resolve(__dirname, '..', '..');
const CACHE = path.join(R, '.orch', 'cache');
const [op, ...argv] = process.argv.slice(2);

function cfg() {
  const base = process.env.JIRA_BASE_URL;
  const email = process.env.JIRA_EMAIL;
  const tok = process.env.JIRA_API_TOKEN;
  if (!base || !email || !tok) {
    throw new Error('JIRA_BASE_URL / JIRA_EMAIL / JIRA_API_TOKEN not set (env var NAMES per docs/SECURITY.md)');
  }
  let key = process.env.JIRA_PROJECT_KEY;
  if (!key) {
    try {
      const c = JSON.parse(fs.readFileSync(path.join(R, 'orchestrator', 'state.config.json'), 'utf8'));
      key = c.jira && c.jira.projectKey;
    } catch { /* fall through */ }
  }
  if (!key) throw new Error('no Jira project key (state.config.json jira.projectKey) — run /core:board-setup');
  return { base: base.replace(/\/$/, ''), email, tok, key };
}
async function api(method, p, body) {
  const { base, email, tok } = cfg();
  const res = await fetch(base + p, {
    method,
    headers: {
      Authorization: 'Basic ' + Buffer.from(`${email}:${tok}`).toString('base64'),
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return {};
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = (data.errorMessages || []).join('; ') || JSON.stringify(data.errors || {}) || res.statusText;
    throw new Error(`jira ${method} ${p}: ${res.status} ${msg}`);
  }
  return data;
}
function arg(flag) { const i = argv.indexOf(flag); return i >= 0 ? argv[i + 1] : undefined; }
function stdin() { return fs.readFileSync(0, 'utf8'); }
function cache(rel, content) {
  const f = path.join(CACHE, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, content);
}
function out(obj) { process.stdout.write(typeof obj === 'string' ? obj : JSON.stringify(obj) + '\n'); }
function slug(s) { return String(s).replace(/[^a-zA-Z0-9._-]/g, '-'); }
function adfCode(text, language) { // Atlassian Document Format: one code block
  return {
    type: 'doc', version: 1,
    content: [{ type: 'codeBlock', attrs: { language }, content: text ? [{ type: 'text', text }] : [] }],
  };
}
function adfText(doc) { // extract all text from an ADF doc (the code block payload)
  const parts = [];
  (function walk(n) {
    if (!n) return;
    if (n.type === 'text' && n.text) parts.push(n.text);
    (n.content || []).forEach(walk);
  })(doc);
  return parts.join('');
}
async function search(jql, fields) {
  const { key } = cfg();
  const issues = [];
  let startAt = 0;
  for (;;) {
    const r = await api('POST', '/rest/api/3/search', {
      jql: `project = "${key}" AND ${jql} ORDER BY created ASC`,
      fields, startAt, maxResults: 100,
    });
    issues.push(...(r.issues || []));
    startAt += 100;
    if (issues.length >= (r.total || 0) || !(r.issues || []).length) break;
  }
  return issues;
}
async function findEpicIssue(id) {
  const found = await search(`labels = "orch-epic" AND summary ~ "\\\\[${id}\\\\]"`, ['summary', 'labels', 'description']);
  return found.find((i) => (i.fields.summary || '').startsWith(`[${id}]`));
}
function parsePayload(issue) {
  try { return JSON.parse(adfText(issue.fields.description)); } catch { return null; }
}
async function upsertEpic(e) {
  const { key } = cfg();
  const payload = JSON.stringify(e, null, 2);
  const labels = ['orch-epic', `orch-state-${slug(e.state || 'Backlog')}`];
  if (e.complexity) labels.push(`orch-complexity-${slug(e.complexity)}`);
  const fields = {
    summary: `[${e.id}] ${e.title || ''}`.trim(),
    description: adfCode(payload, 'json'),
    labels,
  };
  const existing = await findEpicIssue(e.id);
  if (existing) await api('PUT', `/rest/api/3/issue/${existing.key}`, { fields });
  else await api('POST', '/rest/api/3/issue', { fields: { ...fields, project: { key }, issuetype: { name: 'Task' } } });
  cache(`epic-${slug(e.id)}.json`, payload);
}
async function listEpicRecords() {
  const issues = await search('labels = "orch-epic"', ['summary', 'labels', 'description']);
  return issues.map((i) => {
    const p = parsePayload(i);
    if (p) return p;
    const m = (i.fields.summary || '').match(/^\[([^\]]+)\]\s*(.*)$/);
    const st = (i.fields.labels || []).find((l) => l.startsWith('orch-state-'));
    return m ? { id: m[1], title: m[2], state: st ? st.replace('orch-state-', '') : 'Backlog' } : null;
  }).filter(Boolean);
}

(async () => {
  switch (op) {
    case 'health': {
      const { key } = cfg();
      const p = await api('GET', `/rest/api/3/project/${key}`);
      out({ ok: true, backend: 'jira', project: p.name || key });
      break;
    }
    case 'capabilities':
      out({ session: 'cache', spec: true, epics: true, status: true, digest: 'cache', feedback: 'forge' });
      break;
    case 'push-epic': {
      const e = JSON.parse(stdin());
      await upsertEpic(e);
      out({ id: e.id });
      break;
    }
    case 'push-backlog': {
      for (const e of JSON.parse(stdin())) await upsertEpic(e);
      out({ ok: true });
      break;
    }
    case 'get-epic': {
      const id = arg('--id');
      const iss = await findEpicIssue(id);
      if (!iss) throw new Error(`epic ${id} not found`);
      const p = parsePayload(iss);
      out(p ? JSON.stringify(p, null, 2) + '\n' : '{}\n');
      break;
    }
    case 'list-epics': {
      const state = arg('--state');
      out((await listEpicRecords()).filter((e) => !state || e.state === state));
      break;
    }
    case 'push-status': {
      const id = arg('--id');
      const iss = await findEpicIssue(id);
      let e = (iss && parsePayload(iss)) || { id };
      e.state = arg('--state');
      const note = arg('--note'); if (note) e.note = note;
      const pr = arg('--pr'); if (pr) e.pr = Number(pr) || pr;
      const asg = arg('--assignee');
      if (asg === '-') delete e.assignee; else if (asg) e.assignee = asg;
      e.ts = new Date().toISOString();
      await upsertEpic(e);
      out({ id, state: e.state });
      break;
    }
    case 'pull-status': {
      out((await listEpicRecords()).map((e) => ({
        id: e.id, state: e.state || 'Backlog', note: e.note || null, pr: e.pr || null, ts: e.ts || null,
      })));
      break;
    }
    case 'push-spec': {
      const id = arg('--id');
      const md = stdin();
      cache(`spec-${slug(id)}.md`, md);
      const { key } = cfg();
      const found = await search(`labels = "orch-spec" AND summary ~ "\\\\[spec\\\\] ${id}"`, ['summary']);
      const existing = found.find((i) => i.fields.summary === `[spec] ${id}`);
      const fields = { summary: `[spec] ${id}`, description: adfCode(md, 'markdown'), labels: ['orch-spec'] };
      if (existing) await api('PUT', `/rest/api/3/issue/${existing.key}`, { fields });
      else await api('POST', '/rest/api/3/issue', { fields: { ...fields, project: { key }, issuetype: { name: 'Task' } } });
      out({ id });
      break;
    }
    case 'get-spec': {
      const id = arg('--id');
      const f = path.join(CACHE, `spec-${slug(id)}.md`);
      if (fs.existsSync(f)) { out(fs.readFileSync(f, 'utf8')); break; }
      const found = await search(`labels = "orch-spec" AND summary ~ "\\\\[spec\\\\] ${id}"`, ['summary', 'description']);
      const iss = found.find((i) => i.fields.summary === `[spec] ${id}`);
      if (!iss) throw new Error(`spec ${id} not found`);
      out(adfText(iss.fields.description));
      break;
    }
    case 'list-specs': {
      const found = await search('labels = "orch-spec"', ['summary']);
      out(found.map((i) => (i.fields.summary || '').replace(/^\[spec\] /, '')));
      break;
    }
    // sessions are perishable — cache-mirror only (a board issue per session is noise)
    case 'push-session': {
      const s = JSON.parse(stdin());
      const br = s.branch || 'detached';
      cache(`session-${slug(br)}.json`, JSON.stringify(s, null, 2));
      out({ id: slug(br) });
      break;
    }
    case 'pull-session': {
      const br = arg('--branch') || 'detached';
      const f = path.join(CACHE, `session-${slug(br)}.json`);
      out(fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '{}\n');
      break;
    }
    case 'push-plan': {
      const id = arg('--epic');
      const md = stdin();
      cache(`plan-${slug(id)}.md`, md);
      const iss = await findEpicIssue(id);
      if (iss) {
        await api('POST', `/rest/api/3/issue/${iss.key}/comment`, {
          body: adfCode('## Approved plan\n\n' + md, 'markdown'),
        });
      }
      out({ epic: id });
      break;
    }
    case 'get-plan': {
      const id = arg('--epic');
      const f = path.join(CACHE, `plan-${slug(id)}.md`);
      if (!fs.existsSync(f)) throw new Error(`plan ${id} not cached — pull it from the epic issue comments`);
      out(fs.readFileSync(f, 'utf8'));
      break;
    }
    case 'push-digest': {
      const date = arg('--date');
      cache(`digest-${date}.html`, stdin());
      out({ date });
      break;
    }
    default:
      throw new Error(`unknown op: ${op}`);
  }
})().catch((err) => {
  // never echo tokens — print the message only, never headers/env
  process.stderr.write(`pm-jira ${op}: ${String(err.message || err).split('\n')[0]}\n`);
  process.exit(1);
});
