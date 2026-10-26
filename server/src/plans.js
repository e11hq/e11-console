// Content plans on the server (trial, test copy): the client export (PowerPoint + PDF), reading the client's PowerPoint
// back, and after each save — a plan whose tasks are all complete is marked client approved, and an approved plan's
// PowerPoint is filed in Client Assets › Files › "Content plan – <month>" next to its tasks' final-files folders.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createPlanDeck, readReturnedDeck, LINES } from './deck/plandeck.js';
import { isFilesFolder, planFolderOf } from './finals.js';

const rid = (p) => p + crypto.randomBytes(6).toString('hex');
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const safe = (s) => String(s || '').replace(/[\/:\\]/g, '-').replace(/^\.+/, '').replace(/\s+/g, ' ').trim().slice(0, 120) || 'Content plan';
export const monthLabel = (m) => { const [y, mm] = String(m || '').split('-').map(Number); return `${MONTHS[(mm || 1) - 1]} ${y || ''}`; };

export function createPlans({ store, files, access }) {
  const deck = createPlanDeck({ filesRoot: files.root });
  const nameOf = (u) => (u ? u.name || String(u.email || '').split('@')[0] : '');
  // each person's latest CD-approved files on a task (a newer approved version replaces the older one)
  function finishedFiles(t) {
    const latest = new Map();
    for (const r of t.reviews || []) { if (r.state !== 'approved') continue; const p = latest.get(r.by); if (!p || String(r.decidedAt || r.at) >= String(p.decidedAt || p.at)) latest.set(r.by, r); }
    const out = [];
    latest.forEach((r) => (r.files || []).forEach((id) => { const a = (t.attachments || []).find((x) => x.id === id); if (a && a.path) out.push(a); }));
    return out;
  }
  // a post is finished when its task's work is CD approved (or the task is complete)
  const finished = (t) => !!t && (t.done || t.cdStatus === 'approved' || !t.needsCD) && finishedFiles(t).length > 0;

  async function exportDeck(u, body) {
    const pl = store.get('plans', String(body.planId || ''));
    if (!pl || !access.canSee(u, 'plans', pl) || !access.planMaker(u, pl)) return { status: 403, error: 'Not allowed' };
    if (pl.status !== 'approved') return { status: 400, error: 'The content skeleton isn’t approved yet' };
    const p = store.get('projects', String(pl.projectId)) || {};
    const client = p.clientId ? store.get('clients', String(p.clientId)) : null;
    const posts = (pl.posts || []).slice().sort((a, b) => String(a.day).localeCompare(String(b.day)));
    const ready = [];
    for (const x of posts) { const t = x.taskId && store.get('tasks', String(x.taskId)); if (finished(t)) ready.push({ post: x, files: finishedFiles(t) }); }
    if (!ready.length) return { status: 400, error: 'No post is finished yet (CD approved)' };
    ready.forEach((x, i) => { x.n = i + 1; });
    const occ = Array.isArray(body.occasions) ? body.occasions.filter((o) => o && o.name && /^\d{4}-\d{2}-\d{2}$/.test(String(o.date))).slice(0, 40) : [];
    ready.forEach((x) => { const o = occ.find((y) => y.id === x.post.occasion); if (o) x.occasionName = o.name; });
    // the client's logo: a file from its Client Assets
    let logo = null;
    const logoRel = String(body.logo || '');
    if (logoRel && client && (client.folders || []).some((f) => (f.files || []).some((a) => a.path === logoRel))) logo = await deck.picture(logoRel);
    // a Thank-you line this client didn't get last time
    const used = store.list('plans').filter((x) => x.projectId === pl.projectId).flatMap((x) => (x.exports || []).map((e) => ({ at: e.at, line: e.line }))).sort((a, b) => String(a.at).localeCompare(String(b.at)));
    const last = used.length ? used[used.length - 1].line : -1;
    const pool = LINES.map((_, i) => i).filter((i) => i !== last);
    const lineIdx = pool[crypto.randomInt(pool.length)];
    const round = (pl.exports || []).length + 1;
    const ml = monthLabel(pl.month);
    const ams = (p.ams || []).filter((a) => !a.onLeave).map((a) => nameOf(store.get('users', a.id))).filter(Boolean).join(', ');
    const pptx = await deck.build({
      clientName: p.name || 'Client', month: pl.month, monthLabel: ml, round, posts: ready, occasions: occ, logo,
      preparedBy: nameOf(store.get('users', String(pl.createdBy))), amNames: ams,
      sentLabel: new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Asia/Dubai' }),
      line: LINES[lineIdx].replace('{Month}', MONTHS[Number(pl.month.slice(5)) - 1]),
    });
    const base = `${safe(p.name)} – Content plan – ${ml} – Round ${round}`;
    const dir = `attachments/${pl.id}/exports`;
    fs.mkdirSync(files.resolve(dir), { recursive: true });
    const write = (ext, buf) => { const rel = `${dir}/${base}.${ext}`; fs.writeFileSync(files.resolve(rel), buf); return { name: `${base}.${ext}`, path: rel, size: buf.length }; };
    const out = { pptx: write('pptx', pptx), pdf: null };
    const pdf = await deck.toPdf(pptx);
    if (pdf) out.pdf = write('pdf', pdf);
    const now = new Date().toISOString();
    const entry = { id: rid('ex-'), round, at: now, by: u.id, pptx: out.pptx, pdf: out.pdf, posts: ready.map((x) => x.post.id), line: lineIdx };
    const cur = store.get('plans', pl.id);
    const next = { ...cur, exports: (cur.exports || []).concat(entry), log: (cur.log || []).concat({ act: 'export', by: u.id, at: now, round }), updatedAt: now };
    const ops = [{ kind: 'plans', id: pl.id, data: next }];
    if (logoRel && logo && p.id && p.planLogo !== logoRel) ops.push({ kind: 'projects', id: p.id, data: { ...p, planLogo: logoRel } });
    return { ops, exp: entry };
  }

  function readReturn(u, body) {
    const pl = store.get('plans', String(body.planId || ''));
    if (!pl || !access.canSee(u, 'plans', pl) || !access.planMaker(u, pl)) return { status: 403, error: 'Not allowed' };
    const rel = String(body.path || '');
    if (!rel.startsWith(`attachments/${pl.id}/`) || !/\.pptx$/i.test(rel)) return { status: 400, error: 'That isn’t a PowerPoint (.pptx) file' };
    try {
      const r = readReturnedDeck(fs.readFileSync(files.resolve(rel)));
      const known = new Set((pl.posts || []).map((x) => x.id));
      Object.keys(r.posts).forEach((k) => { if (!known.has(k)) delete r.posts[k]; });
      if (!Object.keys(r.posts).length) return { status: 400, error: 'This PowerPoint isn’t one of this plan’s exports' };
      return { result: r };
    } catch (e) { return { status: 400, error: 'Couldn’t read that PowerPoint' }; }
  }

  // after a save: complete plans get approved, approved plans get their PowerPoint filed
  function afterPush(results, byUser) {
    const ids = new Set();
    for (const r of results) {
      if (r.refused || r.deleted || r.unchanged) continue;
      if (r.kind === 'plans') ids.add(String(r.id));
      if (r.kind === 'tasks') { const t = store.get('tasks', String(r.id)); if (t && t.planId) ids.add(String(t.planId)); }
    }
    const ops = [];
    const now = new Date().toISOString();
    for (const id of ids) {
      const pl = store.get('plans', id);
      if (!pl || pl.status !== 'approved') continue;
      const posts = pl.posts || [];
      let next = null;
      const allDone = posts.length > 0 && posts.every((x) => { const t = x.taskId && store.get('tasks', String(x.taskId)); return !!t && t.done; });
      if (allDone && !pl.clientApproved) {
        next = { ...pl, clientApproved: { at: now, by: byUser || null, auto: true }, log: (pl.log || []).concat({ act: 'client-approved', by: byUser || null, at: now, auto: true }), updatedAt: now };
        const p = store.get('projects', String(pl.projectId)) || {};
        const to = new Set([pl.createdBy, ...(p.socials || []), ...(((store.get('meta', 'main') || {}).socialMgrIds) || []), ...(p.ams || []).filter((a) => !a.onLeave).map((a) => a.id)]);
        for (const uid of to) {
          const tu = uid && store.get('users', String(uid));
          if (!tu || uid === byUser || tu.active === false) continue;
          const nid = rid('n-');
          ops.push({ kind: 'notifications', id: nid, data: { id: nid, to: uid, from: byUser || null, kind: 'plan-client', planId: pl.id, text: `completed the last post: the client approved the content plan for <b>${esc(p.name || '')} · ${esc(monthLabel(pl.month))}</b>`, snippet: '', at: now, read: false } });
        }
      }
      const cur = next || pl;
      const last = (cur.exports || [])[(cur.exports || []).length - 1];
      if (cur.clientApproved && !cur.filedDeck && last) {
        const filed = fileDeck(cur, last, byUser, now);
        if (filed) { ops.push(...filed.ops); next = { ...cur, filedDeck: { at: now, round: last.round, folderId: filed.folderId } }; }
      }
      if (next) ops.unshift({ kind: 'plans', id, data: next });
    }
    return ops;
  }
  function fileDeck(pl, exp, byUser, now) {
    const p = store.get('projects', String(pl.projectId));
    const c = p && p.clientId ? store.get('clients', String(p.clientId)) : null;
    if (!c) return null;
    const client = JSON.parse(JSON.stringify(c));
    client.folders = Array.isArray(client.folders) ? client.folders : [];
    let top = client.folders.find(isFilesFolder) || client.folders.find((f) => !f.parentId && f.name === 'Files');
    if (!top) { top = { id: rid('cf-'), name: 'Files', dir: `${client.dir}/Files`, files: [], createdAt: now, createdBy: c.createdBy || null, auto: true }; client.folders.push(top); }
    const folder = planFolderOf(client, top, pl, now, byUser);
    folder.files = folder.files || [];
    for (const f of [exp.pptx, exp.pdf].filter(Boolean)) {
      if (folder.files.some((x) => x.deckOf === exp.id && x.name === f.name)) continue;
      try { const made = files.linkInto(f.path, folder.dir, f.name); folder.files.push({ id: rid('caf-'), name: made.name, path: made.path, size: made.size, addedAt: now, addedBy: byUser || exp.by, deckOf: exp.id }); } catch { /* skipped */ }
    }
    return { ops: [{ kind: 'clients', id: c.id, data: client }], folderId: folder.id };
  }
  return { exportDeck, readReturn, afterPush, finished, finishedFiles };
}
