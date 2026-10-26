// Final files: when a task that went through CD review is completed, its client's Client Assets › Files gets a folder
// named after the task holding each person's latest CD-approved files. The files are hard links to the task's own
// files (no extra space), so they stay when the task expires. Completed again later: the folder gets the newest
// approved files and the ones replaced go to the Trash. One Inbox update per filing.
import crypto from 'node:crypto';

const rid = (p) => p + crypto.randomBytes(6).toString('hex');
const safe = (s) => String(s || '').replace(/[\/:\\]/g, '-').replace(/^\.+/, '').replace(/\s+/g, ' ').trim().slice(0, 80) || 'Untitled';
export const isFilesFolder = (f) => !!f && !f.parentId && f.name === 'Files' && !!f.auto;
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
export const planFolderName = (pl) => { const [y, m] = String(pl.month || '').split('-').map(Number); return `Content plan – ${MONTHS[(m || 1) - 1]} ${y || ''}`.trim(); };
// Content plans: Files › "Content plan – November 2026" holds the approved PowerPoint and a folder per task (made once)
export function planFolderOf(client, top, pl, now, byUser) {
  let f = client.folders.find((x) => x.planOf === pl.id);
  if (f) return f;
  const taken = new Set(client.folders.map((x) => String(x.dir).toLowerCase()));
  let dir = `${top.dir}/${safe(planFolderName(pl))}`, i = 2;
  while (taken.has(dir.toLowerCase())) dir = `${top.dir}/${safe(planFolderName(pl))} (${i++})`;
  f = { id: rid('cf-'), name: planFolderName(pl), dir, files: [], createdAt: now, createdBy: byUser || null, auto: true, parentId: top.id, planOf: pl.id };
  client.folders.push(f);
  return f;
}

export function createFinals({ store, files, access }) {
  const projectOf = (t) => {
    if (!t) return null;
    if (t.projectId) return store.get('projects', String(t.projectId));
    if (t.parentId) return projectOf(store.get('tasks', String(t.parentId)));
    return null;
  };
  // each person's latest approved submission (any round, any review cycle); the CD's decision with it
  function approvedSets(t) {
    const latest = new Map();
    for (const r of t.reviews || []) {
      if (r.state !== 'approved') continue;
      const p = latest.get(r.by);
      if (!p || String(r.decidedAt || r.at) >= String(p.decidedAt || p.at)) latest.set(r.by, r);
    }
    const cur = new Set(t.assignees || []);
    const list = [...latest.values()];
    const now = list.filter((r) => cur.has(r.by));
    return now.length ? now : list;
  }
  const creatorOf = (t) => t.createdBy || null;

  // returns the store ops (client change, notifications, trash) — or [] when there's nothing to file
  function fileOps(t, byUser) {
    if (!t || t.parentId || !t.done) return [];
    const p = projectOf(t);
    const c = p && p.clientId ? store.get('clients', String(p.clientId)) : null;
    if (!c) return [];
    const sets = approvedSets(t);
    const atts = new Map((t.attachments || []).map((a) => [a.id, a]));
    const picked = [];
    for (const r of sets) for (const id of r.files || []) { const a = atts.get(id); if (a && a.path) picked.push({ a, r }); }
    if (!picked.length) return [];
    const now = new Date().toISOString();
    const client = JSON.parse(JSON.stringify(c));
    client.folders = Array.isArray(client.folders) ? client.folders : [];
    let top = client.folders.find(isFilesFolder) || client.folders.find((f) => !f.parentId && f.name === 'Files');
    if (!top) {
      top = { id: rid('cf-'), name: 'Files', dir: `${client.dir}/Files`, files: [], createdAt: now, createdBy: c.createdBy || null, auto: true };
      client.folders.push(top);
    }
    let folder = client.folders.find((f) => f.finalOf === t.id);
    const ops = [];
    // a task made from a content plan: its folder goes inside the plan's folder
    const pl = t.planId ? store.get('plans', String(t.planId)) : null;
    const parent = pl ? planFolderOf(client, top, pl, now, byUser) : top;
    // (a client approval from before the newest CD approval is out of date)
    const lastCD = sets.map((r) => String(r.decidedAt || r.at || '')).sort().pop() || '';
    const fresh = t.clientApproval && String(t.clientApproval.at || '') >= lastCD ? t.clientApproval : null;
    const ca = fresh && !fresh.none ? fresh : null;
    if (!folder) {
      const taken = new Set(client.folders.map((f) => String(f.dir).toLowerCase()));
      let dir = `${parent.dir}/${safe(t.title)}`, i = 2;
      while (taken.has(dir.toLowerCase())) dir = `${parent.dir}/${safe(t.title)} (${i++})`;
      folder = { id: rid('cf-'), name: String(t.title || 'Untitled task').trim().slice(0, 120), dir, files: [], createdAt: now, createdBy: byUser || null, auto: true, parentId: parent.id, finalOf: t.id };
      client.folders.push(folder);
    } else {
      folder.name = String(t.title || folder.name).trim().slice(0, 120);
    }
    const keep = new Map((folder.files || []).filter((x) => x.final && x.final.srcId).map((x) => [x.final.srcId, x]));
    const out = [];
    for (const { a, r } of picked) {
      const meta = {
        taskId: t.id, taskTitle: t.title || '', completedAt: t.completedAt || now, createdBy: creatorOf(t),
        assignee: r.by, cdBy: r.decidedBy || null, cdAt: r.decidedAt || null,
        clientBy: ca ? ca.by || null : null, clientAt: ca ? ca.at || null : null, clientNone: !!(fresh && fresh.none), srcId: a.id,
      };
      const same = keep.get(a.id);
      if (same) { out.push({ ...same, final: meta }); keep.delete(a.id); continue; }
      let made;
      try { made = files.linkInto(a.path, folder.dir, a.name); } catch { continue; }
      out.push({ id: rid('caf-'), name: made.name, path: made.path, size: made.size, addedAt: now, addedBy: r.by, final: meta });
    }
    if (!out.length) return [];
    // the ones replaced go to the Trash (restorable for 30 days)
    for (const old of keep.values()) {
      ops.push({ kind: 'trash', id: rid('tr-'), data: { id: null, type: 'cafile', deletedAt: now, deletedBy: byUser || null, key: 'clients:' + c.id, where: `${c.name} › Files › ${folder.name}`, data: { clientId: c.id, folderId: folder.id, file: old } } });
    }
    (folder.files || []).filter((x) => !x.final).forEach((x) => out.push(x));   // (nothing should be here, but never lose a file)
    folder.files = out;
    ops.forEach((o) => { o.data.id = o.id; });
    ops.unshift({ kind: 'clients', id: c.id, data: client });
    // one Inbox update: the people on this client's tasks, its Account Managers and the Admins
    const pids = new Set(store.list('projects').filter((x) => x.clientId === c.id).map((x) => x.id));
    const to = new Set();
    const tasks = store.list('tasks');
    const byId = new Map(tasks.map((x) => [x.id, x]));
    tasks.filter((x) => pids.has(x.projectId) || (x.parentId && pids.has((byId.get(x.parentId) || {}).projectId))).forEach((x) => {
      (x.assignees || []).forEach((id) => to.add(id));
      if (x.createdBy) to.add(x.createdBy);
      (x.watchers || []).forEach((id) => to.add(id));
    });
    store.list('projects').filter((x) => pids.has(x.id)).forEach((x) => (x.ams || []).forEach((a) => to.add(a.id)));
    store.list('users').forEach((u) => { if (access.isAdm(u)) to.add(u.id); });
    const title = t.title || 'Untitled task';
    for (const id of to) {
      const u = store.get('users', String(id));
      if (!u || id === byUser || u.active === false || access.isFinance(u)) continue;
      if (u.role === 'freelancer' && ![...pids].some((pid) => (u.projectIds || []).includes(pid))) continue;
      const nid = rid('n-');
      ops.push({ kind: 'notifications', id: nid, data: { id: nid, to: id, from: byUser || null, kind: 'asset', clientId: c.id, folderId: folder.id, text: `filed the final files for “${title}” in ${c.name} › Files`, snippet: `${out.length} file${out.length === 1 ? '' : 's'}`, at: now, read: false } });
    }
    return ops;
  }

  // a renamed task: its final-files folder follows the title
  function renameOps(t) {
    if (!t || t.parentId || !t.title) return [];
    for (const c of store.list('clients')) {
      const f = (c.folders || []).find((x) => x.finalOf === t.id);
      if (!f || f.name === t.title.trim()) continue;
      const client = JSON.parse(JSON.stringify(c));
      client.folders.find((x) => x.id === f.id).name = t.title.trim().slice(0, 120);
      return [{ kind: 'clients', id: c.id, data: client }];
    }
    return [];
  }

  // after a push: tasks just completed get filed; renamed ones get their folder renamed
  // (each task's filing is saved before the next one's, so several tasks completed in one save — e.g. a content plan the
  // client approved — each keep their folder in the same client)
  function afterPush(results, before, byUser) {
    let out = null;
    for (const r of results) {
      if (r.kind !== 'tasks' || r.refused || r.deleted || r.unchanged) continue;
      const t = store.get('tasks', String(r.id));
      const was = before.get(String(r.id));
      if (!t) continue;
      const ops = t.done && !(was && was.done) ? fileOps(t, byUser) : was && was.title !== t.title ? renameOps(t) : [];
      if (!ops.length) continue;
      const res = store.apply(ops, 'finals');
      out = out ? { rev: res.rev, results: out.results.concat(res.results) } : res;
    }
    return out;
  }
  return { afterPush, fileOps, approvedSets };
}
