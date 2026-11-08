/* The app's own Me screens, worked out from a person's data (Part B step 2, 2026-11-05): Me's card and Work rows,
   Team members, the Trash and My profile — exactly the models the page builds today for the app (phone.js NativeMe:
   model(), teamModel(), trashModel(), profileModel()), so the iPhone app can draw them from its own copy of the data
   (iPhone's JavaScript engine) with no page at all. It only reads; changes still go the page's / server's way.
   R: E11Rules · data: this person's /api/snapshot data · me: their id · nowMs: the clock (a number, or a function).
   env (optional, last): what the data doesn't hold —
     { ownerId: the app's owner (/api/me ownerId: their Team row shows locked),
       host: the server's address as people type it (Team's note; none: the note without it),
       shell: the iPhone app's shell number (Me's Work: an Office Admin without Finance has Client Assets and Team as
              tabs from 36; default: the current app),
       server: connected to the server (default true: the iPhone app always is) }.
   Not here (the device's / page's own): Me's push, lock, digest, theme, about, test, version, sync; My profile's
   photoBusy and owner (Owner view). */
var E11AppMe = (typeof E11AppMe !== 'undefined' && E11AppMe) || {};
(function (M) {
  'use strict';
  const TRASH_DAYS = 30, AUTO_DELETE_DAYS = 30;
  const PLANS_ON = true;   // (Plans.on(): content plans are on everywhere since 2026-10-28)
  const ROLES = { admin: 'Super Admin', office_admin: 'Office Admin', am: 'Account Manager', production: 'Production', social: 'Social', freelancer: 'Freelancer', finance_admin: 'Finance only · Admin', finance_viewer: 'Finance only · Viewer' };
  const TEAM_LABEL = { admin: 'Super Admin', office_admin: 'Office Admin', am: 'Account Manager', production: 'Production Team', social: 'Social Team', freelancer: 'Freelancer' };
  const FIN_ACCESS = { '': 'No Finance access', admin: 'Finance Admin', viewer: 'Finance Viewer' };
  const AV_COLORS = ['#7b68ee', '#4c9aff', '#3ddc97', '#f9be33', '#ff8a4c', '#e5484d', '#ff8fc7', '#4fd1c5', '#a875ff'];
  const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const PLACE_SHORT = { 'United Arab Emirates': 'UAE', 'United Kingdom': 'UK', 'United States': 'USA', 'Saudi Arabia': 'KSA' };
  const IMG_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp', 'tif', 'tiff', 'svg'];
  const VID_EXT = ['mp4', 'mov', 'm4v', 'webm'];
  const AUD_EXT = ['mp3', 'm4a', 'aac', 'wav', 'aif', 'aiff'];
  const TXT_EXT = ['txt', 'md', 'csv', 'log', 'json', 'xml'];
  const NOTIF_TYPES = [
    { k: 'assign', l: 'Assigned or removed', d: 'Someone adds you to a task or takes you off it' },
    { k: 'mention', l: '@Mentions', d: 'Someone tags you in a comment or a description' },
    { k: 'comment', l: 'Comments & replies', d: 'New comments on your tasks and replies in your threads' },
    { k: 'status', l: 'Status & completion', d: 'A task moves to another status or is marked complete' },
    { k: 'update', l: 'Task Update changes', d: 'The Task Update of a task you’re on changes' },
    { k: 'cd', l: 'CD Status changes', d: 'The CD Status of a task is set or cleared' },
    { k: 'client', l: 'Changes on your clients’ tasks', d: 'Account Managers: anything changed on a task in a client you look after' },
    { k: 'due', l: 'Due dates', d: 'A due date is added, moved or removed' },
    { k: 'priority', l: 'Priority', d: 'Your priority on a task is changed' },
    { k: 'attach', l: 'Files added', d: 'Someone attaches files to a task' },
    { k: 'part', l: 'Parts done', d: 'Someone finishes or reopens their part of a shared task' },
    { k: 'result', l: 'CD review results', d: 'The CD approves your files or asks for amendments' },
    { k: 'review', l: 'New review requests', d: 'Someone submits files for your review', cd: true },
    { k: 'review-wd', l: 'Withdrawn submissions', d: 'Someone withdraws files they sent for review', cd: true },
    { k: 'daily', l: 'Morning round-up', d: '9:00, Monday to Friday (not on UAE public holidays): overdue, due today, waiting for CD and more in one update', lead: true },
  ];
  const TRASH_TYPE = { task: 'Task', project: 'Client', comment: 'Comment', attachment: 'File', cafile: 'Client file', cafolder: 'Client folder' };
  const TR_SYM = { task: ['checkmark.circle.fill', [10, 132, 255]], project: ['folder.fill', [255, 149, 0]], comment: ['quote.bubble.fill', [175, 82, 222]], attachment: ['paperclip', [48, 176, 199]], cafile: ['doc.fill', [48, 176, 199]], cafolder: ['folder.fill', [48, 176, 199]] };
  const GROUPS = [['admin', 'Super Admins'], ['office_admin', 'Office Admins'], ['am', 'Account Managers'], ['production', 'Production'], ['social', 'Social'], ['freelancer', 'Freelancers'], ['finance', 'Finance only']];

  // ---------- text, dates, files (app.js's own, on the clock given) ----------
  const pad2 = (n) => String(n).padStart(2, '0');
  const ymd = (d) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  const parseYmd = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
  const trunc = (v, n = 140) => { v = String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); return v.length > n ? v.slice(0, n - 1) + '…' : v; };
  const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', hellip: '…', mdash: '—', ndash: '–', middot: '·', bull: '•', copy: '©', reg: '®', trade: '™', times: '×', euro: '€' };
  const decode = (s) => s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') { const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10); try { return String.fromCodePoint(n); } catch (x) { return m; } }
    return Object.prototype.hasOwnProperty.call(ENT, e.toLowerCase()) ? ENT[e.toLowerCase()] : m;
  });
  // (notifPlainHTML without a page: the tags gone, the entities read, the spaces as one)
  const plainHTML = (html) => decode(String(html || '').replace(/<(br|\/p|\/li|\/div)>/gi, ' $&').replace(/<!--[\s\S]*?-->/g, '').replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, '').replace(/<\/?[a-z!][^>]*>/gi, '')).replace(/\s+/g, ' ').trim();
  const fileExt = (name) => (String(name).split('.').pop() || '').toLowerCase();
  const isImage = (a) => IMG_EXT.includes(fileExt(a.name));
  const fileKind = (a) => { const e = fileExt(a.name); return IMG_EXT.includes(e) ? 'image' : VID_EXT.includes(e) ? 'video' : AUD_EXT.includes(e) ? 'audio' : e === 'pdf' ? 'pdf' : TXT_EXT.includes(e) ? 'text' : 'other'; };
  const fileUrl = (a) => '/__file/' + String(a.path).split('/').map(encodeURIComponent).join('/');
  // (a middle "Al" is skipped: Yousef Al Hwij → YH, Lana Al Ramli → LR, Al-Ramli too — Haris 2026-11-08)
  const initials = (name) => { const w = String(name || '').trim().split(/\s+/).filter(Boolean); if (w.length > 2 && /^al$/i.test(w[1])) w.splice(1, 1); const two = w.slice(0, 2).map((x, i) => (i > 0 ? x.replace(/^al-(?=.)/i, '') : x)[0] || ''); return two.join('').toUpperCase() || '?'; };
  const avColor = (id) => { let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return AV_COLORS[h % AV_COLORS.length]; };
  const fmtMD = (md) => { const m = /^(\d{2})-(\d{2})$/.exec(String(md || '')); return m ? `${Number(m[2])} ${MONTH_NAMES[Number(m[1]) - 1]}` : ''; };
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
  // search (app.js smart search: whole words, starts, parts, then one or two letters off)
  const sNorm = (s) => String(s || '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/[’'`]/g, '');
  const sWords = (s) => sNorm(s).split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  function editDist(a, b, max) {
    if (Math.abs(a.length - b.length) > max) return max + 1;
    const prev2 = new Array(b.length + 1), prev = new Array(b.length + 1), cur = new Array(b.length + 1);
    for (let j = 0; j <= b.length; j++) prev[j] = j;
    for (let i = 1; i <= a.length; i++) {
      cur[0] = i; let best = cur[0];
      for (let j = 1; j <= b.length; j++) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1;
        let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
        if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
        cur[j] = v; if (v < best) best = v;
      }
      if (best > max) return max + 1;
      for (let j = 0; j <= b.length; j++) { prev2[j] = prev[j]; prev[j] = cur[j]; }
    }
    return prev[b.length];
  }
  const typoLimit = (w) => (w.length >= 8 ? 2 : w.length >= 4 ? 1 : 0);
  function termMatches(term, vocab) {
    const out = new Map();
    let close = false;
    vocab.forEach((w) => {
      if (w === term) { out.set(w, 1); close = true; } else if (w.startsWith(term)) { out.set(w, 0.85); close = true; } else if (term.length >= 3 && w.includes(term)) { out.set(w, 0.55); close = true; }
    });
    let fuzzy = null;
    if (!close && typoLimit(term)) {
      let bestD = 99;
      vocab.forEach((w) => {
        const lim = typoLimit(term);
        const d = Math.min(editDist(term, w, lim), w.length > term.length ? editDist(term, w.slice(0, term.length), lim) : 99);
        if (d <= lim) { out.set(w, d === 1 ? 0.45 : 0.3); if (d < bestD || (d === bestD && fuzzy && w.length < fuzzy.length)) { bestD = d; fuzzy = w; } }
      });
    }
    return { words: out, fuzzy };
  }

  // ---------- one person's world: the data as the website holds it (app.js normalize, where it matters) ----------
  function world(R, data, meId, nowMs, env) {
    data = data || {};
    env = env || {};
    const clock = typeof nowMs === 'function' ? nowMs : () => (nowMs == null ? Date.now() : Number(nowMs));
    const NOW = clock();
    const meta = data.meta || {};
    const users = (Array.isArray(data.users) ? data.users : []).map((u) => Object.assign({}, u, { prefs: u.prefs || {}, active: u.active == null ? true : u.active }));
    const firstAdmin = users.length ? (users.find((u) => u.role === 'admin') || users[0]).id : 'u-haris';
    const tasks = (Array.isArray(data.tasks) ? data.tasks : []).map((t) => (Array.isArray(t.assignees) ? t : Object.assign({}, t, { assignees: [firstAdmin] })));
    const projects = Array.isArray(data.projects) ? data.projects : [];
    const clients = (Array.isArray(data.clients) ? data.clients : []).map((c) => Object.assign({}, c, { folders: Array.isArray(c.folders) ? c.folders : [] }));
    const trash = Array.isArray(data.trash) ? data.trash : [];
    const plans = Array.isArray(data.plans) ? data.plans : [];
    const W = { R, meta, users, tasks, projects, clients, trash, plans, meId, NOW, env };

    const userById = (id) => users.find((u) => u.id === id) || null;
    const me = () => userById(meId);
    const fullName = (u) => (u ? (u.name || u.email.split('@')[0]) : 'Former member');
    const proj = (id) => projects.find((p) => p.id === id);
    const task = (id) => tasks.find((t) => t.id === id);
    const clientById = (id) => clients.find((c) => c.id === id) || null;
    const isAdm = (u) => !!u && (u.role === 'admin' || u.role === 'office_admin' || u.admin === true);
    const isOffice = (u = me()) => !!u && u.role === 'office_admin' && u.admin !== true;
    const isSuper = (u = me()) => isAdm(u) && !isOffice(u);
    const isFinUser = (u = me()) => !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer');
    const finLevel = (u = me()) => (!u ? null : u.role === 'finance_admin' ? 'admin' : u.role === 'finance_viewer' ? 'viewer' : u.fin === 'admin' || u.fin === 'viewer' ? u.fin : null);
    const isManager = (u = me()) => !!u && (isAdm(u) || u.role === 'am');
    const cdUserId = () => { const id = meta.cdUserId; const u = id && userById(id); return u && u.active !== false ? id : null; };
    const isCD = (id = meId) => !!id && id === cdUserId();
    const cdActing = () => !!(meta.cdActing && cdUserId());
    const cdTitle = () => (cdActing() ? 'Acting CD' : 'Creative Director');
    const socialMgrIds = () => (meta.socialMgrIds || []).filter((id) => { const u = userById(id); return u && u.active !== false && u.role === 'social'; });
    const isSocialMgr = (id = meId) => PLANS_ON && !!id && socialMgrIds().includes(id);
    const roleOf = (u) => (u && u.id === cdUserId() ? cdTitle() : u && isSocialMgr(u.id) ? 'Social Manager' : (u && (ROLES[u.role] || u.role)) || '');
    const designationOf = (u) => {
      if (!u) return '';
      if (u.id === cdUserId()) return cdActing() ? `Acting Creative Director · ${TEAM_LABEL[u.role] || ''}` : 'Creative Director';
      if (isSocialMgr(u.id)) return 'Social Manager';
      return TEAM_LABEL[u.role] || '';
    };
    const placeOf = (u) => [u && u.city, u && u.country && (PLACE_SHORT[u.country] || u.country)].filter(Boolean).join(', ');
    const rgb = (hex) => (R && R.rgbOf ? R.rgbOf(hex) : null) || [135, 144, 158];
    const photoOf = (u) => (u && u.avatar ? fileUrl({ path: u.avatar }) : null);
    const server = env.server !== false;
    const imgUrl = (a, w) => fileUrl(a) + (server && !/\.svg$/i.test(String(a.path)) ? '?w=' + w : '');
    // dates on the clock given (the page's own: the device's time zone)
    const todayStr = () => ymd(new Date(NOW));
    const dayDiff = (s) => Math.round((parseYmd(s) - parseYmd(todayStr())) / 86400000);
    const timeAgo = (iso) => {
      const s = (NOW - new Date(iso).getTime()) / 1000;
      if (s < 60) return 'just now';
      if (s < 3600) return Math.floor(s / 60) + 'm ago';
      if (s < 86400) return Math.floor(s / 3600) + 'h ago';
      if (s < 86400 * 7) return Math.floor(s / 86400) + 'd ago';
      return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    };
    // can('manageUsers'): Admin rights (never a Finance-only person)
    const canManageUsers = () => { const u = me(); return !!u && !isFinUser(u) && isAdm(u); };
    Object.assign(W, { userById, me, fullName, proj, task, clientById, isAdm, isOffice, isSuper, isFinUser, finLevel, isManager, cdUserId, isCD, cdActing, cdTitle,
      socialMgrIds, isSocialMgr, roleOf, designationOf, placeOf, rgb, photoOf, imgUrl, todayStr, dayDiff, timeAgo, canManageUsers });

    // ---------- content plans (plans.js: who sees them, who approves, what waits for you) ----------
    const isMgr = (u = me()) => !!u && u.role === 'social' && socialMgrIds().includes(u.id);
    const plansCanSee = (u = me()) => PLANS_ON && !!u && u.active !== false && !isFinUser(u) && !isOffice(u) && (isAdm(u) || u.role === 'am' || u.role === 'social' || isCD(u.id));
    const socialsOf = (p) => ((p && p.socials) || []).filter((id) => { const u = userById(id); return u && u.active !== false; });
    const canEditClient = (pid, u = me()) => PLANS_ON && !!u && u.role === 'social' && u.active !== false && (isMgr(u) || socialsOf(proj(pid)).includes(u.id));
    const isEditor = (pl) => !!pl && canEditClient(pl.projectId);
    const sentTo = (pl, k) => { const t = pl && pl.review && pl.review.to; return !t || t === 'both' || t === k; };
    const canApprove = (pl, u = me()) => !!pl && PLANS_ON && !!u && ((u.id === cdUserId() && sentTo(pl, 'cd')) || (isMgr(u) && pl.createdBy !== u.id && sentTo(pl, 'sm')));
    const plansWaiting = () => (plansCanSee() ? plans.filter((pl) => proj(pl.projectId) && !proj(pl.projectId).inactive && ((pl.status === 'review' && canApprove(pl)) || (pl.status === 'changes' && isEditor(pl) && me() && me().role === 'social' && (pl.createdBy === me().id || socialsOf(proj(pl.projectId)).includes(me().id))))).length : 0);
    const calCanSee = (u = me()) => !!u && u.active !== false && (isAdm(u) || u.role === 'am' || u.role === 'social');
    const calendarRetired = () => PLANS_ON;
    Object.assign(W, { plansCanSee, plansWaiting, calCanSee, calendarRetired });

    // ---------- the Trash (app.js) ----------
    const trashDaysLeft = (it) => Math.max(0, TRASH_DAYS - Math.floor((NOW - new Date(it.deletedAt).getTime()) / 86400000));
    function trashFiles(it) {
      const d = it.data || {};
      const fromTasks = (list) => (list || []).flatMap((t) => (t.attachments || []).concat(...(t.comments || []).map((c) => c.attachments || [])));
      if (it.type === 'task') return fromTasks(d.tasks);
      if (it.type === 'project') return fromTasks(d.tasks);
      if (it.type === 'comment') return (d.comments || []).flatMap((c) => c.attachments || []);
      if (it.type === 'attachment') return d.att ? [d.att] : [];
      if (it.type === 'cafile') return d.file ? [d.file] : [];
      if (it.type === 'cafolder') return [d.folder, ...(d.inner || [])].filter(Boolean).flatMap((x) => x.files || []);
      return [];
    }
    function trashWhere(it) {
      const d = it.data || {};
      if (it.type === 'task') { const p = proj(it.projectId) || (d.tasks && d.tasks[0] && proj(d.tasks[0].projectId)); return p ? p.name : it.projectName || 'My Tasks'; }
      if (it.type === 'project') return `${(d.tasks || []).filter((t) => !t.parentId).length} tasks`;
      if (it.type === 'comment' || it.type === 'attachment') { const t = task(d.taskId); return t ? t.title || 'Untitled task' : it.taskTitle || 'a deleted task'; }
      if (it.type === 'cafile') { const c = clientById(d.clientId); const f = c && c.folders.find((x) => x.id === d.folderId); return c ? `${c.name}${f ? ' › ' + f.name : ''}` : it.where || 'Client Assets'; }
      if (it.type === 'cafolder') { const c = clientById(d.clientId); return c ? c.name : it.where || 'Client Assets'; }
      return '';
    }
    function trashTitle(it) {
      const d = it.data || {};
      if (it.type === 'task') return (d.tasks && (d.tasks.find((t) => !t.parentId || !d.tasks.some((x) => x.id === t.parentId)) || d.tasks[0]) || {}).title || 'Untitled task';
      if (it.type === 'project') return d.project ? d.project.name : 'Client';
      if (it.type === 'comment') { const c = (d.comments || [])[0]; return c ? trunc(c.text || plainHTML(c.html), 80) || 'Comment' : 'Comment'; }
      if (it.type === 'attachment') return d.att ? d.att.name : 'File';
      if (it.type === 'cafile') return d.file ? d.file.name : 'File';
      if (it.type === 'cafolder') return d.folder ? d.folder.name : 'Folder';
      return 'Item';
    }
    function trashSearch(q, list) {
      const terms = sWords(q);
      if (!terms.length) return { items: list.slice().sort((a, b) => b.deletedAt.localeCompare(a.deletedAt)), fixed: [], terms: [] };
      const docs = list.map((it) => {
        const d = it.data || {};
        const files = trashFiles(it);
        const fields = [
          { w: 10, text: trashTitle(it) }, { w: 5, text: trashWhere(it) }, { w: 4, text: TRASH_TYPE[it.type] + ' ' + (it.type === 'attachment' || it.type === 'cafile' ? 'file' : '') },
          { w: 4, text: files.map((a) => `${a.name} ${fileExt(a.name)} ${fileKind(a)}`).join(' ') },
          { w: 3, text: it.deletedBy ? fullName(userById(it.deletedBy)) : 'automatic cleanup' },
          { w: 2, text: (d.tasks || []).map((t) => `${t.title} ${(t.tags || []).join(' ')} ${t.notes || ''} ${(t.comments || []).map((c) => c.text).join(' ')}`).join(' ') },
          { w: 2, text: (d.comments || []).map((c) => c.text || plainHTML(c.html)).join(' ') },
          { w: 3, text: d.project ? d.project.name : '' },
        ];
        const words = new Map();
        fields.forEach((f) => sWords(f.text).forEach((w) => { if (!words.has(w) || words.get(w) < f.w) words.set(w, f.w); }));
        return { it, words };
      });
      const vocab = new Set(); docs.forEach((x) => x.words.forEach((_, w) => vocab.add(w)));
      const fixed = [];
      const per = terms.map((term) => { const m = termMatches(term, vocab); if (m.fuzzy && !m.words.has(term)) fixed.push({ from: term, to: m.fuzzy }); return { term, words: m.words }; });
      const scored = [];
      docs.forEach(({ it, words }) => {
        let score = 0;
        for (const pt of per) { let best = 0; pt.words.forEach((q2, w) => { const v = words.get(w); if (v && v * q2 > best) best = v * q2; }); if (!best) return; score += best; }
        scored.push({ it, score });
      });
      scored.sort((a, b) => b.score - a.score || b.it.deletedAt.localeCompare(a.it.deletedAt));
      return { items: scored.map((x) => x.it), fixed, terms: per };
    }
    const trashFiltered = (f) => { f = f || 'all'; return trash.filter((it) => f === 'all' || (f === 'file' ? it.type === 'attachment' || it.type === 'cafile' || it.type === 'cafolder' : f === 'mine' ? it.deletedBy === meId : it.type === f)); };
    Object.assign(W, { trashDaysLeft, trashFiles, trashWhere, trashTitle, trashSearch, trashFiltered });
    return W;
  }

  // ---------- Me: your card and the Work rows (NativeMe model(): card, work) ----------
  M.me = function (R, data, meId, nowMs, env) {
    const W = world(R, data, meId, nowMs, env), u = W.me();
    if (!u) return null;
    const shell = W.env.shell == null ? Infinity : Number(W.env.shell) || 0;
    const work = [];
    if (W.isCD()) work.push({ k: 'projects', t: 'Clients', s: 'Every client’s tasks', sym: 'folder.fill', col: [10, 132, 255] });
    if (W.calCanSee() && !W.calendarRetired()) work.push({ k: 'calendar', t: 'Content calendar', s: 'Posts by day, channel and occasion', sym: 'calendar', col: [255, 59, 48] });
    const socialPlans = u.role === 'social' && W.plansCanSee(u);
    if (W.plansCanSee() && !socialPlans) work.push({ n: W.plansWaiting(), k: 'plans', t: 'Content plans', s: 'Each client’s month', sym: 'calendar.badge.clock', col: [255, 149, 0] });
    const offTabs = shell >= 36 && W.isOffice() && !(W.isOffice() && !!W.finLevel(u));
    if (!offTabs) work.push({ k: 'clients', t: 'Client Assets', s: 'Logos, guidelines and fonts', sym: 'folder.fill', col: [48, 176, 199] });
    if (!offTabs) work.push({ k: 'team', t: 'Team members', s: '', sym: 'person.2.fill', col: [88, 86, 214] });
    if (W.isManager()) { const n = W.trash.length; work.push({ k: 'trash', t: 'Trash', s: n ? `${plural(n, 'item')} · restore within ${TRASH_DAYS} days` : `Deleted items wait here ${TRASH_DAYS} days`, sym: 'trash.fill', col: [142, 142, 147] }); }
    return {
      card: { id: u.id, name: W.fullName(u), role: W.designationOf(u), email: u.email, photo: W.photoOf(u), ini: initials(W.fullName(u)), rgb: W.rgb(avColor(u.id)) },
      work,
      // (the morning summary row: Production and Social — app.js Digest.wants; step 9)
      digest: u.role === 'production' || u.role === 'social' ? { on: !((u.prefs || {}).digestOff) } : null,
    };
  };

  // ---------- My profile (NativeMe profileModel(), without photoBusy and owner) ----------
  M.profile = function (R, data, meId, nowMs, env) {
    const W = world(R, data, meId, nowMs, env), u = W.me();
    if (!u) return null;
    const off = (u.prefs || {}).notifOff || {};
    const pills = [{ t: W.roleOf(u), c: u.role === 'admin' || u.role === 'office_admin' ? [255, 149, 0] : [10, 132, 255] }];
    if (u.admin && u.role !== 'admin') pills.push({ t: '+ Admin', c: [255, 149, 0] });
    if (u.fin && !W.isFinUser(u)) pills.push({ t: '+ ' + FIN_ACCESS[u.fin], c: [52, 199, 89] });
    if (u.id === W.cdUserId()) pills.push({ t: W.cdTitle(), c: [175, 82, 222] });
    const dailyWants = u.role === 'am' || W.isSuper(u);   // (daily.js Daily.wants)
    const types = (cd) => NOTIF_TYPES.filter((x) => !!x.cd === cd && (!x.lead || dailyWants)).map((x) => ({ k: x.k, t: x.l, s: x.d, on: !off[x.k] }));
    return {
      photo: W.photoOf(u), ini: initials(W.fullName(u)), rgb: W.rgb(avColor(u.id)), hasPhoto: !!u.avatar,
      name: u.name || '', email: u.email || '', country: u.country || '', city: u.city || '', bday: u.bday ? fmtMD(u.bday) : '', md: u.bday || '',
      pills, sound: (u.prefs || {}).sound !== false, notify: types(false), cd: u.id === W.cdUserId() ? { title: W.cdTitle(), types: types(true) } : null,
    };
  };

  // ---------- the Trash (NativeMe trashModel()): q = the search, filter = the category ('all', 'task', …) ----------
  M.trash = function (R, data, meId, nowMs, q, filter, env) {
    const W = world(R, data, meId, nowMs, env), u = W.me();
    if (!u) return null;
    q = q || ''; filter = filter || 'all';
    const r = W.trashSearch(q, W.trashFiltered(filter)), all = W.trash;
    const isAdmMe = W.isAdm(u), superMe = W.isSuper(u), native = true;   // (Host.isNative: the app shows files)
    const groups = [];
    r.items.forEach((it) => {
      const days = -W.dayDiff(ymd(new Date(it.deletedAt)));
      const name = q ? 'Results' : days <= 0 ? 'Today' : days < 7 ? 'This week' : 'Earlier';
      let g = groups.find((x) => x.name === name); if (!g) { g = { name, items: [] }; groups.push(g); }
      const left = W.trashDaysLeft(it), files = W.trashFiles(it);
      const who = it.auto ? 'Cleaned up automatically' : `Deleted by ${it.deletedBy === meId ? 'you' : W.fullName(W.userById(it.deletedBy))}`;
      const [sym, col] = TR_SYM[it.type] || ['trash.fill', [142, 142, 147]];
      g.items.push({ id: it.id, type: it.type, t: W.trashTitle(it), s: [TRASH_TYPE[it.type] || '', W.trashWhere(it), who, W.timeAgo(it.deletedAt)].filter(Boolean).join(' · '), sym, col,
        left: `${left} day${left === 1 ? '' : 's'} left`, soon: left <= 3, task: it.type === 'task',
        restore: it.type !== 'project' || isAdmMe, forever: superMe,
        files: files.slice(0, 4).map((a) => ({ id: a.id, pic: isImage(a) && native ? W.imgUrl(a, 160) : null, ext: (fileExt(a.name) || 'file').slice(0, 4).toUpperCase() })), more: Math.max(0, files.length - 4) });
    });
    return { n: all.length, q, cat: filter, groups, empty: superMe && all.length > 0,
      none: r.items.length ? '' : q ? `Nothing in the Trash matches “${q}”` : `The Trash is empty — deleted tasks, clients, comments and files wait here for ${TRASH_DAYS} days.`,
      note: `Deleted items stay here for ${TRASH_DAYS} days, then they and their files are removed for good. Finished tasks arrive here ${AUTO_DELETE_DAYS} days after they’re completed.` };
  };

  // ---------- Team members (NativeMe teamModel()) ----------
  M.team = function (R, data, meId, nowMs, env) {
    const W = world(R, data, meId, nowMs, env);
    if (!W.me()) return null;
    const admin = W.canManageUsers(), manager = W.isManager(), ownerId = W.env.ownerId || null;
    const person = (u) => {
      const pills = [];
      if (u.id === W.cdUserId()) pills.push({ t: W.cdActing() ? 'Acting CD' : 'Creative Director', c: [175, 82, 222] });
      else if (W.meta.cdHomeId === u.id && W.cdActing()) pills.push({ t: 'CD · away', c: [142, 142, 147] });
      if (W.isSocialMgr(u.id)) pills.push({ t: 'Social Manager', c: [255, 45, 85] });
      if (u.admin && u.role !== 'admin') pills.push({ t: '+ Admin', c: [255, 149, 0] });
      if (u.fin && !W.isFinUser(u)) pills.push({ t: '+ ' + FIN_ACCESS[u.fin], c: [52, 199, 89] });
      if (u.role === 'freelancer') pills.push({ t: plural((u.projectIds || []).length, 'client'), c: [10, 132, 255] });
      const open = manager ? W.tasks.filter((t) => !t.done && !t.parentId && (t.assignees || []).includes(u.id)).length : null;
      return {
        id: u.id, name: W.fullName(u), you: u.id === meId, email: u.email, photo: W.photoOf(u), ini: initials(W.fullName(u)), rgb: W.rgb(avColor(u.id)),
        role: W.roleOf(u), designation: W.designationOf(u), place: W.placeOf(u), pending: u.active !== false && !u.setup, past: u.active === false, pills,
        open, cd: admin && u.active !== false ? { on: W.isCD(u.id), label: W.isCD(u.id) ? (W.cdActing() ? 'Acting CD' : 'Creative Director') : W.meta.cdHomeId === u.id && W.cdActing() ? 'CD · away' : 'Make Creative Director' } : null,
        locked: u.id === ownerId && u.id !== meId,
      };
    };
    const all = W.users.slice().sort((a, b) => W.fullName(a).localeCompare(W.fullName(b)));
    const cur = all.filter((u) => u.active !== false), past = all.filter((u) => u.active === false);
    const groupOf = (u) => (W.isFinUser(u) ? 'finance' : u.role);
    const host = W.env.host;
    return {
      admin, active: cur.length, pastN: past.length,
      groups: GROUPS.map(([k, l]) => ({ k, name: l, people: cur.filter((u) => groupOf(u) === k).map(person) })).filter((g) => g.people.length),
      past: past.map(person),
      note: admin ? (host ? `Only Admins can add people. New members sign in at ${host} with their email — no password needed.` : 'Only Admins can add people.') : 'Only Admins can add or change team members.',
      guide: [
        ['Super Admin', [255, 149, 0], 'Full access, and can add or manage team members.'],
        ['Office Admin', [255, 149, 0], 'Admin rights without the task app: manages team members and Client Assets (full rights), with Finance if given. Doesn’t see tasks or add/edit clients; in the Trash sees and restores Client Assets items only.'],
        ['Account Manager', [10, 132, 255], 'Can do everything except add or manage team members.'],
        ['Freelancer', [48, 176, 199], 'Same as Production, but only sees the clients an Admin chooses for them, plus those clients’ Client Assets. Can sign in with a personal email (Gmail, Outlook…).'],
        ['Production · Social', [52, 199, 89], 'Can update status, submit files for CD review, tick checklist items, add tags, files and comments. Social can also write and change the description, add checklist items, and set a post’s Channel, Go-live and Occasion. Can’t create or delete tasks/subtasks, change dates, rename or remove checklist items (Production can’t add them either), change title, client or priority, assign people or remove tags.'],
        ...(PLANS_ON ? [['Social Manager', [255, 45, 85], 'A Social person picked in the ••• menu. Can start and edit any client’s content plan (Social Executives: the clients they’re set on in the client pop-up). Trial on the test site.']] : []),
        ['Finance only', [52, 199, 89], 'Only sees the Finance pages (Dashboard, Clients, Expenses) — no tasks app. As Admin they add subscriptions, reimbursements and expenses; as Viewer they only look.'],
        ['+ Super Admin · + Finance', [142, 142, 147], 'Extras anyone can have on top of their role (••• menu): full Super Admin rights, or the Finance pages. A task’s Finance status is set by Account Managers and Admins.'],
      ],
    };
  };

  /* ---------- Part B step 4: the questions and sheets the page used to show for Me's own pages ----------
     Each worked out here, read-only, for the app's own sheets and alerts; the change itself goes to the server
     (POST /api/app/act: pfSet, member, cd, addMember, trForever, trEmpty). Each answers an object (or null). */

  // My profile's country / city lists (web/places.js, loaded into the same engine): { list: [...] }
  M.places = function (R, data, meId, nowMs, kind, country) {
    const P = typeof E11_PLACES !== 'undefined' ? E11_PLACES : typeof window !== 'undefined' && window.E11_PLACES ? window.E11_PLACES : null;   // eslint-disable-line no-undef
    if (!P) return { list: [] };
    return { list: (kind === 'country' ? P.COUNTRIES : P.cities(String(country || ''))).slice() };
  };

  // a role pill's colour in a native sheet: the pill's tint, as the page's sheet sends it (styles.css, office.css,
  // finance.css .r-*; the same in both themes — only the pill's text colour changes)
  const ROLE_DOT = { admin: [123, 104, 238], office_admin: [123, 104, 238], am: [76, 154, 255], production: [255, 138, 76], social: [255, 143, 199], freelancer: [79, 209, 197], finance_admin: [61, 220, 151], finance_viewer: [79, 209, 197] };
  const sheetPerson = (W, u) => Object.assign({ initials: initials(W.fullName(u)), color: W.rgb(avColor(u.id)) }, u.avatar ? { photo: u.avatar } : {});

  // A person's menu on Team members (touch and hold): app.js memberMenu, every variant —
  //   { sheet: { sections: [{ header?, person?, rows: [{ i, label, icon?, dot?, checked?, danger?, disabled?, locked? }] }] },
  //     acts: [{ ev: 'member', act, role?, fin?, ask? } | { open: 'clients' }] }   (row i → acts[i]; -1: nothing to do)
  // The first section is the person (name · role, their picture) with no rows. env: as at the top (ownerId; testCopy:
  // the test site, where Owner view isn't offered).
  M.memberMenu = function (R, data, meId, nowMs, id, env) {
    const W = world(R, data, meId, nowMs, env), u = W.userById(id);
    if (!u || !W.canManageUsers()) return null;
    const acts = [], sections = [{ header: `${W.fullName(u)} · ${W.roleOf(u)}`, person: sheetPerson(W, u), rows: [] }];
    let sec = null;
    const head = (h) => { sec = { header: h, rows: [] }; sections.push(sec); };
    const plain = () => { sec = { rows: [] }; sections.push(sec); };
    const row = (r, act) => { if (act) { acts.push(act); r.i = acts.length - 1; } else r.i = -1; sec.rows.push(r); };
    const roleRow = (k, l, act) => row({ label: l, dot: ROLE_DOT[k] || null, checked: u.role === k }, act);
    const finRows = () => Object.keys(FIN_ACCESS).forEach((k) => row({ label: FIN_ACCESS[k], icon: 'coin', checked: (u.fin || '') === k }, { ev: 'member', act: 'fin', fin: k }));
    const supers = () => W.users.filter((x) => W.isSuper(x) && x.active !== false);
    const ownerId = W.env.ownerId || null;
    // the owner's account: only the owner changes it (locked rows)
    if (u.id === ownerId && u.id !== meId) {
      head('Only the owner can change this account');
      [['Change role', 'users'], ['Admin rights', 'shield'], ['Finance access', 'coin'], ['Remove from team', 'trash']].forEach(([l, ic]) => row({ label: l, icon: ic, disabled: true }));
      return { sheet: { sections: sections.filter((x) => x.rows.length || x.person) }, acts };
    }
    // your own row: the owner may work as another role (asked first); everyone their Finance access
    if (u.id === meId) {
      if (ownerId && meId === ownerId && W.isAdm(u)) {
        head('Your role (owner)');
        const others = W.users.filter((x) => x.id !== u.id && W.isSuper(x) && x.active !== false).length;
        Object.keys(ROLES).forEach((k) => {
          const l = ROLES[k];
          const ask = k !== 'admin' && others && u.role !== k ? { title: `Work as ${l}?`, body: `You’ll use the app as ${l}${u.admin ? ' — Admin rights stay switched on until you take them off' : ''}. As the owner, nobody else can change your role or access${W.env.server !== false && !W.env.testCopy ? ', and you can step back in from Owner view at the bottom of My profile' : ''}.`, okText: `Work as ${l}`, danger: false } : null;
          roleRow(k, l, Object.assign({ ev: 'member', act: 'role', role: k }, ask ? { ask } : {}));
        });
      }
      head('Your Finance access');
      finRows();
      return { sheet: { sections: sections.filter((x) => x.rows.length || x.person) }, acts };
    }
    // anyone else
    head('Change role');
    Object.keys(ROLES).forEach((k) => roleRow(k, ROLES[k], { ev: 'member', act: 'role', role: k }));
    const finOnly = W.isFinUser(u);
    plain();
    if (u.role !== 'admin' && !finOnly) row({ label: 'Super Admin rights', icon: 'shield', checked: !!u.admin }, { ev: 'member', act: 'admin' });
    if (!finOnly) finRows();
    plain();
    if (u.role === 'freelancer') row({ label: 'Clients they can see…', icon: 'folder' }, { open: 'clients' });
    if (u.role === 'social' && u.active !== false && PLANS_ON) row({ label: 'Social Manager', icon: 'users', checked: W.isSocialMgr(u.id) }, { ev: 'member', act: 'socialMgr' });
    if (u.active === false) row({ label: 'Restore access', icon: 'user' }, { ev: 'member', act: 'restore' });
    else {
      // (removeMemberFlow: the last Super Admin isn't asked — the server says why not)
      const n = W.tasks.filter((t) => (t.assignees || []).includes(u.id)).length;
      const ask = W.isSuper(u) && supers().length < 2 ? null : { title: `Remove ${W.fullName(u)}?`, body: `They won’t be able to sign in${n ? ` and will be unassigned from ${n} task${n === 1 ? '' : 's'}` : ''}. Their comments stay. You can restore access later.`, okText: 'Remove', danger: true };
      row({ label: 'Remove from team', icon: 'trash', danger: true }, Object.assign({ ev: 'member', act: 'remove' }, ask ? { ask } : {}));
    }
    return { sheet: { sections: sections.filter((x) => x.rows.length || x.person) }, acts };
  };

  // The clients a freelancer can see (projectAccessDialog, the app's sheet): each tick sent at once
  M.clientsMenu = function (R, data, meId, nowMs, id, env) {
    const W = world(R, data, meId, nowMs, env), u = W.userById(id);
    if (!u || !W.canManageUsers()) return null;
    const list = W.projects.slice().sort((a, b) => (a.order || 0) - (b.order || 0));
    const mine = Array.isArray(u.projectIds) ? u.projectIds : [];
    const acts = [];
    const rows = list.map((p) => { const c = p.clientId ? W.clientById(p.clientId) : null; acts.push({ ev: 'member', act: 'clients', project: p.id }); return { i: acts.length - 1, label: p.name, sub: c ? c.name : '', checked: mine.includes(p.id), multi: true, find: p.name }; });
    const sheet = { sections: rows.length ? [{ header: `Clients ${W.fullName(u)} can see`, rows }] : [] };
    if (list.length > 8) { sheet.search = 'Search clients'; sheet.empty = 'No client matches “%@”'; }
    return { sheet, acts };
  };

  // The Creative Director switch's first question (cdToggleFlow): removing the CD, or making someone CD when there's
  // none; { choice: true } when someone else is CD (the server's 409 brings that question); null: not allowed
  M.cdAsk = function (R, data, meId, nowMs, id, env) {
    const W = world(R, data, meId, nowMs, env), u = W.userById(id);
    if (!u || !W.canManageUsers()) return null;
    const cur = W.cdUserId();
    if (cur === id) return { title: `Remove ${W.fullName(u)} as ${W.cdTitle()}?`, body: W.meta.cdHomeId && W.cdActing() ? `${W.fullName(W.userById(W.meta.cdHomeId))} will be Creative Director again.` : 'Review requests will wait until someone else is made Creative Director.', okText: 'Remove', danger: true };
    if (cur) return { choice: true };
    return { title: 'Are you sure?', body: `Make ${W.fullName(u)} the Creative Director? They will review every file submitted for CD review.`, okText: 'Make Creative Director', danger: false };
  };

  // Add team member's form (addMemberFlow on the server: no password) — env.host: where they sign in
  M.addMemberForm = function (R, data, meId, nowMs, env) {
    const W = world(R, data, meId, nowMs, env);
    if (!W.canManageUsers()) return null;
    const entries = (o) => Object.keys(o).map((k) => [k, o[k]]);
    return {
      title: 'Add team member', okText: 'Add member',
      intro: `They sign in at ${W.env.host || ''} with this email — a one-time code is emailed to them. No password needed.`,
      fields: [
        { key: 'name', label: 'Full name (optional — they can set it themselves)', placeholder: 'e.g. Sara Khan' },
        { key: 'email', label: 'Email', type: 'email', placeholder: 'name@e11-digital.com' },
        { key: 'role', label: 'Role', type: 'select', value: 'production', options: entries(ROLES) },
        { key: 'admin', label: 'Admin rights on top of their role', type: 'select', value: '', options: [['', 'No'], ['yes', 'Yes — they can also do everything an Admin can']], hint: 'Not needed for the Admin role or Finance-only people.' },
        { key: 'fin', label: 'Finance access', type: 'select', value: '', options: entries(FIN_ACCESS), hint: 'Finance Admin adds subscriptions, reimbursements and expenses; Finance Viewer only looks. Finance-only people already have it.' },
      ],
    };
  };

  // Delete forever / Empty the Trash: the questions (eraseTrashFlow, emptyTrashFlow) — Super Admins only, as the
  // server (an Office Admin's are only restored)
  // one Trash item, for its tap and touch and hold without the website (phone.js trTap / trashHold): its name, days left,
  // its files (to preview), and what you may do with it — Haris 2026-11-06
  M.trashItem = function (R, data, meId, nowMs, id, env) {
    const W = world(R, data, meId, nowMs, env), it = W.trash.find((x) => x.id === id), u = W.me();
    if (!it || !u) return null;
    const left = W.trashDaysLeft(it);
    return { id: it.id, type: it.type, title: W.trashTitle(it), left: `${left} day${left === 1 ? '' : 's'} left`,
      files: W.trashFiles(it).filter((a) => a && a.path).map((a) => ({ id: a.id || a.path, name: a.name || 'File', path: a.path, size: a.size || 0 })),
      restore: it.type !== 'project' || W.isAdm(u), forever: W.isSuper(u),
      taskId: it.type === 'task' && it.data && (it.data.tasks || [])[0] ? it.data.tasks[0].id : null };
  };
  // a task in the Trash, tapped: the same tall sheet as the website's (app.js trashTaskView → the app's trashSheet) —
  // its title, "In the Trash · deleted by … · N days left", Restore, its details, description, subtasks, checklist, files
  // and comments (Haris 2026-11-06). Pictures come as addresses (photoUrl / thumbUrl); the app fetches them.
  M.trashSheet = function (R, data, meId, nowMs, id, env) {
    const W = world(R, data, meId, nowMs, env), it = W.trash.find((x) => x.id === id), u = W.me();
    if (!it || it.type !== 'task' || !u) return null;
    const list = (it.data && it.data.tasks) || [];
    const t = list.find((x) => !x.parentId || !list.some((y) => y.id === x.parentId)) || list[0];
    if (!t) return null;
    const subs = list.filter((x) => x.parentId === t.id);
    const left = W.trashDaysLeft(it);
    const who = it.auto ? 'cleaned up automatically' : `deleted by ${it.deletedBy === meId ? 'you' : W.fullName(W.userById(it.deletedBy))}`;
    const p = t.projectId ? W.projects.find((x) => x.id === t.projectId) : null;
    const secs = (p && Array.isArray(p.sections) && p.sections.length ? p.sections : null) || (Array.isArray(data.statuses) ? data.statuses : []);
    const st = secs.find((x) => x.id === t.sectionId) || secs[0] || { name: t.done ? 'Done' : 'To do', color: '#8e8e93' };
    const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const day = (s) => { const [y, m, d] = String(s).split('-').map(Number); return `${MON[(m || 1) - 1]} ${d || ''}${y && y !== new Date(W.NOW).getUTCFullYear() ? ', ' + y : ''}`; };
    const plain = (html) => decode(String(html || '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h\d)>/gi, '\n').replace(/<[^>]*>/g, '')).replace(/\n{3,}/g, '\n\n').trim();
    const person = (uid) => { const x = W.userById(uid); return { initials: initials(W.fullName(x)), color: avColor(uid || 'x'), photoUrl: W.photoOf(x) }; };
    const fileOf = (a) => ({ id: a.id, name: a.name || 'File', ext: (fileExt(a.name) || 'file').slice(0, 4), thumbUrl: isImage(a) && a.path ? W.imgUrl(a, 160) : null });
    return {
      title: t.title || 'Untitled task',
      bar: `In the Trash · ${who} ${W.timeAgo(it.deletedAt)} · ${left} day${left === 1 ? '' : 's'} left`,
      canRestore: it.type !== 'project' || W.isAdm(u),
      props: [
        { label: 'Client', text: W.trashWhere(it) },
        { label: 'Status', status: { name: st.name, color: W.rgb(st.color) } },
        { label: 'Assignees', people: (t.assignees || []).map((x) => ({ name: W.fullName(W.userById(x)), person: person(x) })) },
      ].concat(t.start || t.due ? [{ label: 'Dates', text: `${t.start ? 'Start ' + day(t.start) : ''}${t.start && t.due ? ' → ' : ''}${t.due ? 'Due ' + day(t.due) : ''}` }] : [])
        .concat((t.tags || []).length ? [{ label: 'Tags', text: t.tags.join(', ') }] : []),
      desc: t.notesHtml ? plain(t.notesHtml) : String(t.notes || '').trim(),
      subtasks: subs.map((x) => ({ t: x.title || 'Untitled', done: !!x.done })),
      checklist: (t.checklist || []).map((c) => ({ t: c.text || '', done: !!c.done })),
      files: (t.attachments || []).map(fileOf),
      comments: (t.comments || []).filter((c) => !c.deleted).map((c) => ({ name: W.fullName(W.userById(c.authorId)), when: W.timeAgo(c.at), person: person(c.authorId),
        text: c.html ? plain(c.html) : c.text || '', files: (c.attachments || []).map(fileOf) })),
      allFiles: W.trashFiles(it).filter((a) => a && a.path).map((a) => ({ id: a.id, name: a.name || 'File', path: a.path, size: a.size || 0 })),
    };
  };
  // a task in the Trash, view only (phone.js trashTaskView): its page worked out as if it were back, nothing can be changed
  M.trashTask = function (R, data, meId, nowMs, id, env) {
    const W = world(R, data, meId, nowMs, env), it = W.trash.find((x) => x.id === id);
    if (!it || it.type !== 'task' || typeof E11AppView === 'undefined') return null;
    const ts = (it.data && it.data.tasks) || [];
    if (!ts[0]) return null;
    const m = E11AppView.taskPage(R, Object.assign({}, data, { tasks: (data.tasks || []).concat(ts) }), meId, typeof nowMs === 'function' ? nowMs : () => (nowMs == null ? Date.now() : Number(nowMs)), ts[0].id);
    if (!m) return null;
    Object.keys(m).forEach((k) => { if (/^can[A-Z]/.test(k)) m[k] = false; });
    const left = W.trashDaysLeft(it);
    return Object.assign(m, { readOnly: true, complete: null, completed: null, lock: null, trashNote: `In the Trash — view only. ${left} day${left === 1 ? '' : 's'} left to restore it.` });
  };
  M.trashAsk = function (R, data, meId, nowMs, id, env) {
    const W = world(R, data, meId, nowMs, env), it = W.trash.find((x) => x.id === id);
    if (!it || !W.isSuper(W.me())) return null;
    return { title: `Delete “${W.trashTitle(it)}” forever?`, body: 'It can’t be restored after this, and its files are removed too.', okText: 'Delete forever', danger: true };
  };
  // View as (test site only): the team to choose from, as the page's ViewAs.pick gives the app's sheet — everyone still on
  // the team but the real you (realId), by name; their photo, initials and colour, their role
  M.viewAsPeople = function (R, data, meId, nowMs, realId, env) {
    const W = world(R, data, meId, nowMs, env);
    const list = W.users.filter((u) => u.active !== false && u.id !== realId).sort((a, b) => W.fullName(a).localeCompare(W.fullName(b)));
    return { people: list.map((u) => ({ id: u.id, name: W.fullName(u), role: W.roleOf(u) || '', ini: initials(W.fullName(u)), color: avColor(u.id || 'x'), photo: W.photoOf(u) })) };
  };
  M.trashEmptyAsk = function (R, data, meId, nowMs, env) {
    const W = world(R, data, meId, nowMs, env), n = W.trash.length;
    if (!n || !W.isSuper(W.me())) return null;
    return { title: 'Empty the Trash?', body: `All ${n} item${n === 1 ? '' : 's'} and their files are deleted for good. This can’t be undone.`, okText: 'Empty Trash', danger: true };
  };
})(E11AppMe);
if (typeof module !== 'undefined' && module.exports) module.exports = E11AppMe;
