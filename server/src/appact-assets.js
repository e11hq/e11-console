// Part B step 5 (2026-11-05): the iPhone app's Client Assets actions, done on the server — what the hidden website page
// does today for the same input (web/phone.js NativeAssets `__e11Assets`: addClient, uploaded, newFolder, renameFolder,
// deleteFolder, deleteFile, deleteFiles, renameClient, deleteClient), with the same rules (web/app.js canAssets,
// canAddAssets, canUploadTo, canMakeSub, canEditFolder, canDelFolder, canDelAsset, canRenameCA, isFilesTop, FOLDER_DEPTH,
// folderDup, dupClient / dupMsg), the same records (createClient, newFolder, toTrash, assetNotify — over what that
// person's page has: their own visible copy of the data), the same answers and error texts. Each handler is the
// page's event with 'ca' in front and takes (u, body), body = the page's fields (client, folder, parent, name, file,
// files…):
//   { ok: true, changes: [{ kind, id, base?, data } | { kind, id, del: true }], messages: [], answer: { id? | gone? },
//     dirs?: [NAS folders to make — the page's Host makeDir], filesGone?: [the page's safeTrash paths],
//     later?: async () => changes — caUploaded: the client's logo from its Logos folder (autoLogo), after answering }
//   { ok: false, status, error }
// It changes nothing itself: the route checks every change with access.canWrite and saves them all or none.
//
//   const acts = createAssetActs({ store, now, webDir, access, files });
//   (access: the server's own, else one is made over the store; files: files.js — only the logo needs it)
import { execFile } from 'node:child_process';
import { createAccess } from './access.js';

const DEFAULT_FOLDERS = ['Logos', 'Brand Guidelines', 'Fonts', 'Files'];
const FOLDER_DEPTH = 5;
const LOGO_EXT = /\.(png|jpe?g|webp|gif|svg)$/i;
const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const isAdm = (u) => !!u && (u.role === 'admin' || u.role === 'office_admin' || u.admin === true);
const isFinUser = (u) => !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer');
// "Ford", "ford ", "FORD." and "Ford" with different spacing are the same client (app.js clientKey)
const clientKey = (n) => String(n || '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/&/g, 'and').replace(/[^a-z0-9؀-ۿ]+/g, '');
const dupMsg = (c) => `There is already a client named “${c.name}”.`;
const diskSafe = (s) => String(s).replace(/[\/:\\]/g, '-').replace(/^\.+/, '').replace(/\s+/g, ' ').trim().slice(0, 80) || 'Untitled';
function freeDir(base, name, taken) {
  const n = diskSafe(name);
  let d = `${base}/${n}`, i = 2;
  while (taken.some((x) => x.toLowerCase() === d.toLowerCase())) d = `${base}/${n} (${i++})`;
  return d;
}
// (folders: app.js's own helpers, the same names)
const isAutoFolder = (c, f) => !!f.auto || (DEFAULT_FOLDERS.includes(f.name) && (!f.createdBy || f.createdBy === c.createdBy) && Math.abs(Date.parse(f.createdAt || 0) - Date.parse(c.createdAt || 0)) < 60000);
const isFilesTop = (c, f) => !!f && !f.parentId && f.name === 'Files' && isAutoFolder(c, f);
const subFolders = (c, f) => c.folders.filter((x) => x.parentId === f.id);
const parentFolder = (c, f) => (f && f.parentId ? c.folders.find((x) => x.id === f.parentId) || null : null);
const folderAncestors = (c, f) => { const out = []; let p = parentFolder(c, f); while (p && out.length <= FOLDER_DEPTH && !out.includes(p)) { out.unshift(p); p = parentFolder(c, p); } return out; };
const folderDepth = (c, f) => folderAncestors(c, f).length;
const folderTree = (c, f) => subFolders(c, f).flatMap((x) => [x, ...folderTree(c, x)]);
const folderPath = (c, f) => [...folderAncestors(c, f), f].map((x) => x.name).join(' › ');
const inFiles = (c, f) => { const a = folderAncestors(c, f); return !!a.length && isFilesTop(c, a[0]); };
const folderDup = (c, name, exceptId, parentId) => c.folders.find((f) => f.id !== exceptId && (f.parentId || null) === (parentId || null) && f.name.trim().toLowerCase() === name.trim().toLowerCase());
// (who may do what: app.js, with me() = u)
const canAssets = (u) => !!u && (isAdm(u) || u.role === 'am');
const canAddAssets = (u) => !!u && !isFinUser(u) && u.role !== 'freelancer';   // freelancers only look
const canDelAsset = (u, a) => canAddAssets(u) && !(a && a.final) && (canAssets(u) || (!!a && a.addedBy === u.id));
const canEditFolder = (u, c, f) => isAdm(u) || (canAddAssets(u) && !isAutoFolder(c, f) && (canAssets(u) || f.createdBy === u.id));
const canDelFolder = (u, c, f) => canEditFolder(u, c, f) && (canAssets(u) || [f, ...folderTree(c, f)].every((x) => x.createdBy === u.id || x === f) && [f, ...folderTree(c, f)].every((x) => x.files.every((a) => a.addedBy === u.id)));
const canUploadTo = (u, c, f) => canAddAssets(u) && !!f && !f.finalOf && !isFilesTop(c, f);
const canMakeSub = (u, c, f) => canAddAssets(u) && !!f && !f.finalOf && (isFilesTop(c, f) || (inFiles(c, f) && folderDepth(c, f) < FOLDER_DEPTH));
const canRenameCA = (u, c) => isAdm(u) || (!!c && c.createdBy === u.id);

// a command's output as bytes (ffmpeg / ffprobe), null when it fails
const runOut = (cmd, args, timeout = 30000) => new Promise((ok) => execFile(cmd, args, { encoding: 'buffer', maxBuffer: 64 << 20, timeout }, (err, out) => ok(err ? null : out)));

export function createAssetActs({ store, now = () => Date.now(), access, files } = {}) {
  const acc = access || createAccess(store, { plans: true });
  const nowISO = () => new Date(now()).toISOString();
  const uid = () => now().toString(36) + Math.random().toString(36).slice(2, 8);
  const fail = (status, error) => ({ ok: false, status, error });
  const done = (changes, answer = {}, more = {}) => ({ ok: true, changes, messages: [], answer, ...more });

  // what this person's page has (the server's visibleSnapshot): its db.users / projects / tasks / clients / trash
  function view(u) {
    const vis = (k) => store.list(k).filter((x) => acc.canSee(u, k, x)).map((x) => clone(acc.shape(u, k, x)));
    return { users: vis('users'), projects: vis('projects'), tasks: vis('tasks'), clients: vis('clients'), trash: vis('trash'), scheduled: vis('scheduled') };
  }
  // a client changed: the server's record as it was (base) and the page's copy as it is now
  const clientChange = (c) => ({ kind: 'clients', id: String(c.id), base: clone(store.get('clients', String(c.id))), data: clone(c) });

  // app.js assetNotify: an Inbox update (and phone notification) for everyone working on that client's tasks (assignees,
  // creators, watchers), its Account Managers, and every Admin — not the person who did it; freelancers only for their
  // own clients; never Finance-only people or someone who left
  function assetNotify(V, u, out, c, f, verb, names) {
    if (!c || !names.length) return;
    const userById = (id) => V.users.find((x) => x.id === id) || null;
    const task = (id) => V.tasks.find((t) => t.id === id) || null;
    const proj = (id) => V.projects.find((p) => p.id === id) || null;
    // (rules.js creatorOf: an Account Manager who made it but isn't the client's AM (or is on leave) doesn't count)
    const creatorOf = (t) => {
      const root = t && t.parentId ? task(t.parentId) || t : t;
      const id = t && t.createdBy, x = id && userById(id);
      if (!x || x.role !== 'am' || isAdm(x)) return id || null;
      const p = root && root.projectId ? proj(root.projectId) : null;
      if (!p || !(p.ams || []).length) return id;
      return (p.ams || []).some((a) => a.id === id && !a.onLeave) ? id : null;
    };
    const projs = V.projects.filter((p) => p.clientId === c.id);
    const pids = new Set(projs.map((p) => p.id));
    const to = new Set();
    V.tasks.filter((t) => pids.has(t.projectId) || (t.parentId && pids.has((task(t.parentId) || {}).projectId))).forEach((t) => {
      (t.assignees || []).forEach((id) => to.add(id));
      if (creatorOf(t)) to.add(creatorOf(t));
      (t.watchers || []).forEach((id) => to.add(id));
    });
    projs.forEach((p) => (p.ams || []).forEach((a) => to.add(a.id)));
    V.users.forEach((x) => { if (isAdm(x)) to.add(x.id); });
    const n = names.length;
    const text = `${verb} ${n === 1 ? 'a file' : n + ' files'} ${verb === 'added' ? 'to' : verb === 'replaced' ? 'in' : 'from'} ${c.name} › ${folderPath(c, f)}`;
    const snippet = names.slice(0, 4).join(', ') + (n > 4 ? ` +${n - 4} more` : '');
    to.forEach((id) => {
      const x = userById(id);
      if (!x || id === u.id || x.active === false || isFinUser(x)) return;
      if (x.role === 'freelancer' && !projs.some((p) => (x.projectIds || []).includes(p.id))) return;   // only their own clients
      const nt = { id: uid(), to: id, from: u.id, kind: 'asset', clientId: c.id, folderId: f.id, text, snippet, at: nowISO(), read: false };
      out.push({ kind: 'notifications', id: nt.id, data: nt });
    });
  }
  // app.js toTrash: a Trash entry (kept 30 days; the files stay on disk until it's deleted for good)
  function toTrash(u, out, type, data, extra = {}) {
    const item = { id: 'tr-' + uid(), type, deletedAt: nowISO(), deletedBy: u.id, ...extra, data: clone(data) };
    out.push({ kind: 'trash', id: item.id, data: item });
    return item;
  }
  // app.js newFolder: its NAS folder next to its brothers (a free name), made by the page with Host makeDir
  function newFolder(u, c, name, auto = false, parent = null) {
    const f = { id: 'cf-' + uid(), name: name.trim(), dir: freeDir(parent ? parent.dir : c.dir, name, c.folders.map((x) => x.dir)), files: [], createdAt: nowISO(), createdBy: u.id, ...(auto ? { auto: true } : {}), ...(parent ? { parentId: parent.id } : {}) };
    c.folders.push(f);
    return f;
  }
  // the page's start for every action but addClient: its copy of the client (what it can see), and the folder named
  function clientOf(u, body) {
    const V = view(u);
    const c = body.client ? V.clients.find((x) => x.id === String(body.client)) || null : null;
    if (!c) return { err: fail(404, 'That client has been removed') };
    c.folders = c.folders || [];
    const f = body.folder ? c.folders.find((x) => x.id === body.folder) || null : null;
    return { V, c, f };
  }

  // + New client (All Client Assets): with its four folders (Logos, Brand Guidelines, Fonts, Files) — answer.id
  function caAddClient(u, body) {
    if (!canAssets(u)) return fail(403, 'Your role can’t do this');
    const name = String(body.name || '').trim();
    if (!name) return fail(400, 'Enter the client’s name');
    const V = view(u);
    const k = clientKey(name);
    const d = k ? V.clients.find((c) => clientKey(c.name) === k) : null;
    if (d) return fail(409, dupMsg(d));
    const c = { id: 'cl-' + uid(), name: name.trim().replace(/\s+/g, ' '), logo: null, dir: '', folders: [], createdAt: nowISO(), createdBy: u.id };
    c.dir = freeDir('Clients', c.name, V.clients.map((x) => x.dir));
    DEFAULT_FOLDERS.forEach((n) => newFolder(u, c, n, true));   // made with the client: only an Admin removes them
    return done([{ kind: 'clients', id: c.id, data: clone(c) }], { id: c.id }, { dirs: c.folders.map((x) => x.dir) });
  }
  // files the app uploaded (into the folder's NAS folder): body.files [{ name, path, size }] — added to the folder, an
  // Inbox update; then (later) the client's logo from them when it has none and this is its own Logos folder
  function caUploaded(u, body) {
    const { V, c, f, err } = clientOf(u, body); if (err) return err;
    if (!f || !canUploadTo(u, c, f)) return fail(403, f && isFilesTop(c, f) ? 'Open a folder first' : 'You can’t add files here');
    const list = (Array.isArray(body.files) ? body.files : []).filter((x) => x && x.path).map((x) => ({ id: uid(), name: String(x.name || 'File'), path: String(x.path), size: +x.size || 0, addedAt: nowISO(), addedBy: u.id }));
    if (!list.length) return fail(400, 'Nothing was uploaded');
    f.files.push(...list);
    const out = [clientChange(c)];
    assetNotify(V, u, out, c, f, 'added', list.map((x) => x.name));
    return done(out, {}, { later: () => autoLogo(u, c.id, f.id, list) });
  }
  // + New folder: on the client's page (Admins and Account Managers) or inside Files, up to 5 levels deep — answer.id
  function caNewFolder(u, body) {
    const { c, err } = clientOf(u, body); if (err) return err;
    const parent = body.parent ? c.folders.find((x) => x.id === body.parent) || null : null;
    if (!canAddAssets(u)) return fail(403, 'Your role can’t do this');
    if (parent && !canMakeSub(u, c, parent)) return fail(403, parent.finalOf ? 'Final files hold no folders' : `Folders go up to ${FOLDER_DEPTH} levels deep inside Files`);
    if (!parent && !canAssets(u)) return fail(403, 'Add your folder inside Files');
    const name = String(body.name || '').trim();
    if (!name) return fail(400, 'Enter a folder name');
    const dup = folderDup(c, name, null, parent ? parent.id : null); if (dup) return fail(409, `There is already a folder named “${dup.name}”.`);
    const nf = newFolder(u, c, name, false, parent);
    return done([clientChange(c)], { id: nf.id }, { dirs: [nf.dir] });
  }
  // Rename (a folder): its name only — its NAS folder keeps its name
  function caRenameFolder(u, body) {
    const { c, f, err } = clientOf(u, body); if (err) return err;
    if (!f || !canEditFolder(u, c, f) || f.finalOf) return fail(403, 'Your role doesn’t allow this');
    const name = String(body.name || '').trim();
    if (!name) return fail(400, 'Enter a folder name');
    const dup = folderDup(c, name, f.id, f.parentId); if (dup) return fail(409, `There is already a folder named “${dup.name}”.`);
    f.name = name;
    return done([clientChange(c)]);
  }
  // Delete (a folder): into the Trash with the folders inside it and all their files, one entry; an Inbox update when it
  // held files of its own
  function caDeleteFolder(u, body) {
    const { V, c, f, err } = clientOf(u, body); if (err) return err;
    if (!f || !canDelFolder(u, c, f)) return fail(403, 'Your role doesn’t allow this');
    const inner = folderTree(c, f);
    c.folders = c.folders.filter((x) => x !== f && !inner.includes(x));
    const out = [clientChange(c)];
    toTrash(u, out, 'cafolder', { clientId: c.id, folder: f, inner }, { key: 'clients:' + c.id, where: inner.length || f.parentId ? `${c.name} › ${folderPath(c, f)}` : c.name });
    if (f.files.length) assetNotify(V, u, out, c, f, 'removed', f.files.map((a) => a.name));
    return done(out);
  }
  // Delete (a file): into the Trash, an Inbox update; never a final file
  function caDeleteFile(u, body) {
    const { V, c, f, err } = clientOf(u, body); if (err) return err;
    const a = f && f.files.find((x) => x.id === body.file);
    if (!a || f.finalOf || !canDelAsset(u, a)) return fail(403, 'Your role doesn’t allow this');
    f.files = f.files.filter((x) => x.id !== a.id);
    const out = [clientChange(c)];
    toTrash(u, out, 'cafile', { clientId: c.id, folderId: f.id, file: a }, { key: 'clients:' + c.id, where: `${c.name} › ${f.name}` });
    assetNotify(V, u, out, c, f, 'removed', [a.name]);
    return done(out);
  }
  // Select › Delete: body.files [ids] — each to the Trash on its own, one Inbox update; all or none
  function caDeleteFiles(u, body) {
    const { V, c, f, err } = clientOf(u, body); if (err) return err;
    const ids = new Set((Array.isArray(body.files) ? body.files : []).map(String));
    const list = f ? f.files.filter((x) => ids.has(x.id)) : [];
    if (!list.length) return fail(404, 'Those files aren’t here any more');
    if (f.finalOf || list.some((a) => !canDelAsset(u, a))) return fail(403, 'Your role doesn’t allow this');
    f.files = f.files.filter((x) => !ids.has(x.id));
    const out = [clientChange(c)];
    list.forEach((a) => toTrash(u, out, 'cafile', { clientId: c.id, folderId: f.id, file: a }, { key: 'clients:' + c.id, where: `${c.name} › ${f.name}` }));
    assetNotify(V, u, out, c, f, 'removed', list.map((a) => a.name));
    return done(out);
  }
  // Rename (the client's Client Assets): Admins, or whoever made it; its NAS folder keeps its name
  function caRenameClient(u, body) {
    const { V, c, err } = clientOf(u, body); if (err) return err;
    if (!canRenameCA(u, c)) return fail(403, 'You can’t rename this');
    const name = String(body.name || '').trim().replace(/\s+/g, ' ');
    if (!name) return fail(400, 'Enter the client’s name');
    const k = clientKey(name);
    const d = k ? V.clients.find((x) => x.id !== c.id && clientKey(x.name) === k) : null;
    if (d) return fail(409, dupMsg(d));
    c.name = name;
    return done([clientChange(c)]);
  }
  // Delete (a client's Client Assets, Admins): gone with its folders and files — not to the Trash; the clients (projects)
  // using it are unlinked; its files, folders and logo leave the NAS when nothing else uses them (filesGone, as the
  // page's safeTrash) — answer.gone
  function caDeleteClient(u, body) {
    const { V, c, err } = clientOf(u, body); if (err) return err;
    if (!isAdm(u)) return fail(403, 'Only Admins delete clients');
    const paths = [c.logo, ...c.folders.flatMap((x) => x.files.flatMap((a) => [a.path, '.thumbs/' + a.id])), ...c.folders.map((x) => x.dir), c.dir].filter(Boolean);
    const out = [{ kind: 'clients', id: String(c.id), del: true }];
    // (the page saves every project it unlinks; one the server refuses — an Office Admin doesn't change clients' projects
    //  — stays as it is while the rest is saved: so it's left out here, else the route would refuse it all)
    V.projects.forEach((p) => {
      if (p.clientId !== c.id) return;
      const base = store.get('projects', String(p.id));
      const next = clone(p); delete next.clientId;
      const ch = { kind: 'projects', id: String(p.id), base: clone(base), data: next };
      if (acc.canWrite(u, ch, base)) out.push(ch);
    });
    V.clients = V.clients.filter((x) => x.id !== c.id);
    return done(out, { gone: true }, { filesGone: safeTrash(V, paths) });
  }
  // app.js safeTrash: only what nothing else the page has still uses (copied files are shared) — the server's own
  // trash route checks the rest of the server's data again before deleting
  function safeTrash(V, paths) {
    const fileRefsIn = (html) => { const r = []; String(html || '').replace(/data-fpath="([^"]*)"/g, (_, p) => { r.push(p.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')); return ''; }); return r; };
    const s = new Set();
    const add = (a) => { if (a && a.path) { s.add(a.path); if (a.thumb) s.add(a.thumb); } };
    V.tasks.forEach((t) => {
      (t.attachments || []).forEach(add);
      (t.comments || []).forEach((cm) => { (cm.attachments || []).forEach(add); fileRefsIn(cm.html).forEach((p) => s.add(p)); });
      fileRefsIn(t.notesHtml).forEach((p) => s.add(p));
    });
    V.scheduled.forEach((x) => { if (x.state !== 'sent') (x.attachments || []).forEach(add); });
    V.trash.forEach((it) => trashFiles(it).forEach(add));
    V.clients.forEach((c) => { if (c.logo) s.add(c.logo); (c.folders || []).forEach((f) => (f.files || []).forEach(add)); });
    const used = [...s];
    return paths.filter((p) => p && !used.some((x) => x === p || x.startsWith(p.replace(/\/$/, '') + '/') || (p.startsWith('.thumbs/') && x.startsWith(p))));
  }
  function trashFiles(it) {
    const d = it.data || {};
    const fromTasks = (list) => (list || []).flatMap((t) => (t.attachments || []).concat(...(t.comments || []).map((c) => c.attachments || [])));
    if (it.type === 'task' || it.type === 'project') return fromTasks(d.tasks);
    if (it.type === 'comment') return (d.comments || []).flatMap((c) => c.attachments || []);
    if (it.type === 'attachment') return d.att ? [d.att] : [];
    if (it.type === 'cafile') return d.file ? [d.file] : [];
    if (it.type === 'cafolder') return [d.folder, ...(d.inner || [])].filter(Boolean).flatMap((x) => x.files || []);
    return [];
  }

  /* ---- the client's logo from its Logos folder (app.js autoLogo) ----
     The client has no logo and the files went into its own Logos folder (made with the client): the first image among
     them (by name: png, jpg, webp, gif, svg) becomes the logo, made square as the website's squareLogo draws it — a
     transparent logo on a dark square when it's light and a light one when it's dark (16% margin), one with its own
     background on a square of its edge colour (6%), 800 px — then the server's processImage (kind 'logo', 'client-sq':
     Clients/_logos/client-sq-….png, 600 px). Saved only if the client still has no logo, marked logoAuto (which lets
     anyone fill in a missing logo — access.js). One at a time per person, as the page's busy flag (another upload
     meanwhile: no logo from it). The pixels come from ffmpeg instead of the browser's canvas: the same picture, not the
     same bytes. */
  const logoBusy = new Set();
  async function squareLogo(src, svg) {
    const probe = await runOut('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'json', src], 20000);
    let W = 0, H = 0;
    try { const st = JSON.parse(String(probe)).streams[0]; W = +st.width || 0; H = +st.height || 0; } catch { /* not an image */ }
    if (!W || !H) return null;
    // (an SVG is drawn at the size it's needed, as the browser does; anything else is scaled)
    const decode = (w, h) => (svg ? ['-width', String(w), '-height', String(h), '-i', src] : ['-i', src]);
    const k = Math.min(1, 256 / Math.max(W, H));
    const aw = Math.max(1, Math.round(W * k)), ah = Math.max(1, Math.round(H * k));
    const d = await runOut('ffmpeg', ['-v', 'error', ...decode(aw, ah), '-frames:v', '1', '-vf', `scale=${aw}:${ah}:flags=bilinear,format=rgba`, '-f', 'rawvideo', '-']);
    if (!d || d.length < aw * ah * 4) return null;
    let clear = 0, lum = 0, weight = 0; const px = aw * ah;
    for (let i = 0; i < px * 4; i += 4) {
      const al = d[i + 3];
      if (al < 200) clear++;
      if (al > 40) { lum += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255 * al; weight += al; }
    }
    let bg, pad;
    if (clear / px > 0.04) { const L = weight ? lum / weight : 0; bg = L > 0.6 ? '121317' : 'f5f4f0'; pad = 0.16; }
    else {
      let r = 0, g = 0, b = 0, n = 0;
      const edge = (x, y) => { const i = (y * aw + x) * 4; r += d[i]; g += d[i + 1]; b += d[i + 2]; n++; };
      for (let x = 0; x < aw; x++) { edge(x, 0); edge(x, ah - 1); }
      for (let y = 0; y < ah; y++) { edge(0, y); edge(aw - 1, y); }
      bg = [r, g, b].map((v) => Math.round(v / n).toString(16).padStart(2, '0')).join(''); pad = 0.06;
    }
    const S = 800, box = S * (1 - pad * 2), sc = Math.min(box / W, box / H);
    const w = Math.max(1, Math.round(W * sc)), h = Math.max(1, Math.round(H * sc));
    return runOut('ffmpeg', ['-v', 'error', ...decode(w, h), '-f', 'lavfi', '-i', `color=c=0x${bg}:s=${S}x${S}`,
      '-filter_complex', `[0:v]scale=${w}:${h}:flags=lanczos,format=rgba[lg];[1:v][lg]overlay=${Math.round((S - w) / 2)}:${Math.round((S - h) / 2)}:format=auto,format=rgb24[o]`,
      '-map', '[o]', '-frames:v', '1', '-f', 'image2pipe', '-vcodec', 'png', '-'], 60000);
  }
  async function autoLogo(u, clientId, folderId, added) {
    if (!files || logoBusy.has(u.id)) return [];
    const c = store.get('clients', String(clientId)), f = c && (c.folders || []).find((x) => x.id === folderId);
    if (!c || c.logo || !f || f.name !== 'Logos' || !isAutoFolder(c, f)) return [];
    const a = (added || f.files).find((x) => LOGO_EXT.test(x.name || ''));
    if (!a) return [];
    logoBusy.add(u.id);
    try {
      let src; try { src = files.resolve(a.path); } catch { return []; }
      const png = await squareLogo(src, /\.svg$/i.test(src));
      if (!png || !png.length) return [];
      const up = files.commands.writeChunk({ taskId: '_uploads', name: 'logo.png', data: png });
      const r = await files.commands.processImage({ path: up.path, kind: 'logo', userId: 'client-sq' });
      const cur = store.get('clients', String(clientId));
      if (!r || !r.path || !cur || cur.logo) return [];
      return [{ kind: 'clients', id: String(cur.id), base: clone(cur), data: { ...clone(cur), logo: r.path, logoAuto: true } }];
    } catch (e) { return []; /* no logo then; the colour stays */ } finally { logoBusy.delete(u.id); }
  }

  // The logo catch-up (app.js autoLogosAll — step 9: the iPhone app asks when Client Assets opens, as the page did):
  // every client without a logo whose Logos folder has an image gets it, one after another, after answering
  function caLogosAll(u) {
    if (!canAddAssets(u)) return done([]);
    const todo = store.list('clients').filter((c) => !c.logo && (c.folders || []).some((f) => f.name === 'Logos' && (f.files || []).some((x) => LOGO_EXT.test(x.name || ''))));
    if (!todo.length) return done([]);
    return done([], {}, { later: async () => {
      const out = [];
      for (const c of todo) { const f = (c.folders || []).find((x) => x.name === 'Logos'); out.push(...await autoLogo(u, c.id, f.id)); }
      return out;
    } });
  }

  return { caAddClient, caUploaded, caNewFolder, caRenameFolder, caDeleteFolder, caDeleteFile, caDeleteFiles, caRenameClient, caDeleteClient, caLogosAll };
}
