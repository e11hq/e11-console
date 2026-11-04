/* The app's own Me money and review screens (Part B step 2, 2026-11-05): the Office Admin's Overview, Claims and
   Expenses, and the CD's Reviews — worked out from a person's data, no website needed. The same models the page builds
   today (web/phone.js NativeMe: overview, claimsModel, expensesModel, reviewsModel — Reviews without the page's own
   `focus`), from the same rules (claims.js, finance.js, app.js helpers), redone here on `data` alone (no DOM, no `db`).
   "Today", the claim month and every date are Dubai's, from nowMs (the page uses the phone's own clock and zone).
   R: E11Rules · data: this person's /api/snapshot data · me: their id · nowMs: the clock (a function, or a number). */
var E11AppMe = (typeof E11AppMe !== 'undefined' && E11AppMe) || {};
(function (M) {
  'use strict';
  const TZ = 'Asia/Dubai', DUBAI = 4 * 3600000;
  const COLORS = ['#5b8cff', '#3ddc97', '#ffb547', '#ff6b6b', '#c27cff', '#4fd1c5', '#ff8fc7', '#f2f26d', '#9aa0ab'];
  const IMG_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp', 'tif', 'tiff', 'svg'];
  const VID_EXT = ['mp4', 'mov', 'm4v', 'webm'];
  const REVIEWED_DAYS = 15;
  const pad2 = (n) => String(n).padStart(2, '0');
  const msOf = (nowMs) => (typeof nowMs === 'function' ? nowMs() : nowMs == null ? Date.now() : Number(nowMs));
  // a moment's day in Dubai (app.js ymd(new Date(iso)) on a phone in Dubai)
  const dayOf = (ms) => { const d = new Date(ms + DUBAI); return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`; };
  const parseYmd = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
  const addMonth = (m, n) => { const [y, mo] = m.split('-').map(Number); const d = new Date(y, mo - 1 + n, 1); return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`; };
  const monthLong = (m) => { const [y, mo] = m.split('-').map(Number); return new Date(y, mo - 1, 1).toLocaleDateString('en-US', { month: 'long', year: 'numeric' }); };
  const aedOf = (n) => (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const ordN = (n) => n + (n % 10 === 1 && n !== 11 ? 'st' : n % 10 === 2 && n !== 12 ? 'nd' : n % 10 === 3 && n !== 13 ? 'rd' : 'th');
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
  const initials = (name) => String(name).trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?';
  const fullName = (u) => (u ? (u.name || u.email.split('@')[0]) : 'Former member');
  const fileExt = (name) => (String(name).split('.').pop() || '').toLowerCase();
  const isImage = (a) => IMG_EXT.includes(fileExt(a.name));
  const fileUrl = (a) => '/__file/' + String(a.path).split('/').map(encodeURIComponent).join('/');
  const imgUrl = (a, w) => fileUrl(a) + (!/\.svg$/i.test(String(a.path)) ? '?w=' + w : '');   // (the app is always on the server)
  const photoOf = (u) => (u && u.avatar ? fileUrl({ path: u.avatar }) : null);
  // app.js notifPlainHTML (the browser's textContent), without a DOM
  const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—', hellip: '…', lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”', bull: '•', middot: '·', copy: '©', reg: '®', trade: '™', times: '×', euro: '€', pound: '£', zwj: '‍', zwnj: '‌' };
  const decode = (s) => s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') { const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10); try { return String.fromCodePoint(n); } catch (x) { return m; } }
    return Object.prototype.hasOwnProperty.call(ENT, e) ? ENT[e] : ['AMP', 'LT', 'GT', 'QUOT'].includes(e) ? ENT[e.toLowerCase()] : m;
  });
  const plainHTML = (html) => decode(String(html || '').replace(/<(br|\/p|\/li|\/div)>/gi, ' $&').replace(/<!--[\s\S]*?-->/g, '').replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, (m) => m.replace(/<[^>]*>/g, '')).replace(/<\/?[a-z][^>]*>/gi, '')).replace(/\s+/g, ' ').trim();

  // ---------- the person's world, from `data` (the page's normalize where it matters) ----------
  function world(R, data, me, nowMs) {
    data = data || {};
    const now = msOf(nowMs), today = dayOf(now), year = Number(today.slice(0, 4));
    const users = Array.isArray(data.users) ? data.users : [], meta = data.meta || {};
    const projects = (Array.isArray(data.projects) ? data.projects : []).map((p, i) => (p.color ? p : Object.assign({}, p, { color: COLORS[i % COLORS.length] })));
    const tasks = (Array.isArray(data.tasks) ? data.tasks : []).map((t) => {
      if (t.needsCD != null) return t;
      const cdStatus = t.cdStatus === 'review' || t.cdStatus === 'approved' ? t.cdStatus : '';
      return Object.assign({}, t, { needsCD: !t.parentId && !t.done && !!t.projectId && cdStatus !== 'approved' });
    });
    const userById = (id) => users.find((u) => u.id === id) || null;
    const u = userById(me);
    const cdUserId = () => { const id = meta.cdUserId; const x = id && userById(id); return x && x.active !== false ? id : null; };
    const isCD = (id) => !!id && id === cdUserId();
    const isAdm = (x) => !!x && (x.role === 'admin' || x.role === 'office_admin' || x.admin === true);
    const isFinUser = (x) => !!x && (x.role === 'finance_admin' || x.role === 'finance_viewer');
    const finLevel = (x) => (!x ? null : x.role === 'finance_admin' ? 'admin' : x.role === 'finance_viewer' ? 'viewer' : x.fin === 'admin' || x.fin === 'viewer' ? x.fin : null);
    const isOffice = (x) => !!x && x.role === 'office_admin' && x.admin !== true;
    const firstName = (id) => fullName(userById(id)).split(' ')[0];
    const rgb = (hex) => R.rgbOf(hex) || [135, 144, 158];
    const AV = ['#7b68ee', '#4c9aff', '#3ddc97', '#f9be33', '#ff8a4c', '#e5484d', '#ff8fc7', '#4fd1c5', '#a875ff'];
    const avColor = (id) => { let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return AV[h % AV.length]; };
    const fmtDay = (s) => { if (!s) return ''; const d = parseYmd(s); const o = { month: 'short', day: 'numeric' }; if (d.getFullYear() !== year) o.year = 'numeric'; return d.toLocaleDateString('en-US', o); };
    const timeAgo = (iso) => {
      const s = (now - new Date(iso).getTime()) / 1000;
      if (s < 60) return 'just now';
      if (s < 3600) return Math.floor(s / 60) + 'm ago';
      if (s < 86400) return Math.floor(s / 3600) + 'h ago';
      if (s < 86400 * 7) return Math.floor(s / 86400) + 'd ago';
      return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: TZ });
    };
    const isoDay = (iso) => dayOf(new Date(iso).getTime());
    // claims.js
    const claims = Array.isArray(data.claims) ? data.claims : [];
    const finance = Array.isArray(data.finance) ? data.finance : [];
    const claimMonth = () => (Number(today.slice(8, 10)) >= 28 ? addMonth(today.slice(0, 7), 1) : today.slice(0, 7));
    const num = (v) => { const n = parseFloat(String(v == null ? '' : v).replace(/,/g, '')); return Number.isFinite(n) ? n : 0; };
    const totalOf = (c) => (c.groups || []).reduce((a, g) => a + (g.items || []).reduce((b, i) => b + num(i.amount), 0), 0);
    const itemsOf = (c) => (c.groups || []).reduce((a, g) => a + (g.items || []).length, 0);
    const receiptsOf = (c) => (c.groups || []).flatMap((g) => (g.items || []).filter((i) => i.receipt).map((i) => i.receipt));
    const ownerName = (c) => (c.userId ? fullName(userById(c.userId)) : c.personName || 'Someone');
    // finance.js transactions (the office expenses: the only kind these screens list)
    const expenses = () => finance.filter((x) => x.type === 'expense').map((r) => ({ id: r.id, kind: 'expense', name: r.name, amount: Number(r.amount) || 0, date: r.date, invoice: r.invoice || null, ref: r }))
      .sort((a, b) => String(b.date).localeCompare(String(a.date)) || String(b.ref.createdAt || '').localeCompare(String(a.ref.createdAt || '')));
    return { now, today, year, users, meta, projects, tasks, u, userById, cdUserId, isCD, isAdm, isFinUser, finLevel, isOffice, firstName, rgb, avColor, fmtDay, timeAgo, isoDay,
      claims, finance, claimMonth, totalOf, itemsOf, receiptsOf, ownerName, expenses, clients: Array.isArray(data.clients) ? data.clients : [] };
  }

  // Claims: this claim month's reimbursement claims (phone.js claimsModel)
  M.claims = function (R, data, me, nowMs) {
    const W = world(R, data, me, nowMs);
    const m = W.claimMonth();
    const PILL = { submitted: ['Submitted', 'sub'], approved: ['HR approved', 'ok'], paid: ['Paid', 'paid'] };
    const row = (c) => { const nm = W.ownerName(c); const rc = W.receiptsOf(c).length; return { id: c.id, name: nm, ini: initials(nm), rgb: W.rgb(W.avColor(c.userId || c.personId || c.id)), photo: c.userId ? photoOf(W.userById(c.userId)) : null,
      sub: `${c.byHand ? 'Added by hand' : `${plural(W.itemsOf(c), 'item')} · ${plural(rc, 'receipt')}`} · ${W.fmtDay(c.submittedAt || c.updatedAt ? W.isoDay(c.submittedAt || c.updatedAt) : W.today)}`,
      amt: 'AED ' + aedOf(c.total || W.totalOf(c)), st: c.state, pill: (PILL[c.state] || ['', ''])[0] + (c.state === 'paid' && c.paidOn ? ' · ' + W.fmtDay(c.paidOn) : ''), pk: (PILL[c.state] || ['', ''])[1] }; };
    const list = W.claims.filter((c) => c.month === m && ['submitted', 'approved', 'paid'].includes(c.state)).sort((a, b) => String(b.submittedAt || '').localeCompare(String(a.submittedAt || '')));
    const total = list.reduce((a, c) => a + (c.total || W.totalOf(c)), 0);
    const people = W.users.filter((x) => x.active !== false && !W.isFinUser(x)).sort((a, b) => fullName(a).localeCompare(fullName(b))).map((x) => ({ id: 'u:' + x.id, name: fullName(x) }))
      .concat(W.finance.filter((x) => x.type === 'person').map((p) => ({ id: 'p:' + p.id, name: p.name, other: true })));
    const now = W.today.slice(0, 7), prev = addMonth(now, -1);
    return { month: m, label: monthLong(m), sub: `${plural(list.length, 'claim')} · AED ${aedOf(total)}`, admin: W.finLevel(W.u) === 'admin',
      need: list.filter((c) => c.state === 'submitted').map(row), all: list.map(row), people, months: [{ m: prev, t: monthLong(prev) }, { m: now, t: monthLong(now) }] };
  };

  // Expenses: every monthly subscription that's on, and this month's office expenses (phone.js expensesModel)
  M.expenses = function (R, data, me, nowMs) {
    const W = world(R, data, me, nowMs);
    const now = W.today.slice(0, 7);
    const subs = W.finance.filter((x) => x.type === 'sub' && !x.endedAt).sort((a, b) => (Number(a.day) || 0) - (Number(b.day) || 0));
    const office = W.expenses().filter((x) => String(x.date).startsWith(now)).sort((a, b) => String(b.date).localeCompare(String(a.date)));
    return { admin: W.finLevel(W.u) === 'admin', month: monthLong(now),
      subs: subs.map((x) => ({ id: x.id, name: x.name, amt: 'AED ' + aedOf(x.amount), sub: `Billed on the ${ordN(Number(x.day) || 1)} · monthly`, inv: !!Object.keys(x.invoices || {}).length })),
      subsTotal: 'AED ' + aedOf(subs.reduce((a, x) => a + (Number(x.amount) || 0), 0)),
      office: office.map((x) => ({ id: x.id, name: x.name, amt: 'AED ' + aedOf(x.amount), sub: W.fmtDay(x.date) + (x.invoice ? ' · invoice' : ''), inv: !!x.invoice })),
      officeTotal: 'AED ' + aedOf(office.reduce((a, x) => a + (Number(x.amount) || 0), 0)) };
  };

  // a file's small picture (phone.js ovPic / rvPic)
  const picOf = (a, n) => { const e = fileExt(a.name); return isImage(a) && e !== 'svg' ? imgUrl(a, n) : a.thumb ? '/__file/' + a.thumb.split('/').map(encodeURIComponent).join('/') + '?view=1' : a.path && /^(pdf|mp4|mov|m4v|webm|avi|mkv|doc|docx|ppt|pptx|xls|xlsx)$/.test(e) ? '/api/fthumb?path=' + encodeURIComponent(a.path) + '&id=' + encodeURIComponent(a.id || '') : null; };

  // the Office Admin's Overview (phone.js overview)
  M.overview = function (R, data, me, nowMs) {
    const W = world(R, data, me, nowMs), u = W.u;
    const fin = W.isOffice(u) && !!W.finLevel(u);
    const money = aedOf;
    const short = (iso) => { const d = new Date(iso); const days = Math.floor((W.now - d) / 86400000); return days < 1 ? d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit', timeZone: TZ }) : days < 2 ? 'Yesterday' : days < 7 ? d.toLocaleDateString(undefined, { weekday: 'short', timeZone: TZ }) : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', timeZone: TZ }); };
    const ext = (n) => (String(n).split('.').pop() || 'file').slice(0, 4).toUpperCase();
    const colOf = (e) => ({ PNG: [48, 209, 88], JPG: [48, 209, 88], JPEG: [48, 209, 88], PDF: [255, 59, 48], AI: [255, 149, 0], PSD: [10, 132, 255], OTF: [94, 92, 230], TTF: [94, 92, 230], MP4: [175, 82, 222], MOV: [175, 82, 222] }[e] || [142, 142, 147]);
    // app.js clientsSorted: the clients this person sees (caVisible → amSidebarOk → searchClientOk)
    const mentionsIn = (html) => { const out = new Set(); String(html || '').replace(/data-user="([^"]+)"/g, (_, id) => { out.add(id); return ''; }); return out; };
    const partOf = (t, id) => (t.assignees || []).includes(id) || t.createdBy === id || t.guardian === id || (t.comments || []).some((c) => mentionsIn(c.html).has(id)) || mentionsIn(t.notesHtml).has(id);
    const ownOnly = !!u && ['production', 'freelancer'].includes(u.role) && !W.isAdm(u) && !W.isCD(u.id);
    const searchOk = (p) => !ownOnly || W.tasks.some((t) => t.projectId === p.id && partOf(t, u.id)) || (u.role === 'freelancer' && (u.projectIds || []).includes(p.id));
    const amOk = (p) => searchOk(p) && (!u || u.role !== 'am' || W.isAdm(u) || W.isCD(u.id) || !W.projects.some((x) => (x.ams || []).some((a) => a.id === u.id)) || (p.ams || []).some((a) => a.id === u.id && !a.onLeave));
    const visible = (c) => { const linked = W.projects.filter((p) => p.clientId === c.id); return !linked.length || linked.some(amOk); };
    const folders = (c) => (Array.isArray(c.folders) ? c.folders : []);
    const parent = (c, f) => (f && f.parentId ? folders(c).find((x) => x.id === f.parentId) || null : null);
    const folderPath = (c, f) => { const out = []; let p = parent(c, f); while (p && out.length <= 5 && !out.includes(p)) { out.unshift(p); p = parent(c, p); } return [...out, f].map((x) => x.name).join(' › '); };
    const files = [];
    W.clients.filter(visible).sort((a, b) => a.name.localeCompare(b.name)).forEach((c) => folders(c).forEach((f) => (Array.isArray(f.files) ? f.files : []).forEach((a) => files.push({ c, f, a }))));
    files.sort((x, y) => String(y.a.addedAt || '').localeCompare(String(x.a.addedAt || '')));
    const assets = files.slice(0, fin ? 3 : 10).map(({ c, f, a }) => { const e = ext(a.name); return { id: a.id, pic: picOf(a, 160), name: a.name, path: a.path, where: `${c.name} › ${folderPath(c, f)}${a.addedBy ? ' · ' + W.firstName(a.addedBy) : ''}`, when: a.addedAt ? short(a.addedAt) : '', ext: e, rgb: colOf(e) }; });
    const out = { fin, assets };
    if (!fin) return out;
    const m = W.claimMonth();
    const month = W.claims.filter((c) => c.month === m);
    const sent = month.filter((c) => !c.byHand && ['submitted', 'approved', 'paid'].includes(c.state)).length;
    const team = W.users.filter((x) => x.active !== false && !W.isFinUser(x)).length;
    const now = W.today.slice(0, 7);
    const exp = W.expenses().filter((x) => String(x.date).startsWith(now)).sort((a, b) => String(b.date).localeCompare(String(a.date)));
    const subs = W.finance.filter((x) => x.type === 'sub' && !x.endedAt).length;
    const need = W.claims.filter((c) => c.state === 'submitted').sort((a, b) => String(b.submittedAt || '').localeCompare(String(a.submittedAt || '')));
    out.cards = [{ n: `${sent}`, of: `/ ${team}`, t: 'claims submitted this month' }, { n: money(exp.reduce((a, x) => a + (Number(x.amount) || 0), 0)), t: 'AED office expenses so far' }, { n: `${subs}`, t: 'monthly subscriptions' }];
    out.claims = need.slice(0, 3).map((c) => ({ id: c.id, name: W.ownerName(c), ini: initials(W.ownerName(c)), rgb: W.rgb(W.avColor(c.userId || c.personId || c.id)), sub: `${c.byHand ? 'Added by hand' : plural(W.itemsOf(c), 'item')} · ${W.fmtDay(W.isoDay(c.submittedAt || c.updatedAt))}`, amt: 'AED ' + money(c.total || W.totalOf(c)) }));
    out.needN = need.length;
    out.expenses = exp.slice(0, 3).map((x) => ({ id: x.id, name: x.name, sub: W.fmtDay(x.date), amt: 'AED ' + money(x.amount) }));
    return out;
  };

  // the CD's Reviews: Waiting · Reviewed (phone.js reviewsModel, without the page's `focus`)
  M.reviews = function (R, data, me, nowMs) {
    const W = world(R, data, me, nowMs);
    const fileKind = (a) => { const e = fileExt(a.name); return IMG_EXT.includes(e) ? 'image' : VID_EXT.includes(e) ? 'video' : 'other'; };
    const rvFile = (a, mark) => ({ id: a.id, name: a.name || 'File', pic: picOf(a, 160), big: picOf(a, 1000), video: fileKind(a) === 'video', ext: (fileExt(a.name) || 'file').slice(0, 4).toUpperCase(), mark: mark || '' });
    const epochOf = (t) => t.reviewEpoch || 0;
    const needsCD = (t) => !!t && !t.parentId && !!t.needsCD;
    const attOf = (t, id) => (t.attachments || []).find((a) => a.id === id) || null;
    const okIdsOf = (r) => (r.state === 'approved' ? r.ok || r.files || [] : r.state === 'amend' && Array.isArray(r.ok) ? r.ok : []);
    const keptOk = (t, by, upto) => {
      const m = new Map();
      for (const r of t.reviews || []) {
        if (r === upto) break;
        if (r.by !== by || (r.epoch || 0) !== epochOf(t) || !['approved', 'amend'].includes(r.state)) continue;
        okIdsOf(r).forEach((id) => { const a = attOf(t, id); if (a) m.set(String(a.name || id).toLowerCase(), id); });
      }
      return m;
    };
    const carriedOf = (t, r) => {
      const kept = keptOk(t, r.by, r);
      (r.files || []).forEach((id) => { const a = attOf(t, id); if (a) kept.delete(String(a.name || id).toLowerCase()); });
      return [...kept.values()].map((id) => attOf(t, id)).filter(Boolean);
    };
    const resultOf = (r) => {
      if (r.state === 'approved') return { k: 'ok', label: 'Approved', long: `Approved · ${(r.files || []).length} file${(r.files || []).length === 1 ? '' : 's'}` };
      const ok = (r.ok || []).length, need = r.need ? Object.keys(r.need).length : (r.files || []).length;
      if (r.state === 'amend' && ok) return { k: 'mix', label: `${ok} ✓ · ${need} ✎`, long: `${ok} approved · ${need} need${need === 1 ? 's' : ''} changes` };
      return { k: 'amend', label: 'Amendments', long: `Amendments · ${need} file${need === 1 ? '' : 's'}` };
    };
    const all = [];
    W.tasks.forEach((t) => (Array.isArray(t.reviews) ? t.reviews : []).forEach((r) => all.push({ t, r })));
    const wait = all.filter(({ t, r }) => r.state === 'pending' && needsCD(t) && (r.epoch || 0) === epochOf(t) && !t.done).sort((a, b) => a.r.at.localeCompare(b.r.at));
    const done = all.filter(({ r }) => (r.state === 'approved' || r.state === 'amend') && r.decidedAt && (W.now - new Date(r.decidedAt)) < REVIEWED_DAYS * 864e5).sort((a, b) => b.r.decidedAt.localeCompare(a.r.decidedAt));
    const item = (t, r, decided) => {
      const p = W.projects.find((x) => x.id === t.projectId), u = W.userById(r.by);
      const files = (r.files || []).map((id) => attOf(t, id)).filter(Boolean);
      const carried = carriedOf(t, r);
      const mark = (a) => (!decided ? '' : r.state === 'approved' || (r.ok || []).includes(a.id) ? 'ok' : 'need');
      const before = (t.reviews || []).filter((x) => x.by === r.by && (x.epoch || 0) === (r.epoch || 0) && x.state === 'amend' && x !== r && String(x.at) < String(r.at)).pop();
      const res = decided ? resultOf(r) : null;
      return {
        id: r.id, tid: t.id, task: t.title || 'Untitled task', client: p ? p.name : '', crgb: W.rgb(p ? p.color : '#87909e'),
        who: fullName(u), first: W.firstName(r.by), ini: initials(fullName(u)), rgb: W.rgb(W.avColor(r.by)), photo: photoOf(u),
        sub: `${W.firstName(r.by)} sent ${plural(files.length, 'file')} · ${W.timeAgo(decided ? r.decidedAt : r.at)}`,
        round: r.round || 1, carried: carried.length,
        files: files.map((a) => rvFile(a, mark(a))), carriedFiles: carried.map((a) => rvFile(a, 'ok')),
        brief: t.notesHtml ? plainHTML(t.notesHtml) : String(t.notes || '').trim(),
        last: before && before.noteHtml ? plainHTML(before.noteHtml) : '',
        res: res ? { k: res.k, t: res.label, long: res.long } : null,
        note: decided && r.noteHtml ? plainHTML(r.noteHtml) : '',
      };
    };
    return { waiting: wait.map(({ t, r }) => item(t, r, false)), reviewed: done.map(({ t, r }) => item(t, r, true)) };
  };
  M.plainHTML = plainHTML;
})(E11AppMe);
if (typeof module !== 'undefined' && module.exports) module.exports = E11AppMe;
