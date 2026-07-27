#!/usr/bin/env node
// pm-github-projects — state backend on GitHub Issues/labels via the gh CLI
// (ADR-0007). Auth: gh's own auth or GITHUB_TOKEN/GH_TOKEN env (NAME only —
// never stored, never echoed). Every push mirrors to .orch/cache/ so reads
// fail open when offline. Feedback is NOT here — the orch CLI pulls it from
// the forge directly.
//
// Mapping: epic → issue labeled orch:epic + orch:state/<state>;
// spec/plan/session → issue-attached (epic) or cache-only (session — sessions
// are perishable, a board issue per session would be noise).
'use strict';
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const R = process.env.CLAUDE_PROJECT_DIR || path.resolve(__dirname, '..', '..');
const CACHE = path.join(R, '.orch', 'cache');
const [op, ...argv] = process.argv.slice(2);

function gh(args, input) {
  return execFileSync('gh', args, { input, encoding: 'utf8' });
}
function arg(flag) {
  const i = argv.indexOf(flag);
  return i >= 0 ? argv[i + 1] : undefined;
}
function stdin() {
  return fs.readFileSync(0, 'utf8');
}
function cache(rel, content) {
  const f = path.join(CACHE, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, content);
}
function out(obj) {
  process.stdout.write(typeof obj === 'string' ? obj : JSON.stringify(obj) + '\n');
}
function slug(s) {
  return String(s).replace(/[^a-zA-Z0-9._-]/g, '-');
}
function warn(msg) { process.stderr.write(`pm-github-projects: ${msg}\n`); }

// A malformed ```json fence used to throw and kill the ENTIRE listing — one bad
// issue made the whole board unreadable. The `none` backend already guards this.
// Falls back to the "[id] Title" convention so an issue a HUMAN wrote on the
// board is still picked up (GitHub/GitLab silently dropped those; Jira/Notion
// happened to handle it). The board is the golden source — it must be readable
// even when the harness did not write the record.
function extractPayload(body, title) {
  const m = (body || '').match(/```json\n([\s\S]*?)\n```/);
  if (m) {
    try { return JSON.parse(m[1]); }
    catch (e) { warn(`skipping an item with an unparseable payload: ${String(e.message).split('\n')[0]}`); }
  }
  const t = (title || '').match(/^\[([^\]]+)\]\s*(.*)$/);
  return t ? { id: t[1], title: t[2], state: 'Backlog' } : null;
}

// rollupInitiatives — the hierarchy, however the board expresses it. Explicit
// level:"initiative" records win; otherwise one is synthesized per distinct
// .initiative value, so a flat board answers the same question as a nested one.
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

function findEpicIssue(id) {
  const list = JSON.parse(
    gh(['issue', 'list', '--limit', '500', '--label', 'orch:epic', '--state', 'all', '--json', 'number,title'])
  );
  return list.find((i) => i.title.startsWith(`[${id}]`));
}

try {
  switch (op) {
    case 'health': {
      const who = gh(['api', 'user', '--jq', '.login']).trim();
      out({ ok: true, backend: 'github-projects', whoami: who });
      break;
    }
    case 'push-session': {
      // Sessions are perishable — cache-mirror only (the board holds epics).
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
    case 'push-epic': {
      const e = JSON.parse(stdin());
      const title = `[${e.id}] ${e.title || ''}`.trim();
      const body = '```json\n' + JSON.stringify(e, null, 2) + '\n```';
      const existing = findEpicIssue(e.id);
      if (existing) {
        gh(['issue', 'edit', String(existing.number), '--title', title, '--body', body]);
      } else {
        gh(['label', 'create', 'orch:epic', '--force']);
        gh(['issue', 'create', '--title', title, '--body', body, '--label', 'orch:epic']);
      }
      cache(`epic-${slug(e.id)}.json`, JSON.stringify(e, null, 2));
      out({ id: e.id });
      break;
    }
    case 'push-backlog': {
      const epics = JSON.parse(stdin());
      for (const e of epics) {
        gh(['label', 'create', 'orch:epic', '--force']);
        const existing = findEpicIssue(e.id);
        const title = `[${e.id}] ${e.title || ''}`.trim();
        const body = '```json\n' + JSON.stringify(e, null, 2) + '\n```';
        if (existing) gh(['issue', 'edit', String(existing.number), '--body', body]);
        else gh(['issue', 'create', '--title', title, '--body', body, '--label', 'orch:epic']);
        cache(`epic-${slug(e.id)}.json`, JSON.stringify(e, null, 2));
      }
      out({ ok: true });
      break;
    }
    case 'get-epic': {
      const id = arg('--id');
      const iss = findEpicIssue(id);
      if (!iss) throw new Error(`epic ${id} not found`);
      const body = JSON.parse(
        gh(['issue', 'view', String(iss.number), '--json', 'body'])
      ).body;
      const m = body.match(/```json\n([\s\S]*?)\n```/);
      out(m ? m[1] + '\n' : '{}\n');
      break;
    }
    case 'list-epics': {
      const state = arg('--state');
      const initiative = arg('--initiative');
      const parent = arg('--parent');
      const level = arg('--level');
      const list = JSON.parse(
        gh(['issue', 'list', '--limit', '500', '--label', 'orch:epic', '--state', 'all', '--json', 'number,title,body'])
      );
      const epics = list
        .map((i) => extractPayload(i.body, i.title))
        .filter(Boolean)
        .filter((e) => !state || e.state === state)
        .filter((e) => !initiative || e.initiative === initiative)
        .filter((e) => !parent || (e.parentId ?? e.parent) === parent)
        .filter((e) => !level || (e.level ?? 'epic') === level);
      out(epics);
      break;
    }
    case 'list-initiatives': {
      const state = arg('--state');
      const all = JSON.parse(
        gh(['issue', 'list', '--limit', '500', '--label', 'orch:epic', '--state', 'all', '--json', 'number,title,body'])
      ).map((i) => extractPayload(i.body, i.title)).filter(Boolean);
      out(rollupInitiatives(all, state));
      break;
    }
    case 'push-status': {
      const id = arg('--id');
      const state = arg('--state');
      const note = arg('--note');
      const iss = findEpicIssue(id);
      if (!iss) throw new Error(`epic ${id} not found`);
      const body = JSON.parse(gh(['issue', 'view', String(iss.number), '--json', 'body'])).body;
      const m = body.match(/```json\n([\s\S]*?)\n```/);
      const e = m ? JSON.parse(m[1]) : { id };
      e.state = state;
      if (note) e.note = note;
      // --pr / --assignee used to be parsed by Jira and Notion and DROPPED here,
      // and pull-status omitted `pr` entirely. `assignee` is now load-bearing:
      // it carries the claim that stops two agents taking the same card.
      const pr = arg('--pr');
      const assignee = arg('--assignee');
      const lease = arg('--lease-until');
      if (pr) e.pr = Number(pr);
      if (assignee === '-') { delete e.assignee; delete e.leaseUntil; }
      else if (assignee) e.assignee = assignee;
      if (lease) e.leaseUntil = lease;
      e.ts = new Date().toISOString();
      gh(['label', 'create', `orch:state/${state}`, '--force']);
      gh([
        'issue', 'edit', String(iss.number),
        '--body', '```json\n' + JSON.stringify(e, null, 2) + '\n```',
        '--add-label', `orch:state/${state}`,
      ]);
      cache(`epic-${slug(id)}.json`, JSON.stringify(e, null, 2));
      out({ id, state });
      break;
    }
    case 'pull-status': {
      const list = JSON.parse(
        gh(['issue', 'list', '--limit', '500', '--label', 'orch:epic', '--state', 'all', '--json', 'title,body'])
      );
      out(
        list
          .map((i) => extractPayload(i.body, i.title))
          .filter(Boolean)
          // `pr` was omitted entirely here, so nothing downstream could route
          // feedback; assignee/leaseUntil carry the claim (ADR-0027).
          .map((e) => ({
            id: e.id, state: e.state || 'Backlog', note: e.note || null,
            pr: e.pr ?? null, assignee: e.assignee ?? null,
            leaseUntil: e.leaseUntil ?? null, ts: e.ts || null,
          }))
      );
      break;
    }
    case 'push-spec': {
      const id = arg('--id');
      const md = stdin();
      cache(`spec-${slug(id)}.md`, md);
      gh(['label', 'create', 'orch:spec', '--force']);
      const list = JSON.parse(gh(['issue', 'list', '--limit', '500', '--label', 'orch:spec', '--state', 'all', '--json', 'number,title']));
      const existing = list.find((i) => i.title === `[spec] ${id}`);
      if (existing) gh(['issue', 'edit', String(existing.number), '--body', md]);
      else gh(['issue', 'create', '--title', `[spec] ${id}`, '--body', md, '--label', 'orch:spec']);
      out({ id });
      break;
    }
    case 'get-spec': {
      const id = arg('--id');
      const f = path.join(CACHE, `spec-${slug(id)}.md`);
      if (fs.existsSync(f)) { out(fs.readFileSync(f, 'utf8')); break; }
      const list = JSON.parse(gh(['issue', 'list', '--limit', '500', '--label', 'orch:spec', '--state', 'all', '--json', 'number,title']));
      const iss = list.find((i) => i.title === `[spec] ${id}`);
      if (!iss) throw new Error(`spec ${id} not found`);
      out(JSON.parse(gh(['issue', 'view', String(iss.number), '--json', 'body'])).body);
      break;
    }
    case 'list-specs': {
      const list = JSON.parse(gh(['issue', 'list', '--limit', '500', '--label', 'orch:spec', '--state', 'all', '--json', 'title']));
      out(list.map((i) => i.title.replace(/^\[spec\] /, '')));
      break;
    }
    case 'push-plan': {
      const id = arg('--epic');
      cache(`plan-${slug(id)}.md`, stdin());
      const iss = findEpicIssue(id);
      if (iss) gh(['issue', 'comment', String(iss.number), '--body', '## Approved plan\n\n' + fs.readFileSync(path.join(CACHE, `plan-${slug(id)}.md`), 'utf8')]);
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
    case 'capabilities': {
      out({ session: 'cache', spec: true, epics: true, status: true, digest: 'cache', feedback: 'forge',
            hierarchy: 'derived', claims: true });
      break;
    }
    default:
      throw new Error(`unknown op: ${op}`);
  }
} catch (err) {
  // never echo tokens — execFileSync errors can embed env; print message only
  process.stderr.write(`pm-github-projects ${op}: ${err.message.split('\n')[0]}\n`);
  process.exit(1);
}
