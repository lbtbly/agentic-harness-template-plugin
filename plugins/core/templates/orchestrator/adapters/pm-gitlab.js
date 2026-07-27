#!/usr/bin/env node
// pm-gitlab — state backend on GitLab issues/labels via the glab CLI
// (ADR-0007). VPN-friendly: glab talks to self-managed hosts (GITLAB_HOST) and
// authenticates via glab auth or GITLAB_TOKEN (env NAME only — never stored,
// never echoed). Every push mirrors to .orch/cache/ for offline reads.
// Feedback is pulled from the forge by the orch CLI, not here.
'use strict';
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const R = process.env.CLAUDE_PROJECT_DIR || path.resolve(__dirname, '..', '..');
const CACHE = path.join(R, '.orch', 'cache');
const [op, ...argv] = process.argv.slice(2);

function glab(args, input) {
  return execFileSync('glab', args, { input, encoding: 'utf8' });
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
function listIssues(label) {
  // glab issue list --output json
  return JSON.parse(glab(['issue', 'list', '--label', label, '--all', '--per-page', '100', '--output', 'json']));
}
function findEpicIssue(id) {
  return listIssues('orch:epic').find((i) => i.title.startsWith(`[${id}]`));
}
function warn(msg) { process.stderr.write(`pm-gitlab: ${msg}\n`); }

// Guarded: one malformed ```json fence used to throw and kill the ENTIRE
// listing. Falls back to the "[id] Title" convention so an issue a HUMAN wrote
// on the board is still picked up — the board is the golden source and must be
// readable even when the harness did not write the record.
function extractJson(body, title) {
  const m = (body || '').match(/```json\n([\s\S]*?)\n```/);
  if (m) {
    try { return JSON.parse(m[1]); }
    catch (e) { warn(`skipping an item with an unparseable payload: ${String(e.message).split('\n')[0]}`); }
  }
  const t = (title || '').match(/^\[([^\]]+)\]\s*(.*)$/);
  return t ? { id: t[1], title: t[2], state: 'Backlog' } : null;
}

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
    for (const e of all.filter((e) => (e.level ?? 'epic') !== 'initiative')) {
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

try {
  switch (op) {
    case 'health': {
      const who = glab(['api', 'user']).trim();
      out({ ok: true, backend: 'gitlab', whoami: JSON.parse(who).username });
      break;
    }
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
    case 'push-epic': {
      const e = JSON.parse(stdin());
      const title = `[${e.id}] ${e.title || ''}`.trim();
      const body = '```json\n' + JSON.stringify(e, null, 2) + '\n```';
      const existing = findEpicIssue(e.id);
      if (existing) glab(['issue', 'update', String(existing.iid), '--title', title, '--description', body]);
      else glab(['issue', 'create', '--title', title, '--description', body, '--label', 'orch:epic', '--yes']);
      cache(`epic-${slug(e.id)}.json`, JSON.stringify(e, null, 2));
      out({ id: e.id });
      break;
    }
    case 'push-backlog': {
      for (const e of JSON.parse(stdin())) {
        const existing = findEpicIssue(e.id);
        const title = `[${e.id}] ${e.title || ''}`.trim();
        const body = '```json\n' + JSON.stringify(e, null, 2) + '\n```';
        if (existing) glab(['issue', 'update', String(existing.iid), '--description', body]);
        else glab(['issue', 'create', '--title', title, '--description', body, '--label', 'orch:epic', '--yes']);
        cache(`epic-${slug(e.id)}.json`, JSON.stringify(e, null, 2));
      }
      out({ ok: true });
      break;
    }
    case 'get-epic': {
      const iss = findEpicIssue(arg('--id'));
      if (!iss) throw new Error(`epic ${arg('--id')} not found`);
      const full = JSON.parse(glab(['issue', 'view', String(iss.iid), '--output', 'json']));
      const e = extractJson(full.description);
      out(e || {});
      break;
    }
    case 'list-epics': {
      const state = arg('--state');
      const initiative = arg('--initiative');
      const parent = arg('--parent');
      const level = arg('--level');
      out(
        listIssues('orch:epic')
          .map((i) => extractJson(i.description, i.title))
          .filter(Boolean)
          .filter((e) => !state || e.state === state)
          .filter((e) => !initiative || e.initiative === initiative)
          .filter((e) => !parent || (e.parentId ?? e.parent) === parent)
          .filter((e) => !level || (e.level ?? 'epic') === level)
      );
      break;
    }
    case 'list-initiatives': {
      const state = arg('--state');
      out(rollupInitiatives(
        listIssues('orch:epic').map((i) => extractJson(i.description, i.title)).filter(Boolean),
        state));
      break;
    }
    case 'push-status': {
      const id = arg('--id');
      const state = arg('--state');
      const note = arg('--note');
      const iss = findEpicIssue(id);
      if (!iss) throw new Error(`epic ${id} not found`);
      const full = JSON.parse(glab(['issue', 'view', String(iss.iid), '--output', 'json']));
      const e = extractJson(full.description, full.title) || { id };
      e.state = state;
      if (note) e.note = note;
      // --pr / --assignee were parsed by Jira and Notion and DROPPED here.
      // `assignee` is now load-bearing: it carries the claim (ADR-0027).
      const pr = arg('--pr');
      const assignee = arg('--assignee');
      const lease = arg('--lease-until');
      if (pr) e.pr = Number(pr);
      if (assignee === '-') { delete e.assignee; delete e.leaseUntil; }
      else if (assignee) e.assignee = assignee;
      if (lease) e.leaseUntil = lease;
      e.ts = new Date().toISOString();
      glab([
        'issue', 'update', String(iss.iid),
        '--description', '```json\n' + JSON.stringify(e, null, 2) + '\n```',
        '--label', `orch:state/${state}`,
      ]);
      cache(`epic-${slug(id)}.json`, JSON.stringify(e, null, 2));
      out({ id, state });
      break;
    }
    case 'pull-status': {
      out(
        listIssues('orch:epic')
          .map((i) => extractJson(i.description))
          .filter(Boolean)
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
      const existing = listIssues('orch:spec').find((i) => i.title === `[spec] ${id}`);
      if (existing) glab(['issue', 'update', String(existing.iid), '--description', md]);
      else glab(['issue', 'create', '--title', `[spec] ${id}`, '--description', md, '--label', 'orch:spec', '--yes']);
      out({ id });
      break;
    }
    case 'get-spec': {
      const id = arg('--id');
      const f = path.join(CACHE, `spec-${slug(id)}.md`);
      if (fs.existsSync(f)) { out(fs.readFileSync(f, 'utf8')); break; }
      const iss = listIssues('orch:spec').find((i) => i.title === `[spec] ${id}`);
      if (!iss) throw new Error(`spec ${id} not found`);
      out(JSON.parse(glab(['issue', 'view', String(iss.iid), '--output', 'json'])).description);
      break;
    }
    case 'list-specs': {
      out(listIssues('orch:spec').map((i) => i.title.replace(/^\[spec\] /, '')));
      break;
    }
    case 'push-plan': {
      const id = arg('--epic');
      const md = stdin();
      cache(`plan-${slug(id)}.md`, md);
      const iss = findEpicIssue(id);
      if (iss) glab(['issue', 'note', String(iss.iid), '--message', '## Approved plan\n\n' + md]);
      out({ epic: id });
      break;
    }
    case 'get-plan': {
      const id = arg('--epic');
      const f = path.join(CACHE, `plan-${slug(id)}.md`);
      if (!fs.existsSync(f)) throw new Error(`plan ${id} not cached — pull it from the epic issue notes`);
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
  process.stderr.write(`pm-gitlab ${op}: ${err.message.split('\n')[0]}\n`);
  process.exit(1);
}
