/* ================= The Mac app's parts outside its window (Haris 2026-11-18) =================
   The Mac app only (mac/swift/MacNative.swift — appInfo bar / spotlight / dragOut); browsers and the iPhone: nothing here.
   · The menu bar item (canvas "Menu bar item — Mac", B5): the unread count, the newest 3 unread updates (who, what, which
     task, when), what's due today (E11 Day / My Day, as the sidebar's count), Open E11 Console and New Task — live.
   · Spotlight (canvas "Spotlight — Mac", S1–S3): the tasks, clients and Client Assets folders and files this person sees in
     the app, kept on this Mac; signing out takes them away. A result opened: window.__e11Spot.
   · Dragging files out to Finder (canvas "Drag out to Finder — Mac", D1–D4): Client Assets' files and folders (a folder
     with its files and folders in it), a task's files, the Inbox's and the Trash's — the drag also carries the files
     themselves; inside the window the page's own drags are as before. */
const MacNative = (() => {
  let caps = null, asked = false;
  const on = () => typeof Host !== 'undefined' && Host.isMacApp;
  function ask() {
    if (asked || !on()) return;
    asked = true;
    NativeMac.call('appInfo').then((r) => { caps = r || {}; later(); }).catch(() => { caps = {}; });
  }
  const has = (k) => !!(caps && caps[k]);
  const signedIn = () => typeof db !== 'undefined' && db && typeof currentUserId !== 'undefined' && currentUserId && me();
  const abs = (u) => (u ? new URL(u, location.href).href : '');
  const plain = (h) => { const d = document.createElement('div'); d.innerHTML = String(h || ''); return d.textContent.replace(/\s+/g, ' ').trim(); };
  const ago = (iso) => {
    const m = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
    if (m < 1) return 'now';
    if (m < 60) return m + 'm';
    if (m < 60 * 24 && dayDiff(ymd(new Date(iso))) === 0) return Math.floor(m / 60) + 'h';
    return ibTime(iso);
  };

  /* ---------- the menu bar item ---------- */
  function titleOfNotif(n, t) {
    if (/^plan/.test(n.kind) && typeof planTitle === 'function') return planTitle(n);
    if (n.kind === 'asset' && typeof assetTitle === 'function') return assetTitle(n);
    if (n.kind === 'daily') return 'Morning round-up';
    if (n.kind === 'birthday') return 'Birthday';
    if (n.kind === 'signin') return 'Sign-in';
    if (t) return t.title || 'Untitled task';
    return /^claim/.test(n.kind) ? 'Expense claims' : '';
  }
  function face(id) {
    const u = id && userById(id);
    if (!u) return { ini: '', color: '#87909e' };
    return { ini: initials(fullName(u)), color: avColor(id), ...(u.avatar ? { pic: abs(fileUrl({ path: u.avatar })) } : {}) };
  }
  function barModel() {
    if (!signedIn()) return { on: false };
    const unread = myNotifs().filter((n) => !n.read).sort((a, b) => b.at.localeCompare(a.at));
    const rows = unread.slice(0, 3).map((n) => {
      const t = n.taskId ? task(n.taskId) : null;
      const who = n.from && userById(n.from) ? fullName(userById(n.from)) : '';
      let what = plain(notifMsg(n, t));
      if (who && what.startsWith(who)) what = what.slice(who.length).trim();
      const where = titleOfNotif(n, t);
      return { id: n.id, who, what, sub: [where, ago(n.at)].filter(Boolean).join(' · '), ...face(n.from) };
    });
    const D = Work.day();
    const due = D.tasks.filter((t) => D.open(t) && t.due && dayDiff(t.due) === 0).sort((a, b) => byPrio(a, b) || (a.createdAt || '').localeCompare(b.createdAt || ''));
    const day = due.slice(0, 3).map((t) => {
      const p = t.projectId ? proj(t.projectId) : null, st = statusInfo(t);
      return { id: t.id, title: t.title || 'Untitled task', sub: [p ? p.name : '', 'due today'].filter(Boolean).join(' · '), dot: (p && p.color) || '#87909e', pill: { t: st.name, c: st.color } };
    });
    const lab = document.getElementById('save-label');
    return {
      on: true, count: unread.length,
      inbox: { n: unread.length, rows },
      day: { title: Work.dayTitle(), n: due.length, rows: day },
      canNew: can('createTask'),
      sync: lab ? lab.textContent.trim().replace(/ · .*$/, '') : '',
    };
  }
  let barSent = '';
  function paintBar() {
    if (!has('bar')) return;
    const m = barModel(), j = JSON.stringify(m);
    if (j === barSent) return;
    barSent = j;
    NativeMac.call('bar', m).catch(() => {});
  }
  // a row or a button picked in its panel (the window is already in front)
  window.__e11Bar = (a) => {
    a = a || {};
    if (!signedIn()) return;
    if (a.k === 'notif') return openNotif(a.id);
    if (a.k === 'task') return TaskLink.show(a.id);
    if (a.k === 'inbox') return go('inbox');
    if (a.k === 'day') return go('today');
    if (a.k === 'new') { const b = document.querySelector('#sidebar .create-btn'); if (b && can('createTask')) b.click(); }
  };

  /* ---------- Spotlight ---------- */
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
  function pathOf(c, f) {
    const names = []; let x = f, guard = 0;
    while (x && guard++ < 20) { names.unshift(x.name); x = x.parentId ? c.folders.find((y) => y.id === x.parentId) : null; }
    return names.join(' › ');
  }
  function spotItems() {
    const out = [];
    const SEEN = Work.seen();
    const names = (ids) => (ids || []).map((id) => fullName(userById(id))).filter(Boolean);
    topTasks().forEach((t) => {
      if (!SEEN.has(t.id)) return;
      const p = t.projectId ? proj(t.projectId) : null, st = statusInfo(t);
      const when = t.done ? (t.completedAt ? 'done ' + fmtDay(ymd(new Date(t.completedAt))) : 'done') : t.due ? (dayDiff(t.due) === 0 ? 'due today' : 'due ' + fmtDay(t.due)) : '';
      const people = names(t.assignees);
      out.push({ id: 'task:' + t.id, title: t.title || 'Untitled task', kind: 'Task',
        desc: ['Task', st.name, p ? p.name : '', when, people.slice(0, 2).join(', ')].filter(Boolean).join(' · '),
        keys: [p ? p.name : '', st.name, ...people].filter(Boolean) });
    });
    db.projects.filter((p) => !p.inactive && clientListOk(p)).forEach((p) => {
      const open = db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done && SEEN.has(t.id)).length;
      const ams = (p.ams || []).filter((a) => !a.onLeave).map((a) => fullName(userById(a.id))).filter(Boolean);
      out.push({ id: 'client:' + p.id, title: p.name, kind: 'Client', ini: initials(p.name), color: p.color || '#87909e',
        desc: ['Client', plural(open, 'open task'), ams.length ? 'Account Manager ' + ams.join(', ') : ''].filter(Boolean).join(' · '), keys: ['client', ...ams] });
    });
    clientsSorted().forEach((c) => {
      out.push({ id: 'assets:' + c.id, title: `${c.name} — Client Assets`, kind: 'Client Assets', desc: `Client Assets · ${plural(clientFileCount(c), 'file')}`, keys: [c.name, 'client assets'] });
      c.folders.forEach((f) => {
        const where = pathOf(c, f);
        out.push({ id: 'folder:' + c.id + ':' + f.id, title: f.name, kind: 'Folder', desc: `Client Assets · ${c.name} › ${where}`, keys: [c.name, 'folder'] });
        f.files.forEach((a) => {
          if (!a.path) return;
          out.push({ id: 'file:' + c.id + ':' + f.id + ':' + a.id, title: a.name, ext: fileExt(a.name) || '', kind: 'File',
            desc: [`Client Assets · ${c.name} › ${where}`, fmtSize(a.size)].filter(Boolean).join(' · '), keys: [c.name, f.name],
            ...(isImage(a) ? { thumb: abs(imgUrl(a, 160)) } : {}) });
        });
      });
    });
    return out;
  }
  let spotSent = '', spotTimer = 0;
  function paintSpot() {
    spotTimer = 0;
    if (!has('spotlight') || !signedIn()) return;
    const items = spotItems(), j = JSON.stringify(items);
    if (j === spotSent) return;
    spotSent = j;
    NativeMac.call('spotlight', { who: location.host + '|' + currentUserId, items }).catch(() => {});
  }
  // a Spotlight result opened (the window is in front): the task, the client, Client Assets at that folder, the file
  window.__e11Spot = (id) => {
    const run = () => {
      const [k, a, b, c] = String(id || '').split(':');
      if (k === 'task') return TaskLink.show(a);
      if (k === 'client') { if (proj(a)) return go('project', a); return toast('That client has been removed'); }
      if (k === 'assets') return openClient(a);
      if (k === 'folder') return openClient(a, b);
      if (k === 'file') {
        const cl = clientById(a), f = cl && cl.folders.find((x) => x.id === b), file = f && f.files.find((x) => x.id === c);
        if (!file) return toast('That file has been moved or deleted');
        openClient(a, b);
        setTimeout(() => { const el = document.querySelector(`[data-mca-file="${CSS.escape(c)}"], [data-att="${CSS.escape(c)}"]`); if (el) el.click(); else previewFile(file, f.files); }, 350);
      }
    };
    if (signedIn()) return run();
    const iv = setInterval(() => { if (signedIn()) { clearInterval(iv); setTimeout(run, 300); } }, 250);
    setTimeout(() => clearInterval(iv), 30000);
  };
  function signedOut() {
    if (!on()) return;
    barSent = ''; spotSent = '';
    NativeMac.call('signedOut').catch(() => {});
  }

  /* ---------- dragging files out ---------- */
  const fileOut = (a) => (a && a.path ? { name: a.name || 'file', url: abs(fileUrl(a)), size: a.size || 0 } : null);
  function folderOut(c, f, depth = 0) {
    return { name: f.name, folder: true, files: f.files.map(fileOut).filter(Boolean),
      folders: depth > 12 ? [] : c.folders.filter((x) => x.parentId === f.id).map((x) => folderOut(c, x, depth + 1)) };
  }
  // any file the page shows, by its id: Client Assets, a task's (or its comments'), the Trash's
  function anyFile(id) {
    if (!id) return null;
    const ca = clientFileById(id);
    if (ca) return ca;
    const inT = (t) => (t.attachments || []).find((x) => x.id === id) || (t.comments || []).reduce((r, cm) => r || (cm.attachments || []).find((x) => x.id === id), null);
    for (const t of db.tasks) { const a = inT(t); if (a) return a; }
    for (const it of trashList()) { const a = trashFiles(it).find((x) => String(x.id) === String(id)); if (a) return a; }
    return null;
  }
  // what a dragged element is: a Client Assets file or folder, a task's file, an Inbox tile, a Trash file
  const OUT = '.mca-t[data-mca-file], .mca-fc[data-mca-folder], #detail [data-action="quicklook"][data-id], .mib-tile[data-att], .mib-upt[data-att], .mtr-fch[data-file]';
  function outOf(el) {
    const t = el && el.closest && el.closest(OUT);
    if (!t) return null;
    if (t.matches('.mca-fc')) {
      const c = clientById(t.dataset.mcaCl), f = c && c.folders.find((x) => x.id === t.dataset.mcaFolder);
      return f ? { el: t, items: [folderOut(c, f)] } : null;
    }
    const id = t.dataset.mcaFile || t.dataset.att || t.dataset.file || t.dataset.id;
    const a = t.matches('[data-action="quicklook"]') ? findAttachment(task(ui.taskId), id) : anyFile(id);
    const o = fileOut(a);
    return o ? { el: t, items: [o] } : null;
  }
  let made = null;   // (an element made draggable for this press only)
  function down(e) {
    if (!has('dragOut') || e.button !== 0) return;
    const o = outOf(e.target);
    if (!o || o.el.getAttribute('draggable') === 'true') return;
    o.el.setAttribute('draggable', 'true'); made = o.el;
  }
  function undo() { if (made) { made.removeAttribute('draggable'); made = null; } }
  function start(e) {
    if (!has('dragOut') && !has('dragNative')) return;
    const o = outOf(e.target);
    if (!o) return;
    // (the Mac app's own drag, as Finder's: the page's web drag stopped before it starts — WebKit wrote its own data over
    //  the files once it had, and Finder took nothing (measured in the drag notes, Haris 2026-11-19 20:10). The app says
    //  where it is as it moves and where it was let go: Client Assets' moves into a folder are done from that)
    if (has('dragNative')) {
      e.preventDefault();
      const pic = o.el.querySelector('.mca-tp') || o.el, r = pic.getBoundingClientRect();
      dragging = true;
      NativeMac.call('dragNative', { items: o.items, name: o.items[0].name, rect: { x: r.left, y: r.top, w: r.width, h: r.height } })
        .then((res) => { if (!res || !res.ok) window.__e11DragEnd(0, 0, false, 0); })
        .catch(() => window.__e11DragEnd(0, 0, false, 0));
      return;
    }
    // (told first — the Mac app adds the files to the drag WebKit starts right after)
    NativeMac.call('dragOut', { items: o.items }).catch(() => {});
    try { e.dataTransfer.setData('application/x-e11-out', '1'); } catch (x) { /* */ }
    try { if (!e.dataTransfer.effectAllowed || e.dataTransfer.effectAllowed === 'uninitialized') e.dataTransfer.effectAllowed = 'copyMove'; } catch (x) { /* */ }
    dragging = true;
  }
  let dragging = false;
  // (while one of these is dragged over the page: only Client Assets' own moves take it — never an upload of it)
  function guard(e) {
    const ty = [...((e.dataTransfer && e.dataTransfer.types) || [])];
    if (!ty.includes('application/x-e11-out') || ty.includes('application/x-e11-file')) return;
    e.stopImmediatePropagation();
    if (e.type === 'dragover' && e.dataTransfer) e.dataTransfer.dropEffect = 'none';
  }
  function end() { dragging = false; undo(); }
  // (the app's drag: where it is — true when it's over somewhere that takes it — and where it was let go; op 16 a move
  //  the window took, 1 a copy Finder took, 0 turned down)
  window.__e11DragAt = (x, y, inside) => !!(window.__e11CaDrag && window.__e11CaDrag.at(x, y, inside));
  window.__e11DragEnd = (x, y, inside, op) => { try { if (window.__e11CaDrag) window.__e11CaDrag.end(x, y, inside, op); } finally { end(); } };
  if (on()) {
    document.addEventListener('pointerdown', down, true);
    document.addEventListener('pointerup', () => setTimeout(() => { if (!dragging) undo(); }, 0), true);
    document.addEventListener('dragstart', start, true);
    document.addEventListener('dragend', end, true);
    ['dragenter', 'dragover', 'drop'].forEach((k) => window.addEventListener(k, guard, true));
  }

  /* ---------- kept up to date ---------- */
  let timer = 0;
  function later() {
    if (!on()) return;
    if (!caps) { ask(); return; }
    if (!timer) timer = setTimeout(() => { timer = 0; paintBar(); }, 120);
    if (has('spotlight') && !spotTimer) spotTimer = setTimeout(paintSpot, 4000);
  }
  if (on()) setInterval(() => { if (caps && signedIn()) paintBar(); }, 60000);   // ("5m" becomes "6m")
  return { on, later, signedOut, barModel, spotItems, outOf };
})();
