// Scheduled comments: a comment or reply written now and posted by the server at a chosen time (Dubai time),
// even when its author's devices are off. Until then only its author sees it (kind 'scheduled', access.js).
// At the time it's added to the task as a normal comment, and the mentions, watchers and thread people get their
// Inbox update and phone notification then. If the task was completed or deleted first, it isn't sent: the author
// is told (Inbox + phone) and can get it back as a draft.
import crypto from 'node:crypto';

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const trunc = (v, n = 160) => { v = String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); return v.length > n ? v.slice(0, n - 1) + '…' : v; };
const nid = (p) => p + crypto.randomBytes(6).toString('hex');
// "Wed, Oct 28 · 9:00 AM" in Dubai time
export function whenText(iso) {
  const d = new Date(iso);
  const day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'Asia/Dubai' });
  const time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Dubai' });
  return `${day} · ${time}`;
}
// Notification types people can switch off in their profile (web/app.js NOTIF_TYPES): comments and mentions
const PREF_OF = { mention: 'mention', comment: 'comment' };
const mentionsIn = (html) => { const out = new Set(); String(html || '').replace(/data-user="([^"]+)"/g, (_, id) => { out.add(id); return ''; }); return out; };
const KEEP_SENT = 2 * 86400000, KEEP_CANCELLED = 30 * 86400000;

export function createScheduled({ store, access, webPush, notifMessage, deliver, now = () => Date.now(), log = console }) {
  let timer = null, busy = false;
  const user = (id) => (id ? store.get('users', String(id)) : null);
  const task = (id) => (id ? store.get('tasks', String(id)) : null);
  const proj = (id) => (id ? store.get('projects', String(id)) : null);
  const cdId = () => { const id = (store.get('meta', 'main') || {}).cdUserId; const u = user(id); return u && u.active !== false ? id : null; };
  // the same people the app notifies about a comment (web/app.js creatorOf / clientAmsOf / watchersOf)
  const rootOf = (t) => (t && t.parentId ? task(t.parentId) || t : t);
  function creatorOf(t) {
    const id = t && t.createdBy, u = user(id);
    if (!u || u.role !== 'am' || access.isAdm(u)) return id || null;
    const p = proj(rootOf(t).projectId);
    if (!p || !(p.ams || []).length) return id;
    return (p.ams || []).some((a) => a.id === id && !a.onLeave) ? id : null;
  }
  const clientAmsOf = (t) => { const p = proj(rootOf(t).projectId); return p ? (p.ams || []).filter((a) => !a.onLeave).map((a) => a.id) : []; };
  function watchersOf(t) {
    const set = new Set((t.assignees || []).concat(creatorOf(t) ? [creatorOf(t)] : []));
    if (t.parentId) { const p = task(t.parentId); if (p) watchersOf(p).forEach((x) => set.add(x)); }
    return [...set];
  }
  function notifOk(to, from, t, kind) {
    if (!to || to === from) return false;
    const u = user(to);
    if (!u || u.active === false) return false;
    const off = ((u.prefs || {}).notifOff || {});
    if (PREF_OF[kind] && off[PREF_OF[kind]]) return false;
    if (to === cdId() && kind !== 'mention' && rootOf(t).createdBy !== to) return false;   // the CD: their own tasks only
    return true;
  }

  function sendOne(s, t, at) {
    const comment = { id: nid('c-s'), text: s.text || '', html: s.html || '', at, attachments: s.attachments || [], parentId: null, reactions: {}, authorId: s.authorId };
    // a reply whose thread is gone becomes a comment
    if (s.replyTo && (t.comments || []).some((c) => c.id === s.replyTo)) comment.parentId = s.replyTo;
    const reply = !!comment.parentId;
    const ops = [
      { kind: 'tasks', id: t.id, data: { ...t, comments: (t.comments || []).concat(comment), updatedAt: at } },
      { kind: 'scheduled', id: s.id, data: { ...s, state: 'sent', sentAt: at, commentId: comment.id } },
    ];
    const made = new Set();
    const notify = (to, kind, text) => {
      if (made.has(to) || !notifOk(to, s.authorId, t, kind)) return;
      made.add(to);
      const id = nid('n-s');
      ops.push({ kind: 'notifications', id, data: { id, to, from: s.authorId, taskId: t.id, kind, text, snippet: trunc(comment.text || `${comment.attachments.length} file${comment.attachments.length === 1 ? '' : 's'}`), commentId: comment.id, at, read: false } });
    };
    const mentioned = mentionsIn(comment.html);
    mentioned.forEach((to) => notify(to, 'mention', `mentioned you in a ${reply ? 'reply' : 'comment'} on`));
    if (reply) {
      const people = new Set((t.comments || []).filter((c) => c.id === comment.parentId || c.parentId === comment.parentId).map((c) => c.authorId));
      const w = new Set(watchersOf(t));
      people.forEach((to) => { if (!w.has(to)) notify(to, 'comment', 'replied in a thread on'); });
    }
    new Set(watchersOf(t).concat(clientAmsOf(t))).forEach((to) => notify(to, 'comment', reply ? 'replied to a comment on' : 'commented on'));
    return ops;
  }

  function cancelOne(s, t, reason, at) {
    const inTrash = !t && store.list('trash').map((it) => ((it.data || {}).tasks || []).find((x) => x && x.id === s.taskId)).find(Boolean);
    const title = (t && t.title) || (inTrash && inTrash.title) || s.taskTitle || 'the task';
    const what = s.replyTo ? 'reply' : 'comment';
    const id = nid('n-sc');
    return [
      { kind: 'scheduled', id: s.id, data: { ...s, state: 'cancelled', reason, cancelledAt: at, taskTitle: title } },
      { kind: 'notifications', id, data: { id, to: s.authorId, from: s.authorId, kind: 'sched-cancel', schedId: s.id, reason, ...(reason === 'completed' && t ? { taskId: t.id } : {}),
        text: `Your scheduled ${what} wasn’t sent: <b>${esc(title)}</b> was ${reason} before ${esc(whenText(s.sendAt))}`, snippet: trunc(s.text || `${(s.attachments || []).length} file${(s.attachments || []).length === 1 ? '' : 's'}`), at, read: false } },
    ];
  }

  async function tick() {
    if (busy) return 0;
    busy = true;
    try {
      const t0 = now(), at = new Date(t0).toISOString();
      let done = 0;
      for (const s of store.list('scheduled')) {
        // old ones are cleared (sent: their comment is in the task; cancelled: kept 30 days for the author)
        if (s.state === 'sent' && t0 - Date.parse(s.sentAt || 0) > KEEP_SENT) { store.apply([{ kind: 'scheduled', id: s.id, del: true }], 'scheduled'); continue; }
        if (s.state === 'cancelled' && t0 - Date.parse(s.cancelledAt || 0) > KEEP_CANCELLED) { deliver(store.apply([{ kind: 'scheduled', id: s.id, del: true }], 'scheduled')); continue; }
        if (s.state !== 'waiting') continue;
        const author = user(s.authorId);
        const t = task(s.taskId);
        let ops = null;
        if (!author || author.active === false) ops = [{ kind: 'scheduled', id: s.id, data: { ...s, state: 'cancelled', reason: 'author', cancelledAt: at } }];
        else if (!t) ops = cancelOne(s, null, 'deleted', at);
        else if (t.done) ops = cancelOne(s, t, 'completed', at);
        else if (Date.parse(s.sendAt) <= t0) ops = sendOne(s, t, at);
        if (!ops) continue;
        const out = store.apply(ops, s.authorId);
        deliver(out);
        done++;
        for (const r of out.results) {
          if (r.kind !== 'notifications' || r.refused || !r.data) continue;
          const to = user(r.data.to);
          if (!to || !access.canSee(to, 'notifications', r.data)) continue;
          try { await webPush.sendTo(r.data.to, notifMessage(store, r.data)); } catch { /* phone offline */ }
        }
      }
      return done;
    } finally { busy = false; }
  }

  return {
    tick,
    start() { if (!timer) { timer = setInterval(() => { tick().catch((e) => log.error('scheduled comments:', e.message)); }, 20_000); if (timer.unref) timer.unref(); tick().catch(() => {}); } },
    stop() { if (timer) { clearInterval(timer); timer = null; } },
  };
}
