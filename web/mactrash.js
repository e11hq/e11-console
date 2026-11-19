/* ================= The Mac app's Trash (canvas "Trash — Mac" T1–T8, approved by Haris 2026-11-18 16:38: "list is better …
   code it exactly like mockups") =================
   The Mac app only (html.mac-chrome); browsers and the iPhone keep app.js's own Trash (viewTrash). Everything the website's
   Trash does, nothing missed (app.js trashSearch · trashFiltered · trashRow · trashTaskView · restoreTrash · eraseTrash): the
   30-day note, Empty Trash (Super Admins, when there's something), the search (its typo note), the six filters as Apple's
   segmented control, Today · This week · Earlier (one Results group while searching), each row as the board — its kind's
   icon, the name, the kind · where · who · when, up to 4 file chips (+N more), N days left (red at 3 or fewer), Restore
   (a client only by Admins: "Admins restore clients"), Delete Forever (Super Admins). On the Mac besides: a file chip opens
   the Mac's preview flying out of its picture (a photo its own, anything else its coloured badge — never the whole chip)
   and ← → through the row's files; right-click a row: Apple's own menu (Open · Restore · Quick Look · Delete Forever…);
   a deleted task opens in its own Mac window (T4 — Mac app with it: TrashWin.swift), Delete Forever / Empty Trash ask with
   Apple's own alert (T7); older Mac apps: the page's own box, as the website. Drawn again: only what changed (data-key). */
const MacTrash = (() => {
  const on = () => typeof Host !== 'undefined' && Host.isMacApp && document.documentElement.classList.contains('mac-chrome');
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
  const sv = (d, size = 15, w = 1.9) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const IC = {
    task: '<circle cx="12" cy="12" r="9"/><path d="M8 12l3 3 5-6"/>',
    project: '<path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>',
    comment: '<path d="M21 12a8 8 0 01-11.6 7.1L4 20l1-4.4A8 8 0 1121 12z"/>',
    attachment: '<path d="M21 11.5l-8.6 8.6a5 5 0 01-7.1-7.1l8.6-8.6a3.3 3.3 0 014.7 4.7l-8.6 8.6a1.7 1.7 0 01-2.4-2.4l8-8"/>',
    cafile: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
    cafolder: '<path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>',
    plan: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  };
  const BIN = '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>';
  const RESTORE = '<path d="M9 14L4 9l5-5"/><path d="M4 9h10a6 6 0 010 12h-3"/>';
  const FIND = '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>';
  // (a file's coloured badge, by its kind — the board's colours)
  const EXT = { pdf: '#e5484d', ai: '#f76b15', psd: '#0a84ff', pptx: '#f76b15', ppt: '#f76b15', key: '#f76b15', docx: '#0a84ff', doc: '#0a84ff', pages: '#0a84ff',
    xlsx: '#30a46c', xls: '#30a46c', csv: '#30a46c', numbers: '#30a46c', mp4: '#8e4ec6', mov: '#8e4ec6', mp3: '#8e4ec6', wav: '#8e4ec6', zip: '#87909e' };
  const FILTERS = [['all', 'All'], ['task', 'Tasks'], ['project', 'Clients'], ['file', 'Files'], ['comment', 'Comments'], ['mine', 'Deleted by me']];
  const canRestoreIt = (it) => it.type !== 'project' || isAdm(me());

  // (every file's own picture, as Client Assets and the Inbox show it: a photo itself, a video its cover or the server's frame,
  //  a PDF or a Word / PowerPoint / Excel file its first page — Haris 2026-11-18 19:15 "all attachments"; none, or it fails:
  //  its coloured badge)
  function picOf(a) {
    const k = fileKind(a), ext = fileExt(a.name);
    if (k === 'image') return imgUrl(a, 160);
    if (a.path && (k === 'pdf' || /^(docx?|pptx?|xlsx?)$/.test(ext))) return '/api/fthumb?path=' + encodeURIComponent(a.path) + '&id=' + encodeURIComponent(a.id || '') + '&v=3';
    if (a.thumb) return posterUrl(a);
    if (a.path && k === 'video') return '/api/fthumb?path=' + encodeURIComponent(a.path) + '&id=' + encodeURIComponent(a.id || '');
    return '';
  }
  const badge = (a) => `<i class="mib-tpic" style="background:${EXT[fileExt(a.name)] || '#87909e'}">${esc((fileExt(a.name) || 'file').toUpperCase().slice(0, 4))}</i>`;
  function chip(it, a) {
    const u = Host.isNative ? picOf(a) : '';
    const pic = u
      ? `<img class="mib-tpic" src="${u}" alt="" loading="lazy" draggable="false" onerror="this.outerHTML=this.nextElementSibling.innerHTML"><template>${badge(a)}</template>`
      : badge(a);
    return `<button type="button" class="mtr-fch" data-mtr="look" data-id="${it.id}" data-file="${esc(a.id)}" title="Preview ${esc(a.name)}">${pic}<span>${esc(a.name)}</span></button>`;
  }
  function row(it, i, r) {
    const left = trashDaysLeft(it), files = trashFiles(it), task = it.type === 'task';
    const who = it.auto ? 'Cleaned up automatically (finished 30+ days ago)' : `Deleted by ${it.deletedBy === currentUserId ? 'you' : esc(fullName(userById(it.deletedBy)))}`;
    const mk = (s) => (r && r.terms.length ? sMark(s, r) : esc(s));
    const chips = files.slice(0, 4).map((a) => chip(it, a)).join('') + (files.length > 4 ? `<span class="mtr-more">+${files.length - 4} more</span>` : '');
    const act = (canRestoreIt(it) ? `<button type="button" class="mtr-pill pri" data-mtr="restore" data-id="${it.id}">${sv(RESTORE, 13, 2.1)}Restore</button>` : '<span class="mtr-only">Admins restore clients</span>')
      + (isSuper() ? `<button type="button" class="mtr-rnd" data-mtr="forever" data-id="${it.id}" title="Delete Forever" aria-label="Delete Forever">${sv(BIN, 14)}</button>` : '');
    return `<div class="mtr-row ${i % 2 === 0 ? 'alt' : ''} ${task ? 'opens' : ''}" data-key="r-${it.id}" data-tr="${it.id}"${task ? ` data-mtr="open" data-id="${it.id}"` : ''}>
      <span class="mtr-ic">${sv(IC[it.type] || BIN)}</span>
      <span class="mtr-main"><span class="mtr-t"><span class="mtr-tt">${mk(trashTitle(it))}</span>${task ? '<span class="mtr-open">›</span>' : ''}</span>
        <span class="mtr-sub"><span class="mtr-ty">${TRASH_TYPE[it.type] || ''}</span><span class="mtr-sl">${mk(trashWhere(it))} · ${who} · ${esc(timeAgo(it.deletedAt))}</span></span>
        ${chips ? `<span class="mtr-files">${chips}</span>` : ''}</span>
      <span class="mtr-left ${left <= 3 ? 'soon' : ''}" title="Deleted for good after ${TRASH_DAYS} days">${left} day${left === 1 ? '' : 's'} left</span>
      <span class="mtr-acts">${act}</span>
    </div>`;
  }
  const emptyHTML = (big, small) => `<div class="mtr-empty" data-key="empty">${sv(BIN, 44, 1.5)}<b>${big}</b><span>${small}</span></div>`;

  function view() {
    if (!isManager()) return `<div class="hm mtr" data-key="mtr">${emptyHTML('The Trash is for Admins and Account Managers', 'Ask one of them if something needs to come back.')}</div>`;
    const f = ui.trashFilter || 'all', q = ui.trashQ || '';
    const n = trashList().length;
    const r = trashSearch(q, trashFiltered());
    const groups = [];
    r.items.forEach((it) => {
      const days = -dayDiff(ymd(new Date(it.deletedAt)));
      const name = q ? 'Results' : days <= 0 ? 'Today' : days < 7 ? 'This week' : 'Earlier';
      let g = groups.find((x) => x.name === name); if (!g) { g = { name, rows: [] }; groups.push(g); }
      g.rows.push(it);
    });
    const list = r.items.length
      ? groups.map((g) => `<h2 class="mtr-grp" data-key="g:${g.name}">${g.name} <span>${g.rows.length}</span></h2><div class="mtr-card" data-key="c:${g.name}">${g.rows.map((it, i) => row(it, i, r)).join('')}</div>`).join('')
      : q ? emptyHTML(`Nothing in the Trash matches “${esc(q)}”`, 'Try a task or file name, a client, a file type like “pdf”, or who deleted it.')
        : emptyHTML('The Trash Is Empty', `Deleted tasks, clients, comments and files wait here for ${TRASH_DAYS} days.`);
    const fix = r.fixed.length ? `<div class="mtr-fix" data-key="fix">Showing results for ${r.fixed.map((x) => `<b>${esc(x.to)}</b>`).join(', ')} (you typed ${r.fixed.map((x) => `“${esc(x.from)}”`).join(', ')})</div>` : '';
    return `<div class="hm mtr" data-key="mtr">
      <div class="mtr-head" data-key="head"><div class="mtr-intro">Deleted items stay here for ${TRASH_DAYS} days, then they and their files are removed for good. Finished tasks arrive here ${AUTO_DELETE_DAYS} days after they’re completed.</div>${isSuper() && n ? `<button type="button" class="mtr-danger" data-mtr="empty">${sv(BIN, 13)}Empty Trash</button>` : ''}</div>
      <label class="mtr-search" data-key="search">${sv(FIND, 14)}<input id="mtr-q" type="search" placeholder="Search the Trash — names, files, “pdf”, people…" autocomplete="off" spellcheck="false" data-form-type="other" aria-label="Search the Trash"><button type="button" class="mtr-x" data-mtr="clear" aria-label="Clear" tabindex="-1"><svg viewBox="0 0 10 10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M2 2l6 6M8 2l-6 6"/></svg></button></label>
      <div class="mtr-seg" data-key="seg" role="tablist">${FILTERS.map(([k, l]) => `<button type="button" role="tab" class="${f === k ? 'on' : ''}" aria-selected="${f === k}" data-mtr="filter" data-k="${k}">${l}</button>`).join('')}</div>
      ${fix}${list}
    </div>`;
  }

  // ---------- drawn again: only what changed (the Mac Inbox's, Client Assets' and Search's way); what comes fades in ----------
  const keyOf = (n) => (n.nodeType === 1 ? n.getAttribute('data-key') : null);
  function morph(a, b) {
    if (a.nodeType !== b.nodeType || a.nodeName !== b.nodeName) { a.replaceWith(b); return; }
    if (a.nodeType !== 1) { if (a.nodeValue !== b.nodeValue) a.nodeValue = b.nodeValue; return; }
    if (a.isEqualNode(b)) return;
    if (a.nodeName === 'IMG') { if (a.getAttribute('src') !== b.getAttribute('src')) a.replaceWith(b); return; }
    if (a.nodeName === 'INPUT') return;   // (the search field keeps what's typed and the caret)
    [...a.attributes].forEach((x) => { if (!b.hasAttribute(x.name) && !x.name.startsWith('data-live')) a.removeAttribute(x.name); });
    [...b.attributes].forEach((x) => { if (a.getAttribute(x.name) !== x.value) a.setAttribute(x.name, x.value); });
    const byKey = new Map();
    [...a.childNodes].forEach((x) => { const k = keyOf(x); if (k) byKey.set(k, x); });
    const neu = [...b.childNodes];
    neu.forEach((nb, i) => {
      const k = keyOf(nb), cur = a.childNodes[i] || null, had = k ? byKey.get(k) : null;
      if (had) { if (had !== cur) a.insertBefore(had, cur); byKey.delete(k); morph(had, nb); }
      else if (cur && !k && !keyOf(cur)) morph(cur, nb);
      else { if (k) nb.classList.add('mtr-in'); a.insertBefore(nb, cur); }
    });
    while (a.childNodes.length > neu.length) a.lastChild.remove();
  }
  // (the page as it was last shown, kept while another page is up: coming back, it's put back and only what changed is
  //  drawn — its files' pictures were made afresh and loaded again each time: Haris 2026-11-19 12:13)
  let kept = null;
  function draw(c) {
    const cur = c.firstElementChild;
    const t = document.createElement('template');
    t.innerHTML = view().trim();
    const nb = t.content.firstElementChild;
    if (cur && c.children.length === 1 && cur.classList.contains('mtr')) morph(cur, nb);
    else if (kept) {
      c.innerHTML = ''; c.appendChild(kept); morph(kept, nb);
      const inp = kept.querySelector('#mtr-q'); if (inp) inp.value = ui.trashQ || '';
    } else {
      c.innerHTML = ''; c.appendChild(nb);
      const inp = nb.querySelector('#mtr-q'); if (inp) inp.value = ui.trashQ || '';
    }
    kept = c.firstElementChild;
    winRefresh();
  }
  const redraw = () => { const c = $('#content'); if (c && on() && ui.view === 'trash' && !ui.search) draw(c); };

  // ---------- asking first: Apple's own alert (T7); older Mac apps the page's own box ----------
  function ask(title, body, ok) {
    return NativeMac.call('alert', { title, body, ok, cancel: 'Cancel', destructive: true })
      .then((r) => !!(r && r.pressed))
      .catch(() => dialog({ title, body, okText: ok, danger: true }));
  }
  async function forever(id) {
    if (!isAdm(me())) return denied();
    const it = trashList().find((x) => x.id === id);
    if (!it) return;
    if (await ask(`Delete “${trashTitle(it)}” forever?`, 'It can’t be restored after this, and its files are removed too.', 'Delete Forever')) {
      if (!trashList().some((x) => x.id === id)) return;
      eraseTrash([id]); render(); toast('Deleted forever');
    }
  }
  async function emptyAll() {
    if (!isAdm(me())) return denied();
    const n = trashList().length;
    if (!n) return;
    if (await ask('Empty the Trash?', `All ${n} item${n === 1 ? '' : 's'} and their files are deleted for good. This can’t be undone.`, 'Empty Trash')) {
      eraseTrash(trashList().map((x) => x.id)); render(); toast('The Trash is empty');
    }
  }
  function look(id, fileId) {
    const it = trashList().find((x) => x.id === id);
    const files = it ? trashFiles(it) : [];
    const a = files.find((x) => String(x.id) === String(fileId));
    // (← → through the row's files, as the Inbox and Client Assets; marked as in the Trash: no Copy Link in the preview)
    if (a) { const fs = files.map((x) => ({ ...x, trashed: true })); previewFile(fs[files.indexOf(a)], fs); }
  }

  // ---------- a deleted task in its own Mac window (T4 — TrashWin.swift); older Mac apps: the page's own box ----------
  const wins = new Map();   // trash id → what was sent (sent again only when it changes)
  const abs = (u) => (u ? new URL(u, location.href).href : '');
  function winLoad(it) {
    const list = (it.data && it.data.tasks) || [];
    const t = list.find((x) => !x.parentId || !list.some((y) => y.id === x.parentId)) || list[0];
    if (!t) return null;
    const left = trashDaysLeft(it);
    const who = it.auto ? 'cleaned up automatically' : `deleted by ${it.deletedBy === currentUserId ? 'you' : fullName(userById(it.deletedBy))}`;
    const st = statusInfo(t);
    const plain = (html) => { const d = document.createElement('div'); d.innerHTML = String(html).replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h\d)>/gi, '\n'); return d.textContent.replace(/\n{3,}/g, '\n\n').trim(); };
    // (dl: the file itself, for dragging it out to Finder — Mac app 13 with MacNative.swift, Haris 2026-11-18)
    const fileOf = (a) => ({ id: String(a.id), name: a.name, ext: (fileExt(a.name) || 'file').slice(0, 4), color: EXT[fileExt(a.name)] || '#87909e', pic: picOf(a) ? abs(picOf(a)) : '', sz: fmtSize(a.size) || '', ...(a.path ? { dl: abs(fileUrl(a)), size: a.size || 0 } : {}) });
    // (a person's face for the window W2 — Haris 2026-11-18 19:16: their photo, or their initials on their colour)
    const face = (id) => { const u = userById(id), n = fullName(u) || 'Former member'; return { name: n, ini: initials(n), color: avColor(id || 'x'), ...(u && u.avatar ? { pic: abs(fileUrl({ path: u.avatar })) } : {}) }; };
    const goes = new Date(Date.now() + left * 86400000);
    const p0 = t.projectId && typeof proj === 'function' ? proj(t.projectId) : null;
    return {
      key: it.id, title: t.title || 'Untitled task',
      bar: `In the Trash · ${who} ${timeAgo(it.deletedAt)} · ${left} day${left === 1 ? '' : 's'} left`,
      canRestore: canRestoreIt(it), canForever: isSuper() && isAdm(me()),
      // (W2: the window's subtitle, and its note of when it goes — no red)
      sub: 'In the Trash · read only',
      noteB: `${who.charAt(0).toUpperCase() + who.slice(1)} ${timeAgo(it.deletedAt)}.`,
      note: ` Kept until ${fmtDay(ymd(goes))} — ${left} day${left === 1 ? '' : 's'} left.${canRestoreIt(it) ? ' Restore it to work on it again.' : ''}`,
      clientColor: (p0 && p0.color) || '',
      faces: (t.assignees || []).map(face),
      client: trashWhere(it), status: st.name, statusColor: st.color,
      people: (t.assignees || []).map((u) => fullName(userById(u)) || 'Former member'),
      dates: t.start || t.due ? `${t.start ? 'Start ' + fmtDay(t.start) : ''}${t.start && t.due ? ' → ' : ''}${t.due ? 'Due ' + fmtDay(t.due) : ''}` : '',
      tags: t.tags || [],
      desc: t.notesHtml ? plain(sanitizeHTML(t.notesHtml, true)) : t.notes || '',
      subtasks: list.filter((x) => x.parentId === t.id).map((x) => ({ t: x.title || 'Untitled', done: !!x.done })),
      checklist: (t.checklist || []).map((x) => ({ t: x.text || '', done: !!x.done })),
      files: (t.attachments || []).map(fileOf),
      comments: (t.comments || []).filter((c) => !c.deleted).map((c) => ({ ...face(c.authorId), name: userName(c.authorId), when: timeAgo(c.at), text: c.html ? plain(sanitizeHTML(c.html, true)) : c.text || '', files: (c.attachments || []).map(fileOf) })),
    };
  }
  function winSend(it, update) {
    const load = winLoad(it);
    if (!load) return Promise.resolve(false);
    const json = JSON.stringify(load);
    if (update && wins.get(it.id) === json) return Promise.resolve(true);
    return NativeMac.call('trashWindow', { ...load, update: !!update }).then((r) => { if (r && r.ok) { wins.set(it.id, json); return true; } return false; }, () => false);
  }
  function open(id) {
    const it = trashList().find((x) => x.id === id);
    if (!it || it.type !== 'task') return;
    winSend(it, false).then((ok) => { if (!ok) trashTaskView(id, true); });
  }
  // (what's open is kept as it is now: changed elsewhere, it changes; gone — restored or deleted, here or anywhere — it goes)
  function winRefresh() {
    wins.forEach((_, id) => {
      const it = trashList().find((x) => x.id === id);
      if (!it) { wins.delete(id); NativeMac.call('trashClose', { key: id }).catch(() => {}); } else winSend(it, true);
    });
  }
  setInterval(() => { if (wins.size) winRefresh(); }, 3000);   // (changes made while another page is on show too)
  window.__e11Trash = (e) => {
    if (!e || !e.key) return;
    if (e.act === 'closed') wins.delete(e.key);
    if (e.act === 'restore') { NativeMac.call('trashClose', { key: e.key }).catch(() => {}); wins.delete(e.key); restoreTrash(e.key); }
    // (W2's Delete Forever…: Apple's alert, as the row's; gone for good — its window goes too)
    if (e.act === 'forever') forever(e.key).then(() => { if (!trashList().some((x) => x.id === e.key)) { NativeMac.call('trashClose', { key: e.key }).catch(() => {}); wins.delete(e.key); } });
    if (e.act === 'preview') {
      const it = trashList().find((x) => x.id === e.key);
      const list = (it && it.data && it.data.tasks) || [];
      const t = list.find((x) => !x.parentId || !list.some((y) => y.id === x.parentId)) || list[0];
      const files = t ? (t.attachments || []).concat(...(t.comments || []).map((c) => c.attachments || [])) : [];
      const a = files.find((x) => String(x.id) === String(e.file));
      if (a) { const fs = ((t.attachments || []).some((x) => x.id === a.id) ? t.attachments : files).map((x) => ({ ...x, trashed: true })); previewFile(fs.find((x) => x.id === a.id), fs); }
    }
  };

  // ---------- right-click a row: Apple's own menu (T5) ----------
  function menuFor(it, pt) {
    const files = trashFiles(it);
    const items = [
      it.type === 'task' ? { label: 'Open', run: () => open(it.id) } : null,
      canRestoreIt(it) ? { label: 'Restore', run: () => restoreTrash(it.id) } : null,
      files.length ? '-' : null,
      files.length ? { label: `Quick Look “${files[0].name}”`, run: () => look(it.id, files[0].id) } : null,
      isSuper() ? '-' : null,
      isSuper() ? { label: 'Delete Forever…', danger: true, run: () => forever(it.id) } : null,
    ].filter(Boolean);
    while (items[0] === '-') items.shift();
    if (typeof MacBar !== 'undefined' && MacBar.on()) MacBar.menu(pt, items);
    else showMenu({ getBoundingClientRect: () => ({ left: pt.x, right: pt.x, top: pt.y, bottom: pt.y, width: 0, height: 0 }) }, items, { native: true });
  }

  // ---------- what's clicked, typed and right-clicked on the page ----------
  document.addEventListener('click', (e) => {
    if (!on() || ui.view !== 'trash') return;
    const b = e.target.closest && e.target.closest('[data-mtr]');
    if (!b || !b.closest('.mtr')) return;
    e.preventDefault(); e.stopPropagation();
    const id = b.dataset.id, k = b.dataset.mtr;
    if (k === 'filter') { ui.trashFilter = b.dataset.k; redraw(); }
    else if (k === 'clear') { ui.trashQ = ''; const i = $('#mtr-q'); if (i) { i.value = ''; i.focus(); } redraw(); }
    else if (k === 'restore') restoreTrash(id);
    else if (k === 'forever') forever(id);
    else if (k === 'empty') emptyAll();
    else if (k === 'look') look(id, b.dataset.file);
    else if (k === 'open') open(id);
  }, true);
  document.addEventListener('input', (e) => {
    if (e.target.id !== 'mtr-q') return;
    ui.trashQ = e.target.value;
    redraw();
  });
  document.addEventListener('keydown', (e) => {
    if (e.target.id !== 'mtr-q' || e.key !== 'Escape' || !e.target.value) return;
    e.preventDefault(); ui.trashQ = ''; e.target.value = ''; redraw();
  });
  document.addEventListener('contextmenu', (e) => {
    if (!on() || ui.view !== 'trash') return;
    const rw = e.target.closest && e.target.closest('.mtr-row');
    if (!rw) return;
    const it = trashList().find((x) => x.id === rw.dataset.tr);
    if (!it) return;
    e.preventDefault(); e.stopPropagation();
    menuFor(it, { x: e.clientX, y: e.clientY });
  }, true);

  return { on, draw, view };
})();
