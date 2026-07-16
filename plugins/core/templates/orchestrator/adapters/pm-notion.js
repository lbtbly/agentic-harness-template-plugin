#!/usr/bin/env node
// pm-notion — state backend on a Notion database (created by /core:board-setup).
// Auth env NAME (value lives in the vault, never in the repo): NOTION_TOKEN.
// Config: orchestrator/state.config.json → { notion: { databaseId } }.
// Mapping: epic → page in the database — properties (Name "[id] title", State
// select, Epic ID, PR, Note, Updated) are the human board view; the FULL epic
// record JSON lives in the page body as a code block (the machine's source of
// truth, like the issue body on the github-projects adapter). spec → page too
// (Name "[spec] id"). session/plan/digest → cache-only (perishable). Every push
// mirrors to .orch/cache/ so reads fail open offline. Feedback is NOT here —
// the orch CLI pulls it from the forge. Headless uses REST-via-token (MCP
// oauth/stdio is fragile in cron — ADR-0007).
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const R = process.env.CLAUDE_PROJECT_DIR || path.resolve(__dirname, '..', '..');
const CACHE = path.join(R, '.orch', 'cache');
const [op, ...argv] = process.argv.slice(2);

const API = 'https://api.notion.com/v1';
const NOTION_VERSION = '2022-06-28';

function cfg() {
  const f = path.join(R, 'orchestrator', 'state.config.json');
  const c = JSON.parse(fs.readFileSync(f, 'utf8'));
  const dbId = c.notion && c.notion.databaseId;
  if (!dbId) throw new Error('state.config.json has no notion.databaseId — run /core:board-setup');
  return { dbId };
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
async function findPage(titlePrefix) {
  const { dbId } = cfg();
  const r = await api('POST', `/databases/${dbId}/query`, {
    filter: { property: 'Name', title: { starts_with: titlePrefix } }, page_size: 1,
  });
  return r.results[0];
}
async function readCodeBlock(pageId) {
  const r = await api('GET', `/blocks/${pageId}/children?page_size=100`);
  const code = r.results.find((b) => b.type === 'code');
  if (!code) return null;
  return { blockId: code.id, text: code.code.rich_text.map((t) => t.plain_text).join('') };
}
function epicProps(e) {
  return {
    Name: { title: [{ type: 'text', text: { content: `[${e.id}] ${e.title || ''}`.trim() } }] },
    State: { select: { name: e.state || 'Backlog' } },
    'Epic ID': { rich_text: rt(e.id) },
    ...(e.pr != null ? { PR: { number: Number(e.pr) || null } } : {}),
    ...(e.note ? { Note: { rich_text: rt(String(e.note).slice(0, 1900)) } } : {}),
    Updated: { date: { start: new Date().toISOString() } },
  };
}
async function upsertEpic(e) {
  const { dbId } = cfg();
  const payload = JSON.stringify(e, null, 2);
  const existing = await findPage(`[${e.id}]`);
  if (existing) {
    await api('PATCH', `/pages/${existing.id}`, { properties: epicProps(e) });
    const code = await readCodeBlock(existing.id);
    if (code) await api('PATCH', `/blocks/${code.blockId}`, { code: { rich_text: rt(payload), language: 'json' } });
    else await api('PATCH', `/blocks/${existing.id}/children`, { children: [{ type: 'code', code: { rich_text: rt(payload), language: 'json' } }] });
  } else {
    await api('POST', '/pages', {
      parent: { database_id: dbId },
      properties: epicProps(e),
      children: [{ type: 'code', code: { rich_text: rt(payload), language: 'json' } }],
    });
  }
  cache(`epic-${slug(e.id)}.json`, payload);
}
async function listEpicRecords() {
  const { dbId } = cfg();
  const pages = [];
  let cursor;
  do {
    const r = await api('POST', `/databases/${dbId}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    pages.push(...r.results);
    cursor = r.has_more ? r.next_cursor : undefined;
  } while (cursor);
  const epics = [];
  for (const p of pages) {
    const title = ((p.properties.Name || {}).title || []).map((t) => t.plain_text).join('');
    if (!title.startsWith('[') || title.startsWith('[spec]')) continue;
    const code = await readCodeBlock(p.id);
    if (code) { try { epics.push(JSON.parse(code.text)); continue; } catch { /* fall back to properties */ } }
    epics.push({
      id: title.replace(/^\[([^\]]+)\].*/, '$1'),
      title: title.replace(/^\[[^\]]+\]\s*/, ''),
      state: ((p.properties.State || {}).select || {}).name || 'Backlog',
    });
  }
  return epics;
}

(async () => {
  switch (op) {
    case 'health': {
      token(); // credentials are the first complaint, before config
      const { dbId } = cfg();
      const db = await api('GET', `/databases/${dbId}`);
      out({ ok: true, backend: 'notion', database: (db.title || []).map((t) => t.plain_text).join('') });
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
      const page = await findPage(`[${id}]`);
      if (!page) throw new Error(`epic ${id} not found`);
      const code = await readCodeBlock(page.id);
      out(code ? code.text + '\n' : '{}\n');
      break;
    }
    case 'list-epics': {
      const state = arg('--state');
      out((await listEpicRecords()).filter((e) => !state || e.state === state));
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
      const { dbId } = cfg();
      const existing = await findPage(`[spec] ${id}`);
      if (existing) {
        const code = await readCodeBlock(existing.id);
        if (code) await api('PATCH', `/blocks/${code.blockId}`, { code: { rich_text: rt(md), language: 'markdown' } });
        else await api('PATCH', `/blocks/${existing.id}/children`, { children: [{ type: 'code', code: { rich_text: rt(md), language: 'markdown' } }] });
      } else {
        await api('POST', '/pages', {
          parent: { database_id: dbId },
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
      const { dbId } = cfg();
      const r = await api('POST', `/databases/${dbId}/query`, {
        filter: { property: 'Name', title: { starts_with: '[spec] ' } }, page_size: 100,
      });
      out(r.results.map((p) => ((p.properties.Name || {}).title || []).map((t) => t.plain_text).join('').replace(/^\[spec\] /, '')));
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
