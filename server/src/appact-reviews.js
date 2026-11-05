// Part B step 3: the CD's review decisions (the app's Reviews page: Approve / Request amendments) done on the server, so
// the iPhone app can send them straight here instead of through the hidden website page (phone.js NativeMe
// `case 'rvApprove'` / `case 'rvAmend'` → app.js decideReview). The same steps in the same order, with the website's own
// shared rules (web/rules.js: logActivity, logChange, pushNotif — each person's notification settings —, moveToStatus,
// creatorOf, clientAmsOf), on the full records from the store, so the task, its comments, activity, status and the
// notifications come out exactly as the website's.
//
//   const acts = createReviewActs({ store, now })
//   acts.rvApprove(u, { id })                          id: the review request's id
//   acts.rvAmend(u, { id, note, need })                note: the general note (plain text); need: { fileId: note } the
//                                                      files ticked for changes (none / null: every file needs changes)
//   → { ok: true, changes: [{ kind, id, base?, data }], messages: [], answer: { next } }   (next: the next waiting request)
//   → { ok: false, status, error }
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const clone = (v) => JSON.parse(JSON.stringify(v));
// app.js esc
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
// app.js notifPlainHTML (the browser's textContent: tags gone, entities read)
const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
function notifPlainHTML(html) {
  const s = String(html || '').replace(/<(br|\/p|\/li|\/div)>/gi, ' $&').replace(/<[^>]*>/g, '')
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => (e[0] === '#' ? String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : Number(e.slice(1))) : ENT[e.toLowerCase()] ?? m));
  return s.replace(/\s+/g, ' ').trim();
}
const CD = { review: { label: 'Internal Review' }, approved: { label: 'Approved' } };
const SEC_PROGRESS = /^in ?-?progress$/i, SEC_REVIEW = /^(internal )?review$/i, SEC_CTR = /^ctr$/i;

export function createReviewActs({ store, now = () => Date.now(), webDir } = {}) {
  const file = path.join(webDir || path.resolve(here, '../../web'), 'rules.js');
  let rules = null, loadedAt = '';
  function R() {
    const m = String(fs.statSync(file).mtimeMs);
    if (!rules || m !== loadedAt) {
      rules = vm.runInNewContext(`${fs.readFileSync(file, 'utf8')}; E11Rules`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent });
      loadedAt = m;
    }
    return rules;
  }
  const fail = (status, error) => ({ ok: false, status, error });

  // The data as the CD's own website has it: every task but an inactive client's (access.js taskVisible), all people
  function load() {
    const projects = store.list('projects');
    const off = new Set(projects.filter((p) => p.inactive).map((p) => p.id));
    const all = store.list('tasks');
    const byId = new Map(all.map((t) => [t.id, t]));
    const pidOf = (t) => t.projectId || (t.parentId && byId.get(t.parentId) ? byId.get(t.parentId).projectId || null : null);
    const tasks = off.size ? all.filter((t) => !off.has(pidOf(t))) : all;
    return { users: store.list('users'), projects, tasks, statuses: store.list('statuses'), plans: store.list('plans'), meta: store.get('meta', 'main') || {}, notifications: store.list('notifications'), trash: [] };
  }

  function run(u, body, decision) {
    if (!u || !u.id) return fail(401, 'Sign in first');
    const db = load();
    const meId = u.id;
    const nowISO = () => new Date(now()).toISOString();
    const uid = () => now().toString(36) + Math.random().toString(36).slice(2, 8);
    const env = { nowISO, nowMs: () => now(), uid };
    const Rl = R();
    const rl = Rl.withEnv(env, db, meId, Rl.dubaiDay(now()));
    const userById = (id) => db.users.find((x) => x.id === id) || null;
    const fullName = (x) => (x ? (x.name || String(x.email || '').split('@')[0]) : 'Former member');
    const proj = (id) => db.projects.find((p) => p.id === id);
    const statusList = (t) => { const p = proj(t.projectId); return p ? p.sections : db.statuses; };
    const cdUserId = () => { const id = db.meta.cdUserId; const x = id && userById(id); return x && x.active !== false ? id : null; };
    const isCD = () => !!meId && meId === cdUserId();
    const needsCD = (t) => !!t && !t.parentId && !!t.needsCD;
    const reviewersOf = (t) => (t.assignees || []).filter((x) => x !== cdUserId());
    const epochOf = (t) => t.reviewEpoch || 0;
    const lastReview = (t, w) => { const l = (t.reviews || []).filter((r) => r.by === w && (r.epoch || 0) === epochOf(t) && r.state !== 'withdrawn'); return l[l.length - 1] || null; };
    const reviewState = (t, w) => { const r = lastReview(t, w); return r ? r.state : 'none'; };
    const reviewPending = (t) => needsCD(t) && reviewersOf(t).some((w) => reviewState(t, w) === 'pending');
    const attOf = (t, id) => (t.attachments || []).find((a) => a.id === id) || null;
    const okIdsOf = (r) => (r.state === 'approved' ? r.ok || r.files || [] : r.state === 'amend' && Array.isArray(r.ok) ? r.ok : []);
    function keptOk(t, w, upto = null) {
      const m = new Map();
      for (const r of t.reviews || []) {
        if (r === upto) break;
        if (r.by !== w || (r.epoch || 0) !== epochOf(t) || !['approved', 'amend'].includes(r.state)) continue;
        okIdsOf(r).forEach((id) => { const a = attOf(t, id); if (a) m.set(String(a.name || id).toLowerCase(), id); });
      }
      return m;
    }
    function carriedOf(t, r) {
      const kept = keptOk(t, r.by, r);
      (r.files || []).forEach((id) => { const a = attOf(t, id); if (a) kept.delete(String(a.name || id).toLowerCase()); });
      return [...kept.values()].map((id) => attOf(t, id)).filter(Boolean);
    }
    function findReview(id) { for (const t of db.tasks) { const r = (t.reviews || []).find((x) => x.id === id); if (r) return { t, r }; } return null; }
    const activeReviews = () => {
      const out = [];
      db.tasks.forEach((t) => (t.reviews || []).forEach((r) => out.push({ t, r })));
      return out.filter(({ t, r }) => r.state === 'pending' && needsCD(t) && (r.epoch || 0) === epochOf(t) && !t.done).sort((a, b) => a.r.at.localeCompare(b.r.at));
    };
    function syncCD(t) {
      if (!needsCD(t)) return;
      const rv = reviewersOf(t);
      if (!rv.length) return;
      const st = rv.map((w) => reviewState(t, w));
      const prev = t.cdStatus || '';
      t.cdStatus = st.includes('pending') ? 'review' : st.every((s) => s === 'approved') ? 'approved' : '';
      if (prev === t.cdStatus) return;
      if (prev && t.cdStatus) rl.logChange(t, 'the <b>CD Status</b>', CD[prev].label, CD[t.cdStatus].label);
      else if (t.cdStatus) rl.logActivity(t, `CD Status is now <b>${esc(CD[t.cdStatus].label)}</b>`);
      else rl.logActivity(t, `CD Status cleared <span class="chg-old">${esc(trunc(CD[prev].label, 80))}</span>`);
    }
    const trunc = (v, n) => { v = String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); return v.length > n ? v.slice(0, n - 1) + '…' : v; };
    // app.js moveToSection → moveTask (a status change: logged, the people on it told)
    function moveToSection(t, re) {
      const s = (statusList(t) || []).find((x) => re.test(String(x.name).trim()));
      if (s && t.sectionId !== s.id) rl.moveToStatus(t, s.id, false);
    }
    const creatorAndAms = (t) => [...new Set([rl.creatorOf(t)].concat(rl.clientAmsOf(t)).filter(Boolean))];
    function postApprovedFiles(t, r) {
      const files = (r.set || r.files || []).map((id) => (t.attachments || []).find((a) => a.id === id)).filter(Boolean);
      if (!files.length) return;
      t.comments = t.comments || [];
      const cr = t.createdBy && userById(t.createdBy) ? t.createdBy : null;
      const hello = cr ? `Hello <span class="mention" data-user="${esc(cr)}" contenteditable="false">@${esc(fullName(userById(cr)))}</span>, ` : 'Hello, ';
      const text = `${cr ? 'Hello @' + fullName(userById(cr)) + ', ' : 'Hello, '}here are the final files (Approved) by the CD, ready to be sent to client for review.`;
      const c = { id: uid(), text, html: `${hello}here are the final files (<b>Approved</b>) by the CD, ready to be sent to client for review.`, at: nowISO(),
        attachments: files.map((a) => ({ ...a, id: uid(), linked: true })), parentId: null, reactions: {}, authorId: r.by, auto: true };
      t.comments.push(c);
      if (cr && cr !== r.by && userById(cr).active !== false) {
        db.notifications.push({ id: uid(), to: cr, from: r.by, taskId: t.id, kind: 'mention', text: 'mentioned you in a comment on', snippet: text, commentId: c.id, at: nowISO(), read: false });
      }
    }
    // app.js decideReview
    function decideReview(t, r, decision, noteHtml, need = null) {
      const files = r.files || [];
      if (decision === 'amend' && need && !Object.keys(need).some((id) => files.includes(id))) decision = 'approve';   // (nothing ticked: all approved)
      r.decidedAt = nowISO(); r.decidedBy = meId;
      const who = fullName(userById(r.by));
      if (decision === 'approve') {
        r.state = 'approved';
        r.ok = files.slice();
        r.set = [...carriedOf(t, r).map((a) => a.id), ...files];
        t.partsDone = t.partsDone || {};
        t.partsDone[r.by] = nowISO();
        rl.logActivity(t, `approved <b>${esc(who)}</b>’s files`);
        rl.pushNotif(r.by, t, 'review-ok', 'approved your files for');
        postApprovedFiles(t, r);
        const allOK = reviewersOf(t).every((w) => reviewState(t, w) === 'approved');
        syncCD(t);
        if (allOK) {
          moveToSection(t, SEC_CTR);
          creatorAndAms(t).forEach((w) => { if (w !== r.by) rl.pushNotif(w, t, 'review-ok', 'approved all files — it moved to CTR:'); });
        } else if (!reviewPending(t)) moveToSection(t, SEC_PROGRESS);
      } else {
        r.state = 'amend';
        const picked = need ? files.filter((id) => Object.prototype.hasOwnProperty.call(need, id)) : files.slice();
        r.ok = files.filter((id) => !picked.includes(id));
        r.need = Object.fromEntries(picked.map((id) => [id, need ? String(need[id] || '') : '']));
        const parts = need ? picked.map((id) => { const a = attOf(t, id); return `<b>${esc((a && a.name) || 'File')}</b>${r.need[id] ? '<br>' + r.need[id] : ''}`; }) : [];
        const general = String(noteHtml || '').trim();
        const okLine = r.ok.length ? `<br><span class="rv-okline">✓ Approved: ${r.ok.map((id) => esc((attOf(t, id) || {}).name || 'File')).join(', ')}</span>` : '';
        noteHtml = [general, ...parts].filter(Boolean).join('<br><br>') + okLine;
        r.noteHtml = noteHtml;
        if (t.partsDone) delete t.partsDone[r.by];
        t.comments = t.comments || [];
        const c = { id: uid(), text: 'Amendments required: ' + notifPlainHTML(noteHtml), html: `<b>Amendments required</b> for <span class="mention" data-user="${esc(r.by)}" contenteditable="false">@${esc(who)}</span><br>${noteHtml}`, at: nowISO(),
          attachments: need ? picked.map((id) => attOf(t, id)).filter(Boolean).map((a) => ({ ...a, id: uid(), linked: true })) : [], parentId: null, reactions: {}, authorId: meId };
        t.comments.push(c);
        rl.logActivity(t, r.ok.length ? `approved ${r.ok.length} of <b>${esc(who)}</b>’s files and asked for changes on ${picked.length}` : `asked <b>${esc(who)}</b> for amendments`);
        rl.pushNotif(r.by, t, 'review-amend', 'requested amendments on your submission for', { snippet: notifPlainHTML(noteHtml).slice(0, 160), commentId: c.id });
        creatorAndAms(t).forEach((w) => { if (w !== r.by) rl.pushNotif(w, t, 'review-amend', `requested amendments from <b>${esc(who)}</b> on`, { commentId: c.id }); });
        if (!reviewPending(t)) moveToSection(t, SEC_PROGRESS);
        syncCD(t);
      }
      t.updatedAt = nowISO();
    }

    // phone.js NativeMe: the same checks and refusals
    const f = findReview(String(body && body.id || ''));
    if (!f || !isCD()) return fail(403, 'Only the Creative Director can decide');
    if (f.r.state !== 'pending') return fail(409, 'This request was already decided');
    const before = new Map(db.tasks.map((t) => [t.id, JSON.stringify(t)]));
    const notifBefore = new Map(db.notifications.map((n) => [n.id, JSON.stringify(n)]));
    if (decision === 'approve') decideReview(f.t, f.r, 'approve');
    else {
      const enc = (v) => esc(String(v || '').trim()).replace(/\n/g, '<br>');
      const raw = body.need && typeof body.need === 'object' ? body.need : null;
      const need = raw ? Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, enc(v)])) : null;
      if (need && !Object.keys(need).length) return fail(400, 'Tick the files that need changes');
      if (!need && !String(body.note || '').trim()) return fail(400, 'Say what needs changing');
      decideReview(f.t, f.r, 'amend', enc(body.note), need);
    }
    // what changed, as the website pushes it (each with the version it started from, merged on the server)
    const changes = [];
    for (const t of db.tasks) {
      const was = before.get(t.id);
      if (!was) changes.push({ kind: 'tasks', id: t.id, data: t });
      else if (JSON.stringify(t) !== was) changes.push({ kind: 'tasks', id: t.id, base: JSON.parse(was), data: t });
    }
    for (const n of db.notifications) {
      const was = notifBefore.get(n.id);
      if (!was) changes.push({ kind: 'notifications', id: n.id, data: n });
      else if (JSON.stringify(n) !== was) changes.push({ kind: 'notifications', id: n.id, base: JSON.parse(was), data: n });
    }
    const nx = activeReviews()[0];
    return { ok: true, changes: clone(changes), messages: [], answer: { next: nx ? nx.r.id : null } };
  }

  return {
    rvApprove: (u, body) => run(u, body || {}, 'approve'),
    rvAmend: (u, body) => run(u, body || {}, 'amend'),
  };
}
