/* ================= The Mac app's Client Assets — Finder's way (canvas "Client Assets — Mac" C1–C7, Haris 2026-11-17) =================
   The Mac app only (html.mac-chrome); browsers and the iPhone keep app.js's own pages.
   C1 all clients: Finder's icon view of logos · C2 a client: its folders as cards · C3 a folder: its folders, then its files as
   the Inbox's tiles · C4 search: clients and folders as rows, files as tiles with where they live, the words found marked ·
   C5 Info: a Get Info window of its own (several can be open) · C6 dropping files: a folder's whole page, or a client's folder
   card · C7 New Folder: in place, as Finder. Right-clicks: Apple's own menu. Pinned folders (each person's own): first.
   Drawn again: only what changed (data-key, as the Mac Inbox). */
const MacAssets = (() => {
  const on = () => typeof Host !== 'undefined' && Host.isMacApp && document.documentElement.classList.contains('mac-chrome');
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : (w === w.toUpperCase() ? 'S' : 's')}`;
  const svg = (d, w = 1.8) => `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const SV = {
    plus: svg('<path d="M8 3v10M3 8h10"/>'),
    info: svg('<circle cx="8" cy="8" r="5.5"/><path d="M8 7.2v3.3M8 5.2v.1"/>', 1.6),
    down: svg('<path d="M8 2.5v8M4.8 7.5 8 10.7l3.2-3.2M3 13.2h10"/>', 1.6),
    up: svg('<path d="M8 11V3M4.8 6.2 8 3l3.2 3.2M3 13.2h10"/>', 1.6),
    more: '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><circle cx="3.5" cy="8" r="1.3"/><circle cx="8" cy="8" r="1.3"/><circle cx="12.5" cy="8" r="1.3"/></svg>',
    link: svg('<path d="M6.8 9.2a2.6 2.6 0 0 0 3.7 0l2-2a2.6 2.6 0 0 0-3.7-3.7l-.6.6M9.2 6.8a2.6 2.6 0 0 0-3.7 0l-2 2a2.6 2.6 0 0 0 3.7 3.7l.6-.6"/>', 1.6),
    search: svg('<circle cx="7" cy="7" r="4.5"/><path d="m10.5 10.5 3 3"/>'),
    pin: '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M10.2 1.6 14.4 5.8a.6.6 0 0 1-.2 1l-2 .7-2.4 2.4.3 2.5a.6.6 0 0 1-1 .5L6.6 10.4 3 14l-1-1 3.6-3.6-2.5-2.5a.6.6 0 0 1 .5-1l2.5.3 2.4-2.4.7-2a.6.6 0 0 1 1-.2z"/></svg>',
  };
  // our folder drawing: E11 blue, or green for a task's final files
  const folderSVG = (final, cls = 'mca-fi') => `<svg class="${cls}" viewBox="0 0 40 32" aria-hidden="true"><path d="M2 6a3 3 0 0 1 3-3h10l3 3h17a3 3 0 0 1 3 3v18a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z" fill="${final ? '#2fa35a' : '#3f7ee8'}"/><path d="M2 11h36v16a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z" fill="${final ? '#45c06f' : '#5e95f0'}"/></svg>`;

  // ---------- pinned folders: each person's own (kept with their settings), first in their row ----------
  const pins = () => { const p = db && db.meta && db.meta.prefs && db.meta.prefs.caPins; return Array.isArray(p) ? p : []; };
  const pinned = (f) => pins().includes(f.id);
  function togglePin(f) {   // (a folder, or a file in its folder — Haris 19:00)
    const p = pins().filter((x) => x !== f.id);
    if (!pinned(f)) p.unshift(f.id);
    savePref('caPins', p);
    renderContent();
  }
  const pinSort = (list) => { const p = pins(); const at = (f) => { const i = p.indexOf(f.id); return i < 0 ? Infinity : i; }; return list.slice().sort((a, b) => at(a) - at(b)); };

  // (each picture's address carries its file's id after # — the same file twice on a page, moved, keeps its own picture)
  // ---------- a file's picture: a photo its own, a video its cover, a PDF or Office file the server's first page ----------
  function picOf(a) {
    const k = fileKind(a);
    if (k === 'image') return imgUrl(a, 480);
    if (a.path && (k === 'pdf' || /^(docx?|pptx?|xlsx?)$/.test(fileExt(a.name)))) return '/api/fthumb?path=' + encodeURIComponent(a.path) + '&id=' + encodeURIComponent(a.id || '') + '&v=3';
    if (a.thumb) return posterUrl(a);
    if (a.path && k === 'video') return '/api/fthumb?path=' + encodeURIComponent(a.path) + '&id=' + encodeURIComponent(a.id || '');
    return '';
  }
  function picHTML(a) {
    if (isFont(a)) return `<span class="mca-aa" style="font-family:'caf-${a.id}'">Aa</span>`;
    const k = fileKind(a), u = picOf(a), ext = fileExt(a.name);
    const page = k === 'pdf' || k === 'text' || ['doc', 'docx', 'pages', 'rtf'].includes(ext);
    const fb = page ? '<span class="mib-page"><i></i><i></i><i></i><i></i><i></i><i></i></span>'
      : `<span class="mib-ficon">${icon(k === 'image' ? 'image' : k === 'video' ? 'play' : 'clip')}<b>${esc(ext.slice(0, 4).toUpperCase() || 'FILE')}</b></span>`;
    return (u ? (k === 'image' ? '' : fb) + `<img src="${u}#${esc(a.id || '')}" alt="" draggable="false" decoding="sync" onerror="this.remove()">` : fb) + (k === 'video' ? '<span class="mib-play">▶</span>' : '');
  }
  const fontFaces = (list) => { const f = list.filter(isFont); return f.length ? `<style data-key="fonts">${f.map((a) => `@font-face{font-family:'caf-${a.id}';src:url("${fileUrl(a)}");}`).join('')}</style>` : ''; };

  // ---------- pieces ----------
  const pill = (label, attrs, ic, blue) => `<button type="button" class="mca-pill ${blue ? 'blue' : ''}" ${attrs}>${ic || ''}${label}</button>`;
  function bar(c) {
    const q = (c ? ui.caScope === c.id : !ui.caScope) ? ui.caQ || '' : '';
    return `<div class="mca-field" data-key="bar">${SV.search}<input id="ca-q" value="${esc(q)}" placeholder="${c ? `Search ${esc(c.name)}’s folders and files` : 'Search clients, folders and files — e.g. “ford logo png”'}" autocomplete="off" spellcheck="false">`
      + `<button type="button" class="mca-x ca-q-x" data-action="ca-q-clear" title="Clear (Esc)" ${q ? '' : 'hidden'}><svg viewBox="0 0 10 10" aria-hidden="true"><path d="M2.6 2.6l4.8 4.8M7.4 2.6 2.6 7.4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg></button><span class="mca-scope">${c ? `In ${esc(c.name)}` : 'All clients'}</span></div>`;
  }
  const lg = (c, s) => `<span class="mca-lg s${s}">${clientLogoHTML(c, s)}</span>`;
  function clientCard(c) {
    return `<div class="mca-cc" data-key="c-${c.id}" data-action="open-client" data-id="${c.id}" data-mca-client="${c.id}" title="${esc(c.name)}">${lg(c, 112)}<div class="mca-cn">${esc(c.name)}</div><div class="mca-cm">${plural(topFolders(c).length, 'folder')} · ${plural(clientFileCount(c), 'file')}</div></div>`;
  }
  function folderCard(c, f, sm) {
    const imgs = sm ? [] : f.files.filter((a) => isImage(a)).slice(0, 3);
    const subs = subFolders(c, f).length;
    const meta = [subs ? plural(subs, 'folder') : '', f.files.length ? plural(f.files.length, 'file') : ''].filter(Boolean).join(' · ') || 'Empty';
    return `<div class="mca-fc ${sm ? 'sm' : ''} ${f.finalOf ? 'final' : ''}" data-key="f-${f.id}" data-action="open-cfolder" data-id="${f.id}" data-mca-folder="${f.id}" data-mca-cl="${c.id}" title="${esc(f.name)}">`
      + `<div class="mca-ftop">${folderSVG(!!f.finalOf)}<div class="mca-ftx"><div class="mca-fn">${esc(f.name)}</div><div class="mca-fm">${f.finalOf ? '<span class="mca-fin">Final</span>' : ''}<span>${meta}</span></div></div></div>`
      + (imgs.length ? `<div class="mca-peek">${imgs.map((a) => `<span><img src="${imgUrl(a, 240)}" alt="" draggable="false"></span>`).join('')}</div>` : '')
      + (pinned(f) ? `<span class="mca-pin" title="Pinned">${SV.pin}</span>` : '') + '</div>';
  }
  // (a new folder, in place: its name ready to type — C7 B)
  let nf = null;
  function nfCard(c, parent, sm) {
    if (!nf || nf.cid !== c.id || nf.pid !== (parent ? parent.id : null)) return '';
    return `<div class="mca-fc new ${sm ? 'sm' : ''} ${nf.err ? 'bad' : ''}" data-key="nf"><div class="mca-ftop">${folderSVG(false)}<div class="mca-ftx"><input class="mca-nfin" data-key="nfin" value="New folder" maxlength="80" spellcheck="false" autocomplete="off"><div class="mca-fm">${nf.err ? `<span class="mca-warn">${esc(nf.err)}</span>` : '<span>Empty</span>'}</div></div></div></div>`;
  }
  function tile(c, f, a, q) {
    return `<div class="mca-t" data-key="a-${a.id}" ${!q && canDelAsset(a) ? 'draggable="true"' : ''} data-action="tile-open" data-id="${a.id}" data-att="${a.id}" data-mca-file="${a.id}" data-mca-cl="${c.id}" title="${esc(a.name)}">`
      + `<div class="mib-tpic mca-tp ${isFont(a) ? 'font' : ''}">${picHTML(a)}<button type="button" class="mca-cl" data-action="copy-att" data-id="${a.id}" title="Copy link — paste it in a comment, or send it to anyone">${SV.link}Copy Link</button>${!q && pinned(a) ? `<span class="mca-pin t" title="Pinned">${SV.pin}</span>` : ''}</div>`
      + `<div class="mca-tn">${q ? caMark(a.name, q) : esc(a.name)}</div>`
      + (q ? `<a class="mca-loc" data-action="open-cfolder-of" data-client="${c.id}" data-id="${f.id}" title="Open this folder">${lg(c, 12)}<span>${esc(c.name)} › ${esc(folderPath(c, f))}</span></a>`
        : `<div class="mca-ts">${esc(fmtSize(a.size) || '')}${a.addedBy ? ` · ${esc(firstName(a.addedBy))}` : ''}</div>`)
      + '</div>';
  }

  // ---------- C4: search ----------
  function results(q, scope) {
    const r = caSearch(q, scope);
    const n = r.clients.length + r.folders.length + r.files.length;
    if (!n) return `<div class="mca-none" data-key="none">${SV.search}<b>Nothing matches “${esc(q.trim())}”</b><span>Try a client name, a folder like “fonts”, or a file type like “pdf” or “otf”.</span></div>`;
    const shown = r.files.slice(0, 120);
    return `<div class="mca-res" data-key="res">${fontFaces(shown.map((x) => x.a))}`
      + (r.loose ? '<div class="mca-loose" data-key="loose">Close matches — check the spelling</div>' : '')
      + (r.clients.length ? `<div class="mca-cap" data-key="cc">CLIENTS · ${r.clients.length}</div><div class="mca-rows" data-key="cr">${r.clients.map((c) => `<div class="mca-row" data-key="rc-${c.id}" data-action="open-client" data-id="${c.id}" data-mca-client="${c.id}">${lg(c, 24)}<span class="mca-rn">${caMark(c.name, q)}</span><span class="mca-rl">${plural(topFolders(c).length, 'folder')} · ${plural(clientFileCount(c), 'file')}</span></div>`).join('')}</div>` : '')
      + (r.folders.length ? `<div class="mca-cap" data-key="fc">FOLDERS · ${r.folders.length}</div><div class="mca-rows" data-key="fr">${r.folders.map(({ c, f }) => {
        const where = [c.name, ...folderAncestors(c, f).map((x) => x.name)].join(' › ');
        return `<div class="mca-row" data-key="rf-${f.id}" data-action="open-cfolder-of" data-client="${c.id}" data-id="${f.id}" data-mca-folder="${f.id}" data-mca-cl="${c.id}">${folderSVG(!!f.finalOf)}<span class="mca-rn">${caMark(f.name, q)}</span><span class="mca-rl">${caMark(where, q)} · ${plural(f.files.length, 'file')}</span></div>`;
      }).join('')}</div>` : '')
      + (r.files.length ? `<div class="mca-cap" data-key="ac">FILES · ${r.files.length}</div><div class="mca-tgrid" data-key="ag">${shown.map(({ c, f, a }) => tile(c, f, a, q)).join('')}</div>${r.files.length > shown.length ? `<div class="mca-loose" data-key="more">Showing the first ${shown.length} files — add another word to narrow it down.</div>` : ''}` : '')
      + '</div>';
  }

  // ---------- C1: all clients ----------
  function listView() {
    const list = clientsSorted();
    const q = !ui.caScope ? ui.caQ || '' : '';
    const grid = list.length ? `<div class="mca-cgrid" data-key="grid">${list.map(clientCard).join('')}</div>`
      : `<div class="mca-none" data-key="none"><b>No clients yet</b><span>${canAssets() ? 'Add your first client to start collecting their brand assets.' : 'An Admin or Account Manager will add clients here.'}</span></div>`;
    return `<div class="mca" data-key="mca-list" data-page="list">
      <div class="mca-head" data-key="head"><div class="mca-ht"><h1>Client Assets</h1><div class="mca-sub">Brand guidelines, logos and fonts for every client · Copy Link on any file to paste it straight into a task</div></div>${canAssets() ? pill('Add Client', 'data-action="add-client"', SV.plus, true) : ''}</div>
      ${bar(null)}
      <div id="ca-body" data-scope="" data-key="body">${q.trim() ? results(q, null) : grid}</div>
      <template id="ca-default" data-key="tpl">${grid}</template></div>`;
  }
  // ---------- C2: a client ----------
  function clientView(c) {
    if (!c.logo && canAddAssets()) { const lf = c.folders.find((f) => f.name === 'Logos'); if (lf && lf.files.length) setTimeout(() => autoLogo(c, lf), 0); }
    const projects = db.projects.filter((p) => p.clientId === c.id);
    const q = ui.caScope === c.id ? ui.caQ || '' : '';
    const grid = `<div class="mca-fgrid" data-key="grid">${pinSort(topFolders(c)).map((f) => folderCard(c, f)).join('')}${nfCard(c, null)}</div>`;
    return `<div class="mca" data-key="mca-c-${c.id}" data-page="client">
      <div class="mca-head c" data-key="head">${canAssets() ? `<span class="mca-lgb" data-mca="client-more" title="Client options">${lg(c, 64)}</span>` : lg(c, 64)}<div class="mca-ht"><h1>${esc(c.name)}</h1><div class="mca-meta">${plural(topFolders(c).length, 'folder')} · ${plural(clientFileCount(c), 'file')}${projects.length ? ` · Clients ${projects.map((p) => `<a class="mca-chip" data-action="go-project" data-id="${p.id}"><i style="background:${esc(p.color || '#87909e')}"></i>${esc(p.name)}</a>`).join('')}` : ''}</div></div>
        ${canAssets() ? pill('New Folder', 'data-mca="new-folder"', SV.plus) + `<button type="button" class="mca-pill ico" data-mca="client-more" title="Client options" aria-label="Client options">${SV.more}</button>` : ''}</div>
      ${bar(c)}
      <div id="ca-body" data-scope="${c.id}" data-key="body">${q.trim() ? results(q, c) : grid}</div>
      <template id="ca-default" data-key="tpl">${grid}</template></div>`;
  }
  // ---------- C3: a folder ----------
  function folderView(c, f) {
    const top = isFilesTop(c, f), up = canUploadTo(c, f), mk = canMakeSub(c, f);
    const subs = pinSort(subFolders(c, f).slice().sort((a, b) => String(a.createdAt || '').localeCompare(String(b.createdAt || ''))));
    const files = pinSort(f.files.slice().sort((a, b) => a.name.localeCompare(b.name)));
    const src = f.finalOf ? task(f.finalOf) : null;
    const count = [subs.length || top ? plural(subs.length, 'folder') : '', top && !files.length ? '' : plural(files.length, 'file')].filter(Boolean).join(' · ');
    const where = `<a data-action="open-client" data-id="${c.id}">${esc(c.name)}</a>${folderAncestors(c, f).map((x) => ` › <a data-action="open-cfolder" data-id="${x.id}">${esc(x.name)}</a>`).join('')}`;
    const nfH = nfCard(c, f, true);
    // (inside a folder: the pinned first, then in the order they were made — the newest last, where a new one is typed — Haris 19:23)
    const empty = files.length || subs.length || nfH ? '' : `<div class="mca-none" data-key="empty"><b>${top ? 'No folders yet' : up ? 'Nothing here yet' : 'Nothing in this folder yet'}</b><span>${top ? (canAddAssets() ? 'Make a folder for each job. Final files of finished tasks are filed here too.' : 'Final files of finished tasks are filed here.') : f.finalOf ? 'The final files are filed here when the task is completed.' : up ? 'Drop files anywhere on this page, or click Upload Files.' : 'The E11 team adds files here.'}</span></div>`;
    return `<div class="mca" data-key="mca-f-${f.id}" data-page="folder">${fontFaces(files)}
      <div class="mca-head f" data-key="head"><button type="button" class="mca-pill ico mca-back" ${parentFolder(c, f) ? `data-action="open-cfolder" data-id="${parentFolder(c, f).id}" title="Back to ${esc(parentFolder(c, f).name)}"` : `data-action="open-client" data-id="${c.id}" title="Back to ${esc(c.name)}"`} aria-label="Back">${svg('<path d="m10 3-5 5 5 5"/>')}</button>${lg(c, 44)}<div class="mca-ht"><h1>${esc(f.name)}</h1><div class="mca-meta">${where} · ${count}${f.finalOf ? ` · <span class="mca-fin">Final files</span>${src && !src.deleted ? ` · <a data-action="open-task" data-id="${src.id}">Open Task</a>` : ''}` : ''}</div></div>
        ${pill('Info', `data-mca="info-folder" data-id="${f.id}"`, SV.info)}${files.length ? pill('Download All', 'data-action="ca-download-all"', SV.down) : ''}${mk ? pill('New Folder', `data-mca="new-folder" data-parent="${f.id}"`, SV.plus, !up) : ''}${up ? pill('Upload Files', 'data-action="ca-upload"', SV.up, true) : ''}</div>
      <div class="ca-uploads mca-ups" id="ca-uploads" data-key="ups" data-keep></div>
      ${subs.length || nfH ? `<div class="mca-cap" data-key="sc">FOLDERS</div><div class="mca-subs" data-key="subs">${subs.map((x) => folderCard(c, x, true)).join('')}${nfH}</div>` : ''}
      ${files.length ? `<div class="mca-cap" data-key="ac">${plural(files.length, 'FILE')}</div><div class="mca-tgrid" data-key="ag">${files.map((a) => tile(c, f, a)).join('')}</div>` : ''}${empty}
    </div>`;
  }
  function view() {
    if (ui.view === 'client') {
      const c = clientById(ui.clientId), f = c && c.folders.find((x) => x.id === ui.folderId);
      if (nf && (!c || nf.cid !== c.id || nf.pid !== (f ? f.id : null))) nf = null;
      if (c) return f ? folderView(c, f) : clientView(c);
    }
    nf = null;
    return listView();
  }

  // ---------- drawn again: only what changed (the Mac Inbox's way) ----------
  const keyOf = (n) => (n.nodeType === 1 ? n.getAttribute('data-key') : null);
  function morph(a, b) {
    if (a.nodeType !== b.nodeType || a.nodeName !== b.nodeName) { a.replaceWith(b); return; }
    if (a.nodeType !== 1) { if (a.nodeValue !== b.nodeValue) a.nodeValue = b.nodeValue; return; }
    if (a.nodeName === 'TEMPLATE') { if (a.innerHTML !== b.innerHTML) a.innerHTML = b.innerHTML; return; }
    if (a.isEqualNode(b)) return;
    if (a.nodeName === 'IMG') { a.replaceWith(b); return; }
    [...a.attributes].forEach((x) => { if (!b.hasAttribute(x.name) && !x.name.startsWith('data-live')) a.removeAttribute(x.name); });
    [...b.attributes].forEach((x) => { if (a.getAttribute(x.name) !== x.value) a.setAttribute(x.name, x.value); });
    if (a.nodeName === 'INPUT' || a.nodeName === 'TEXTAREA' || a.hasAttribute('data-keep')) return;   // (what's typed, and uploads under way, stay)
    const byKey = new Map();
    [...a.childNodes].forEach((x) => { const k = keyOf(x); if (k) byKey.set(k, x); });
    const neu = [...b.childNodes];
    neu.forEach((nb, i) => {
      const k = keyOf(nb), cur = a.childNodes[i] || null, had = k ? byKey.get(k) : null;
      if (had) { if (had !== cur) a.insertBefore(had, cur); byKey.delete(k); morph(had, nb); }
      else if (cur && !k && !keyOf(cur)) morph(cur, nb);
      else a.insertBefore(nb, cur);
    });
    while (a.childNodes.length > neu.length) a.lastChild.remove();
  }
  function patch(c) {
    const cur = c.firstElementChild;
    if (!cur || c.children.length !== 1 || !cur.classList.contains('mca')) return false;
    const t = document.createElement('template');
    t.innerHTML = view().trim();
    const nb = t.content.firstElementChild;
    if (!nb || keyOf(nb) !== keyOf(cur)) return false;   // (another page: drawn afresh)
    morph(cur, nb);
    return true;
  }
  function draw(c) { if (!patch(c)) c.innerHTML = view(); }

  // ---------- C7: New Folder in place ----------
  function startNew(c, parent) {
    if (parent ? !canMakeSub(c, parent) : !canAssets()) return;
    const box = document.getElementById('ca-q');
    if (box && box.value) { box.value = ''; runCaSearch(box); }
    nf = { cid: c.id, pid: parent ? parent.id : null, err: '' };
    renderContent();
    const i = document.querySelector('.mca-nfin');
    if (i) { i.focus(); i.select(); i.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }
  }
  function endNew(keep) {
    const inp = document.querySelector('.mca-nfin');
    if (!nf) return;
    const c = clientById(nf.cid), parent = c && nf.pid ? c.folders.find((x) => x.id === nf.pid) : null;
    const name = inp ? inp.value.trim() : '';
    if (!keep || !c || !name) { nf = null; renderContent(); return; }
    const d = folderDup(c, name, null, nf.pid);
    if (d) { nf.err = `A folder called “${d.name}” is already here`; renderContent(); if (inp) inp.focus(); return; }
    nf = null;
    newFolder(c, name, false, parent); persist(0); render();
  }
  document.addEventListener('keydown', (e) => {
    const inp = e.target.closest && e.target.closest('.mca-nfin');
    if (!inp) return;
    if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); endNew(true); }
    else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); endNew(false); }
    else e.stopPropagation();
  }, true);
  document.addEventListener('input', (e) => { if (nf && nf.err && e.target.closest && e.target.closest('.mca-nfin')) { nf.err = ''; renderContent(); } });
  // (a click elsewhere: kept if the name is free, as Finder; else taken away)
  document.addEventListener('focusout', (e) => {
    if (!nf || !(e.target.closest && e.target.closest('.mca-nfin'))) return;
    setTimeout(() => { if (!nf || document.activeElement && document.activeElement.closest && document.activeElement.closest('.mca-nfin')) return; const inp = document.querySelector('.mca-nfin'); const c = clientById(nf.cid); if (inp && c && inp.value.trim() && !folderDup(c, inp.value.trim(), null, nf.pid)) endNew(true); else endNew(false); }, 0);
  });

  // ---------- right-clicks: Apple's own menu ----------
  const TITLE = { 'Copy link': 'Copy Link', 'Turn off link': 'Turn Off Link', 'Rename folder': 'Rename Folder…', 'Move left': 'Move Left', 'Move right': 'Move Right', 'Trash folder': 'Trash Folder',
    'Rename client': 'Rename Client', 'Change logo': 'Change Logo', 'Add logo': 'Add Logo', 'Delete client': 'Delete Client' };
  const retitle = (it) => (it && typeof it === 'object' && TITLE[it.label] ? { ...it, label: TITLE[it.label] } : it);
  const anchorAt = (pt) => ({ __pt: pt, getBoundingClientRect: () => ({ left: pt.x, top: pt.y, right: pt.x, bottom: pt.y, width: 0, height: 0 }) });
  // (the page's own menu, its words as the Mac's — Title Case — with our first items before it)
  function macMenu(pt, lead, show) {
    const orig = MacBar.menu;
    let done = false;
    MacBar.menu = (p, items) => { done = true; return orig(p, [...lead, ...(lead.length && items.length ? ['-'] : []), ...items].map(retitle)); };
    try { if (show) show(anchorAt(pt)); } finally { MacBar.menu = orig; }
    if (!done && lead.length) showMenu(anchorAt(pt), lead.map(retitle), { native: true });
  }
  let selEl = null, selAt = 0;
  function select(el) { unselect(); if (el) { el.setAttribute('data-live-sel', ''); selEl = el; selAt = Date.now(); } }
  function unselect() { if (selEl) selEl.removeAttribute('data-live-sel'); selEl = null; }
  // (the menu closed: the first move of the pointer after it takes the selection away)
  document.addEventListener('mousemove', () => { if (selEl && Date.now() - selAt > 250) unselect(); }, true);
  document.addEventListener('mousedown', () => { if (selEl && Date.now() - selAt > 250) unselect(); }, true);
  const folderOf = (el) => { const c = clientById(el.dataset.mcaCl); return c ? { c, f: c.folders.find((x) => x.id === el.dataset.mcaFolder) } : {}; };
  const fileOf = (id) => { for (const c of db.clients || []) for (const f of c.folders) { const a = f.files.find((x) => x.id === id); if (a) return { c, f, a }; } return {}; };
  document.addEventListener('contextmenu', (e) => {
    if (!on() || (ui.view !== 'clients' && ui.view !== 'client')) return;
    const root = e.target.closest && e.target.closest('.mca');
    if (!root || e.target.closest('input, textarea')) return;
    e.preventDefault();
    const pt = { x: e.clientX, y: e.clientY };
    const fileEl = e.target.closest('[data-mca-file]'), folEl = e.target.closest('[data-mca-folder]'), cliEl = e.target.closest('[data-mca-client]');
    if (fileEl) {
      const { c, f, a } = fileOf(fileEl.dataset.mcaFile); if (!a) return;
      select(fileEl);
      const here = ui.view === 'client' && ui.folderId === f.id;
      macMenu(pt, [
        { label: 'Copy Link', run: () => copyAttachment(a) },
        { label: 'Preview', run: () => previewFile(a) },
        { label: 'Download', run: () => downloadClientFiles([a], a.name.replace(/\.[^.]+$/, '')) },
        { label: 'Info', run: () => info('file', a.id) },
        ...(here ? [{ label: pinned(a) ? 'Unpin File' : 'Pin File', run: () => togglePin(a) }] : []),
        ...(isAdm(me()) ? [{ label: 'Turn Off Link', danger: true, run: () => FileLinks.toggle(a) }] : []),
        ...(here && canDelAsset(a) ? ['-', { label: 'Trash', danger: true, run: () => removeClientFile(a.id) }] : []),
      ]);
      return;
    }
    if (folEl) {
      const { c, f } = folderOf(folEl); if (!f) return;
      select(folEl);
      const lead = [
        { label: 'Open', run: () => folEl.click() },
        { label: 'Info', run: () => info('folder', f.id) },
        { label: pinned(f) ? 'Unpin Folder' : 'Pin Folder', run: () => togglePin(f) },
      ];
      macMenu(pt, [], (an) => folderMenu(an, c, f, lead));
      return;
    }
    if (cliEl) {
      const c = clientById(cliEl.dataset.mcaClient); if (!c) return;
      select(cliEl);
      macMenu(pt, [{ label: 'Open', run: () => cliEl.click() }], canAssets() ? (an) => clientMenu(an, c) : null);
      return;
    }
    // (a client's picture on its page: the same options as ••• — Haris 19:18)
    const lgEl = e.target.closest('.mca-lgb');
    if (lgEl) { const c = clientById(ui.clientId); if (c && canAssets()) macMenu(pt, [], (an) => clientMenu(an, c)); return; }
    // empty space: what this page can make
    const c = clientById(ui.clientId), f = c && ui.view === 'client' ? c.folders.find((x) => x.id === ui.folderId) : null;
    let items = [];
    if (ui.view === 'clients' || !c) items = canAssets() ? [{ label: 'Add Client', run: addClientDialog }] : [];
    else if (!f) items = canAssets() ? [{ label: 'New Folder', run: () => startNew(c, null) }] : [];
    else items = [...(canMakeSub(c, f) ? [{ label: 'New Folder', run: () => startNew(c, f) }] : []), ...(canUploadTo(c, f) ? [{ label: 'Upload Files…', run: pickIntoFolder }] : [])];
    if (items.length) macMenu(pt, items, null);
  }, true);

  // ---------- the page's own buttons ----------
  document.addEventListener('click', (e) => {
    const b = e.target.closest && e.target.closest('[data-mca]');
    if (!b || !on()) return;
    e.preventDefault(); e.stopPropagation();
    const k = b.dataset.mca, c = clientById(ui.clientId);
    if (k === 'new-folder' && c) startNew(c, b.dataset.parent ? c.folders.find((x) => x.id === b.dataset.parent) : null);
    else if (k === 'client-more' && c) { const r = b.getBoundingClientRect(); macMenu({ x: r.left, y: r.bottom + 5 }, [], (an) => clientMenu(an, c)); }
    else if (k === 'info-folder') info('folder', b.dataset.id);
  }, true);

  // ---------- C5: Info — a Get Info window of its own; several can stay open, moved anywhere, closed with the red dot or Esc ----------
  const wins = new Map();
  let zTop = 900;
  const front = (w) => { w.style.zIndex = ++zTop; };
  function info(kind, id) {
    let c = null, f = null, a = null;
    for (const cl of db.clients || []) for (const fo of cl.folders) {
      if (kind === 'folder' && fo.id === id) { c = cl; f = fo; }
      if (kind === 'file') { const x = fo.files.find((y) => y.id === id); if (x) { c = cl; f = fo; a = x; } }
    }
    if (!f) return;
    const key = kind + ':' + id;
    if (wins.has(key)) { front(wins.get(key)); return; }
    const who = (u) => (u && userById(u) ? esc(fullName(userById(u))) : u ? 'Former team member' : '—');
    const when = (iso) => (iso ? esc(fmtDateTime(iso)) : '—');
    const row = (k2, v) => `<div class="mca-k"><span>${k2}</span><b>${v}</b></div>`;
    const loc = esc([c.name, ...folderAncestors(c, f).map((x) => x.name), ...(a ? [f.name] : [])].join(' › '));
    let title, sub, pic, rows, fin = '', taskId = null;
    if (a) {
      const k = fileKind(a), ext = (fileExt(a.name) || 'file').toUpperCase();
      title = a.name;
      sub = `${esc(ext)} ${isFont(a) ? 'font' : k === 'image' ? 'image' : k === 'video' ? 'video' : k === 'pdf' ? 'document' : 'file'} · ${esc(fmtSize(a.size) || '—')}`;
      pic = `<div class="mib-tpic mca-iw-pic ${isFont(a) ? 'font' : ''}">${picHTML(a)}</div>`;
      if (a.final) {
        const m = a.final, t = task(m.taskId);
        fin = '<div class="mca-fin big">Final files of a completed task</div>';
        const client = m.clientNone ? 'not needed' : m.clientBy ? `recorded by ${who(m.clientBy)}` : 'not recorded';
        rows = [row('Completed', when(m.completedAt)), row('Task', esc(m.taskTitle || f.name)), row('Created by', who(m.createdBy)), row('Assignee', who(m.assignee)),
          row('Approved by', `${who(m.cdBy)} (CD)${m.clientBy ? ' &amp; the client' : ''}`), row('Client approval', m.clientBy ? when(m.clientAt) + ' · ' + client : client), row('Where', loc)];
        if (t && !t.deleted && db.tasks.includes(t)) taskId = t.id;
      } else rows = [row('Added by', who(a.addedBy)), row('Date added', when(a.addedAt)), row('Where', loc)];
    } else {
      const tree = folderTree(c, f), all = f.files.concat(...tree.map((x) => x.files));
      title = f.name;
      sub = `Folder · ${esc(fmtSize(all.reduce((n, x) => n + (x.size || 0), 0)) || '0 KB')}`;
      pic = `<div class="mca-iw-pic fold">${folderSVG(!!f.finalOf, 'mca-iw-fi')}</div>`;
      if (f.finalOf) { fin = '<div class="mca-fin big">Final files of a completed task</div>'; const t = task(f.finalOf); if (t && !t.deleted && db.tasks.includes(t)) taskId = t.id; }
      rows = [row('Created by', isAutoFolder(c, f) && !f.finalOf ? 'Made with the client' : who(f.createdBy)), row('Date', when(f.createdAt || c.createdAt)),
        ...(isFilesTop(c, f) || tree.length ? [row('Folders', String(tree.length))] : []), row('Files', String(all.length)), row('Where', loc)];
    }
    const w = document.createElement('div');
    w.className = 'mca-iw';
    w.setAttribute('role', 'dialog');
    w.innerHTML = `<div class="mca-iw-tb"><i class="r" title="Close"></i><i class="y"></i><i class="g"></i><b>${esc(title)} Info</b></div>${pic}<div class="mca-nm">${esc(title)}</div><div class="mca-sm">${sub}</div>${fin}<div class="mca-icap">GENERAL</div><div class="mca-ks">${rows.join('')}</div>${taskId ? `<div class="mca-iw-act"><button type="button" class="mca-pill" data-ot>Open Task</button></div>` : ''}`;
    document.body.appendChild(w);
    const n = wins.size;
    w.style.left = Math.max(12, Math.round((innerWidth - w.offsetWidth) / 2 + n * 26)) + 'px';
    w.style.top = Math.max(12, Math.round((innerHeight - w.offsetHeight) / 2 + n * 26)) + 'px';
    front(w); wins.set(key, w);
    const close = () => { w.remove(); wins.delete(key); };
    w.addEventListener('mousedown', () => front(w));
    w.querySelector('.r').addEventListener('click', close);
    const ot = w.querySelector('[data-ot]'); if (ot) ot.addEventListener('click', () => { close(); openTask(taskId); });
    // (moved by its title bar)
    w.querySelector('.mca-iw-tb').addEventListener('mousedown', (e) => {
      if (e.target.closest('i')) return;
      e.preventDefault();
      const sx = e.clientX - w.offsetLeft, sy = e.clientY - w.offsetTop;
      const mv = (m) => { w.style.left = Math.min(innerWidth - 60, Math.max(-w.offsetWidth + 60, m.clientX - sx)) + 'px'; w.style.top = Math.min(innerHeight - 30, Math.max(0, m.clientY - sy)) + 'px'; };
      const upF = () => { removeEventListener('mousemove', mv, true); removeEventListener('mouseup', upF, true); };
      addEventListener('mousemove', mv, true); addEventListener('mouseup', upF, true);
    });
  }
  // (Esc: the window in front goes)
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !wins.size) return;
    if (e.target.closest && e.target.closest('input, textarea, [contenteditable="true"]')) return;
    const r = document.getElementById('overlay-root'); if (r && r.children.length) return;
    let top = null, tk = null;
    wins.forEach((w, k) => { if (!top || +w.style.zIndex > +top.style.zIndex) { top = w; tk = k; } });
    if (top) { e.preventDefault(); e.stopPropagation(); top.remove(); wins.delete(tk); }
  }, true);

  // ---------- C6: dropping files ----------
  const fileDrag = (e) => !!e.dataTransfer && [...(e.dataTransfer.types || [])].includes('Files');
  const nFiles = (e) => { const it = e.dataTransfer && e.dataTransfer.items; return it ? [...it].filter((x) => x.kind === 'file').length : 0; };
  let ov = null, hot = null, offT = null;
  function showOv(f, n) {
    const ct = document.getElementById('content'); if (!ct) return;
    if (!ov) { ov = document.createElement('div'); ov.className = 'mca-ov'; ov.innerHTML = '<div class="mca-ov-in"><div><div class="mca-ov-big">Drop it like it’s hot</div><div class="mca-ov-sub"></div></div></div>'; document.body.appendChild(ov); requestAnimationFrame(() => ov && ov.classList.add('on')); }
    const r = ct.getBoundingClientRect();
    Object.assign(ov.style, { left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px' });
    ov.querySelector('.mca-ov-sub').innerHTML = `${n ? plural(n, 'file') : 'Files'} into <b>${esc(f.name)}</b>`;
  }
  function setHot(card, n) {
    if (hot && hot !== card) { const m = hot.querySelector('.mca-fm'); if (m) m.removeAttribute('data-live-hot'); }
    hot = card;
    if (card) { const m = card.querySelector('.mca-fm'); if (m) m.setAttribute('data-live-hot', typeof n === 'string' ? n : `Drop ${n ? plural(n, 'file') : 'files'} here`); }
  }
  function clear() {
    clearTimeout(offT); setHot(null);
    if (ov) { const o = ov; ov = null; o.classList.remove('on'); setTimeout(() => o.remove(), 160); }
  }
  document.addEventListener('dragover', (e) => {
    if (!on() || ui.view !== 'client' || (typeof dragId !== 'undefined' && dragId) || !fileDrag(e) || [...e.dataTransfer.types].includes('application/x-e11-file')) return;
    moving = null;   // (files from outside: no file of ours is being dragged)
    const ct = document.getElementById('content');
    const { c, f } = curFolder();
    clearTimeout(offT); offT = setTimeout(clear, 1200);   // (a safety net: leaving the window clears it too)
    if (!c || !ct || !ct.contains(e.target) || !canAddAssets()) { clear(); return; }
    if (f) {
      if (!canUploadTo(c, f)) return;
      e.preventDefault(); e.stopPropagation(); e.dataTransfer.dropEffect = 'copy';
      showOv(f, nFiles(e));
      return;
    }
    const card = e.target.closest('.mca-fgrid [data-mca-folder]');
    const fo = card && c.folders.find((x) => x.id === card.dataset.mcaFolder);
    setHot(fo && canUploadTo(c, fo) ? card : null, nFiles(e));
    e.preventDefault(); e.stopPropagation();
    e.dataTransfer.dropEffect = hot ? 'copy' : 'none';   // (anywhere else on a client's page: nothing happens)
  }, true);
  document.addEventListener('dragleave', (e) => { if ((ov || hot) && !e.relatedTarget) clear(); }, true);
  document.addEventListener('drop', (e) => {
    if (!on() || ui.view !== 'client' || (typeof dragId !== 'undefined' && dragId) || !fileDrag(e) || [...e.dataTransfer.types].includes('application/x-e11-file')) return;
    moving = null;   // (files from outside: no file of ours is being dragged)
    const { c, f } = curFolder();
    const card = hot, files = [...(e.dataTransfer.files || [])];
    clear();
    if (!c) return;
    if (f) {
      if (!canUploadTo(c, f)) return;
      e.preventDefault(); e.stopPropagation();
      if (files.length) uploadIntoFolder(files);
      return;
    }
    e.preventDefault(); e.stopPropagation();
    if (!card || !files.length) return;
    PageHistory.mark(); ui.folderId = card.dataset.mcaFolder; const ct = document.getElementById('content'); if (ct) ct.scrollTop = 0; render(); PageHistory.mark();
    uploadIntoFolder(files);
  }, true);

  // ---------- a file held and dragged onto a folder card: moved there (as C6's client page — Haris 19:08) ----------
  // (only the app's list changes: the file stays where it's kept on disk, its link and copies pasted in tasks keep working)
  let moving = null;   // { cid, fid, aid }
  document.addEventListener('dragstart', (e) => {
    const t = on() && e.target.closest && e.target.closest('.mca-t[draggable="true"]');
    if (!t) return;
    const { c, f, a } = fileOf(t.dataset.mcaFile);
    if (!a || !canDelAsset(a)) { e.preventDefault(); return; }
    moving = { cid: c.id, fid: f.id, aid: a.id };
    e.dataTransfer.effectAllowed = 'move';
    try { e.dataTransfer.setData('application/x-e11-file', a.id); } catch (x) { /* */ }
    // (what's dragged: the file small, as Finder's — its picture and its name under it — Haris 19:24); the tile itself
    //  is gone from its place until it's let go (19:28)
    try { const gh = ghostOf(t, a); e.dataTransfer.setDragImage(gh.g, gh.w / 2 + 14, gh.h / 2 + 6); setTimeout(() => gh.g.remove(), 0); } catch (x) { /* the page's own picture of it */ }
    drag = { t, a, pt: null, moved: false };
    requestAnimationFrame(() => { if (drag && drag.t === t) t.setAttribute('data-live-moving', ''); });
  }, true);
  let drag = null;
  function ghostOf(t, a) {
    const pic = t.querySelector('.mca-tp'), r = pic.getBoundingClientRect(), w = 96, h = Math.round(w * r.height / Math.max(1, r.width));
    const g = document.createElement('div'); g.className = 'mca-ghost';
    const pc = pic.cloneNode(true); pc.querySelectorAll('.mca-cl, .mca-pin').forEach((x) => x.remove()); pc.removeAttribute('data-live-pvhide');
    pc.style.width = w + 'px'; pc.style.height = h + 'px';
    g.appendChild(pc);
    const nm = document.createElement('div'); nm.className = 'mca-ghost-n'; nm.textContent = a.name; g.appendChild(nm);
    document.body.appendChild(g);
    return { g, w, h, pc };
  }
  // (where the pointer is while dragging: the page's own events, the last real one kept)
  const track = (e) => { if (drag && (e.clientX || e.clientY)) drag.pt = { x: e.clientX, y: e.clientY }; };
  document.addEventListener('drag', track, true);
  document.addEventListener('dragover', track, true);
  // (let go anywhere it can't go: it springs back into its place from where it was let go, as Finder's)
  function springBack(d) {
    const t = d.t, done = () => t.removeAttribute('data-live-moving');
    if (!t.isConnected) return;
    const pic = t.querySelector('.mca-tp'), r = pic && pic.getBoundingClientRect();
    if (!d.pt || !r || !r.width || !Element.prototype.animate) { done(); t.animate([{ transform: 'scale(.92)', opacity: 0 }, { transform: 'scale(1)', opacity: 1 }], { duration: 260, easing: 'cubic-bezier(.3,1.35,.5,1)' }); return; }
    const gh = ghostOf(t, d.a), g = gh.g;
    g.classList.add('back');
    const gw = g.offsetWidth, gh2 = g.offsetHeight;
    const x0 = d.pt.x - gw / 2, y0 = d.pt.y - gh2 / 2;
    const sc = r.width / gh.w, x1 = r.left - 14 * sc, y1 = r.top - 6 * sc;
    g.style.left = '0px'; g.style.top = '0px'; g.style.transformOrigin = '0 0';
    const a1 = g.animate([{ transform: `translate(${x0}px, ${y0}px) scale(1)` }, { transform: `translate(${x1}px, ${y1}px) scale(${sc})` }], { duration: 380, easing: 'cubic-bezier(.3,1.25,.5,1)', fill: 'forwards' });
    gh.g.querySelector('.mca-ghost-n').animate([{ opacity: 1 }, { opacity: 0 }], { duration: 220, fill: 'forwards' });
    a1.onfinish = () => { done(); g.remove(); };
    setTimeout(() => { if (g.isConnected) { done(); g.remove(); } }, 700);
  }
  document.addEventListener('dragend', () => {
    const d = drag; drag = null;
    moving = null; setHot(null);
    if (d && !d.moved) springBack(d);
    document.querySelectorAll('[data-live-moving]').forEach((x) => { if (!d || x !== d.t || d.moved) x.removeAttribute('data-live-moving'); });
  }, true);
  const moveTarget = (e) => {
    const c = moving && clientById(moving.cid);
    const card = c && e.target.closest && e.target.closest('.mca [data-mca-folder]');
    const fo = card && card.dataset.mcaCl === c.id && c.folders.find((x) => x.id === card.dataset.mcaFolder);
    return fo && fo.id !== moving.fid && canUploadTo(c, fo) ? { c, card, fo } : null;
  };
  // (a drag of ours only while one is under way: files from Finder or elsewhere are never taken for it, and once the
  //  pointer moves with no button held the drag is over, even if its end was never told — Haris 19:21)
  const ours = (e) => { const ty = [...((e.dataTransfer && e.dataTransfer.types) || [])]; if (ty.includes('application/x-e11-file')) return true; if (ty.includes('Files')) { moving = null; return false; } return true; };
  document.addEventListener('mousemove', (e) => { if (e.buttons) return; if (moving) moving = null; if (on() && typeof pageDrag !== 'undefined' && pageDrag) pageDrag = false; }, true);
  document.addEventListener('dragover', (e) => {
    if (!moving || !ours(e)) return;
    const m = moveTarget(e);
    e.preventDefault(); e.stopPropagation();
    e.dataTransfer.dropEffect = m ? 'move' : 'none';
    setHot(m ? m.card : null, 'Move 1 file here');
  }, true);
  document.addEventListener('drop', (e) => {
    if (!moving || !ours(e)) return;
    const m = moveTarget(e), mv = moving;
    e.preventDefault(); e.stopPropagation();
    moving = null; setHot(null);
    if (!m) return;
    if (drag) drag.moved = true;
    const src = m.c.folders.find((x) => x.id === mv.fid), a = src && src.files.find((x) => x.id === mv.aid);
    if (!a || !canDelAsset(a) || m.fo.files.some((x) => x.id === a.id)) return;
    const put = (from, to) => { from.files = from.files.filter((x) => x.id !== a.id); to.files.push(a); persist(0); render(); };
    // (drawn again only once the drag has ended: the file's tile is still there to be told so — else the page would
    //  think a drag of its own was still under way and take no files from Finder — Haris 19:21)
    setTimeout(() => { if (typeof pageDrag !== 'undefined') pageDrag = false; }, 0);
    setTimeout(() => put(src, m.fo), 0);
    toast(`Moved “${a.name}” to ${m.fo.name}`, { label: 'Undo', run: () => { const c = clientById(mv.cid), s2 = c && c.folders.find((x) => x.id === mv.fid), d2 = c && c.folders.find((x) => x.id === m.fo.id); if (s2 && d2 && d2.files.some((x) => x.id === a.id)) put(d2, s2); } }, 8000);
  }, true);

  return { on, view, draw, results, info };
})();
