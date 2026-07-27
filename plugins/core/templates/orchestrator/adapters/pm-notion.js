#!/usr/bin/env node
// pm-notion — state backend on Notion, using NATIVE Notion relations (ADR-0030).
//
//   initiative  → a page in a SEPARATE Initiatives data source
//   epic        → a page in the epics data source, Type = Epic
//   task/child  → a page in the SAME data source, Type = Task, linked by the
//                 "Parent epic" self-relation (Notion syncs "Sub-tasks" back)
//   state       → the State select; the 12 lifecycle options ARE the columns
//
// The `Type` select is the parallel of Jira's/Linear's orch-epic / orch-child
// labels: without it, epics and tasks are indistinguishable in one flat table.
// The FULL record JSON still lives in the page body as a code block — that is
// the precise source of truth; the properties are the human/board view.
//
// API 2025-09-03 split databases into databases + DATA SOURCES. This adapter
// speaks data sources (matching the Notion MCP lane, so /core:board-setup and
// the headless runner agree). Relation WRITES may only use data_source_id now;
// database_id is rejected. A legacy config carrying only `databaseId` is still
// accepted — the data source is resolved from it once, per run.
//
// EVERY relation feature degrades: a board without `Type`, `Parent epic`, or a
// configured Initiatives source keeps working exactly as before, with that part
// of the hierarchy living in the payload only. `capabilities.hierarchy` reports
// which of the two it is, so callers never have to guess.
//
// Config: orchestrator/state.config.json →
//   { notion: { dataSourceId, initiativesDataSourceId?, databaseId? } }
// Auth env NAME (value lives in the vault, never the repo): NOTION_TOKEN.
// BOTH databases must be shared with the integration, or relation reads 404.
// Feedback is NOT here — the orch CLI pulls it from the forge (ADR-0007).
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const R = process.env.CLAUDE_PROJECT_DIR || path.resolve(__dirname, '..', '..');
const CACHE = path.join(R, '.orch', 'cache');
const [op, ...argv] = process.argv.slice(2);

const API = process.env.NOTION_API_URL || 'https://api.notion.com/v1';
const NOTION_VERSION = process.env.NOTION_VERSION || '2026-03-11';

const P_TYPE = 'Type';
const P_PARENT = 'Parent epic';
const P_INITIATIVE = 'Initiative';
const P_INIT_ID = 'Initiative ID';

function rawCfg() {
  const f = path.join(R, 'orchestrator', 'state.config.json');
  const c = JSON.parse(fs.readFileSync(f, 'utf8'));
  return (c && c.notion) || {};
}
function token() {
  const t = process.env.NOTION_TOKEN;
  if (!t) throw new Error('NOTION_TOKEN not set (env var NAME per docs/SECURITY.md)');
  return t;
}
async function api(method, p, body) {
  const res = await fetch(API + p, {
    method,
    headers: {
      Authorization: `Bearer ${token()}`,
      'Notion-Version': NOTION_VERSION,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const msg = (await res.json().catch(() => ({}))).message || res.statusText;
    throw new Error(`notion ${method} ${p}: ${res.status} ${msg}`);
  }
  return res.json();
}
function warn(msg) { process.stderr.write(`pm-notion: ${msg}\n`); }
function arg(flag) { const i = argv.indexOf(flag); return i >= 0 ? argv[i + 1] : undefined; }
function stdin() { return fs.readFileSync(0, 'utf8'); }
function cache(rel, content) {
  const f = path.join(CACHE, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, content);
}
function out(obj) { process.stdout.write(typeof obj === 'string' ? obj : JSON.stringify(obj) + '\n'); }
function slug(s) { return String(s).replace(/[^a-zA-Z0-9._-]/g, '-'); }
function rt(s) { // rich_text chunks (Notion caps each item at 2000 chars)
  const chunks = [];
  for (let i = 0; i < s.length; i += 1900) chunks.push({ type: 'text', text: { content: s.slice(i, i + 1900) } });
  return chunks.length ? chunks : [{ type: 'text', text: { content: '' } }];
}
function titleOf(page) {
  const t = Object.values(page.properties || {}).find((v) => v && v.type === 'title');
  return ((t && t.title) || []).map((x) => x.plain_text).join('');
}
function textOf(page, name) {
  const v = (page.properties || {})[name];
  return ((v && v.rich_text) || []).map((x) => x.plain_text).join('');
}
function selectOf(page, name) {
  const v = (page.properties || {})[name];
  return (v && v.select && v.select.name) || null;
}
function relIds(page, name) {
  const v = (page.properties || {})[name];
  return ((v && v.relation) || []).map((x) => x.id);
}

// --- data-source resolution (legacy databaseId still accepted) ---------------
let _ds = null;
async function ds() {
  if (_ds) return _ds;
  const c = rawCfg();
  if (c.dataSourceId) {
    _ds = { id: c.dataSourceId, initId: c.initiativesDataSourceId || null };
    return _ds;
  }
  if (!c.databaseId) throw new Error('state.config.json has no notion.dataSourceId — run /core:board-setup');
  // A 2022-06-28-era config. Resolve the database's data source once, and say so
  // — the operator should record the id rather than pay this lookup every run.
  const db = await api('GET', `/databases/${c.databaseId}`);
  const first = (db.data_sources || [])[0];
  if (!first) throw new Error(`database ${c.databaseId} exposes no data source`);
  warn(`resolved notion.databaseId → dataSourceId ${first.id}; record it in state.config.json to skip this lookup`);
  _ds = { id: first.id, initId: c.initiativesDataSourceId || null };
  return _ds;
}
// What does the board actually support? Every relation feature is optional, so
// this is read once and every write consults it rather than assuming.
let _schema = null;
async function schema() {
  if (_schema) return _schema;
  const { id, initId } = await ds();
  const src = await api('GET', `/data_sources/${id}`);
  const props = src.properties || {};
  _schema = {
    title: (src.title || []).map((t) => t.plain_text).join(''),
    props,
    hasType: !!props[P_TYPE],
    hasParent: (props[P_PARENT] || {}).type === 'relation',
    hasInitiative: (props[P_INITIATIVE] || {}).type === 'relation' && !!initId,
  };
  return _schema;
}
async function hierarchyMode() {
  const s = await schema();
  return s.hasParent || s.hasInitiative ? 'native' : 'derived';
}

async function queryAll(dataSourceId, body) {
  const pages = [];
  let cursor;
  do {
    const r = await api('POST', `/data_sources/${dataSourceId}/query`,
      { page_size: 100, ...(body || {}), ...(cursor ? { start_cursor: cursor } : {}) });
    pages.push(...(r.results || []));
    cursor = r.has_more ? r.next_cursor : undefined;
  } while (cursor);
  return pages;
}
async function findPage(titlePrefix) {
  const { id } = await ds();
  const s = await schema();
  const titleProp = Object.entries(s.props).find(([, v]) => v.type === 'title');
  const name = titleProp ? titleProp[0] : 'Name';
  const r = await api('POST', `/data_sources/${id}/query`, {
    filter: { property: name, title: { starts_with: titlePrefix } }, page_size: 1,
  });
  return (r.results || [])[0];
}
async function readCodeBlock(pageId) {
  const r = await api('GET', `/blocks/${pageId}/children?page_size=100`);
  const code = (r.results || []).find((b) => b.type === 'code');
  if (!code) return null;
  return { blockId: code.id, text: code.code.rich_text.map((t) => t.plain_text).join('') };
}

// --- the initiatives data source --------------------------------------------
async function initiativePages() {
  const { initId } = await ds();
  if (!initId) return [];
  return queryAll(initId);
}
function initiativeIdOf(page) {
  // an explicit "Initiative ID" wins; otherwise the title is the id
  return textOf(page, P_INIT_ID) || titleOf(page) || page.id;
}
async function initiativePageIdFor(name) {
  const { initId } = await ds();
  if (!initId || !name) return null;
  const pages = await initiativePages();
  const hit = pages.find((p) => initiativeIdOf(p) === name || titleOf(p) === name);
  if (!hit) {
    warn(`no Initiative page named "${name}" — keeping it as a payload field only (create it to get the native tier)`);
    return null;
  }
  return hit.id;
}

async function epicProps(e, ctx) {
  const s = await schema();
  const props = {
    Name: { title: [{ type: 'text', text: { content: `[${e.id}] ${e.title || ''}`.trim() } }] },
    State: { select: { name: e.state || 'Backlog' } },
    'Epic ID': { rich_text: rt(e.id) },
    ...(e.pr != null ? { PR: { number: Number(e.pr) || null } } : {}),
    ...(e.note ? { Note: { rich_text: rt(String(e.note).slice(0, 1900)) } } : {}),
    'Assigned to': { rich_text: rt(e.assignee || '') },
    Complexity: { select: e.complexity ? { name: e.complexity } : null },
    Updated: { date: { start: new Date().toISOString() } },
  };
  const isChild = !!(e.parent || e.parentId);
  if (s.hasType) props[P_TYPE] = { select: { name: isChild ? 'Task' : 'Epic' } };
  if (s.hasParent && isChild) {
    const pid = (ctx && ctx.parentPageId) || null;
    // Only ever SET the relation we resolved. Writing [] would clear a link a
    // human made in Notion, and the board is the golden source.
    if (pid) props[P_PARENT] = { relation: [{ id: pid }] };
  }
  if (s.hasInitiative && e.initiative) {
    const iid = await initiativePageIdFor(e.initiative);
    if (iid) props[P_INITIATIVE] = { relation: [{ id: iid }] };
  }
  return props;
}

async function upsertEpic(e) {
  const { id: dsId } = await ds();
  const s = await schema();
  const payload = JSON.stringify(e, null, 2);
  const parentRef = e.parent || e.parentId;
  let parentPageId = null;
  if (s.hasParent && parentRef) {
    const pp = await findPage(`[${parentRef}]`);
    if (pp) parentPageId = pp.id;
    else warn(`parent epic "${parentRef}" not found — creating "${e.id}" unlinked`);
  }
  const props = await epicProps(e, { parentPageId });
  const existing = await findPage(`[${e.id}]`);
  if (existing) {
    await api('PATCH', `/pages/${existing.id}`, { properties: props });
    const code = await readCodeBlock(existing.id);
    if (code) await api('PATCH', `/blocks/${code.blockId}`, { code: { rich_text: rt(payload), language: 'json' } });
    else await api('PATCH', `/blocks/${existing.id}/children`, { children: [{ type: 'code', code: { rich_text: rt(payload), language: 'json' } }] });
  } else {
    await api('POST', '/pages', {
      parent: { type: 'data_source_id', data_source_id: dsId },
      properties: props,
      children: [{ type: 'code', code: { rich_text: rt(payload), language: 'json' } }],
    });
  }
  cache(`epic-${slug(e.id)}.json`, payload);
}

async function listEpicRecords() {
  const { id: dsId } = await ds();
  const s = await schema();
  const pages = (await queryAll(dsId)).filter((p) => {
    const t = titleOf(p);
    return t.startsWith('[') && !t.startsWith('[spec]');
  });
  // page id → epic id, so a relation can be resolved without another round trip
  const byPage = new Map();
  for (const p of pages) {
    const t = titleOf(p);
    byPage.set(p.id, textOf(p, 'Epic ID') || t.replace(/^\[([^\]]+)\].*/, '$1'));
  }
  const initById = new Map();
  if (s.hasInitiative) for (const ip of await initiativePages()) initById.set(ip.id, initiativeIdOf(ip));

  const epics = [];
  for (const p of pages) {
    const t = titleOf(p);
    let rec = null;
    const code = await readCodeBlock(p.id);
    if (code) { try { rec = JSON.parse(code.text); } catch { warn(`skipping an unparseable payload on "${t}"`); } }
    // No payload: a human made this card. Read it anyway — the board is the
    // source of truth, not a mirror of what we happened to push.
    if (!rec) {
      rec = {
        id: t.replace(/^\[([^\]]+)\].*/, '$1'),
        title: t.replace(/^\[[^\]]+\]\s*/, ''),
        state: selectOf(p, 'State') || 'Backlog',
      };
    }
    // NATIVE values win over the payload: a link a human set in Notion is truth.
    if (s.hasType) {
      const ty = selectOf(p, P_TYPE);
      if (ty) rec.level = ty === 'Task' ? 'child' : 'epic';
    }
    if (s.hasParent) {
      const pid = relIds(p, P_PARENT)[0];
      if (pid && byPage.has(pid)) rec.parentId = byPage.get(pid);
    }
    if (s.hasInitiative) {
      const iid = relIds(p, P_INITIATIVE)[0];
      if (iid && initById.has(iid)) rec.initiative = initById.get(iid);
    }
    epics.push(rec);
  }
  return epics;
}

// rollupInitiatives — real Initiative PAGES when the separate data source is
// configured; a synthesized tier otherwise. Same shape either way.
function rollupInitiatives(all, state, pages) {
  let inits;
  if (pages && pages.length) {
    inits = pages.map((p) => {
      const id = initiativeIdOf(p);
      const kids = all.filter((e) => (e.level ?? 'epic') === 'epic' && e.initiative === id);
      return {
        id, title: titleOf(p) || id, level: 'initiative',
        epics: kids.map((e) => e.id),
        state: selectOf(p, 'State')
            || (kids.length && kids.every((e) => e.state === 'Merged') ? 'Merged'
                : kids.some((e) => e.state === 'In-progress') ? 'In-progress' : 'Backlog'),
      };
    });
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
      token(); // credentials are the first complaint, before config
      const s = await schema();
      const { id, initId } = await ds();
      const result = {
        ok: true, backend: 'notion', dataSource: s.title || id,
        hierarchy: await hierarchyMode(),
      };
      const missing = [];
      if (!s.hasType) missing.push(`${P_TYPE} (select: Epic/Task)`);
      if (!s.hasParent) missing.push(`${P_PARENT} (self-relation)`);
      if (initId && !(s.props[P_INITIATIVE] || {}).type) missing.push(`${P_INITIATIVE} (relation)`);
      if (!initId) warn('no notion.initiativesDataSourceId — the initiative tier is derived from the record, not a real Notion page');
      for (const m of missing) warn(`board is missing "${m}" — that part of the hierarchy stays in the payload only (run /core:board-setup to add it)`);
      result.schema = { hasType: s.hasType, hasParent: s.hasParent, hasInitiative: s.hasInitiative, missing };
      if (initId) {
        // a related database must ALSO be shared with the integration, and the
        // failure is a 404 that reads like the id being wrong
        await api('GET', `/data_sources/${initId}`).catch((e) => {
          throw new Error(`initiatives data source unreachable (${String(e.message).split('\n')[0]}) — is it shared with the integration?`);
        });
      }
      out(result);
      break;
    }
    case 'capabilities':
      out({ session: 'cache', spec: true, epics: true, children: true, status: true, digest: 'cache', feedback: 'forge',
            hierarchy: await hierarchyMode(), claims: true });
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
      const page = await findPage(`[${id}]`);
      if (!page) throw new Error(`epic ${id} not found`);
      const code = await readCodeBlock(page.id);
      out(code ? code.text + '\n' : JSON.stringify({ id, title: titleOf(page).replace(/^\[[^\]]+\]\s*/, ''), state: selectOf(page, 'State') || 'Backlog' }, null, 2) + '\n');
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
        // always did — Tasks are newly VISIBLE and must not change it.
        .filter((e) => (level ? (e.level ?? 'epic') === level : (e.level ?? 'epic') !== 'child')));
      break;
    }
    case 'list-initiatives': {
      const s = await schema();
      out(rollupInitiatives(await listEpicRecords(), arg('--state'),
        s.hasInitiative ? await initiativePages() : null));
      break;
    }
    case 'push-status': {
      const id = arg('--id');
      const page = await findPage(`[${id}]`);
      let e = { id };
      if (page) {
        const code = await readCodeBlock(page.id);
        if (code) { try { e = JSON.parse(code.text); } catch { /* keep minimal */ } }
      }
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
      const { id: dsId } = await ds();
      const existing = await findPage(`[spec] ${id}`);
      if (existing) {
        const code = await readCodeBlock(existing.id);
        if (code) await api('PATCH', `/blocks/${code.blockId}`, { code: { rich_text: rt(md), language: 'markdown' } });
        else await api('PATCH', `/blocks/${existing.id}/children`, { children: [{ type: 'code', code: { rich_text: rt(md), language: 'markdown' } }] });
      } else {
        await api('POST', '/pages', {
          parent: { type: 'data_source_id', data_source_id: dsId },
          properties: { Name: { title: [{ type: 'text', text: { content: `[spec] ${id}` } }] } },
          children: [{ type: 'code', code: { rich_text: rt(md), language: 'markdown' } }],
        });
      }
      out({ id });
      break;
    }
    case 'get-spec': {
      const id = arg('--id');
      const f = path.join(CACHE, `spec-${slug(id)}.md`);
      if (fs.existsSync(f)) { out(fs.readFileSync(f, 'utf8')); break; }
      const page = await findPage(`[spec] ${id}`);
      if (!page) throw new Error(`spec ${id} not found`);
      const code = await readCodeBlock(page.id);
      out(code ? code.text : '');
      break;
    }
    case 'list-specs': {
      const { id: dsId } = await ds();
      const r = await api('POST', `/data_sources/${dsId}/query`, {
        filter: { property: 'Name', title: { starts_with: '[spec] ' } }, page_size: 100,
      });
      out((r.results || []).map((p) => titleOf(p).replace(/^\[spec\] /, '')));
      break;
    }
    // sessions are perishable — cache-mirror only (a board page per session is noise)
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
      cache(`plan-${slug(id)}.md`, stdin());
      out({ epic: id });
      break;
    }
    case 'get-plan': {
      const id = arg('--epic');
      const f = path.join(CACHE, `plan-${slug(id)}.md`);
      if (!fs.existsSync(f)) throw new Error(`plan ${id} not cached`);
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
  process.stderr.write(`pm-notion ${op}: ${String(err.message || err).split('\n')[0]}\n`);
  process.exit(1);
});
