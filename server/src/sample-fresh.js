// "Start fresh with sample data" (TEST COPY ONLY): the usual sample story (sample.js), set up the way the app works now —
// clients with their Account Managers (one on leave, someone covering), an inactive client, a Client Assets folder per
// client (Logos, Brand Guidelines, Fonts, Files) with a few files and logos, only Production / Social / Freelancers /
// the Creative Director assigned, newer tasks under the new CD review rule, a freelancer, and Inbox updates of the
// newer kinds (Client Assets, changes on an AM's client).
import fs from 'node:fs';
import path from 'node:path';
import { sampleData } from './sample.js';

const DEFAULT_FOLDERS = ['Logos', 'Brand Guidelines', 'Fonts', 'Files'];
const LOGO_COLORS = { 'Ford & Lincoln': ['#0b2a63', '#ffffff'], ALAIN: ['#6c4cf0', '#ffffff'], 'KOREA 360': ['#c8102e', '#ffffff'], HRE: ['#0f8a5f', '#ffffff'], DEEPAL: ['#111111', '#f9be33'], Nakheel: ['#9a7b4f', '#ffffff'] };
const logoSvg = (name, [bg, fg]) => `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="300" viewBox="0 0 600 300"><rect width="600" height="300" rx="24" fill="${bg}"/><text x="300" y="168" font-family="Helvetica, Arial, sans-serif" font-size="${name.length > 9 ? 64 : 84}" font-weight="700" fill="${fg}" text-anchor="middle" letter-spacing="2">${name.toUpperCase().replace(/&/g, '&amp;')}</text></svg>`;   // (escape after uppercasing: "&AMP;" breaks the SVG)

export function freshSample(store, me, filesRoot) {
  const out = sampleData(store, me, filesRoot);
  const iso = (daysAgo, h = 10) => new Date(Date.now() - daysAgo * 86400000 + (h - 12) * 3600000).toISOString();
  const users = new Map(out.users.map((u) => [u.id, u]));
  const role = (id) => (id === me ? 'admin' : (users.get(id) || {}).role);
  const cd = 'u-karim';                                   // Carine (an Account Manager) is the Creative Director
  out.meta = { ...(out.meta || {}), cdUserId: users.has(cd) ? cd : out.meta.cdUserId };

  // a freelancer on Ford & Lincoln
  const free = { id: 'u-smp-free', name: 'Sam Rivera', email: 'sam.rivera.design@gmail.com', role: 'freelancer', designation: 'Motion Designer (freelance)', active: true, setup: true, avatar: null, prefs: {}, createdAt: iso(60), office: 'Remote', projectIds: ['p-ford'] };
  out.users.push(free); users.set(free.id, free);

  // an inactive client with a few tasks (switch it on in Edit client list to see them)
  const nak = { id: 'p-nakheel', name: 'Nakheel', color: '#9a7b4f', view: 'list', createdAt: iso(300), order: 99, inactive: true,
    sections: [{ id: 'nk-todo', name: 'To do', color: '#87909e' }, { id: 'nk-prog', name: 'In progress', color: '#a875ff' }, { id: 'nk-done', name: 'Done', color: '#3ddc97' }] };
  out.projects.push(nak);
  ['Palm Jebel Ali | Teaser 30s', 'Nakheel Mall | Ramadan Key Visual', 'Dragon City | Social Pack'].forEach((title, i) => out.tasks.push({
    id: `smp-nk-${i}`, title, projectId: nak.id, sectionId: i === 2 ? 'nk-done' : 'nk-todo', parentId: null, assignees: ['u-ali'], createdBy: 'u-lana', createdAt: iso(200 - i * 10), updatedAt: iso(120),
    due: iso(110 - i * 5).slice(0, 10), done: i === 2, completedAt: i === 2 ? iso(115) : null, notes: '', notesHtml: '', tags: [], comments: [], attachments: [], activity: [], checklist: [], prio: {}, order: i,
  }));

  // Account Managers per client: KOREA 360's is on leave and Areej covers
  const AMS = { 'p-ford': [{ id: 'u-lina' }], 'p-alain': [{ id: 'u-lana' }], 'p-korea': [{ id: 'u-nadia', onLeave: true }, { id: 'u-lina' }], 'p-hre': [{ id: 'u-lana' }], 'p-deepal': [{ id: 'u-nadia' }], 'p-nakheel': [{ id: 'u-lana' }] };
  out.projects.forEach((p) => { p.ams = (AMS[p.id] || []).filter((a) => users.has(a.id)); });

  // a Client Assets folder per client, linked; logos waiting in Logos for three of them (the first one becomes the logo)
  const put = (rel, data) => { const dest = path.join(filesRoot, ...rel.split('/')); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, data); return fs.statSync(dest).size; };
  const copy = (name, rel) => { const dest = path.join(filesRoot, ...rel.split('/')); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.copyFileSync(new URL('./sample-files/' + name, import.meta.url), dest); return fs.statSync(dest).size; };
  out.clients = out.projects.map((p, i) => {
    const at = p.createdAt || iso(300);
    const dir = `Clients/${p.name.replace(/[/:\\]/g, '-')}`;
    const folders = DEFAULT_FOLDERS.map((n) => ({ id: `cf-${p.id}-${n.replace(/\W+/g, '').toLowerCase()}`, name: n, dir: `${dir}/${n}`, files: [], createdAt: at, createdBy: me, auto: true }));
    folders.forEach((f) => fs.mkdirSync(path.join(filesRoot, ...f.dir.split('/')), { recursive: true }));
    const add = (fname, file, by, daysAgo, data) => {
      const f = folders.find((x) => x.name === fname);
      const rel = `${f.dir}/${file}`;
      const size = data ? put(rel, data) : copy(file, rel);
      f.files.push({ id: `smp-caf-${p.id}-${f.files.length}-${fname.length}`, name: file, path: rel, size, addedAt: iso(daysAgo), addedBy: by });
    };
    const am = (p.ams[0] || {}).id || me;
    if (i < 3 && LOGO_COLORS[p.name]) add('Logos', `${p.name} logo.svg`, am, 20, logoSvg(p.name, LOGO_COLORS[p.name]));
    if (i % 2 === 0) add('Brand Guidelines', 'creative-brief.pdf', am, 18);
    if (i === 1 || i === 3) add('Files', 'client-presentation.pptx', 'u-sara', 9);
    if (i === 0) add('Files', 'ford-key-visual.jpg', 'u-omar', 4);
    // a folder someone added (they can remove it; the four made with the client are Admin-only)
    if (i === 0) folders.push({ id: 'cf-p-ford-social', name: 'Social templates', dir: `${dir}/Social templates`, files: [{ id: 'smp-caf-ford-st', name: 'story-frame-1.png', path: `${dir}/Social templates/story-frame-1.png`, size: copy('story-frame-1.png', `${dir}/Social templates/story-frame-1.png`), addedAt: iso(3), addedBy: 'u-maya' }], createdAt: iso(5), createdBy: 'u-maya' });
    p.clientId = `cl-${p.id}`;
    return { id: `cl-${p.id}`, name: p.name, logo: null, dir, folders, createdAt: at, createdBy: me };
  });

  // assignees: only Production, Social, Freelancers and the Creative Director
  const prod = out.users.filter((u) => ['production', 'social'].includes(u.role)).map((u) => u.id);
  let k = 0;
  out.tasks.forEach((t) => {
    const keep = (t.assignees || []).filter((id) => id === cd || ['production', 'social', 'freelancer'].includes(role(id)));
    if (keep.length !== (t.assignees || []).length) {
      const gone = (t.assignees || []).filter((id) => !keep.includes(id));
      t.prio = Object.fromEntries(Object.entries(t.prio || {}).filter(([id]) => !gone.includes(id)));
      t.partsDone = Object.fromEntries(Object.entries(t.partsDone || {}).filter(([id]) => !gone.includes(id)));
    }
    t.assignees = keep.length || t.parentId ? keep : [prod[k++ % prod.length]];
  });
  // the freelancer on two Ford tasks
  out.tasks.filter((t) => t.projectId === 'p-ford' && !t.parentId && !t.done).slice(0, 2).forEach((t) => { t.assignees = [...new Set([...(t.assignees || []), free.id])]; });
  // newer tasks follow the new CD review rule (the CD isn't assigned while a task needs CD review)
  const open = out.tasks.filter((t) => !t.parentId && !t.done && t.projectId);
  open.forEach((t, i) => {
    if (i % 2 === 0) return;                              // the others stay older tasks (the old way)
    t.cdRule = 2;
    if (t.needsCD && (t.assignees || []).includes(cd)) t.assignees = t.assignees.filter((id) => id !== cd);
  });
  // the Creative Director working on two newer tasks (no CD review on those)
  open.filter((t) => t.cdRule && !t.needsCD).slice(0, 2).forEach((t) => { t.assignees = [...new Set([...(t.assignees || []), cd])]; });

  // who created each task: mostly the client's Account Manager, some by you (Admin), a few by the Creative Director,
  // KOREA 360's older ones by Nadia (now on leave, so Areej covers), and a few made by an AM in a client that isn't
  // theirs (moved since) — so every case can be tried
  const CREATORS = { 'p-ford': ['u-lina', 'u-lina', me, 'u-karim'], 'p-alain': ['u-lana', 'u-lana', me, 'u-lina'], 'p-korea': ['u-nadia', 'u-nadia', 'u-lina', me],
    'p-hre': ['u-lana', me, 'u-nadia'], 'p-deepal': ['u-nadia', 'u-nadia', me, 'u-karim'], 'p-nakheel': ['u-lana'] };
  const roots = out.tasks.filter((t) => !t.parentId);
  const nth = {};
  roots.forEach((t) => {
    const list = (CREATORS[t.projectId] || [me, 'u-lina', 'u-lana']).filter((id) => id === me || users.has(id));
    const i = (nth[t.projectId] = (nth[t.projectId] || 0) + 1) - 1;    // each client follows its own list
    t.createdBy = list[i % list.length] || me;
  });
  out.tasks.filter((t) => t.parentId).forEach((t) => { const r = out.tasks.find((x) => x.id === t.parentId); if (r) t.createdBy = r.createdBy; });
  // (a CD-created task the CD is assigned to doesn't need review under the new rule)
  out.tasks.forEach((t) => { if (t.cdRule && t.needsCD && (t.assignees || []).includes(cd)) t.assignees = t.assignees.filter((id) => id !== cd); });

  // Inbox updates of the newer kinds
  const fordFolder = out.clients[0].folders.find((f) => f.name === 'Logos');
  [me, 'u-sara', 'u-maya'].forEach((to, i) => out.notifications.push({ id: `smp-nas-${i}`, to, from: 'u-lina', kind: 'asset', clientId: out.clients[0].id, folderId: fordFolder.id, text: `added a file to ${out.clients[0].name} › Logos`, snippet: `${out.clients[0].name} logo.svg`, at: iso(0, 9 + i), read: false }));
  open.filter((t) => t.projectId === 'p-ford' && t.createdBy !== 'u-lina').slice(0, 3).forEach((t, i) => out.notifications.push({ id: `smp-ned-${i}`, to: 'u-lina', from: me, taskId: t.id, kind: 'edit', text: 'changed the due date on', snippet: '', commentId: null, at: iso(0, 8 + i), read: false }));
  return out;
}
