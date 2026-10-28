// "Start fresh with sample data" (TEST COPY ONLY): a running agency, built from 50 real recent ClickUp tasks
// (sample-story.json + sample-files/clickup/): clients with their Account Managers, tasks created by different AMs and
// assigned to Production / Social / a freelancer, real comment threads and files, and every stage of the job —
// to do, in progress, waiting for the CD (Review Requests), CD amendments, sent back by the client for a new round,
// CD approved but not yet client approved, client approved, and completed with final files in Client Assets › Files.
// Every date is relative to the day it's loaded (a task posted "today" is always posted today).
// The finance records, expense claims and Finance people come from the older sample (sample.js).
import fs from 'node:fs';
import path from 'node:path';
import { sampleData } from './sample.js';

const DAY = 86400000;
// (read only when the test copy starts fresh — live releases don't carry the story or its files)
let STORY_CACHE = null;
const MEDIA_DIR = new URL('./sample-files/clickup/', import.meta.url);
const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// clients: id, colour, Account Managers (first is the main one) — as in ClickUp
const CLIENTS = [
  ['p-ford', 'Ford & Lincoln', '#0b3d91', ['u-nadia']],
  ['p-kia', 'KIA', '#c8102e', ['u-lina']],
  ['p-deepal', 'DEEPAL', '#111827', ['u-lina']],
  ['p-atm', 'AL TAYER MOTORS', '#6b7280', ['u-lina']],
  ['p-alain', 'ALAIN', '#7b68ee', ['u-lana']],
  ['p-hre', 'HRE', '#0f8a5f', ['u-lana']],
  ['p-korea', 'KOREA 360', '#e5484d', [{ id: 'u-nadia', onLeave: true }, 'u-lina']],   // Nadia on leave, Areej covers
  ['p-cpt', 'CPT', '#d97706', ['u-lana']],
  ['p-asv', 'ASV', '#0ea5e9', ['u-nadia']],
  ['p-gm', 'Gebriel Motors', '#14b8a6', ['u-lina']],
  ['p-bizreh', 'Bizreh', '#a855f7', ['u-lana']],
  ['p-forta', 'FORTA', '#f97316', ['u-nadia']],
  ['p-e11', 'E11', '#64748b', []],
];
const SOCIAL_CLIENTS = new Set(['p-cpt', 'p-asv', 'p-gm', 'p-bizreh', 'p-hre', 'p-korea', 'p-alain']);
const TEAM = {   // who usually works on each client (Production / Social)
  'p-ford': ['u-joe', 'u-moon'], 'p-kia': ['u-sara', 'u-ali'], 'p-deepal': ['u-joe', 'u-maab'], 'p-atm': ['u-maab'], 'p-alain': ['u-ali', 'u-maya'],
  'p-hre': ['u-maab', 'u-maya'], 'p-korea': ['u-moon', 'u-aish'], 'p-cpt': ['u-aish', 'u-sara'], 'p-asv': ['u-maya', 'u-omar'], 'p-gm': ['u-aish', 'u-joe'],
  'p-bizreh': ['u-aish'], 'p-forta': ['u-ali'], 'p-e11': ['u-ali', 'u-maab'],
};
const CLIENT_OF = { 'Ford & Lincoln': 'p-ford', KIA: 'p-kia', DEEPAL: 'p-deepal', 'AL TAYER MOTORS': 'p-atm', ALAIN: 'p-alain', HRE: 'p-hre', 'KOREA 360': 'p-korea',
  CPT: 'p-cpt', ASV: 'p-asv', 'Gebriel Motors': 'p-gm', Bizreh: 'p-bizreh', FORTA: 'p-forta', E11: 'p-e11' };
// people from ClickUp (real names and photos)
const PEOPLE = {
  'u-nadia': ['Nadia Khashem', 'Nadia_khashem'], 'u-lina': ['Areej Masri', 'Areej_Masri'], 'u-lana': ['Lana Al Ramli', 'Lana_E11'], 'u-karim': ['Carine Abou Jaoude', 'Carine_Abou_Jaoude'],
  'u-ali': ['Ali Raza', 'Ali_Raza'], 'u-moon': ['Moon-Ray Jabra', 'Moon_Ray_Jabra'], 'u-maab': ['Maab Osama', 'Maab_Osama'], 'u-omar': ['Zaahir Hamid', 'Zaahir_Hamid'],
  'u-aish': ['Aishwarya Sanjay', 'Aishwarya_Sanjay'], 'u-new': ['Maria', null], 'u-maya': ['Amelia Aouidat', 'Amelia_Aouidat'], 'u-joe': ['Joe Hajj', 'Joe_Hajj'], 'u-sara': ['Yousef Al Hwij', null],
};
// ClickUp status → stage here, and the Task Update shown with it
const STAGE = { NEW: 'todo', BRAINSTORM: 'todo', '–': 'todo', '': 'todo', WIP: 'prog', STORYBOARD: 'prog', SHOOT: 'prog', 'EDIT VIDEO': 'prog', ADAPTATIONS: 'prog', 'ON HOLD': 'prog',
  'INTERNAL REVIEW': 'review', AMENDMENTS: 'amend', CTR: 'ctr', COMPLETED: 'done' };
const UPDATE = { NEW: 'Brief to come', BRAINSTORM: 'Brainstorm', WIP: 'WIP', STORYBOARD: 'Storyboard', SHOOT: 'Shoot', 'EDIT VIDEO': 'Edit Video', ADAPTATIONS: 'Adaptations', 'ON HOLD': 'On hold',
  'INTERNAL REVIEW': 'Oversee', AMENDMENTS: 'Amendments', CTR: 'Followup', COMPLETED: 'Ready to Post' };
const FIN = { 'PO Pending': 'LPO Pending', 'LPO Pending': 'LPO Pending', 'PO Received': 'To be invoiced', 'Quote to be sent': 'Quote to be sent' };
const CD_NOTES = ['The end frame logo comes in too early, hold it one second longer.', 'Raise the headline, it is fighting with the visual.', 'The Arabic line is too long, cut it to one line and check the kerning.'];
const LOGO = (name, bg) => `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="300" viewBox="0 0 600 300"><rect width="600" height="300" rx="24" fill="${bg}"/><text x="300" y="168" font-family="Helvetica, Arial, sans-serif" font-size="${name.length > 9 ? 56 : 84}" font-weight="700" fill="#ffffff" text-anchor="middle" letter-spacing="2">${esc(name.toUpperCase())}</text></svg>`;

// opts (the App Review demo, demo.js): its own story, media folder, sample files and photos
export function freshSample(store, me, filesRoot, opts = {}) {
  const STORY = opts.story || (STORY_CACHE = STORY_CACHE || JSON.parse(fs.readFileSync(new URL('./sample-story.json', import.meta.url), 'utf8')));
  const MEDIA = opts.media || MEDIA_DIR;
  const SRC = opts.src || new URL('./sample-files/', import.meta.url);
  const out = sampleData(store, me, filesRoot, opts);
  const now = Date.now();
  const today0 = (() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d.getTime(); })();
  // "hours ago" from now; a day offset (negative = past) as YYYY-MM-DD in local time
  const ago = (h) => new Date(now - h * 3600000).toISOString();
  const dayStr = (off) => { const d = new Date(today0 + off * DAY); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
  let seed = 11; const rnd = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; };
  const cd = 'u-karim';
  const ME = (id) => (id === 'u-haris' || id === 'me' ? me : id);

  // ---------- people: real names and photos; Joe Hajj joins; a freelancer on Ford & Lincoln ----------
  const users = new Map(out.users.map((u) => [u.id, u]));
  if (!users.has('u-joe') && !store.list('users').some((x) => String(x.email).toLowerCase() === 'joe@e11-digital.com')) {
    const joe = { id: 'u-joe', name: 'Joe Hajj', email: 'joe@e11-digital.com', role: 'production', designation: 'Senior Designer', active: true, setup: true, avatar: null, prefs: {}, createdAt: ago(24 * 200), office: 'Dubai — Business Bay office' };
    out.users.push(joe); users.set(joe.id, joe);
  }
  // Maria: a Social Executive (content plans trial)
  if (!users.has('u-new') && !store.list('users').some((x) => String(x.email).toLowerCase() === 'maria@e11-digital.com')) {
    const maria = { id: 'u-new', name: 'Maria', email: 'maria@e11-digital.com', role: 'social', designation: 'Social Media Executive', active: true, setup: true, avatar: null, prefs: {}, createdAt: ago(24 * 90), office: 'Dubai — Business Bay office' };
    out.users.push(maria); users.set(maria.id, maria);
  }
  // Muhammad Arsal runs the office: Office Admin, with Finance Admin access
  { const a = users.get('u-arsal'); if (a) { a.role = 'office_admin'; a.fin = 'admin'; a.designation = 'Office Manager'; } }
  const free = { id: 'u-smp-free', name: 'Sam Rivera', email: 'sam.rivera.design@gmail.com', role: 'freelancer', designation: 'Motion Designer (freelance)', active: true, setup: true, avatar: null, prefs: {}, createdAt: ago(24 * 60), office: 'Remote', projectIds: ['p-ford'] };
  out.users.push(free); users.set(free.id, free);
  const putFile = (rel, src) => { const dest = path.join(filesRoot, ...rel.split('/')); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.copyFileSync(src, dest); return fs.statSync(dest).size; };
  const putData = (rel, data) => { const dest = path.join(filesRoot, ...rel.split('/')); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, data); return fs.statSync(dest).size; };
  for (const [id, [name, photo]] of Object.entries(PEOPLE)) {
    const u = users.get(id); if (!u) continue;
    u.name = name;
    if ((photo || opts.photo) && filesRoot) { try { const rel = `attachments/_avatars/smp-${id}.jpg`; putFile(rel, opts.photo ? opts.photo(id) : new URL(`ph-${photo}.jpg`, MEDIA)); u.avatar = rel; } catch (e) { /* photo missing: initials */ } }
  }
  const has = (id) => id === me || users.has(id);
  const team = (pid) => (TEAM[pid] || []).map(ME).filter(has);

  // ---------- clients ----------
  const keepFinance = out.tasks.filter((t) => String(t.id).startsWith('smp-fin-'));   // finished jobs for the Finance graphs
  const oldProjects = new Map(out.projects.map((p) => [p.id, p]));
  const sections = (pid) => ['To do', 'In progress', 'Review', 'CTR', 'Done'].map((n, i) => ({ id: `${pid}-${i}`, name: n, color: ['#87909e', '#a875ff', '#f9be33', '#ff8a4c', '#3ddc97'][i] }));
  out.projects = CLIENTS.map(([id, name, color, ams], i) => ({
    id, name, color, view: 'list', order: i + 1, createdAt: (oldProjects.get(id) || {}).createdAt || ago(24 * (300 - i * 9)),
    sections: sections(id),
    ams: ams.map((a) => (typeof a === 'string' ? { id: a } : a)).filter((a) => has(a.id)),
  }));
  // an inactive client (switch it on in Edit client list to see it)
  const nak = { id: 'p-nakheel', name: 'Nakheel', color: '#9a7b4f', view: 'list', createdAt: ago(24 * 300), order: 99, inactive: true, ams: [{ id: 'u-lana' }].filter((a) => has(a.id)), sections: sections('p-nakheel') };
  out.projects.push(nak);
  const proj = new Map(out.projects.map((p) => [p.id, p]));
  const sec = (pid, i) => proj.get(pid).sections[i].id;
  // finance-graph jobs only on clients that still exist
  keepFinance.forEach((t) => { if (!proj.has(t.projectId)) { t.projectId = 'p-ford'; t.sectionId = sec('p-ford', 4); } });

  // ---------- tasks from ClickUp ----------
  const tasks = [];
  const notifs = out.notifications.filter((n) => !n.taskId && /^claim/.test(String(n.kind || '')));   // (expense claim updates stay)
  const notify = (to, from, t, kind, text, extra = {}) => { to = ME(to); from = ME(from); if (!has(to) || to === from) return; notifs.push({ id: `smp-n${notifs.length}`, to, from, taskId: t.id, kind, text, snippet: '', commentId: null, at: extra.at || ago(2), read: !!extra.read, ...extra }); };
  const nameOf = (id) => (id === me ? (store.get('users', me) || {}).name || 'Haris' : (users.get(id) || {}).name || '');
  const MENTION = Object.fromEntries(Object.entries(PEOPLE).map(([id, [name]]) => [name.toLowerCase(), id]));
  Object.assign(MENTION, { 'nadia khashem': 'u-nadia', 'lana e11': 'u-lana', 'zaahir hamid': 'u-omar', 'mohammad haris': me, 'muhammad haris sharif': me, 'yousef al hwij': 'u-sara', 'maab osama': 'u-maab' });
  const html = (text, mentioned) => esc(text).replace(/@([A-Z][\w-]+(?: [A-Z][\w-]+)?(?: [A-Z][\w-]+)?)/gi, (m, nm) => {
    for (let k = nm.split(' ').length; k > 0; k--) { const cand = nm.split(' ').slice(0, k).join(' '); const id = MENTION[cand.toLowerCase()]; if (id && has(id)) { mentioned.push(id); return `<span class="mention" data-user="${id}" contenteditable="false">@${esc(nameOf(id) || cand)}</span>` + esc(nm.split(' ').slice(k).map((w) => ' ' + w).join('')); } }
    return m;
  }).replace(/\n/g, '<br>');
  // due dates: a mix — overdue, today, this week, later (the completed ones finished in the last ten days)
  const DUE = [-6, -3, -2, -1, -1, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 6, 7, 8, 10, 12, 14, 18];
  let ctrN = 0, amendN = 0, reviewN = 0, doneN = 0;

  STORY.tasks.forEach((s, i) => {
    const pid = CLIENT_OF[s.client] || 'p-e11';
    const p = proj.get(pid);
    let stage = STAGE[s.status] || 'prog';
    if (stage === 'prog' && s.media.length && reviewN + (i % 3) < 5 && i % 3 === 0) stage = 'review';   // (a couple more waiting for the CD)
    const id = `smp-cu-${s.key}`;
    const am = ((p.ams || []).find((a) => !a.onLeave) || {}).id || me;
    const creator = s.creator && has(ME(s.creator)) && ['u-lina', 'u-nadia', 'u-lana', 'u-karim', 'u-aish', 'u-maya'].includes(s.creator) ? ME(s.creator) : (i % 4 === 3 ? me : am);
    // the people on it: who talked on the task from Production / Social, else the client's usual team
    const roles = (uid) => (users.get(uid) || store.get('users', uid) || {}).role;   // (you, the owner, only when you work as Production)
    const talked = [...new Set(s.comments.map((c) => ME(c.who)).filter((u) => has(u) && ['production', 'social'].includes(roles(u))))];
    let assignees = (talked.length ? talked : team(pid).slice(0, 1 + (i % 2))).slice(0, 3);
    if (!assignees.length) assignees = [team(pid)[0] || 'u-ali'].filter(has);
    const createdDays = stage === 'done' ? 14 + (i % 10) : 3 + ((i * 7) % 20);
    const t = {
      id, title: s.title, projectId: pid, sectionId: sec(pid, 1), parentId: null, assignees, createdBy: creator, createdAt: ago(24 * createdDays + 3), updatedAt: ago(1 + (i % 9)),
      due: null, start: null, done: false, completedAt: null, notes: s.notes || '', notesHtml: s.notes ? esc(s.notes).replace(/\n/g, '<br>') : '', tags: [], comments: [], attachments: [], activity: [], checklist: [], prio: {}, order: i + 1,
      needsCD: false, cdRule: 2, cdStatus: '', reviews: [], partsDone: {}, update: UPDATE[s.status] || 'WIP', finance: FIN[s.finance] || (SOCIAL_CLIENTS.has(pid) && i % 3 === 0 ? 'Retainer' : undefined),
    };
    if (t.finance) { t.financeAt = ago(24 * (2 + (i % 12))); t.financeBy = am; }
    if (stage === 'done') t.due = dayStr(-(1 + (doneN % 6)));
    else t.due = dayStr(DUE[(i * 7) % DUE.length]);
    if (i % 4 === 1 && stage !== 'done') t.start = dayStr(DUE[(i * 7) % DUE.length] - 3);
    if (i % 5 === 0) Object.assign(t.prio, Object.fromEntries(assignees.slice(0, 1).map((u) => [u, 1 + (i % 3)])));
    if (SOCIAL_CLIENTS.has(pid) && stage !== 'done') { t.channels = [['ig'], ['ig', 'tt'], ['ig', 'fb'], ['li'], ['tt']][i % 5]; t.golive = dayStr(DUE[(i * 7) % DUE.length] + 2); }
    // two posts for UAE National Day on the Content calendar
    if (SOCIAL_CLIENTS.has(pid) && stage === 'prog' && i % 6 === 2) { const d = new Date(); const y = d.getMonth() === 11 && d.getDate() > 3 ? d.getFullYear() + 1 : d.getFullYear(); t.golive = `${y}-12-02`; t.occasion = `nationalday-${y}`; t.channels = ['ig', 'tt']; }
    if (/content plan|cp\b|plan$/i.test(s.title)) t.checklist = ['Pull last month’s insights', 'Draft the post list', 'Share with the AM'].map((x, k) => ({ id: `${id}-cl${k}`, text: x, done: k === 0 }));

    // files on the task, and in the comments
    const att = (m, k, by, at, extra = {}) => { const rel = `attachments/${id}/${m.name.replace(/[/:\\]/g, '-')}`; const size = filesRoot ? putFile(rel, new URL(m.key, MEDIA)) : 0; return { id: `${id}-f${k}`, name: m.name, path: rel, size, addedAt: at, addedBy: by, ...extra }; };
    // comments: spread from when it was created to a few hours ago, in order
    const n = s.comments.length;
    const span = createdDays * 24 - 2;
    s.comments.forEach((c, k) => {
      const at = ago(span - (span - 1.5) * ((k + 1) / (n + 1)) + rnd());
      const who = has(ME(c.who)) ? ME(c.who) : am;
      const mentioned = [];
      const cid = `${id}-c${k}`;
      const files = (c.media || []).map((m, j) => ({ ...att(m, `c${k}-${j}`, who, at), id: `${cid}-a${j}` }));
      t.comments.push({ id: cid, text: c.text, html: html(c.text, mentioned), at, attachments: files, parentId: null, reactions: c.reacts ? { '👍': c.reacts } : {}, authorId: who });
      [...new Set(mentioned)].forEach((u) => notify(u, who, t, 'mention', 'mentioned you in a comment on', { at, commentId: cid, snippet: c.text.slice(0, 160), read: k < n - 3 }));
    });
    // tasks without a conversation in ClickUp get a short, plausible one
    if (!n) {
      const a = assignees[0];
      const lines = [[am, `Hi ${'@' + nameOf(a)}, brief is in the description. Please share a first direction by ${t.due ? 'the due date' : 'end of week'}.`], [a, 'Noted, working on it now.']];
      if (stage === 'todo') lines.pop();
      lines.forEach(([who, text], k) => { const mentioned = []; const at = ago(span * (k ? 0.4 : 0.8)); t.comments.push({ id: `${id}-g${k}`, text, html: html(text, mentioned), at, attachments: [], parentId: null, reactions: k ? { '👍': 1 } : {}, authorId: who }); mentioned.forEach((u) => notify(u, who, t, 'mention', 'mentioned you in a comment on', { at, commentId: `${id}-g${k}`, snippet: text })); });
    }
    // a reply thread on some conversations
    const top = t.comments.find((c) => c.authorId !== assignees[0]);
    if (top && i % 3 === 0 && assignees[0]) {
      t.comments.push({ id: `${id}-r1`, text: 'On it — will share the update shortly.', html: 'On it — will share the update shortly.', at: ago(3 + (i % 5)), attachments: [], parentId: top.id, reactions: {}, authorId: assignees[0] });
    }
    const taskFiles = s.media.map((m, k) => att(m, k, assignees[0] || am, ago(24 * Math.max(1, createdDays - 2))));

    // ---------- the stage ----------
    const by = assignees.find((u) => u !== cd) || assignees[0];
    const review = (state, round, at, files, extra = {}) => ({ id: `${id}-rv${round}`, by, at, files: files.map((f) => f.id), state, epoch: extra.epoch || 0, round, ...(state !== 'pending' ? { decidedAt: extra.decidedAt || ago(1), decidedBy: cd } : {}), ...(extra.noteHtml ? { noteHtml: extra.noteHtml } : {}) });
    const withReview = (f, rid) => ({ ...f, reviewId: rid });
    const files = taskFiles.length ? taskFiles : [];
    const half = Math.max(1, Math.ceil(files.length / 2));
    const approve = (round, at, list, epoch = 0) => {
      const r = review('approved', round, at, list, { decidedAt: at, epoch });
      t.partsDone[by] = at;
      // the submitter posts the approved files for the person who created the task
      t.comments.push({ id: `${id}-ok${round}`, text: 'Here are the final files (Approved) by the CD, ready to be sent to client for review.', html: `Hello <span class="mention" data-user="${t.createdBy}" contenteditable="false">@${esc(nameOf(t.createdBy))}</span>, here are the final files (<b>Approved</b>) by the CD, ready to be sent to client for review.`, at, attachments: list.map((f, j) => ({ ...f, id: `${id}-okf${round}-${j}`, linked: true })), parentId: null, reactions: {}, authorId: by, auto: true });
      return r;
    };
    if (stage === 'todo') { t.sectionId = sec(pid, 0); t.needsCD = pid !== 'p-e11'; t.attachments = files; }
    else if (stage === 'prog') { t.needsCD = !/content plan|cp\b|plan$|headshots|summary|strategy/i.test(s.title); t.attachments = files; if (s.status === 'ON HOLD') t.update = 'On hold'; }
    else if (stage === 'review') {
      // files waiting for the Creative Director (Review Requests)
      t.needsCD = true; t.sectionId = sec(pid, 2); t.cdStatus = 'review';
      const sub = (files.length ? files : []).slice(0, 3).map((f) => withReview(f, `${id}-rv1`));
      const at = ago(2 + reviewN * 3);
      t.reviews = [review('pending', 1, at, sub)];
      t.attachments = files.map((f) => sub.find((x) => x.id === f.id) || f);
      if (!sub.length) {
        // nothing of its own in ClickUp: a real piece of work from the same client (or any client) goes in
        const other = STORY.tasks.find((x) => (CLIENT_OF[x.client] || 'p-e11') === pid && x.media.length && x.key !== s.key) || STORY.tasks.find((x) => x.media.length && x.key !== s.key);
        const m = other.media[i % other.media.length];
        const ph = { ...att(m, 'r', by, at), reviewId: `${id}-rv1` };
        t.attachments.push(ph); t.reviews[0].files = [ph.id];
      }
      notify(cd, by, t, 'review', `submitted ${t.reviews[0].files.length === 1 ? '1 file' : t.reviews[0].files.length + ' files'} for your review on`, { at, read: reviewN > 1 });
      reviewN++;
    } else if (stage === 'amend') {
      t.needsCD = true;
      if (amendN % 2 === 0) {
        // the CD asked for amendments (this round)
        const sub = files.slice(0, half).map((f) => withReview(f, `${id}-rv1`));
        const at = ago(30 + amendN * 5), dec = ago(20 + amendN * 4);
        const note = CD_NOTES[amendN % CD_NOTES.length];
        t.reviews = [review('amend', 1, at, sub, { decidedAt: dec, noteHtml: esc(note) })];
        t.attachments = files.map((f) => sub.find((x) => x.id === f.id) || f);
        const cid = `${id}-am`;
        t.comments.push({ id: cid, text: 'Amendments required: ' + note, html: `<b>Amendments required</b> for <span class="mention" data-user="${by}" contenteditable="false">@${esc(nameOf(by))}</span><br>${esc(note)}`, at: dec, attachments: [], parentId: null, reactions: {}, authorId: cd });
        notify(by, cd, t, 'review-amend', 'requested amendments on your submission for', { at: dec, commentId: cid, snippet: note });
        t.update = 'Amendments';
      } else {
        // approved by the CD, sent to the client, and the client asked for changes: a new round needs CD review again
        const sub = files.slice(0, half).map((f) => withReview(f, `${id}-rv1`));
        const at = ago(24 * 4), dec = ago(24 * 4 - 3);
        t.reviews = [approve(1, dec, sub)];
        t.reviews[0].at = at;
        t.reviewEpoch = 1; t.partsDone = {}; t.cdStatus = '';
        t.attachments = files.map((f) => sub.find((x) => x.id === f.id) || f);
        t.activity.push({ id: `${id}-ac1`, at: ago(30), text: 'sent it back for changes — <b>needs CD review again</b>', actor: am });
        t.update = 'Amendments';
      }
      amendN++;
    } else if (stage === 'ctr') {
      // CD approved, with the client: about half have the client's approval recorded
      t.needsCD = true; t.sectionId = sec(pid, 3); t.cdStatus = 'approved';
      const sub = files.slice(0, half).map((f) => withReview(f, `${id}-rv1`));
      const dec = ago(6 + ctrN * 7);
      t.reviews = [review('approved', 1, ago(10 + ctrN * 7), sub, { decidedAt: dec })];
      t.partsDone[by] = dec;
      if (!sub.length) { t.needsCD = false; t.cdStatus = 'approved'; }
      t.attachments = files.map((f) => sub.find((x) => x.id === f.id) || f);
      notify(by, cd, t, 'review-ok', 'approved your files for', { at: dec, read: ctrN > 1 });
      notify(t.createdBy, cd, t, 'review-ok', 'approved all files — it moved to CTR:', { at: dec, read: ctrN > 2 });
      if (ctrN % 2 === 1) t.clientApproval = { by: am, at: ago(2 + ctrN) };
      ctrN++;
    } else if (stage === 'done') {
      // completed: CD approved, client approved, final files filed in Client Assets
      t.needsCD = true; t.sectionId = sec(pid, 4); t.cdStatus = 'approved'; t.done = true;
      const doneAt = ago(24 * (1 + doneN * 2) + 4);
      t.completedAt = doneAt;
      const sub = files.slice(0, Math.max(1, files.length - 1)).map((f) => withReview(f, `${id}-rv1`));
      const dec = ago(24 * (2 + doneN * 2));
      t.reviews = [review('approved', 1, ago(24 * (3 + doneN * 2)), sub, { decidedAt: dec })];
      t.partsDone[by] = dec;
      t.attachments = files.map((f) => sub.find((x) => x.id === f.id) || f);
      t.clientApproval = doneN === 2 ? { none: true, by: am, at: doneAt } : { by: am, at: new Date(Date.parse(doneAt) - 3 * 3600000).toISOString() };
      t.finance = t.finance || 'To be invoiced'; t.financeAt = doneAt; t.financeBy = am;
      notify(by, am, t, 'done', 'completed', { at: doneAt, read: true });
      doneN++;
    }
    if (t.attachments.length === 0 && files.length) t.attachments = files;
    // the person who created it hears about the latest comments from others
    t.comments.filter((c) => !c.parentId && c.authorId !== t.createdBy).slice(-2).forEach((c, k) => notify(t.createdBy, c.authorId, t, 'comment', 'commented on', { at: c.at, commentId: c.id, snippet: c.text.slice(0, 160), read: k === 0 && i % 2 === 0 }));
    t.activity.unshift({ id: `${id}-ac0`, at: t.createdAt, text: 'created this task', actor: t.createdBy });
    assignees.forEach((u) => notify(u, t.createdBy, t, 'assigned', 'assigned you to', { at: ago(24 * createdDays), read: createdDays > 4 }));
    tasks.push(t);
  });

  // the freelancer works on two open Ford & Lincoln tasks
  tasks.filter((t) => t.projectId === 'p-ford' && !t.done).slice(0, 2).forEach((t) => { t.assignees = [...new Set([...t.assignees, free.id])]; });
  // a few subtasks
  tasks.filter((t) => !t.done && /campaign|emailers|plan/i.test(t.title)).slice(0, 4).forEach((t, k) => {
    ['English version', 'Arabic adaptation'].forEach((x, j) => tasks.push({ id: `${t.id}-s${j}`, title: x, projectId: null, sectionId: t.sectionId, parentId: t.id, assignees: t.assignees.slice(0, 1), createdBy: t.createdBy, createdAt: t.createdAt, updatedAt: t.updatedAt, due: t.due, done: j === 0 && k % 2 === 0, completedAt: j === 0 && k % 2 === 0 ? ago(20) : null, notes: '', notesHtml: '', tags: [], comments: [], attachments: [], activity: [], checklist: [], prio: {}, order: j + 1 }));
  });
  // the inactive client's tasks
  ['Palm Jebel Ali | Teaser 30s', 'Nakheel Mall | Ramadan Key Visual', 'Dragon City | Social Pack'].forEach((title, i) => tasks.push({
    id: `smp-nk-${i}`, title, projectId: nak.id, sectionId: sec(nak.id, i === 2 ? 4 : 0), parentId: null, assignees: ['u-ali'].filter(has), createdBy: 'u-lana', createdAt: ago(24 * (200 - i * 10)), updatedAt: ago(24 * 120),
    due: dayStr(-110 + i * 5), done: i === 2, completedAt: i === 2 ? ago(24 * 115) : null, notes: '', notesHtml: '', tags: [], comments: [], attachments: [], activity: [], checklist: [], prio: {}, order: i,
  }));
  out.tasks = tasks.concat(keepFinance);

  // ---------- Client Assets: a folder per client (Logos, Brand Guidelines, Fonts, Files), job folders, final files ----------
  out.clients = out.projects.map((p) => {
    const at = p.createdAt;
    const dir = `Clients/${p.name.replace(/[/:\\]/g, '-')}`;
    const folders = ['Logos', 'Brand Guidelines', 'Fonts', 'Files'].map((n) => ({ id: `cf-${p.id}-${n.replace(/\W+/g, '').toLowerCase()}`, name: n, dir: `${dir}/${n}`, files: [], createdAt: at, createdBy: me, auto: true }));
    if (filesRoot) folders.forEach((f) => fs.mkdirSync(path.join(filesRoot, ...f.dir.split('/')), { recursive: true }));
    const am = ((p.ams || [])[0] || {}).id || me;
    const add = (f, name, src, by, hoursAgo, data) => { const rel = `${f.dir}/${name}`; const size = filesRoot ? (data ? putData(rel, data) : putFile(rel, src)) : 0; f.files.push({ id: `${f.id}-${f.files.length}`, name, path: rel, size, addedAt: ago(hoursAgo), addedBy: by }); };
    add(folders[0], `${p.name} logo.svg`, null, am, 24 * 40, LOGO(p.name, p.color));
    if (['p-ford', 'p-kia', 'p-alain', 'p-hre'].includes(p.id)) add(folders[1], `${p.name} brand guidelines.pdf`, new URL('creative-brief.pdf', SRC), am, 24 * 35);
    p.clientId = `cl-${p.id}`;
    return { id: `cl-${p.id}`, name: p.name, logo: null, dir, folders, createdAt: at, createdBy: me };
  });
  const clientOf = (pid) => out.clients.find((c) => c.id === `cl-${pid}`);
  // a job folder inside Files with the latest work (and one a step deeper), on the busier clients
  [['p-kia', 'Q4 Family Cars Campaign', ['Shoot selects']], ['p-deepal', 'S09 Pre-Book Campaign', []], ['p-ford', 'Tactical Always On', ['Landing page banners']], ['p-gm', 'Automechanika', []]].forEach(([pid, name, subs]) => {
    const c = clientOf(pid); if (!c) return;
    const top = c.folders.find((f) => f.name === 'Files');
    const t = tasks.find((x) => x.projectId === pid && !x.done && x.attachments.length);
    const by = t ? t.assignees[0] || me : me;
    const mk = (parent, nm) => { const f = { id: `cf-${pid}-${nm.replace(/\W+/g, '').toLowerCase()}`, name: nm, dir: `${parent.dir}/${nm}`, files: [], createdAt: ago(24 * 6), createdBy: by, parentId: parent.id }; c.folders.push(f); return f; };
    const job = mk(top, name);
    (t ? t.attachments.slice(0, 2) : []).forEach((a, k) => { const rel = `${job.dir}/${a.name}`; const size = filesRoot ? putFile(rel, path.join(filesRoot, ...a.path.split('/'))) : 0; job.files.push({ id: `${job.id}-${k}`, name: a.name, path: rel, size, addedAt: ago(24 * 2 + k), addedBy: by }); });
    subs.forEach((nm) => mk(job, nm));
  });
  // completed tasks: their final files, filed the way the app files them (Files › <task>, with the approval details)
  tasks.filter((t) => t.done && !t.parentId && t.reviews && t.reviews.length && t.projectId !== nak.id).forEach((t) => {
    const c = clientOf(t.projectId); if (!c) return;
    const top = c.folders.find((f) => f.name === 'Files');
    const r = t.reviews[t.reviews.length - 1];
    const picked = t.attachments.filter((a) => r.files.includes(a.id));
    if (!picked.length) return;
    const fdir = `${top.dir}/${t.title.replace(/[/:\\]/g, '-').slice(0, 80)}`;
    const folder = { id: `cf-final-${t.id}`, name: t.title, dir: fdir, files: [], createdAt: t.completedAt, createdBy: t.createdBy, auto: true, parentId: top.id, finalOf: t.id };
    picked.forEach((a, k) => {
      const rel = `${fdir}/${a.name}`;
      let size = 0;
      if (filesRoot) { const src = path.join(filesRoot, ...a.path.split('/')); const dest = path.join(filesRoot, ...rel.split('/')); fs.mkdirSync(path.dirname(dest), { recursive: true }); try { fs.linkSync(src, dest); } catch (e) { fs.copyFileSync(src, dest); } size = fs.statSync(dest).size; }
      const ca = t.clientApproval || {};
      folder.files.push({ id: `caf-final-${t.id}-${k}`, name: a.name, path: rel, size, addedAt: t.completedAt, addedBy: r.by,
        final: { taskId: t.id, taskTitle: t.title, completedAt: t.completedAt, createdBy: t.createdBy, assignee: r.by, cdBy: r.decidedBy, cdAt: r.decidedAt, clientBy: ca.none ? null : ca.by || null, clientAt: ca.none ? null : ca.at || null, clientNone: !!ca.none, srcId: a.id } });
    });
    c.folders.push(folder);
    // one Inbox update for the team about it
    [...new Set([...t.assignees, t.createdBy, me])].forEach((u) => { if (has(u) && u !== t.createdBy) notifs.push({ id: `smp-nf-${t.id}-${u}`, to: u, from: t.createdBy, kind: 'asset', clientId: c.id, folderId: folder.id, text: `filed the final files for “${t.title}” in ${c.name} › Files`, snippet: `${folder.files.length} file${folder.files.length === 1 ? '' : 's'}`, at: t.completedAt, read: false }); });
  });
  // a Client Assets update
  { const c = clientOf('p-kia'); const f = c && c.folders.find((x) => x.name === 'Logos'); if (f) [me, 'u-sara', 'u-ali'].filter(has).forEach((to, i) => notifs.push({ id: `smp-nas-${i}`, to, from: 'u-lina', kind: 'asset', clientId: c.id, folderId: f.id, text: `added a file to ${c.name} › Logos`, snippet: f.files[0] ? f.files[0].name : '', at: ago(5 + i), read: false })); }

  // ---------- content plans (trial): Amelia is Social Manager; Aishwarya and Maria are the Social Executives ----------
  const mgr = 'u-maya', exec = 'u-aish', exec2 = 'u-new';
  const SOCIALS = { 'p-korea': [exec], 'p-asv': [exec], 'p-cpt': [exec2] };   // (for now only these clients have Social people)
  out.projects.forEach((p) => { const s = (SOCIALS[p.id] || []).filter(has); if (s.length) p.socials = s; });
  out.plans = [];
  if (has(exec) && has(exec2)) {
    const nm = (() => { const d = new Date(today0); return new Date(d.getFullYear(), d.getMonth() + 1, 1); })();
    const month = `${nm.getFullYear()}-${String(nm.getMonth() + 1).padStart(2, '0')}`;
    const day = (n) => `${month}-${String(Math.min(n, new Date(nm.getFullYear(), nm.getMonth() + 1, 0).getDate())).padStart(2, '0')}`;
    // the fixed-date occasions of that month (the app has the full list; these link a few posts to them)
    const FIXED = { '01-01': ['newyear', 'New Year’s Day'], '02-14': ['valentine', 'Valentine’s Day'], '03-08': ['womensday', 'Women’s Day'], '03-21': ['mothersday', 'Mother’s Day'], '10-31': ['halloween', 'Halloween'], '11-30': ['commemoration', 'Commemoration Day'], '12-02': ['nationalday', 'UAE National Day'], '12-25': ['christmas', 'Christmas'], '12-31': ['nye', 'New Year’s Eve'] };
    const occs = Object.entries(FIXED).filter(([md]) => md.slice(0, 2) === month.slice(5)).map(([md, [k, name]]) => ({ id: `${k}-${month.slice(0, 4)}`, day: `${month.slice(0, 4)}-${md}`, name }));
    const refFile = (plId, key) => {
      if (!filesRoot) return null;
      try { const rel = `attachments/${plId}/${key}`; const size = putFile(rel, new URL(key, MEDIA)); return { id: `pr-${plId}-${key}`, name: key, path: rel, size, addedAt: ago(30) }; } catch (e) { return null; }
    };
    const mk = (pid, by, posts, startedHours) => {
      const id = `pl-smp-${pid}`;
      const pl = { id, projectId: pid, month, status: 'draft', createdBy: by, createdAt: ago(startedHours), updatedAt: ago(2), posts: [] };
      posts.forEach((x, i) => {
        const refs = (x.refs || []).map((k) => refFile(id, k)).filter(Boolean).concat((x.links || []).map((u, j) => ({ id: `pr-${id}-l${i}-${j}`, url: u, label: u.replace(/^https?:\/\/(www\.)?/, '').slice(0, 50) })));
        pl.posts.push({ id: `pp-${id}-${i}`, day: x.day, title: x.title, desc: x.desc || '', format: x.format || 'post', channels: x.ch || ['ig'], occasion: x.occ || null, shots: x.shots || '', copyEn: x.en || '', copyAr: x.ar || '', refs, createdBy: by, createdAt: ago(startedHours - i), updatedAt: ago(startedHours - i) });
      });
      out.plans.push(pl);
    };
    const occ0 = occs[0], occ1 = occs[1];
    const koreaPosts = [
      { day: day(1), title: 'This month at KOREA 360', format: 'carousel', ch: ['ig', 'fb'], desc: 'What’s on this month, one event per slide: K-food week, K-pop night, the beauty corner and the photo booth.', en: 'A whole month of Korea, right here in Dubai. Swipe to see what’s coming.', ar: 'شهر كامل من كوريا هنا في دبي. اسحب لترى ما ينتظرك.', shots: 'Event key visuals, one per slide; end slide with dates and location.' },
      { day: day(5), title: 'K-food week', format: 'reel', ch: ['ig', 'tt'], desc: 'Tasting reel at the food stalls: tteokbokki, Korean fried chicken, bingsu.', shots: '1. Sizzling pan, close-up (2s)\n2. Stall owner serving (2s)\n3. First bite, reaction (3s)\n4. Wide of the food hall (3s)\n5. End card with dates (2s)', en: 'Hungry? K-food week starts today.', links: ['https://www.instagram.com/explore/tags/kfood/'] },
      { day: day(9), title: 'K-pop night', format: 'reel', ch: ['ig', 'tt', 'yt'], desc: 'Dance cover crew on stage, crowd singing along. Night lighting like the reference.', en: 'Bring your lightstick. K-pop night is back.', refs: ['cu04.jpg'] },
      { day: day(12), title: 'K-beauty corner', format: 'post', ch: ['ig'], desc: 'Flat lay of the products at the beauty corner, soft pastel set.', en: 'Glass skin, sorted. Visit the K-beauty corner this weekend.' },
      { day: day(18), title: 'Hanbok photo booth', format: 'story', ch: ['ig', 'sc'], desc: 'Story series: visitors in hanbok at the photo booth, with a poll sticker.' },
      { day: day(24), title: 'Win a trip to Seoul', format: 'post', ch: ['ig', 'fb'], desc: 'Giveaway announcement: follow, tag two friends, share to story.', en: 'Win a trip for two to Seoul. Follow, tag two friends and share to your story to enter. T&Cs apply.' },
    ];
    if (occ0) koreaPosts.push({ day: occ0.day, title: occ0.name, format: 'reel', ch: ['ig', 'tt'], occ: occ0.id, desc: `A short greeting film for ${occ0.name} with the KOREA 360 team.`, en: `Happy ${occ0.name} from KOREA 360.` });
    mk('p-korea', exec, koreaPosts, 50);
    // KOREA 360's skeleton is waiting for the Social Manager's approval
    { const k = out.plans.find((x) => x.projectId === 'p-korea'); if (k && has(mgr)) {
      Object.assign(k, { status: 'review', round: 1, review: { to: 'sm', by: exec, at: ago(3), round: 1 }, log: [{ act: 'sent', by: exec, at: ago(3), to: 'sm', round: 1 }] });
      notifs.push({ id: 'smp-npl-1', to: mgr, from: exec, kind: 'plan', planId: k.id, text: `sent the content skeleton for <b>KOREA 360 · ${nm.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })}</b> for your approval`, snippet: '', at: ago(3), read: false });
    } }
    mk('p-cpt', exec2, [
      { day: day(3), title: 'Highlights of the month', format: 'reel', ch: ['ig', 'tt'], desc: 'Fast-cut highlights from last month’s events.' },
      { day: day(10), title: 'Behind the scenes', format: 'carousel', ch: ['ig', 'li'], desc: 'The team setting up, five photos.' },
      { day: day(21), title: 'Customer stories', format: 'video', ch: ['ig', 'yt'], desc: 'Two short interviews with customers.' },
    ].concat(occ1 ? [{ day: occ1.day, title: occ1.name, format: 'post', ch: ['ig', 'fb'], occ: occ1.id }] : []), 30);
  }
  // the Creative Director is Carine; Amelia is Social Manager (content plans trial)
  out.meta = { ...(out.meta || {}), cdUserId: has(cd) ? cd : (out.meta || {}).cdUserId || null, ...(has(mgr) ? { socialMgrIds: [mgr] } : {}) };
  const ids = new Set([me, ...out.users.map((u) => u.id), ...store.list('users').map((u) => u.id)]);
  out.notifications = notifs.filter((x) => ids.has(x.to));
  return out;
}
