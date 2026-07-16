#!/usr/bin/env node
// pm-jira — state backend on a Jira project using NATIVE Jira semantics (ADR-0021):
// orchestrator epics are Jira Epics (epicIssueType, default "Epic"); work items
// are child issues (childIssueType, default "Task") linked via `parent`; and
// lifecycle state maps onto REAL Jira statuses through a configurable statusMap,
// applied as workflow TRANSITIONS — never invented. Statuses/columns are created
// MANUALLY in the Jira UI (the API/connector cannot create statuses or
// reconfigure the board/workflow); /core:board-setup prints the steps and
// `health` validates the map against the project's real statuses.
//
// A Jira workflow is a GRAPH: the mapped status may be unreachable from the
// current one, or missing entirely. Fallback at every seam — no statusMap, a
// missing entry, a missing/unreachable target — reverts THAT update to the
// label scheme (orch-state-<State>), logged to stderr, never a failed run.
// The EXACT orchestrator state always lives in the epic-record JSON in the
// description code block (precise source of truth); the Jira status is the
// coarse human/board view. Reads derive state: payload JSON → reverse
// statusMap → orch-state-* label.
//
// Config (state.config.json): { jira: { projectKey, epicIssueType?,
//   childIssueType?, statusMap? } } — statusMap: lifecycleState → status name,
//   many-to-one allowed. A record carrying `parent: "<epicId>"` is a child.
// Auth env NAMES only (values in the vault, never the repo): JIRA_BASE_URL,
// JIRA_EMAIL, JIRA_API_TOKEN. Errors NEVER echo tokens, headers, or env.
// Every push mirrors to .orch/cache (fail-open offline reads). Feedback is NOT
// here — the orch CLI pulls it from the forge (ADR-0007).
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
  let j = {};
  try {
    const c = JSON.parse(fs.readFileSync(path.join(R, 'orchestrator', 'state.config.json'), 'utf8'));
    j = c.jira || {};
  } catch { /* fall through */ }
  const key = process.env.JIRA_PROJECT_KEY || j.projectKey;
  if (!key) throw new Error('no Jira project key (state.config.json jira.projectKey) — run /core:board-setup');
  return {
    base: base.replace(/\/$/, ''), email, tok, key,
    epicType: j.epicIssueType || 'Epic',
    childType: j.childIssueType || 'Task',
    statusMap: j.statusMap && typeof j.statusMap === 'object' ? j.statusMap : null,
  };
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
function warn(msg) { process.stderr.write(`pm-jira: ${msg}\n`); }
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
const EPIC_FIELDS = ['summary', 'labels', 'description', 'status'];
async function findIssue(id) { // epics AND children share the [id] summary convention
  const found = await search(
    `labels in ("orch-epic","orch-child") AND summary ~ "\\\\[${id}\\\\]"`, EPIC_FIELDS);
  return found.find((i) => (i.fields.summary || '').startsWith(`[${id}]`));
}
function parsePayload(issue) {
  try { return JSON.parse(adfText(issue.fields.description)); } catch { return null; }
}
// --- statusMap helpers -------------------------------------------------------
function statusFor(state) {
  const { statusMap } = cfg();
  if (!statusMap) return null;
  const target = statusMap[state];
  if (!target) warn(`statusMap has no entry for "${state}" — falling back to the label scheme for this update`);
  return target || null;
}
function reverseMapStatus(statusName) {
  const { statusMap } = cfg();
  if (!statusMap || !statusName) return null;
  for (const [state, status] of Object.entries(statusMap)) {
    if (String(status).toLowerCase() === String(statusName).toLowerCase()) return state;
  }
  return null;
}
// One direct hop only: workflows are graphs, and multi-hop pathing through
// unknown intermediate statuses is riskier than the label fallback (ADR-0021).
async function transitionTo(issueKey, targetStatus, currentStatus) {
  if (currentStatus && currentStatus.toLowerCase() === targetStatus.toLowerCase()) return true;
  const r = await api('GET', `/rest/api/3/issue/${issueKey}/transitions`);
  const t = (r.transitions || []).find(
    (x) => x.to && String(x.to.name).toLowerCase() === targetStatus.toLowerCase());
  if (!t) return false;
  await api('POST', `/rest/api/3/issue/${issueKey}/transitions`, { transition: { id: t.id } });
  return true;
}
function stateFromIssue(i) { // read priority: payload → reverse statusMap → label
  const p = parsePayload(i);
  if (p && p.state) return { record: p, state: p.state };
  const byStatus = reverseMapStatus(i.fields.status && i.fields.status.name);
  if (byStatus) return { record: p, state: byStatus };
  const lbl = (i.fields.labels || []).find((l) => l.startsWith('orch-state-'));
  return { record: p, state: lbl ? lbl.replace('orch-state-', '') : 'Backlog' };
}
async function upsertEpic(e) {
  const { key, epicType, childType } = cfg();
  const isChild = !!e.parent;
  const payload = JSON.stringify(e, null, 2);
  const state = e.state || 'Backlog';
  const target = statusFor(state);         // null → label scheme from the start
  const labels = [isChild ? 'orch-child' : 'orch-epic'];
  if (e.complexity) labels.push(`orch-complexity-${slug(e.complexity)}`);
  if (!target) labels.push(`orch-state-${slug(state)}`);
  const fields = { summary: `[${e.id}] ${e.title || ''}`.trim(), description: adfCode(payload, 'json'), labels };

  const existing = await findIssue(e.id);
  let issueKey, currentStatus = null;
  if (existing) {
    issueKey = existing.key;
    currentStatus = existing.fields.status && existing.fields.status.name;
    await api('PUT', `/rest/api/3/issue/${issueKey}`, { fields });
  } else {
    if (isChild) {
      const parent = await findIssue(e.parent);
      if (parent) fields.parent = { key: parent.key };
      else warn(`parent epic "${e.parent}" not found — creating "${e.id}" unlinked`);
    }
    const type = isChild ? childType : epicType;
    try {
      issueKey = (await api('POST', '/rest/api/3/issue', {
        fields: { ...fields, project: { key }, issuetype: { name: type } },
      })).key;
    } catch (err) {
      if (!isChild && /issue.?type/i.test(String(err.message))) {
        warn(`issue type "${type}" rejected — retrying as "${childType}"`);
        issueKey = (await api('POST', '/rest/api/3/issue', {
          fields: { ...fields, project: { key }, issuetype: { name: childType } },
        })).key;
      } else throw err;
    }
  }
  if (target) {
    const ok = await transitionTo(issueKey, target, currentStatus).catch((err) => {
      warn(`transition to "${target}" errored (${String(err.message).split('\n')[0]})`);
      return false;
    });
    if (!ok) {
      warn(`status "${target}" unreachable from "${currentStatus || 'new'}" for ${issueKey} — falling back to the orch-state label`);
      await api('PUT', `/rest/api/3/issue/${issueKey}`, {
        fields: { labels: [...labels, `orch-state-${slug(state)}`] },
      });
    }
  }
  cache(`epic-${slug(e.id)}.json`, payload);
  return issueKey;
}
async function listEpicRecords() {
  const issues = await search('labels = "orch-epic"', EPIC_FIELDS);
  return issues.map((i) => {
    const { record, state } = stateFromIssue(i);
    if (record) return { ...record, state: record.state || state };
    const m = (i.fields.summary || '').match(/^\[([^\]]+)\]\s*(.*)$/);
    return m ? { id: m[1], title: m[2], state } : null;
  }).filter(Boolean);
}

(async () => {
  switch (op) {
    case 'health': {
      const { key, statusMap } = cfg();
      const p = await api('GET', `/rest/api/3/project/${key}`);
      const result = { ok: true, backend: 'jira', project: p.name || key };
      if (statusMap) {
        // validate every mapped target against the project's REAL statuses —
        // they are created manually in the UI; the API cannot create them.
        let known = null;
        try {
          const types = await api('GET', `/rest/api/3/project/${key}/statuses`);
          known = new Set();
          for (const t of types) for (const s of (t.statuses || [])) known.add(String(s.name).toLowerCase());
        } catch (err) {
          warn(`could not list project statuses (${String(err.message).split('\n')[0]}) — statusMap unvalidated`);
        }
        const targets = [...new Set(Object.values(statusMap))];
        const missing = known ? targets.filter((s) => !known.has(String(s).toLowerCase())) : [];
        for (const s of missing) {
          warn(`statusMap target "${s}" does not exist in ${key} — create the column/status manually (board "+" adds a column); updates mapping to it will fall back to labels`);
        }
        result.statusMap = { configured: Object.keys(statusMap).length, targets: targets.length, missing };
      } else {
        warn('no jira.statusMap configured — lifecycle will use the orch-state-* label scheme (run /core:board-setup to map statuses)');
      }
      out(result);
      break;
    }
    case 'capabilities':
      out({ session: 'cache', spec: true, epics: true, children: true, status: true, digest: 'cache', feedback: 'forge' });
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
      const iss = await findIssue(id);
      if (!iss) throw new Error(`epic ${id} not found`);
      const { record, state } = stateFromIssue(iss);
      out(record ? JSON.stringify(record, null, 2) + '\n' : JSON.stringify({ id, state }) + '\n');
      break;
    }
    case 'list-epics': {
      const state = arg('--state');
      out((await listEpicRecords()).filter((e) => !state || e.state === state));
      break;
    }
    case 'push-status': {
      const id = arg('--id');
      const iss = await findIssue(id);
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
      const { key, childType } = cfg();
      const found = await search(`labels = "orch-spec" AND summary ~ "\\\\[spec\\\\] ${id}"`, ['summary']);
      const existing = found.find((i) => i.fields.summary === `[spec] ${id}`);
      const fields = { summary: `[spec] ${id}`, description: adfCode(md, 'markdown'), labels: ['orch-spec'] };
      if (existing) await api('PUT', `/rest/api/3/issue/${existing.key}`, { fields });
      else await api('POST', '/rest/api/3/issue', { fields: { ...fields, project: { key }, issuetype: { name: childType } } });
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
      const iss = await findIssue(id);
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
  // never echo tokens/headers/env — print the message only
  process.stderr.write(`pm-jira ${op}: ${String(err.message || err).split('\n')[0]}\n`);
  process.exit(1);
});
