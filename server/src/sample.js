// Sample data for the test copy: E11 people, projects, tasks, comments with replies and Inbox
// updates, moved so they happen around today. The person who asks becomes "Haris" in the story.
import fs from 'node:fs';
import path from 'node:path';

const REF_DAY = Date.UTC(2026, 9, 20); // the day the sample story was written
const DAY = 86400000;
const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export function sampleData(store, me, filesRoot = null) {
  const raw = fs.readFileSync(new URL('./sample-data.json', import.meta.url), 'utf8');
  // Sample people already on the team (same email, e.g. from an earlier fill) keep their existing id,
  // so their comments, tasks and reviews point at a real person instead of a "Former member"
  const byEmail = new Map(store.list('users').map((u) => [String(u.email || '').toLowerCase(), u.id]));
  let text = raw.split('"u-haris"').join(JSON.stringify(me));
  JSON.parse(raw).users.forEach((u) => {
    const id = byEmail.get(String(u.email || '').toLowerCase());
    if (id && id !== u.id && u.id !== 'u-haris') text = text.split(JSON.stringify(u.id)).join(JSON.stringify(id));
  });
  const d = JSON.parse(text);
  const now = new Date();
  const shift = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) - REF_DAY;
  const move = (v) => {
    if (typeof v === 'string') {
      if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return new Date(Date.parse(v + 'T00:00:00Z') + shift).toISOString().slice(0, 10);
      if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v)) return new Date(Date.parse(v) + shift).toISOString();
      return v;
    }
    if (Array.isArray(v)) return v.map(move);
    if (v && typeof v === 'object') { const o = {}; for (const [k, x] of Object.entries(v)) o[k] = move(x); return o; }
    return v;
  };
  const out = move(d);

  // people: skip anyone already on the team (same email), and the asker
  const have = new Set(store.list('users').map((u) => String(u.email || '').toLowerCase()));
  // everyone in the sample story (new or already on the team), for comments, Finance and reviews below
  const cast = out.users.filter((u) => u.id !== me && u.name);
  out.users = out.users.filter((u) => u.id !== me && u.name && !have.has(String(u.email || '').toLowerCase()))
    .map((u) => ({ ...u, setup: true, office: u.office || 'Dubai — Business Bay office' }));
  const known = new Set([me, ...store.list('users').map((u) => u.id), ...out.users.map((u) => u.id)]);

  // no files in the sample (they'd point at files that aren't on this server)
  out.tasks.forEach((t) => { t.attachments = []; (t.comments || []).forEach((c) => { c.attachments = []; }); (t.reviews || []).length = 0; });

  // a few threads with replies, some mentioning you
  const others = cast.map((u) => u.id);
  const pick = (i) => others[i % others.length];
  const mention = (id, name) => `<span class="mention" data-user="${id}" contenteditable="false">@${name}</span>`;
  const meUser = store.get('users', me) || {};
  const meName = meUser.name || String(meUser.email || 'you').split('@')[0];
  let n = 0;
  out.tasks.filter((t) => !t.parentId && !t.done).slice(0, 6).forEach((t, i) => {
    let top = (t.comments || []).find((c) => !c.parentId);
    const at = (h) => new Date(Date.now() - h * 3600000).toISOString();
    if (!top) {
      top = { id: `smp-c${i}`, text: 'Kick-off notes are in the brief. Shout if anything is unclear.', html: 'Kick-off notes are in the brief. Shout if anything is unclear.', at: at(30 - i), attachments: [], parentId: null, reactions: {}, authorId: pick(i) };
      t.comments = (t.comments || []).concat(top);
    }
    const a = pick(i + 1), b = pick(i + 2);
    t.comments.push(
      { id: `smp-r${i}a`, text: 'On it — first draft by this afternoon.', html: 'On it — first draft by this afternoon.', at: at(20 - i), attachments: [], parentId: top.id, reactions: { '👍': 1 }, authorId: a },
      { id: `smp-r${i}b`, text: `@${meName} can you check the copy before it goes to the client?`, html: `${mention(me, meName)} can you check the copy before it goes to the client?`, at: at(6 - i / 2), attachments: [], parentId: top.id, reactions: {}, authorId: b },
    );
    out.notifications.push({ id: `smp-n${i}`, to: me, from: b, taskId: t.id, kind: 'mention', text: 'mentioned you in a reply on', snippet: `@${meName} can you check the copy before it goes to the client?`, commentId: `smp-r${i}b`, at: at(6 - i / 2), read: false });
    n++;
  });

  // ---------- Finance sample: statuses on tasks, extra finished jobs, Finance people and expense records ----------
  const STATUSES = ['Quote to be sent', 'LPO Pending', 'Invoiced', 'Retainer', 'To be invoiced'];
  const UPDATES = ['WIP', 'Brief to come', 'Amendments', 'Shoot', 'Edit Video', 'Ready to Post', 'On hold', 'Awaiting client assets', 'Storyboard', 'Mockup'];
  const iso = (daysAgo, h = 10) => new Date(Date.now() - daysAgo * DAY + (h - 12) * 3600000).toISOString();
  const dayStr = (daysAgo) => iso(daysAgo).slice(0, 10);
  let seed = 7;
  const rnd = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; };
  const prodIds = cast.filter((u) => ['production', 'social'].includes(u.role)).map((u) => u.id);
  const AMS = cast.filter((u) => u.role === 'am').map((u) => u.id).concat(me).slice(0, 5);
  out.tasks.filter((t) => !t.parentId).forEach((t, i) => {
    if (i % 5 !== 4) { t.finance = STATUSES[i % STATUSES.length]; t.financeAt = iso(Math.floor(rnd() * 150)); t.financeBy = AMS[i % AMS.length]; }
    t.update = UPDATES[i % UPDATES.length];
    if (prodIds.length && i % 3 === 0) t.guardian = prodIds[i % prodIds.length];
  });
  // finished jobs from the last six months, so the Finance graphs have something to show
  const projects = (out.projects || []).map((p) => p.id);
  const jobs = ['Social Reel', 'Print Ad', 'EDM', 'Launch Video', 'Story Pack', 'Photo Shoot', 'Key Visual', 'Brochure', 'Event Recap', 'Teaser 15s'];
  for (let i = 0; i < 36 && projects.length; i++) {
    const p = (out.projects || [])[i % projects.length];
    const proj = projects[i % projects.length];
    const sec = (p.sections || []).find((x) => /done|complete|ctr/i.test(x.name)) || (p.sections || [])[0];
    const daysAgo = Math.floor(rnd() * 170);
    const st = rnd() < 0.45 ? 'Invoiced' : STATUSES[Math.floor(rnd() * STATUSES.length)];
    out.tasks.push({
      id: `smp-fin-t${i}`, title: `${p.name} | ${jobs[i % jobs.length]} ${['A', 'B', 'C', 'D'][i % 4]}`, projectId: proj, sectionId: sec ? sec.id : null, parentId: null,
      assignees: prodIds.length ? [prodIds[i % prodIds.length]] : [], createdBy: me, createdAt: iso(daysAgo + 14), updatedAt: iso(Math.min(daysAgo, 20)),
      ...((doneAgo) => ({ due: dayStr(i % 7 === 3 ? doneAgo + 2 : doneAgo - (i % 3)), completedAt: iso(doneAgo) }))(Math.floor(rnd() * 20) + 1), done: true, notes: '', notesHtml: '', tags: [], comments: [], attachments: [], activity: [], checklist: [],
      finance: st, financeAt: iso(daysAgo), financeBy: AMS[i % AMS.length], update: 'Ready to Post', order: 1000 + i,
    });
  }
  // two Finance-only people
  [['u-smp-fin-a', 'Rania Haddad', 'rania.finance@e11-digital.com', 'finance_admin', 'Finance Manager'], ['u-smp-fin-v', 'Omar Saleh', 'omar.accounts@e11-digital.com', 'finance_viewer', 'Accountant']]
    .forEach(([id, name, email, role, designation]) => { if (!have.has(email)) out.users.push({ id, name, email, role, designation, active: true, setup: true, avatar: null, prefs: {}, createdAt: iso(200), office: 'Dubai — Business Bay office' }); });
  // expense records: subscriptions, staff reimbursements, office expenses
  const monthKey = (d) => d.toISOString().slice(0, 7);
  const sixAgo = new Date(); sixAgo.setUTCDate(1); sixAgo.setUTCMonth(sixAgo.getUTCMonth() - 5);
  out.finance = [
    ['Adobe Creative Cloud (team)', 1250, 3], ['Figma Professional', 540, 8], ['Google Workspace', 1100, 1], ['Frame.io', 220, 15], ['Envato Elements', 120, 20], ['Office internet', 650, 25],
  ].map(([name, amount, day], i) => ({ id: `smp-fin-s${i}`, type: 'sub', name, amount, day, startMonth: monthKey(sixAgo), endedAt: null, invoices: {}, createdAt: iso(185), createdBy: 'u-smp-fin-a' }));
  out.finance.push({ id: 'smp-fin-p0', type: 'person', name: 'Omar (driver)', createdAt: iso(160), createdBy: 'u-smp-fin-a' },
    { id: 'smp-fin-p1', type: 'person', name: 'Studio Lights Rental LLC', createdAt: iso(120), createdBy: 'u-smp-fin-a' });
  const reasons = [['Taxi to client shoot', 85], ['Props for Ford shoot', 340], ['Team lunch — ALAIN launch', 420], ['Parking at Expo City', 60], ['Printing samples', 180], ['Fuel — location scout', 150]];
  for (let i = 0; i < 26; i++) {
    const [, amt] = reasons[i % reasons.length];
    const who = i % 5 === 0 ? { personId: 'smp-fin-p0', personName: 'Omar (driver)' } : { userId: prodIds[i % Math.max(1, prodIds.length)] || me };
    out.finance.push({ id: `smp-fin-r${i}`, type: 'reimb', ...who, amount: amt + Math.round(rnd() * 60), date: dayStr(Math.floor(rnd() * 175)), invoice: null, note: reasons[i % reasons.length][0], createdAt: iso(1), createdBy: 'u-smp-fin-a' });
  }
  const big = [['Camera lens — Sony 24-70mm', 8900], ['Studio rental (2 days)', 4200], ['Drone pilot', 2500], ['Stock music licence', 950], ['Print run — brochures', 3600], ['Laptop for new hire', 6200], ['Event booth build', 12500], ['Lighting kit', 3100]];
  for (let i = 0; i < 18; i++) {
    const [name, amt] = big[i % big.length];
    out.finance.push({ id: `smp-fin-e${i}`, type: 'expense', name, amount: Math.round(amt * (0.85 + rnd() * 0.3)), date: dayStr(Math.floor(rnd() * 175)), invoice: null, createdAt: iso(1), createdBy: 'u-smp-fin-a' });
  }

  // ---------- Sample files: real small files copied into the data folder ----------
  if (filesRoot) {
    const SRC = new URL('./sample-files/', import.meta.url);
    const size = (n) => fs.statSync(new URL(n, SRC)).size;
    const put = (name, rel) => {
      const dest = path.join(filesRoot, ...rel.split('/'));
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      if (!fs.existsSync(dest)) fs.copyFileSync(new URL(name, SRC), dest);
      return { name, path: rel, size: size(name) };
    };
    const SETS = [
      ['ford-key-visual.jpg', 'creative-brief.pdf', 'copy-deck.docx'],
      ['alain-tower-render.jpg', 'client-presentation.pptx'],
      ['teaser-rough-cut.mp4', 'story-frame-1.png'],
      ['korea360-recap-cover.jpg', 'media-plan.xlsx'],
      ['creative-brief.pdf', 'story-frame-1.png', 'ford-key-visual.jpg'],
      ['client-presentation.pptx', 'teaser-rough-cut.mp4'],
    ];
    const by = cast.length ? cast.map((u) => u.id) : [me];
    out.tasks.filter((t) => !t.parentId && !String(t.id).startsWith('smp-fin-')).slice(0, 10).forEach((t, i) => {
      t.attachments = SETS[i % SETS.length].map((name, k) => ({ id: `smp-a-${t.id}-${k}`, ...put(name, `attachments/${t.id}/${name}`), addedAt: iso(3 + k), addedBy: by[(i + k) % by.length] }));
      const c = (t.comments || []).find((x) => !x.parentId);
      if (c && i % 2 === 0) {
        const name = ['story-frame-1.png', 'alain-tower-render.jpg', 'korea360-recap-cover.jpg'][i % 3];
        c.attachments = [{ id: `smp-ca-${c.id}`, ...put(name, `attachments/${t.id}/${name}`), addedAt: c.at }];
      }
    });
    // files waiting for the Creative Director (Reviews page): a pending submission on three open tasks
    const cdNow = (store.get('meta', 'main') || {}).cdUserId || 'u-karim';
    const REV = [['ford-key-visual.jpg', 'story-frame-1.png'], ['teaser-rough-cut.mp4'], ['alain-tower-render.jpg', 'creative-brief.pdf']];
    out.tasks.filter((t) => !t.parentId && !t.done && t.projectId && (t.assignees || []).some((u) => u !== cdNow)).slice(1, 4).forEach((t, i) => {
      const by = t.assignees.find((u) => u !== cdNow);
      const id = `smp-rp${i}`;
      const at = iso(0, 7 + i);
      const files = REV[i].map((name, k) => ({ id: `smp-ra-${t.id}-${k}`, ...put(name, `attachments/${t.id}/review/${name}`), addedAt: at, addedBy: by, reviewId: id }));
      t.needsCD = true;
      t.reviews = [{ id, by, at, files: files.map((f) => f.id), state: 'pending', epoch: t.reviewEpoch || 0, round: 1 }];
      t.attachments = (t.attachments || []).concat(files);
      t.cdStatus = 'review';
      const p = (out.projects || []).find((x) => x.id === t.projectId);
      const sec = p && (p.sections || []).find((x) => /^(internal )?review$/i.test(String(x.name).trim()));
      if (sec) t.sectionId = sec.id;
      out.notifications.push({ id: `smp-nr${i}`, to: cdNow, from: by, taskId: t.id, kind: 'review', text: `submitted ${files.length === 1 ? '1 file' : files.length + ' files'} for your review on`, snippet: '', commentId: null, at, read: false });
      t.pendingSample = true;
    });

    // ---------- Content calendar: channels and go-live dates on some open tasks, a few for UAE National Day ----------
    {
      const CHS = [['ig'], ['ig', 'tt'], ['li'], ['edm'], ['ig', 'fb'], ['tt'], ['yt'], ['x', 'li']];
      const now = new Date();
      const ndYear = now.getMonth() === 11 && now.getDate() > 3 ? now.getFullYear() + 1 : now.getFullYear();
      out.tasks.filter((t) => !t.parentId && !t.done && t.projectId && !String(t.id).startsWith('smp-fin-')).slice(0, 14).forEach((t, k) => {
        t.channels = CHS[k % CHS.length];
        if (k < 4) { t.golive = `${ndYear}-12-0${k === 3 ? 1 : 2}`; t.occasion = `nationalday-${ndYear}`; }
        else t.golive = dayStr(-(k * 2 - 6));
      });
    }

    // ---------- Expense claims (My reimbursements / Finance → Staff reimbursements) ----------
    {
      const today = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Dubai' }));   // (Dubai's day, like the closing rule)
      const ymdL = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      const cm = today.getDate() >= 28 ? ymdL(new Date(today.getFullYear(), today.getMonth() + 1, 1)) : ymdL(today);
      const pm = ymdL(new Date(Number(cm.slice(0, 4)), Number(cm.slice(5)) - 2, 1));
      const day = (m, d) => `${m}-${String(d).padStart(2, '0')}`;
      const rc = (uid, m, name) => ({ id: `smp-cr-${uid}-${m}-${name}`, ...put(name, `Claims/${uid}/${m}/${name}`), addedAt: iso(2) });
      const prod = cast.filter((u) => ['production', 'social'].includes(u.role)).map((u) => u.id);
      const G = (date, title, items) => ({ id: `g-${title}-${date}`.replace(/\W+/g, '-'), date, title, items: items.map(([desc, amount, receipt], k) => ({ id: `i-${title}-${k}`.replace(/\W+/g, '-'), desc, amount, receipt: receipt || null })) });
      const total = (gs) => Math.round(gs.reduce((a, g) => a + g.items.reduce((b, i) => b + (Number(i.amount) || 0), 0), 0) * 100) / 100;
      const mk = (uid, m, state, groups, extra = {}) => ({ id: `cl-${uid}-${m}`, userId: uid, month: m, state, groups, total: total(groups), signature: null, submittedAt: state === 'none' ? null : iso(2), createdAt: iso(4), updatedAt: iso(1), ...extra });
      out.claims = [];
      if (prod[0]) out.claims.push(mk(prod[0], cm, 'submitted', [
        G(day(cm, 6), 'Address Shoot', [['Salik', 24], ['Petrol', 180, rc(prod[0], cm, 'receipt-reimbursement.pdf')], ['Parking', 45]]),
        G(day(cm, 14), 'Ford Bronco location scout', [['Taxi', 68.5]]),
      ]));
      if (prod[1]) out.claims.push(mk(prod[1], cm, 'approved', [G(day(cm, 9), 'KOREA 360 event setup', [['Taxi', 55], ['Props', 120, rc(prod[1], cm, 'invoice-expense.pdf')]])], { approvedAt: iso(1), approvedBy: 'u-smp-fin-a' }));
      if (prod[2]) out.claims.push(mk(prod[2], cm, 'none', []));
      if (prod[3]) {
        const c = mk(prod[3], pm, 'paid', [G(day(pm, 12), 'Client meeting — ALAIN', [['Parking', 30], ['Coffee for client', 42]]), G(day(pm, 20), 'Hatta shoot', [['Petrol', 150], ['Salik', 16]])], { approvedAt: iso(20), approvedBy: 'u-smp-fin-a', paidOn: day(pm, 27), paidBy: 'u-smp-fin-a', reimbId: `smp-fin-rc-${prod[3]}` });
        out.claims.push(c);
        (out.finance = out.finance || []).push({ id: c.reimbId, type: 'reimb', userId: prod[3], claimId: c.id, amount: c.total, date: c.paidOn, invoice: null, createdAt: iso(20), createdBy: 'u-smp-fin-a' });
      }
      if (prod[4]) out.claims.push(mk(prod[4], cm, 'submitted', [G(day(cm, 18), 'Studio supplies', [['Gaffer tape', 38], ['Batteries', 64]])]));
      // Finance hears about the submitted ones
      // …and so does everyone on the team with Finance access (e.g. an Admin who is also a Finance Admin)
      const hasFin = (u) => u && u.active !== false && (['finance_admin', 'finance_viewer'].includes(u.role) || u.fin === 'admin' || u.fin === 'viewer');
      const finTo = new Set(['u-smp-fin-a', 'u-smp-fin-v', ...store.list('users').filter(hasFin).map((u) => u.id)]);
      const monthL = (m) => new Date(Number(m.slice(0, 4)), Number(m.slice(5)) - 1, 1).toLocaleDateString('en-US', { month: 'long' });
      out.claims.filter((c) => c.state === 'submitted').forEach((c, k) => finTo.forEach((to) => { if (to !== c.userId) out.notifications.push({ id: `smp-ncl-${k}-${to}`, to, from: c.userId, taskId: null, claimId: c.id, month: c.month, kind: 'claim', text: `submitted their ${monthL(c.month)} expense claim`, snippet: 'AED ' + c.total.toFixed(2), commentId: null, at: c.submittedAt, read: false }); }));
    }

    // invoices on expense records
    const inv = (name, folder, m, id) => ({ id, ...put(name, `Finance/${folder}/${m}/${name}`), addedAt: iso(1), addedBy: 'u-smp-fin-a' });
    out.finance.forEach((r, i) => {
      if (r.type === 'sub' && i < 4) {
        const ms = [0, 1, 2].map((k) => { const d = new Date(); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - k); return d.toISOString().slice(0, 7); });
        r.invoices = Object.fromEntries(ms.map((m) => [m, inv('invoice-subscription.pdf', 'Subscriptions', m, `smp-inv-${r.id}-${m}`)]));
      }
      if (r.type === 'reimb' && i % 2 === 0) r.invoice = inv('receipt-reimbursement.pdf', 'Reimbursements', r.date.slice(0, 7), `smp-inv-${r.id}`);
      if (r.type === 'expense' && i % 2 === 1) r.invoice = inv('invoice-expense.pdf', 'Expenses', r.date.slice(0, 7), `smp-inv-${r.id}`);
    });
  }

  // ---------- Home page sample: checklists, start dates and CD review history ----------
  const cdId = (store.get('meta', 'main') || {}).cdUserId || 'u-karim';
  const CL = [['Read the brief', 'Pull references', 'First draft'], ['Export 9:16 and 1:1', 'Add EN / AR subtitles'], ['Shot list sign-off', 'Back up the cards to the NAS', 'Send selects to the AM']];
  const NOTES = ['End card logo comes in too early, hold it one second longer.', 'Raise the headline, it is fighting with the visual.', 'The Arabic caption is too long, cut it to one line.'];
  const ago = (d) => new Date(Date.now() - d * DAY).toISOString();
  let amendN = 0;
  out.tasks.filter((t) => !t.parentId && !t.done).forEach((t, i) => {
    if (i % 2 === 0 && !(t.checklist || []).length) t.checklist = CL[i % CL.length].map((text, j) => ({ id: `smp-cl${i}-${j}`, text, done: j === 0 && i % 4 === 0 }));
    if (t.due && !t.start && i % 3 === 1) t.start = new Date(Date.parse(t.due + 'T00:00:00Z') - 2 * DAY).toISOString().slice(0, 10);
    const by = (t.assignees || []).find((u) => u !== cdId);
    if (by && t.projectId && i % 3 === 0 && amendN < 4 && !t.pendingSample) {
      t.needsCD = true;
      t.reviews = [{ id: `smp-rv${i}`, by, at: ago(2), files: [], state: 'amend', epoch: t.reviewEpoch || 0, round: 1, decidedAt: ago(1), decidedBy: cdId, noteHtml: esc(NOTES[amendN % NOTES.length]) }];
      amendN++;
    }
  });
  out.tasks.forEach((t) => { delete t.pendingSample; });
  out.tasks.filter((t) => !t.parentId && t.done && (t.assignees || []).length).forEach((t, i) => {
    const by = t.assignees.find((u) => u !== cdId);
    if (!by) return;
    const when = t.completedAt || ago(3);
    const before = new Date(Date.parse(when) - DAY).toISOString();
    const rv = i % 4 === 3 ? [{ id: `smp-rd${i}a`, by, at: before, files: [], state: 'amend', epoch: 0, round: 1, decidedAt: before, decidedBy: cdId, noteHtml: esc(NOTES[i % NOTES.length]) }] : [];
    rv.push({ id: `smp-rd${i}`, by, at: when, files: [], state: 'approved', epoch: 0, round: rv.length + 1, decidedAt: when, decidedBy: cdId });
    t.reviews = rv;
  });

  // Creative Director for the review flow, unless one is already set
  const meta = store.get('meta', 'main') || {};
  out.meta = { ...meta, cdUserId: meta.cdUserId || (known.has('u-karim') ? 'u-karim' : null) };
  const ids = new Set(out.users.map((u) => u.id));
  out.notifications = out.notifications.filter((x) => x.to === me || known.has(x.to) || ids.has(x.to));
  return out;
}
