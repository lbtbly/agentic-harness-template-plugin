#!/usr/bin/env node
// pm-linear — state backend on a Linear team using NATIVE Linear semantics
// (ADR-0007, ADR-0021's discipline, ADR-0027's hierarchy):
//   orchestrator epic          → Linear Issue          (label orch-epic)
//   record carrying `parent`   → Linear SUB-ISSUE      (parentId, label orch-child)
//   orchestrator initiative    → Linear PROJECT        (issue.projectId)
//   lifecycle state            → Linear WorkflowState  (configurable stateMap)
//
// Linear is the closest fit of any backend: Initiative → Project → Issue →
// Sub-issue is its own model, so the tier is read from the board rather than
// synthesized. `capabilities.hierarchy` reports "native".
//
// One real difference from Jira, and it is a simplification: a Linear workflow
// is NOT a transition graph. `stateId` is set directly, so there is no
// "unreachable status" case and no multi-hop pathing — a mapped state either
// exists in the team or it does not. The fallback is the same as Jira's: an
// unmapped or missing state reverts THAT update to the orch-state-<State>
// label, logged to stderr, never a failed run. The EXACT orchestrator state
// always lives in the record JSON in the issue description (precise source of
// truth); the Linear state is the coarse human/board view. Reads derive state:
// payload JSON → reverse stateMap → orch-state-* label.
//
// Config (state.config.json): { linear: { teamKey, stateMap?, createMissingLabels? } }
//   stateMap: lifecycleState → workflow state name, many-to-one allowed.
// Auth env NAMES only (values in the vault, never the repo): LINEAR_API_KEY.
// Personal keys (lin_api_…) go in Authorization raw; OAuth tokens use Bearer.
// Errors NEVER echo tokens, headers, or env. Every push mirrors to .orch/cache
// (fail-open offline reads). Feedback is NOT here — the orch CLI pulls it from
// the forge (ADR-0007).
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const R = process.env.CLAUDE_PROJECT_DIR || path.resolve(__dirname, '..', '..');
const CACHE = path.join(R, '.orch', 'cache');
const [op, ...argv] = process.argv.slice(2);
const ENDPOINT = process.env.LINEAR_API_URL || 'https://api.linear.app/graphql';

function cfg() {
  const tok = process.env.LINEAR_API_KEY;
  if (!tok) throw new Error('LINEAR_API_KEY not set (env var NAMES per docs/SECURITY.md)');
  let l = {};
  try {
    const c = JSON.parse(fs.readFileSync(path.join(R, 'orchestrator', 'state.config.json'), 'utf8'));
    l = c.linear || {};
  } catch { /* fall through */ }
  const teamKey = process.env.LINEAR_TEAM_KEY || l.teamKey;
  if (!teamKey) throw new Error('no Linear team key (state.config.json linear.teamKey) — run /core:board-setup');
  return {
    tok, teamKey,
    stateMap: l.stateMap && typeof l.stateMap === 'object' ? l.stateMap : null,
    createMissingLabels: l.createMissingLabels !== false,
  };
}
// A personal API key is sent RAW; only OAuth access tokens take "Bearer".
// Sending a personal key as Bearer is a silent 401, so detect rather than guess.
function authHeader(tok) {
  return /^lin_oauth_/.test(tok) ? `Bearer ${tok}` : tok;
}
async function gql(query, variables) {
  const { tok } = cfg();
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: {
      Authorization: authHeader(tok),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query, variables: variables || {} }),
  });
  const data = await res.json().catch(() => ({}));
  // GraphQL answers 200 with an `errors` array — status alone is not enough.
  if (!res.ok || (data.errors && data.errors.length)) {
    const msg = (data.errors || []).map((e) => e.message).join('; ') || res.statusText || `HTTP ${res.status}`;
    throw new Error(`linear: ${msg}`);
  }
  return data.data || {};
}
function warn(msg) { process.stderr.write(`pm-linear: ${msg}\n`); }
function arg(flag) { const i = argv.indexOf(flag); return i >= 0 ? argv[i + 1] : undefined; }
function stdin() { return fs.readFileSync(0, 'utf8'); }
function cache(rel, content) {
  const f = path.join(CACHE, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, content);
}
function out(obj) { process.stdout.write(typeof obj === 'string' ? obj : JSON.stringify(obj) + '\n'); }
function slug(s) { return String(s).replace(/[^a-zA-Z0-9._-]/g, '-'); }
function fence(payload) { return '```json\n' + payload + '\n```'; }
// Guarded, like every other adapter: one malformed fence must not kill a listing.
function extractPayload(description, title) {
  const m = (description || '').match(/```json\n([\s\S]*?)\n```/);
  if (m) {
    try { return JSON.parse(m[1]); }
    catch (e) { warn(`skipping an unparseable payload: ${String(e.message).split('\n')[0]}`); }
  }
  const t = (title || '').match(/^\[([^\]]+)\]\s*(.*)$/);
  return t ? { id: t[1], title: t[2] } : null;
}

// --- team, states, labels, projects (resolved once per process) --------------
let _team = null;
async function team() {
  if (_team) return _team;
  const { teamKey } = cfg();
  const d = await gql(
    `query($k:String!){ teams(filter:{key:{eq:$k}}, first:1){ nodes{
        id key name
        states(first:100){ nodes{ id name type } }
        labels(first:250){ nodes{ id name } }
      } } }`, { k: teamKey });
  const t = (d.teams && d.teams.nodes && d.teams.nodes[0]) || null;
  if (!t) throw new Error(`team "${teamKey}" not found — check state.config.json linear.teamKey`);
  _team = t;
  return t;
}
async function stateIdFor(name) {
  const t = await team();
  const s = (t.states.nodes || []).find((x) => String(x.name).toLowerCase() === String(name).toLowerCase());
  return s ? s.id : null;
}
async function labelIdFor(name) {
  const t = await team();
  const hit = (t.labels.nodes || []).find((x) => String(x.name).toLowerCase() === String(name).toLowerCase());
  if (hit) return hit.id;
  if (!cfg().createMissingLabels) return null;
  const d = await gql(
    `mutation($i:IssueLabelCreateInput!){ issueLabelCreate(input:$i){ success issueLabel{ id name } } }`,
    { i: { name, teamId: t.id } }).catch((e) => {
      warn(`could not create label "${name}" (${String(e.message).split('\n')[0]})`); return null;
    });
  const lbl = d && d.issueLabelCreate && d.issueLabelCreate.issueLabel;
  if (lbl) { t.labels.nodes.push(lbl); return lbl.id; }
  return null;
}
async function labelIds(names) {
  const ids = [];
  for (const n of names) { const id = await labelIdFor(n); if (id) ids.push(id); }
  return ids;
}
// The initiative tier: a Linear PROJECT. Never created implicitly — a project is
// a human artefact, and inventing one from a free-text field is how boards get
// littered. Missing → warn, keep the payload field, never fail (ADR-0021).
async function projectIdFor(name) {
  if (!name) return null;
  const d = await gql(
    `query($n:String!){ projects(filter:{name:{eqIgnoreCase:$n}}, first:1){ nodes{ id name } } }`,
    { n: name });
  const p = (d.projects && d.projects.nodes && d.projects.nodes[0]) || null;
  if (!p) warn(`no Linear project named "${name}" — keeping it as a payload field only (create the project to get the native tier)`);
  return p ? p.id : null;
}

const ISSUE_FIELDS = `
  id identifier title description url
  state { id name }
  labels(first:50){ nodes{ name } }
  parent { id title }
  project { id name }
  assignee { displayName }`;

async function findIssue(id) {
  const d = await gql(
    `query($t:String!){ issues(filter:{ labels:{ name:{ in:["orch-epic","orch-child"] } },
                                        title:{ startsWith:$t } }, first:10){ nodes{ ${ISSUE_FIELDS} } } }`,
    { t: `[${id}]` });
  const nodes = (d.issues && d.issues.nodes) || [];
  return nodes.find((i) => (i.title || '').startsWith(`[${id}]`)) || null;
}
async function allOrchIssues() {
  const nodes = [];
  let after = null;
  for (;;) {
    const d = await gql(
      `query($a:String){ issues(filter:{ labels:{ name:{ in:["orch-epic","orch-child"] } } },
                                first:100, after:$a){ nodes{ ${ISSUE_FIELDS} } pageInfo{ hasNextPage endCursor } } }`,
      { a: after });
    const c = d.issues || { nodes: [], pageInfo: {} };
    nodes.push(...(c.nodes || []));
    if (!c.pageInfo || !c.pageInfo.hasNextPage) break;
    after = c.pageInfo.endCursor;
  }
  return nodes;
}

// --- stateMap helpers (the Jira parallel, minus the transition graph) --------
function mappedState(state) {
  const { stateMap } = cfg();
  if (!stateMap) return null;
  const target = stateMap[state];
  if (!target) warn(`stateMap has no entry for "${state}" — falling back to the label scheme for this update`);
  return target || null;
}
function reverseMapState(name) {
  const { stateMap } = cfg();
  if (!stateMap || !name) return null;
  for (const [s, w] of Object.entries(stateMap)) {
    if (String(w).toLowerCase() === String(name).toLowerCase()) return s;
  }
  return null;
}
function stateFromIssue(i) { // payload → reverse stateMap → orch-state-* label
  const p = extractPayload(i.description, i.title);
  if (p && p.state) return { record: p, state: p.state };
  const byState = reverseMapState(i.state && i.state.name);
  if (byState) return { record: p, state: byState };
  const names = ((i.labels && i.labels.nodes) || []).map((l) => l.name);
  const lbl = names.find((n) => n.startsWith('orch-state-'));
  return { record: p, state: lbl ? lbl.replace('orch-state-', '') : 'Backlog' };
}

async function upsertEpic(e) {
  const t = await team();
  const isChild = !!(e.parent || e.parentId);
  const parentRef = e.parent || e.parentId;
  const payload = JSON.stringify(e, null, 2);
  const state = e.state || 'Backlog';
  const target = mappedState(state);
  const names = [isChild ? 'orch-child' : 'orch-epic'];
  if (e.complexity) names.push(`orch-complexity-${slug(e.complexity)}`);

  let stateId = null;
  if (target) {
    stateId = await stateIdFor(target);
    if (!stateId) warn(`workflow state "${target}" does not exist in team ${t.key} — falling back to the orch-state label`);
  }
  if (!stateId) names.push(`orch-state-${slug(state)}`);

  const input = {
    title: `[${e.id}] ${e.title || ''}`.trim(),
    description: fence(payload),
    labelIds: await labelIds(names),
  };
  if (stateId) input.stateId = stateId;
  if (e.initiative) {
    const pid = await projectIdFor(e.initiative);
    if (pid) input.projectId = pid;
  }

  const existing = await findIssue(e.id);
  if (existing) {
    await gql(`mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id, input:$i){ success } }`,
      { id: existing.id, i: input });
  } else {
    if (isChild) {
      const parent = await findIssue(parentRef);
      if (parent) input.parentId = parent.id;
      else warn(`parent epic "${parentRef}" not found — creating "${e.id}" unlinked`);
    }
    await gql(`mutation($i:IssueCreateInput!){ issueCreate(input:$i){ success issue{ id identifier } } }`,
      { i: { ...input, teamId: t.id } });
  }
  cache(`epic-${slug(e.id)}.json`, payload);
  return e.id;
}

function recordFrom(i) {
  const { record, state } = stateFromIssue(i);
  const names = ((i.labels && i.labels.nodes) || []).map((l) => l.name);
  const level = names.includes('orch-child') ? 'child' : 'epic';
  // The board is the golden source: a parent or project set by a HUMAN in Linear
  // wins over a stale value inside the payload the harness wrote earlier.
  const pm = ((i.parent && i.parent.title) || '').match(/^\[([^\]]+)\]/);
  const nativeParent = pm ? pm[1] : null;
  const nativeProject = (i.project && i.project.name) || null;
  const base = record || (() => {
    const m = (i.title || '').match(/^\[([^\]]+)\]\s*(.*)$/);
    return m ? { id: m[1], title: m[2] } : null;
  })();
  if (!base) return null;
  return {
    ...base,
    state: base.state || state,
    level: base.level ?? level,
    ...(nativeParent ? { parentId: nativeParent } : {}),
    ...(nativeProject ? { initiative: nativeProject } : {}),
  };
}
async function listEpicRecords() { return (await allOrchIssues()).map(recordFrom).filter(Boolean); }

// rollupInitiatives — Linear PROJECTS are the tier where they exist, and a
// synthesized level where the team is flat. Same shape as every other backend.
function rollupInitiatives(all, state) {
  const explicit = all.filter((e) => (e.level ?? 'epic') === 'initiative');
  let inits;
  if (explicit.length) {
    inits = explicit.map((i) => ({
      ...i,
      epics: all.filter((e) => (e.parentId ?? e.parent ?? e.initiative) === i.id).map((e) => e.id),
    }));
  } else {
    const by = new Map();
    // EPICS only. A child belongs to its parent epic, not directly to an
    // initiative — including them made every un-parented child conjure an
    // "unassigned" initiative that does not exist on anyone's board.
    for (const e of all.filter((e) => (e.level ?? 'epic') === 'epic')) {
      const k = e.initiative || 'unassigned';
      if (!by.has(k)) by.set(k, []);
      by.get(k).push(e);
    }
    inits = [...by].map(([k, kids]) => ({
      id: k, title: k === 'unassigned' ? 'Unassigned work' : k,
      level: 'initiative', synthesized: true,
      epics: kids.map((e) => e.id),
      state: kids.every((e) => e.state === 'Merged') ? 'Merged'
           : kids.some((e) => e.state === 'In-progress') ? 'In-progress' : 'Backlog',
    }));
  }
  return state ? inits.filter((i) => i.state === state) : inits;
}

(async () => {
  switch (op) {
    case 'health': {
      const { teamKey, stateMap } = cfg();
      const t = await team();
      const result = { ok: true, backend: 'linear', team: `${t.key} — ${t.name}` };
      if (stateMap) {
        // Validate every mapped target against the team's REAL workflow states.
        // Unlike Jira these are creatable via the UI only, so a missing one is a
        // setup gap the operator must close, not something to invent.
        const known = new Set((t.states.nodes || []).map((s) => String(s.name).toLowerCase()));
        const targets = [...new Set(Object.values(stateMap))];
        const missing = targets.filter((s) => !known.has(String(s).toLowerCase()));
        for (const s of missing) {
          warn(`stateMap target "${s}" does not exist in team ${teamKey} — create it in Linear (Team settings → Workflow); updates mapping to it will fall back to labels`);
        }
        result.stateMap = { configured: Object.keys(stateMap).length, targets: targets.length, missing };
      } else {
        warn('no linear.stateMap configured — lifecycle will use the orch-state-* label scheme (run /core:board-setup to map states)');
      }
      out(result);
      break;
    }
    case 'capabilities':
      out({ session: 'cache', spec: true, epics: true, children: true, status: true, digest: 'cache', feedback: 'forge',
            hierarchy: 'native', claims: true });
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
      const i = await findIssue(id);
      if (!i) throw new Error(`epic ${id} not found`);
      const rec = recordFrom(i);
      out(JSON.stringify(rec || { id }, null, 2) + '\n');
      break;
    }
    case 'list-epics': {
      const state = arg('--state');
      const initiative = arg('--initiative');
      const parent = arg('--parent');
      const level = arg('--level');
      out((await listEpicRecords())
        .filter((e) => !state || e.state === state)
        .filter((e) => !initiative || e.initiative === initiative)
        .filter((e) => !parent || (e.parentId ?? e.parent) === parent)
        // Default to epic-level so the un-flagged call returns exactly what it
        // always did — children are VISIBLE here and must not change it.
        .filter((e) => (level ? (e.level ?? 'epic') === level : (e.level ?? 'epic') !== 'child')));
      break;
    }
    case 'list-initiatives': {
      out(rollupInitiatives(await listEpicRecords(), arg('--state')));
      break;
    }
    case 'push-status': {
      const id = arg('--id');
      const i = await findIssue(id);
      const e = (i && recordFrom(i)) || { id };
      e.state = arg('--state');
      const note = arg('--note'); if (note) e.note = note;
      const pr = arg('--pr'); if (pr) e.pr = Number(pr) || pr;
      const asg = arg('--assignee');
      if (asg === '-') { delete e.assignee; delete e.leaseUntil; } else if (asg) e.assignee = asg;
      const lease = arg('--lease-until'); if (lease) e.leaseUntil = lease;
      e.ts = new Date().toISOString();
      await upsertEpic(e);
      out({ id, state: e.state });
      break;
    }
    case 'pull-status': {
      out((await listEpicRecords()).map((e) => ({
        id: e.id, state: e.state || 'Backlog', note: e.note || null,
        pr: e.pr ?? null, assignee: e.assignee ?? null,
        leaseUntil: e.leaseUntil ?? null, ts: e.ts || null,
      })));
      break;
    }
    case 'push-spec': {
      const id = arg('--id');
      const md = stdin();
      cache(`spec-${slug(id)}.md`, md);
      const t = await team();
      const d = await gql(
        `query($t:String!){ issues(filter:{ labels:{ name:{ eq:"orch-spec" } }, title:{ eq:$t } }, first:1){ nodes{ id } } }`,
        { t: `[spec] ${id}` });
      const existing = (d.issues && d.issues.nodes && d.issues.nodes[0]) || null;
      const input = { title: `[spec] ${id}`, description: md, labelIds: await labelIds(['orch-spec']) };
      if (existing) await gql(`mutation($id:String!,$i:IssueUpdateInput!){ issueUpdate(id:$id, input:$i){ success } }`, { id: existing.id, i: input });
      else await gql(`mutation($i:IssueCreateInput!){ issueCreate(input:$i){ success } }`, { i: { ...input, teamId: t.id } });
      out({ id });
      break;
    }
    case 'get-spec': {
      const id = arg('--id');
      const f = path.join(CACHE, `spec-${slug(id)}.md`);
      if (fs.existsSync(f)) { out(fs.readFileSync(f, 'utf8')); break; }
      const d = await gql(
        `query($t:String!){ issues(filter:{ labels:{ name:{ eq:"orch-spec" } }, title:{ eq:$t } }, first:1){ nodes{ description } } }`,
        { t: `[spec] ${id}` });
      const n = (d.issues && d.issues.nodes && d.issues.nodes[0]) || null;
      if (!n) throw new Error(`spec ${id} not found`);
      out(n.description || '');
      break;
    }
    case 'list-specs': {
      const d = await gql(
        `query{ issues(filter:{ labels:{ name:{ eq:"orch-spec" } } }, first:250){ nodes{ title } } }`);
      out(((d.issues && d.issues.nodes) || []).map((n) => (n.title || '').replace(/^\[spec\] /, '')));
      break;
    }
    // sessions are perishable — cache-mirror only (an issue per session is noise)
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
      const i = await findIssue(id);
      if (i) {
        await gql(`mutation($i:CommentCreateInput!){ commentCreate(input:$i){ success } }`,
          { i: { issueId: i.id, body: '## Approved plan\n\n' + md } });
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
  process.stderr.write(`pm-linear ${op}: ${String(err.message || err).split('\n')[0]}\n`);
  process.exit(1);
});
