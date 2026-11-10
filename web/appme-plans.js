/* The app's own Content plans and Client Assets (Part B step 2, Haris 2026-11-05): the same screen models the page builds
   today — web/plans.js Plans.native (list, plan, post, search, waiting) and web/phone.js NativeAssets (All Client Assets,
   a client's assets) — worked out from a person's own data, with no page and no `db`. Run where E11AppView runs (the
   iPhone app's JavaScript engine, on its own copy of the data); it only reads.
   R: E11Rules · data: this person's data (/api/snapshot) · me: their id · nowMs: the clock (a number, or a function).
   Days and times are Dubai's (UTC+4), as the iPhone shows them. */
var E11AppMe = (typeof E11AppMe !== 'undefined' && E11AppMe) || {};
(function (X) {
  'use strict';
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const MON3 = MONTHS.map((m) => m.slice(0, 3));
  const WD3 = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const COLORS = ['#5b8cff', '#3ddc97', '#ffb547', '#ff6b6b', '#c27cff', '#4fd1c5', '#ff8fc7', '#f2f26d', '#9aa0ab'];
  const AV_COLORS = ['#7b68ee', '#4c9aff', '#3ddc97', '#f9be33', '#ff8a4c', '#e5484d', '#ff8fc7', '#4fd1c5', '#a875ff'];
  const FORMATS = [['post', 'Post', '#8b8b96'], ['carousel', 'Carousel', '#7b68ee'], ['reel', 'Reel', '#e5484d'], ['story', 'Story', '#f2b23e'], ['video', 'Video', '#3ddc97']];
  const FMT = Object.fromEntries(FORMATS.map(([k, name, color]) => [k, { k, name, color }]));
  const fmtOf = (k) => FMT[k] || FMT.post;
  const CHANNELS = [
    ['ig', 'Instagram', 'IG', '#e1306c'], ['tt', 'TikTok', 'TT', '#25f4ee'], ['li', 'LinkedIn', 'IN', '#0a66c2'], ['x', 'X', 'X', '#8b8b96'],
    ['fb', 'Facebook', 'FB', '#1877f2'], ['yt', 'YouTube', 'YT', '#ff3d3d'], ['sc', 'Snapchat', 'SC', '#f7d417'], ['edm', 'EDM', 'EDM', '#f08a24'],
  ];
  const CH = Object.fromEntries(CHANNELS.map(([k, name, short, color]) => [k, { k, name, short, color }]));
  const PROG = { none: ['Not created', '#8b8b96'], prod: ['In production', '#a875ff'], cd: ['With the CD', '#f2b23e'], ready: ['Finished', '#3ddc97'], changes: ['Client changes', '#ff8a4c'], done: ['Client approved', '#5b9bff'] };
  const IMG_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp', 'tif', 'tiff', 'svg'];
  const VID_EXT = ['mp4', 'mov', 'm4v', 'webm'];
  const AUD_EXT = ['mp3', 'm4a', 'aac', 'wav', 'aif', 'aiff'];
  const TXT_EXT = ['txt', 'md', 'csv', 'log', 'json', 'xml'];
  const OFFICE_LABEL = { ppt: 'PowerPoint', pptx: 'PowerPoint', key: 'Keynote', doc: 'Word', docx: 'Word', pages: 'Pages', xls: 'Excel', xlsx: 'Excel', numbers: 'Numbers', zip: 'Archive' };
  const THUMBED = ['mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'odt', 'odp', 'ods', 'rtf'];
  const FOLDER_HEX = ['#0a84ff', '#af52de', '#ff9f0a', '#34c759', '#30b0c7', '#ff375f', '#5e5ce6'];
  const DEFAULT_FOLDERS = ['Logos', 'Brand Guidelines', 'Fonts', 'Files'];
  const FOLDER_DEPTH = 5;

  // ---------- days (no time zone: 'YYYY-MM-DD'; the clock read as Dubai's) ----------
  const p2 = (n) => String(n).padStart(2, '0');
  const DUBAI = 4 * 3600000;
  const dubai = (ms) => new Date(ms + DUBAI);   // read with the UTC getters
  const utcYmd = (d) => `${d.getUTCFullYear()}-${p2(d.getUTCMonth() + 1)}-${p2(d.getUTCDate())}`;
  const dayDate = (s) => { const [y, m, d] = String(s).split('-').map(Number); return new Date(Date.UTC(y, m - 1, d)); };
  const plusDays = (s, n) => { const [y, m, d] = s.split('-').map(Number); return utcYmd(new Date(Date.UTC(y, m - 1, d + n))); };
  const monthKey = (y, m0) => { const d = new Date(Date.UTC(y, m0, 1)); return `${d.getUTCFullYear()}-${p2(d.getUTCMonth() + 1)}`; };
  const shiftMonth = (m, n) => { const [y, mm] = m.split('-').map(Number); return monthKey(y, mm - 1 + n); };
  const monthLabel = (m) => { const [y, mm] = m.split('-').map(Number); return `${MONTHS[mm - 1]} ${y}`; };
  const firstDay = (m) => `${m}-01`;
  const lastDay = (m) => { const [y, mm] = m.split('-').map(Number); return utcYmd(new Date(Date.UTC(y, mm, 0))); };
  // (en-GB { weekday: 'short', day: 'numeric', month: 'short' }: "Sat 5 Dec")
  // (dates are written by this engine's own Intl, as the page's toLocaleDateString — on the iPhone the page's engine and
  //  this one are the same, so the words and commas are too; written by hand only where Intl isn't there)
  const intl = (fn, plain) => { try { const v = fn(); if (typeof v === 'string' && v && v !== 'Invalid Date') return v; } catch (e) { /* no Intl */ } return plain(); };
  const dayLong = (s) => { const d = dayDate(s); return intl(() => d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' }), () => `${WD3[d.getUTCDay()]} ${d.getUTCDate()} ${MON3[d.getUTCMonth()]}`); };
  const fmtSize = (b) => (b == null ? '' : b < 1024 ? b + ' B' : b < 1048576 ? (b / 1024).toFixed(0) + ' KB' : (b / 1048576).toFixed(1) + ' MB');
  const fileExt = (name) => (String(name).split('.').pop() || '').toLowerCase();
  const isImage = (a) => IMG_EXT.includes(fileExt(a.name));
  function fileKind(a) {
    const e = fileExt(a.name);
    if (IMG_EXT.includes(e)) return 'image';
    if (VID_EXT.includes(e)) return 'video';
    if (AUD_EXT.includes(e)) return 'audio';
    if (e === 'pdf') return 'pdf';
    if (TXT_EXT.includes(e)) return 'text';
    return 'other';
  }
  const pathUrl = (p) => '/__file/' + String(p).split('/').map(encodeURIComponent).join('/');
  const fileUrl = (a) => pathUrl(a.path);
  const imgUrl = (a, w) => fileUrl(a) + (!/\.svg$/i.test(String(a.path)) ? '?w=' + w : '');   // (the app is always on the server)
  // (a middle "Al" is skipped: Yousef Al Hwij → YH, Lana Al Ramli → LR, Al-Ramli too — Haris 2026-11-08)
  const initials = (name) => { const w = String(name || '').trim().split(/\s+/).filter(Boolean); if (w.length > 2 && /^al$/i.test(w[1])) w.splice(1, 1); const two = w.slice(0, 2).map((x, i) => (i > 0 ? x.replace(/^al-(?=.)/i, '') : x)[0] || ''); return two.join('').toUpperCase() || '?'; };
  const avColor = (id) => { let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return AV_COLORS[h % AV_COLORS.length]; };
  const mentionsIn = (html) => { const out = new Set(); String(html || '').replace(/data-user="([^"]+)"/g, (_, id) => { out.add(id); return ''; }); return out; };
  // (letters added, dropped, changed — two swapped count as one: app.js editDist)
  function typoDist(a, b, max) {
    if (Math.abs(a.length - b.length) > max) return max + 1;
    let prev2 = [], prev = [], cur = [];
    for (let j = 0; j <= b.length; j++) prev[j] = j;
    for (let i = 1; i <= a.length; i++) {
      cur = [i]; let best = i;
      for (let j = 1; j <= b.length; j++) {
        let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
        if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
        cur[j] = v; if (v < best) best = v;
      }
      if (best > max) return max + 1;
      prev2 = prev; prev = cur;
    }
    return prev[b.length];
  }
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;

  // ---------- Occasions (web/calendar.js), with this person's data's meta ----------
  const OCC_FIXED = [
    ['newyear', 'New Year’s Day', '01-01', null, 'Happy New Year'],
    ['valentine', 'Valentine’s Day', '02-14', null, null],
    ['womensday', 'International Women’s Day', '03-08', null, 'Happy Women’s Day'],
    ['mothersday', 'Mother’s Day (UAE)', '03-21', null, 'Happy Mother’s Day'],
    ['halloween', 'Halloween', '10-31', null, 'Happy Halloween'],
    ['commemoration', 'Commemoration Day', '11-30', null, null],
    ['nationalday', 'UAE National Day', '12-02', '12-03', 'Eshi Biladi', '12-15'],
    ['christmas', 'Christmas', '12-25', null, 'Merry Christmas'],
    ['nye', 'New Year’s Eve', '12-31', null, null],
  ];
  const OCC_TABLE = [
    ['ramadan', 'Ramadan', 'Ramadan Kareem', true, 0, { 2026: ['2026-02-18', '2026-03-19'], 2027: ['2027-02-08', '2027-03-09'], 2028: ['2028-01-28', '2028-02-26'] }],
    ['eidfitr', 'Eid al-Fitr', 'Eid Mubarak', true, 2, { 2026: '2026-03-20', 2027: '2027-03-10', 2028: '2028-02-27' }],
    ['arafat', 'Arafat Day', null, true, 0, { 2026: '2026-05-26', 2027: '2027-05-15', 2028: '2028-05-04' }],
    ['eidadha', 'Eid al-Adha', 'Eid Mubarak', true, 3, { 2026: '2026-05-27', 2027: '2027-05-16', 2028: '2028-05-05' }],
    ['hijri', 'Islamic New Year', 'Happy Hijri New Year', true, 0, { 2026: '2026-06-16', 2027: '2027-06-06', 2028: '2028-05-25' }],
    ['mawlid', 'Prophet’s Birthday', null, true, 0, { 2026: '2026-08-25', 2027: '2027-08-15', 2028: '2028-08-03' }],
    ['cny', 'Chinese New Year', 'Happy Lunar New Year', false, 0, { 2026: '2026-02-17', 2027: '2027-02-06', 2028: '2028-01-26' }],
    ['easter', 'Easter', 'Happy Easter', false, 0, { 2026: '2026-04-05', 2027: '2027-03-28', 2028: '2028-04-16' }],
    ['diwali', 'Diwali', 'Happy Diwali', false, 0, { 2026: '2026-11-08', 2027: '2027-10-29', 2028: '2028-10-17' }],
    ['dsf', 'Dubai Shopping Festival', null, true, 0, { 2025: ['2025-12-05', '2026-01-11'], 2026: ['2026-12-04', '2027-01-10'], 2027: ['2027-12-03', '2028-01-09'] }],
  ];
  const nth = (y, m, wd, n) => { const d = new Date(Date.UTC(y, m - 1, 1)); d.setUTCDate(1 + ((wd - d.getUTCDay() + 7) % 7) + (n - 1) * 7); return utcYmd(d); };
  const OCC_RULES = [
    ['mothersday-us', 'Mother’s Day (US & Europe)', (y) => nth(y, 5, 0, 2), null],
    ['fathersday', 'Father’s Day', (y) => nth(y, 6, 0, 3), 'Happy Father’s Day'],
    ['blackfriday', 'Black Friday', (y) => plusDays(nth(y, 11, 4, 4), 1), null],
  ];
  const DIWALI = { 2029: '2029-11-05', 2030: '2030-10-26', 2031: '2031-11-14', 2032: '2032-11-02', 2033: '2033-10-22', 2034: '2034-11-10', 2035: '2035-10-30' };
  const scans = {};
  function scan(cal, y) {
    const k = cal + y;
    if (scans[k]) return scans[k];
    const out = {};
    try {
      const f = new Intl.DateTimeFormat('en-u-ca-' + cal, { day: 'numeric', month: 'numeric', timeZone: 'UTC' });
      for (let t = Date.UTC(y, 0, 1); t < Date.UTC(y + 1, 0, 1); t += 864e5) {
        const p = Object.fromEntries(f.formatToParts(new Date(t)).map((x) => [x.type, x.value]));
        const key = `${parseInt(p.month, 10)}-${parseInt(p.day, 10)}`;
        (out[key] = out[key] || []).push(new Date(t).toISOString().slice(0, 10));
      }
    } catch (e) { /* no such calendar here */ }
    return (scans[k] = out);
  }
  const hijri = (y, m, d) => scan('islamic-umalqura', y)[`${m}-${d}`] || [];
  function easter(y) {
    const a = y % 19, b = Math.floor(y / 100), c = y % 100, d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3);
    const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451);
    const month = Math.floor((h + l - 7 * m + 114) / 31), day = ((h + l - 7 * m + 114) % 31) + 1;
    return `${y}-${p2(month)}-${p2(day)}`;
  }
  function computed(k, y) {
    const ends = (start) => {
      for (let i = 28; i <= 31; i++) { const d = plusDays(start, i), yy = Number(d.slice(0, 4)); if ((hijri(yy, 10, 1)).includes(d)) return plusDays(d, -1); }
      return plusDays(start, 29);
    };
    switch (k) {
      case 'ramadan': return hijri(y, 9, 1).map((d) => [d, ends(d)]);
      case 'eidfitr': return hijri(y, 10, 1).map((d) => [d, null]);
      case 'arafat': return hijri(y, 12, 9).map((d) => [d, null]);
      case 'eidadha': return hijri(y, 12, 10).map((d) => [d, null]);
      case 'hijri': return hijri(y, 1, 1).map((d) => [d, null]);
      case 'mawlid': return hijri(y, 3, 12).map((d) => [d, null]);
      case 'cny': return (scan('chinese', y)['1-1'] || []).filter((d) => d.slice(5, 7) <= '02').slice(0, 1).map((d) => [d, null]);
      case 'easter': return [[easter(y), null]];
      case 'diwali': return DIWALI[y] ? [[DIWALI[y], null]] : [];
      case 'dsf': { const d = new Date(Date.UTC(y, 11, 3)); d.setUTCDate(3 + ((5 - d.getUTCDay() + 7) % 7)); const s0 = utcYmd(d); return [[s0, plusDays(s0, 37)]]; }
      default: return [];
    }
  }
  const builtCache = {};
  function builtIn(y) {
    if (builtCache[y]) return builtCache[y];
    const out = [];
    OCC_FIXED.forEach(([k, name, md, end, greet, until]) => out.push({ id: `${k}-${y}`, key: k, name, date: `${y}-${md}`, end: end ? `${y}-${end}` : null, greet, greetUntil: until ? `${y}-${until}` : null, est: false }));
    OCC_TABLE.forEach(([k, name, greet, est, extra, by]) => {
      const v = by[y];
      if (v) {
        const date = Array.isArray(v) ? v[0] : v;
        const end = Array.isArray(v) ? v[1] : extra ? plusDays(date, extra) : null;
        out.push({ id: `${k}-${y}`, key: k, name, date, end, greet, est });
        return;
      }
      if (Number(Object.keys(by).sort().pop()) > y) return;
      computed(k, y).forEach(([date, end], i) => out.push({ id: `${k}-${y}${i ? 'b' : ''}`, key: k, name, date, end: end || (extra ? plusDays(date, extra) : null), greet, est: k !== 'easter' }));
    });
    OCC_RULES.forEach(([k, name, fn, greet]) => out.push({ id: `${k}-${y}`, key: k, name, date: fn(y), end: null, greet, est: false }));
    return (builtCache[y] = out);
  }
  function occasions(meta) {
    function between(from, to) {
      const fix = meta.occDates || {};
      const y0 = Number(from.slice(0, 4)) - 1, y1 = Number(to.slice(0, 4));
      let all = [];
      for (let y = y0; y <= y1; y++) all = all.concat(builtIn(y));
      all = all.map((o) => (fix[o.id] ? { ...o, date: fix[o.id].date || o.date, end: fix[o.id].end === undefined ? o.end : fix[o.id].end, est: false, fixed: true, confirmed: !!fix[o.id].auto, estDate: o.date } : o));
      all = all.concat((meta.occasions || []).map((o) => ({ ...o, custom: true, est: false })));
      return all.filter((o) => (o.end || o.date) >= from && o.date <= to).sort((a, b) => a.date.localeCompare(b.date) || a.name.localeCompare(b.name));
    }
    const on = (day) => between(day, day);
    const byId = (id) => {
      if (!id) return null;
      const custom = (meta.occasions || []).find((o) => o.id === id);
      if (custom) return { ...custom, custom: true };
      const m = /(\d{4})b?$/.exec(String(id));
      const y = m ? Number(m[1]) : 0;
      if (!y) return null;
      return between(`${y - 1}-01-01`, `${y + 1}-12-31`).find((o) => o.id === id) || null;
    };
    return { between, on, byId };
  }

  // ---------- the person's world: app.js's helpers, on their data ----------
  function world(R, data, meId, nowMs) {
    const NOW = typeof nowMs === 'function' ? Number(nowMs()) : nowMs != null ? Number(nowMs) : Date.now();
    data = data || {};
    const meta = data.meta || {};
    const users = data.users || [], projects = data.projects || [], tasks = data.tasks || [], plans = data.plans || [], clients = data.clients || [];
    // (the website's normalize on load, where it matters here)
    const firstAdmin = users.length ? (users.find((u) => u.role === 'admin') || users[0]).id : 'u-haris';
    const pOrder = new Map(), pColor = new Map();
    projects.forEach((p, i) => { pOrder.set(p, p.order == null ? i + 1 : p.order); pColor.set(p, p.color || COLORS[i % COLORS.length]); });
    const colorOf = (p) => (pColor.has(p) ? pColor.get(p) : p.color);
    const byOrder = (a, b) => (pOrder.get(a) || 0) - (pOrder.get(b) || 0);
    const assigneesOf = (t) => (Array.isArray(t.assignees) ? t.assignees : [firstAdmin]);
    const cdStatusOf = (t) => (t.cdStatus === 'review' || t.cdStatus === 'approved' ? t.cdStatus : '');
    const needsCDRaw = (t) => (t.needsCD == null ? !t.parentId && !t.done && !!t.projectId && cdStatusOf(t) !== 'approved' : t.needsCD);
    const foldersOf = (c) => (Array.isArray(c.folders) ? c.folders : []);
    const filesOf = (f) => (Array.isArray(f.files) ? f.files : []);

    const uMap = new Map(users.map((u) => [u.id, u])), pMap = new Map(), tMap = new Map();
    projects.forEach((p) => { if (!pMap.has(p.id)) pMap.set(p.id, p); });
    tasks.forEach((t) => { if (!tMap.has(t.id)) tMap.set(t.id, t); });
    const userById = (id) => uMap.get(id) || null;
    const proj = (id) => pMap.get(id);
    const task = (id) => tMap.get(id);
    const me = () => userById(meId);
    const fullName = (u) => (u ? (u.name || u.email.split('@')[0]) : 'Former member');
    const firstName = (id) => fullName(userById(id)).split(' ')[0];
    const isAdm = (u) => !!u && (u.role === 'admin' || u.role === 'office_admin' || u.admin === true);
    const isOffice = (u = me()) => !!u && u.role === 'office_admin' && u.admin !== true;
    const isFinUser = (u = me()) => !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer');
    const cdUserId = () => { const id = meta.cdUserId; const u = id && userById(id); return u && u.active !== false ? id : null; };
    const isCD = (id = meId) => !!id && id === cdUserId();
    const socialMgrIds = () => (meta.socialMgrIds || []).filter((id) => { const u = userById(id); return u && u.active !== false && u.role === 'social'; });
    // CD review (app.js)
    const needsCD = (t) => !!t && !t.parentId && !!needsCDRaw(t);
    const reviewersOf = (t) => assigneesOf(t).filter((u) => u !== cdUserId());
    const lastReview = (t, u) => { const l = (t.reviews || []).filter((r) => r.by === u && (r.epoch || 0) === (t.reviewEpoch || 0) && r.state !== 'withdrawn'); return l[l.length - 1] || null; };
    const reviewState = (t, u) => { const r = lastReview(t, u); return r ? r.state : 'none'; };
    const reviewPending = (t) => needsCD(t) && reviewersOf(t).some((u) => reviewState(t, u) === 'pending');
    // whose clients
    const subtasksOf = (id) => tasks.filter((t) => t.parentId === id);
    function partOfTask(t, id, deep = true) {
      if (!t) return false;
      if (assigneesOf(t).includes(id) || t.createdBy === id || t.guardian === id) return true;
      if ((t.comments || []).some((c) => mentionsIn(c.html).has(id)) || mentionsIn(t.notesHtml).has(id)) return true;
      if (!deep) return false;
      return (t.parentId && partOfTask(task(t.parentId), id, false)) || subtasksOf(t.id).some((x) => partOfTask(x, id, false));
    }
    const ownSearchOnly = (u = me()) => !!u && ['production', 'freelancer'].includes(u.role) && !isAdm(u) && !isCD(u.id);
    const searchClientOk = (p, u = me()) => !ownSearchOnly(u) || tasks.some((t) => t.projectId === p.id && partOfTask(t, u.id, false)) || (u.role === 'freelancer' && (u.projectIds || []).includes(p.id));
    const amSidebarOk = (p, u = me()) => searchClientOk(p, u) && (!u || u.role !== 'am' || isAdm(u) || isCD(u.id) || !projects.some((x) => (x.ams || []).some((a) => a.id === u.id)) || (p.ams || []).some((a) => a.id === u.id && !a.onLeave));
    // time
    const thisYear = dubai(NOW).getUTCFullYear();
    const fmtDay = (s) => {
      if (!s) return ''; const d = dayDate(s); const y = d.getUTCFullYear();
      return intl(() => d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', ...(y !== thisYear ? { year: 'numeric' } : {}), timeZone: 'UTC' }), () => `${MON3[d.getUTCMonth()]} ${d.getUTCDate()}${y !== thisYear ? `, ${y}` : ''}`);
    };
    function timeAgo(iso) {
      const t = new Date(iso).getTime(), s = (NOW - t) / 1000;
      if (s < 60) return 'just now';
      if (s < 3600) return Math.floor(s / 60) + 'm ago';
      if (s < 86400) return Math.floor(s / 3600) + 'h ago';
      if (s < 86400 * 7) return Math.floor(s / 86400) + 'd ago';
      if (!isFinite(t)) return 'Invalid Date';
      const d = dubai(t); return intl(() => new Date(t).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'Asia/Dubai' }), () => `${MON3[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`);
    }
    const fmtDateTime = (iso) => {
      const t = new Date(iso).getTime(); if (!isFinite(t)) return 'Invalid Date';
      const d = dubai(t), h = d.getUTCHours();
      return intl(() => new Date(t).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Dubai' }),
        () => `${MON3[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}, ${h % 12 || 12}:${p2(d.getUTCMinutes())} ${h < 12 ? 'AM' : 'PM'}`);
    };
    const today = utcYmd(dubai(NOW));
    const thisMonth = () => today.slice(0, 7);
    const nextMonth = () => shiftMonth(thisMonth(), 1);
    return { NOW, meta, users, projects, tasks, plans, clients, colorOf, byOrder, foldersOf, filesOf, userById, proj, task, me, meId, fullName, firstName, isAdm, isOffice, isFinUser,
      cdUserId, isCD, socialMgrIds, reviewPending, amSidebarOk, fmtDay, timeAgo, fmtDateTime, thisMonth, nextMonth, Occ: occasions(meta), rgb: (h) => (R && R.rgbOf && R.rgbOf(h)) || [135, 144, 158] };
  }

  // ---------- Content plans (web/plans.js) ----------
  function plansOf(W) {
    const { userById, proj, task, me, meId, firstName, isAdm, isOffice, isFinUser, cdUserId, isCD, socialMgrIds, Occ } = W;
    const planOf = (pid, month) => W.plans.find((p) => p.projectId === pid && p.month === month) || null;
    const planById = (id) => W.plans.find((p) => p.id === id) || null;
    const isMgr = (u = me()) => !!u && u.role === 'social' && socialMgrIds().includes(u.id);
    const canSee = (u = me()) => !!u && u.active !== false && !isFinUser(u) && !isOffice(u) && (isAdm(u) || u.role === 'am' || u.role === 'social' || isCD(u.id));
    const socialsOf = (p) => ((p && p.socials) || []).filter((id) => { const u = userById(id); return u && u.active !== false; });
    const canEditClient = (pid, u = me()) => !!u && u.role === 'social' && u.active !== false && (isMgr(u) || socialsOf(proj(pid)).includes(u.id));
    const isEditor = (pl) => !!pl && canEditClient(pl.projectId);
    const sentTo = (pl, k) => { const t = pl && pl.review && pl.review.to; return !t || t === 'both' || t === k; };
    const canApprove = (pl, u = me()) => !!pl && !!u && ((u.id === cdUserId() && sentTo(pl, 'cd')) || (isMgr(u) && pl.createdBy !== u.id && sentTo(pl, 'sm')));
    function finishedFiles(t) {
      const latest = new Map();
      (t.reviews || []).forEach((r) => { if (r.state !== 'approved') return; const p = latest.get(r.by); if (!p || String(r.decidedAt || r.at) >= String(p.decidedAt || p.at)) latest.set(r.by, r); });
      const files = [];
      latest.forEach((r) => (r.set || r.files || []).forEach((id) => { const a = (t.attachments || []).find((x) => x.id === id); if (a) files.push(a); }));
      return files;
    }
    const needsCDOf = (t) => (t.needsCD == null ? !t.parentId && !t.done && !!t.projectId && t.cdStatus !== 'approved' : t.needsCD);
    function progress(x) {
      const t = x.taskId && task(x.taskId);
      if (!x.taskId) return { k: 'none', t: null, files: [] };
      if (!t) return { k: 'none', t: null, files: [], gone: true };
      const files = finishedFiles(t);
      const fin = files.length && (t.cdStatus === 'approved' || !needsCDOf(t));
      const k = t.done ? 'done' : W.reviewPending(t) ? 'cd' : fin ? 'ready' : x.client && x.client.state === 'changes' ? 'changes' : 'prod';
      return { k, t, files, fin: !!fin || t.done };
    }
    const hasTasks = (pl) => (pl.posts || []).some((x) => x.taskId);
    const toLabel = (to) => (to === 'cd' ? (userById(cdUserId()) ? firstName(cdUserId()) : 'the CD') : to === 'sm' ? 'the Social Manager' : `${userById(cdUserId()) ? firstName(cdUserId()) : 'the CD'} & the Social Manager`);
    function clientsInScope() {
      const u = me();
      const active = W.projects.filter((p) => !p.inactive).sort(W.byOrder);
      if (u.role === 'social' && !isMgr(u)) return active.filter((p) => socialsOf(p).includes(u.id));
      if (u.role === 'am' && !isAdm(u) && !isCD(u.id)) return active.filter((p) => W.amSidebarOk(p));
      return active;
    }
    const occKey = (o) => o.key || o.id;
    const skipped = (p, o) => ((p && p.planSkips) || []).includes(occKey(o));
    const postsSorted = (pl) => (pl.posts || []).slice().sort((a, b) => String(a.day).localeCompare(String(b.day)) || String(a.createdAt).localeCompare(String(b.createdAt)));
    const showChecks = (pl) => pl.status === 'review' || pl.status === 'changes';

    const who = (id) => (id === meId ? 'You' : userById(id) ? firstName(id) : 'Someone');
    const rgb = W.rgb;
    function stOf(pl) {
      if (!pl) return { t: 'Not started', k: 'none' };
      if (pl.status === 'approved' && pl.clientApproved) return { t: 'Client approved', k: 'ok' };
      if (pl.status === 'approved' && pl.sent && (pl.exports || []).length && pl.sent.round === pl.exports[pl.exports.length - 1].round) return { t: `With the client · R${pl.sent.round}`, k: 'sent' };
      if (pl.status === 'approved' && hasTasks(pl)) { const n = (pl.posts || []).length, r = (pl.posts || []).filter((x) => ['ready', 'done'].includes(progress(x).k)).length; return { t: `In production · ${r}/${n}`, k: 'prod' }; }
      if (pl.status === 'review') return { t: canApprove(pl) ? 'Waiting for you' : 'Waiting', k: 'wait' };
      if (pl.status === 'changes') return { t: `Changes${(pl.round || 1) > 1 ? ' · R' + pl.round : ''}`, k: 'chg' };
      if (pl.status === 'approved') return { t: 'Approved', k: 'ok' };
      return { t: 'Draft', k: 'draft' };
    }
    const monthOr = (month) => (month && /^\d{4}-\d{2}$/.test(month) ? month : W.nextMonth());
    function list(month) {
      if (!me()) return null;
      const m = monthOr(month);
      const rows = clientsInScope().map((p) => {
        const pl = planOf(p.id, m), ppl = socialsOf(p).map((id) => (id === meId ? 'you' : firstName(id)));
        return { pid: p.id, name: p.name || 'Client', ini: initials(p.name || 'C'), rgb: rgb(W.colorOf(p)), st: stOf(pl), sub: [pl ? plural((pl.posts || []).length, 'post') : '', ppl.join(', ')].filter(Boolean).join(' · ') || '—', mine: !!pl && (pl.status === 'review' ? canApprove(pl) : pl.status === 'changes' && isEditor(pl)) };
      });
      rows.sort((a, b) => (b.mine ? 1 : 0) - (a.mine ? 1 : 0));
      const wait = rows.filter((r) => r.mine && r.st.k === 'wait').length, back = rows.filter((r) => r.mine && r.st.k === 'chg').length;
      const mine = me().role === 'social' && !isMgr(me());
      return { month: m, label: monthLabel(m), canPrev: m > W.thisMonth(), first: W.thisMonth(), now: W.nextMonth(), last: shiftMonth(W.nextMonth(), 6), rows,
        note: wait ? `${plural(wait, 'skeleton')} waiting for your approval` : back ? `${plural(back, 'skeleton')} sent back for changes` : '',
        foot: `${mine ? 'Your clients. ' : ''}View only on the iPhone — skeletons are made, changed and sent on the computer.` };
    }
    const chName = (ks) => (ks || []).filter((k) => CH[k]).map((k) => CH[k].name).join(' · ');
    function postRow(pl, x) {
      const g = progress(x), ck = showChecks(pl) && x.check ? x.check : null;
      return { id: x.id, title: x.title || 'Untitled post', fmt: fmtOf(x.format).name, fcol: rgb(fmtOf(x.format).color), ch: chName(x.channels),
        check: ck ? { k: ck.state === 'ok' ? 'ok' : 'chg', t: ck.state === 'ok' ? `Looks good — ${who(ck.by)}` : `${who(ck.by)}: “${ck.note || 'changes'}”` } : null,
        prog: pl.status === 'approved' && x.taskId ? { t: PROG[g.k][0], k: g.k } : null };
    }
    function plan(pid, month) {
      const p = proj(pid); if (!p || !canSee() || !clientsInScope().some((x) => x.id === pid)) return null;
      const m = monthOr(month);
      const pl = planOf(pid, m);
      const head = { pid, month: m, name: p.name || 'Client', sub: monthLabel(m) + (pl && (pl.round || 1) > 1 ? ` · Round ${pl.round}` : ''), st: stOf(pl) };
      if (!pl) return { ...head, empty: 'Not started yet — content skeletons are made on the computer.' };
      const last = (act) => (pl.log || []).filter((x) => x.act === act).pop();
      let banner = null;
      if (pl.status === 'review' && pl.review) banner = { t: `Sent by ${who(pl.review.by)} · ${W.timeAgo(pl.review.at)}`, s: `To ${toLabel(pl.review.to)}${canApprove(pl) ? ' — open each post to mark it, then approve the skeleton or send it back.' : ''}` };
      else if (pl.status === 'changes') { const l = last('changes'), n = (pl.posts || []).filter((x) => x.check && x.check.state === 'changes').length; banner = { t: `By ${l ? who(l.by) : 'the approver'}${l ? ' · ' + W.timeAgo(l.at) : ''}${n ? ` — ${plural(n, 'post')} to change` : ''}`, note: l && l.note ? l.note : '' }; }
      else if (pl.status === 'approved' && pl.approval) { const made = (pl.posts || []).filter((x) => x.taskId).length; banner = { t: `By ${who(pl.approval.by)} · ${W.fmtDay(String(pl.approval.at).slice(0, 10))}`, s: made ? `${plural(made, 'task')} made` : 'Next: the tasks are made on the computer' }; }
      else banner = { t: 'Being made on the computer', s: '' };
      const posts = postsSorted(pl);
      const occs = Occ.between(firstDay(m), lastDay(m)).map((o) => { const n = posts.filter((x) => x.occasion === o.id).length; return { t: o.name, k: n ? 'ok' : skipped(p, o) ? 'skip' : 'miss' }; });
      const days = [...new Set(posts.map((x) => x.day))].map((d) => ({ d, label: dayLong(d), occ: Occ.on(d).map((o) => o.name).join(' · '),
        posts: posts.filter((x) => x.day === d).map((x) => postRow(pl, x)) }));
      const flagged = (pl.posts || []).filter((x) => x.check && x.check.state === 'changes').length;
      // (••• Trash Skeleton: its maker and the Social Manager, before any task is made from it — Haris 2026-11-10)
      const trash = !!me() && (pl.createdBy === meId || isMgr()) && !hasTasks(pl) && !pl.tasksAt;
      return { ...head, id: pl.id, banner, occs, days, trash, approve: pl.status === 'review' && canApprove(pl) ? { flagged } : null,
        foot: pl.status === 'changes' && isEditor(pl) ? 'Change it on the computer, then send it again.' : pl.status === 'approved' ? 'Each post’s progress, from its task. The client export is on the computer.' : '' };
    }
    function post(planId, postId) {
      const pl = planById(planId), x = pl && (pl.posts || []).find((y) => y.id === postId);
      if (!pl || !x || !plan(pl.projectId, pl.month)) return null;
      const o = x.occasion && Occ.byId(x.occasion), g = progress(x);
      const ref = (r) => (r.url ? { link: r.url, name: r.label || r.url } : { name: r.name || 'File', path: r.path, url: fileUrl(r), img: fileKind(r) === 'image', size: r.size || 0 });
      const ck = showChecks(pl) && x.check ? x.check : null;
      return { id: x.id, plan: pl.id, title: x.title || 'Untitled post', fmt: fmtOf(x.format).name, day: dayLong(x.day), occ: o ? o.name : '', ch: chName(x.channels),
        desc: x.desc || '', shots: x.shots || '', copyEn: x.copyEn || '', copyAr: x.copyAr || '', refs: (x.refs || []).map(ref), made: g.files.map(ref),
        check: ck ? { k: ck.state === 'ok' ? 'ok' : 'chg', t: ck.state === 'ok' ? `Looks good — ${who(ck.by)}` : `Changes asked by ${who(ck.by).replace(/^You$/, 'you')}: “${ck.note || 'changes'}”`, note: ck.note || '' } : null,
        prog: pl.status === 'approved' && x.taskId ? { t: PROG[g.k][0], k: g.k } : null,
        review: pl.status === 'review' && canApprove(pl) };
    }
    function search(q, cur, loose) {
      if (!me()) return [];
      const norm = (t) => String(t || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
      const words = norm(q).split(/\s+/).filter(Boolean);
      if (!words.length) return [];
      // (exact first; nothing found — small typos forgiven, as every search: Haris 2026-11-06)
      const lim = (w) => (w.length >= 8 ? 2 : w.length >= 4 ? 1 : 0);
      const near = (w, n) => n.includes(w) || (loose && lim(w) > 0 && n.split(/[^\p{L}\p{N}]+/u).some((x) => typoDist(w, x, lim(w)) <= lim(w) || (x.length > w.length && typoDist(w, x.slice(0, w.length), lim(w)) <= lim(w))));
      const hit = (t) => { const n = norm(t); return words.every((w) => near(w, n)); };
      const months = []; for (let m = W.thisMonth(); m <= shiftMonth(W.nextMonth(), 6); m = shiftMonth(m, 1)) months.push(m);
      if (cur && months.includes(cur)) months.sort((a, b) => (a === cur ? -1 : b === cur ? 1 : a.localeCompare(b)));
      const out = [];
      months.forEach((m) => {
        const items = [];
        clientsInScope().forEach((p) => {
          const pl = planOf(p.id, m);
          if (hit(p.name)) items.push({ pid: p.id, title: p.name || 'Client', sub: pl ? `${stOf(pl).t} · ${plural((pl.posts || []).length, 'post')}` : 'Not started', ini: initials(p.name || 'C'), rgb: rgb(W.colorOf(p)) });
          if (pl) postsSorted(pl).forEach((x) => { if (hit(x.title) || hit(`${p.name} ${x.title}`)) items.push({ pid: p.id, post: x.id, plan: pl.id, title: x.title || 'Untitled post', sub: `${p.name} · ${dayLong(x.day)}`, ini: initials(p.name || 'C'), rgb: rgb(W.colorOf(p)) }); });
        });
        if (items.length) out.push({ month: m, label: monthLabel(m), items: items.slice(0, 40) });
      });
      if (!out.length && !loose) { const l = search(q, cur, true); if (l.length) l.loose = true; return l; }
      return out;
    }
    // skeletons waiting for this person (the Plans tab's count, Plans.waiting)
    const waiting = () => (canSee() ? W.plans.filter((pl) => proj(pl.projectId) && !proj(pl.projectId).inactive && ((pl.status === 'review' && canApprove(pl)) || (pl.status === 'changes' && isEditor(pl) && me() && me().role === 'social' && (pl.createdBy === me().id || socialsOf(proj(pl.projectId)).includes(me().id))))).length : 0);
    // the skeletons waiting for this person's approval, every month, oldest sent first (the CD's Review Requests: their own
    // group "Content plans" on top of Waiting — Haris 2026-11-10, the mock-up "Review Requests — fully Apple", A2)
    const waitingList = () => (canSee() ? W.plans.filter((pl) => proj(pl.projectId) && !proj(pl.projectId).inactive && pl.status === 'review' && canApprove(pl))
      .sort((a, b) => String((a.review && a.review.at) || '').localeCompare(String((b.review && b.review.at) || '')))
      .map((pl) => {
        const p = proj(pl.projectId);
        return { id: pl.id, pid: p.id, month: pl.month, name: p.name || 'Client', ini: initials(p.name || 'C'), rgb: rgb(W.colorOf(p)),
          title: `${p.name || 'Client'} · ${monthLabel(pl.month)}`,
          sub: pl.review && pl.review.by ? `Content skeleton · ${who(pl.review.by)} sent it · ${W.timeAgo(pl.review.at)}` : 'Content skeleton' };
      }) : []);
    return { list, plan, post, search, waiting, waitingList, byId: planById };
  }

  // ---------- Client Assets (web/phone.js NativeAssets, app.js's Client Assets rules) ----------
  function assetsOf(W) {
    const { userById, fullName, me, meId, isAdm, isFinUser, foldersOf, filesOf, fmtDateTime } = W;
    const rgb = W.rgb;
    const isAdmin = () => !!isAdm(me());
    const canAssets = () => { const u = me(); return !!u && (isAdm(u) || u.role === 'am'); };
    const canAddAssets = () => { const u = me(); return !!u && !isFinUser(u) && u.role !== 'freelancer'; };
    const isAutoFolder = (c, f) => !!f.auto || (DEFAULT_FOLDERS.includes(f.name) && (!f.createdBy || f.createdBy === c.createdBy) && Math.abs(Date.parse(f.createdAt || 0) - Date.parse(c.createdAt || 0)) < 60000);
    const isFilesTop = (c, f) => !!f && !f.parentId && f.name === 'Files' && isAutoFolder(c, f);
    const topFolders = (c) => foldersOf(c).filter((f) => !f.parentId);
    const subFolders = (c, f) => foldersOf(c).filter((x) => x.parentId === f.id);
    const parentFolder = (c, f) => (f && f.parentId ? foldersOf(c).find((x) => x.id === f.parentId) || null : null);
    const folderAncestors = (c, f) => { const out = []; let p = parentFolder(c, f); while (p && out.length <= FOLDER_DEPTH && !out.includes(p)) { out.unshift(p); p = parentFolder(c, p); } return out; };
    const folderDepth = (c, f) => folderAncestors(c, f).length;
    const folderTree = (c, f) => subFolders(c, f).flatMap((x) => [x, ...folderTree(c, x)]);
    const folderPath = (c, f) => [...folderAncestors(c, f), f].map((x) => x.name).join(' › ');
    const inFiles = (c, f) => { const a = folderAncestors(c, f); return !!a.length && isFilesTop(c, a[0]); };
    const canUploadTo = (c, f) => canAddAssets() && !!f && !f.finalOf && !isFilesTop(c, f);
    const canMakeSub = (c, f) => canAddAssets() && !!f && !f.finalOf && (isFilesTop(c, f) || (inFiles(c, f) && folderDepth(c, f) < FOLDER_DEPTH));
    const folderFileCount = (c, f) => [f, ...folderTree(c, f)].reduce((n, x) => n + filesOf(x).length, 0);
    const canDelAsset = (a) => canAddAssets() && !(a && a.final) && (canAssets() || (!!a && a.addedBy === meId));
    const canEditFolder = (c, f) => isAdmin() || (canAddAssets() && !isAutoFolder(c, f) && (canAssets() || f.createdBy === meId));
    const canDelFolder = (c, f) => canEditFolder(c, f) && (canAssets() || [f, ...folderTree(c, f)].every((x) => x.createdBy === meId || x === f) && [f, ...folderTree(c, f)].every((x) => filesOf(x).every((a) => a.addedBy === meId)));
    const canRenameCA = (c) => isAdmin() || (!!c && c.createdBy === meId);
    const clientById = (id) => W.clients.find((c) => c.id === id) || null;
    const caVisible = (c) => { const linked = W.projects.filter((p) => p.clientId === c.id); return !linked.length || linked.some((p) => W.amSidebarOk(p)); };
    const clientsSorted = () => W.clients.filter(caVisible).sort((a, b) => a.name.localeCompare(b.name));
    const clientFileCount = (c) => foldersOf(c).reduce((n, f) => n + filesOf(f).length, 0);
    const logoOf = (c) => (c.logo ? pathUrl(c.logo) : null);

    function infoOf(c, f, a) {
      const who = (id) => (id && userById(id) ? fullName(userById(id)) : id ? 'Former team member' : '—');
      const when = (iso) => (iso ? fmtDateTime(iso) : '—');
      if (a && a.final) {
        const m = a.final, t = W.task(m.taskId);
        const client = m.clientNone ? 'not needed' : m.clientBy ? `recorded by ${who(m.clientBy)}` : 'not recorded';
        return { rows: [['Completed', when(m.completedAt)], ['Task', m.taskTitle || f.name], ['Task created by', who(m.createdBy)], ['Assignee', who(m.assignee)],
          ['Approved by', `${who(m.cdBy)} (CD)${m.clientBy ? ' & the client' : ''}`], ['CD approved', when(m.cdAt)], ['Client approval', m.clientBy ? when(m.clientAt) + ' · ' + client : client],
          ['Size', fmtSize(a.size)], ['Type', (fileExt(a.name) || 'file').toUpperCase()]],
          task: t && !t.deleted ? t.id : null };
      }
      if (a) return { rows: [['Added by', who(a.addedBy)], ['Date added', when(a.addedAt)], ['Size', fmtSize(a.size)], ['Type', (fileExt(a.name) || 'file').toUpperCase()], ['Folder', `${c.name} › ${folderPath(c, f)}`]] };
      const tree = folderTree(c, f), all = filesOf(f).concat(...tree.map((x) => filesOf(x)));
      const rows = [['Created by', isAutoFolder(c, f) && !f.finalOf ? 'Made with the client' : who(f.createdBy)], ['Date', when(f.createdAt || c.createdAt)],
        ...(isFilesTop(c, f) || tree.length ? [['Folders', String(tree.length)]] : []), ...(f.parentId ? [['Location', `${c.name} › ${folderAncestors(c, f).map((x) => x.name).join(' › ')}`]] : []),
        ['Files', String(all.length)], ['Size', fmtSize(all.reduce((n, x) => n + (x.size || 0), 0))]];
      if (f.finalOf) rows.unshift(['Kind', 'Final files of a completed task']);
      return { rows };
    }
    function fileOf(c, f, a) {
      const e = fileExt(a.name);
      const pic = isImage(a) && !/\.svg$/i.test(String(a.path || ''));
      return {
        id: a.id, name: a.name, size: a.size || 0, file: a.path || null, url: a.path ? fileUrl(a) + '?view=1' : null,
        thumbUrl: pic ? imgUrl(a, 320) : e === 'svg' && a.path ? fileUrl(a) + '?view=1' : a.thumb ? pathUrl(a.thumb) + '?view=1'
          : a.path && THUMBED.includes(e) ? '/api/fthumb?path=' + encodeURIComponent(a.path) + '&id=' + encodeURIComponent(a.id || '') : null,
        ext: (e || 'file').slice(0, 5), kind: fileKind(a), label: OFFICE_LABEL[e] || (e ? e.toUpperCase() : 'File'),
        folder: f.id, at: a.addedAt || '', by: a.addedBy ? fullName(userById(a.addedBy)) : '', where: `${c.name} › ${folderPath(c, f)}`,
        canDel: !f.finalOf && canDelAsset(a), info: infoOf(c, f, a),
      };
    }
    function folderOf(c, f) {
      const sibs = foldersOf(c).filter((x) => (x.parentId || null) === (f.parentId || null));
      return {
        id: f.id, name: f.name, parent: f.parentId || null, final: !!f.finalOf, dir: f.dir, rgb: rgb(FOLDER_HEX[Math.max(0, sibs.indexOf(f)) % FOLDER_HEX.length]),
        files: filesOf(f).length, subs: subFolders(c, f).length, total: folderFileCount(c, f), path: folderPath(c, f),
        by: isAutoFolder(c, f) && !f.finalOf ? 'Made with the client' : f.createdBy ? fullName(userById(f.createdBy)) : '', at: f.createdAt || c.createdAt || '',
        size: [f, ...folderTree(c, f)].reduce((n, x) => n + filesOf(x).reduce((m, a) => m + (a.size || 0), 0), 0),
        canUpload: canUploadTo(c, f), canSub: canMakeSub(c, f), canRename: canEditFolder(c, f) && !f.finalOf, canDel: canDelFolder(c, f), info: infoOf(c, f, null),
        canLink: !isFilesTop(c, f),
        note: isFilesTop(c, f) ? 'Files holds folders — one per job. Make a folder here, then add the files in it.' : f.finalOf ? 'Final files are filed by the app when the task is completed.' : '',
      };
    }
    function clientModel(c) {
      const tops = topFolders(c);
      const files = [];
      foldersOf(c).forEach((f) => filesOf(f).forEach((a) => files.push(fileOf(c, f, a))));
      const recent = files.filter((x) => x.at).sort((a, b) => b.at.localeCompare(a.at)).slice(0, 5).map((x) => x.id);
      return {
        kind: 'client', id: c.id, name: c.name, logo: logoOf(c), rgb: rgb(avColor(c.id)), ini: initials(c.name),
        sub: `${plural(tops.length, 'folder')} · ${plural(files.length, 'file')}`,
        folders: foldersOf(c).map((f) => folderOf(c, f)), files, recent,
        canNewTop: canAssets(), canRename: canRenameCA(c), canDelete: isAdmin(),
        by: c.createdBy ? fullName(userById(c.createdBy)) : '', at: c.createdAt || '',
      };
    }
    function allModel() {
      const list = clientsSorted();
      const n = list.reduce((s, c) => s + clientFileCount(c), 0);
      return {
        kind: 'all', sub: `${plural(list.length, 'client')} · ${plural(n, 'file')}`, canAdd: canAssets(),
        clients: list.map((c) => ({ id: c.id, name: c.name, logo: logoOf(c), rgb: rgb(avColor(c.id)), ini: initials(c.name), sub: `${plural(topFolders(c).length, 'folder')} · ${plural(clientFileCount(c), 'file')}` })),
        files: list.flatMap((c) => foldersOf(c).flatMap((f) => filesOf(f).map((a) => ({ ...fileOf(c, f, a), client: c.id })))),
      };
    }
    // (NativeAssets modelFor: a client not there or not shared with this person → null)
    const modelFor = (id) => (id ? (clientById(id) && caVisible(clientById(id)) ? clientModel(clientById(id)) : null) : allModel());
    return { modelFor };
  }

  // ---------- the screens ----------
  X.plansList = (R, data, me, nowMs, month) => plansOf(world(R, data, me, nowMs)).list(month);
  X.plan = (R, data, me, nowMs, pid, month) => plansOf(world(R, data, me, nowMs)).plan(String(pid || ''), month);
  X.plansPost = (R, data, me, nowMs, planId, postId) => plansOf(world(R, data, me, nowMs)).post(String(planId || ''), String(postId || ''));
  X.plansSearch = (R, data, me, nowMs, q, cur) => plansOf(world(R, data, me, nowMs)).search(q, cur);
  X.plansFind = (R, data, me, nowMs, q, cur) => { const f = plansOf(world(R, data, me, nowMs)).search(String(q || ''), String(cur || '')); return { ok: true, q, found: f, loose: !!f.loose }; };   // (the app without the website — Haris 2026-11-06)
  // (a skeleton by its own id — a notification about it, its link files…/p/<id>: its client and month, as the app opens
  //  it; null when it's gone or not this person's to see — Haris 2026-11-10)
  X.planRef = (R, data, me, nowMs, id) => { const P = plansOf(world(R, data, me, nowMs)), pl = P.byId(String(id || '')); return pl && P.plan(pl.projectId, pl.month) ? { pid: pl.projectId, month: pl.month } : null; };
  X.plansWaiting = (R, data, me, nowMs) => plansOf(world(R, data, me, nowMs)).waiting();
  X.plansForMe = (R, data, me, nowMs) => ({ rows: plansOf(world(R, data, me, nowMs)).waitingList() });
  X.plansShift = (m, n) => shiftMonth(m, n);
  X.assets = (R, data, me, nowMs, clientId) => assetsOf(world(R, data, me, nowMs)).modelFor(clientId || null);
})(E11AppMe);
if (typeof module !== 'undefined' && module.exports) module.exports = E11AppMe;
