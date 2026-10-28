/* File preview (phone and computer). The file fills the screen; you move through its group only — the client folder
   it's in, the task's attachments, or that one comment's files (a review submission's own files on the Reviews page)
   — by swiping (phone) or with ‹ › and ← → (computer). "3 of 8" at the top, the name, size, who added it and when
   above a strip of thumbnails, Copy and Download, and ⋯ for Info and
   Remove / Delete where allowed. Phone: tap to hide everything, pinch or double-tap to zoom, pull down to close.
   Follows the app's theme. (The phone's Review request screen keeps its own swipe.) */
const Viewer = (() => {
  let list = [], at = 0, root = null, bare = false, keyOn = false, hideT = null;
  const phone = () => typeof Phone !== 'undefined' && Phone.on;
  const W = () => (root ? root.querySelector('.fpv-stage').clientWidth : innerWidth);

  // the group a file belongs to (order as shown there)
  function groupOf(a) {
    const t = ui.taskId && task(ui.taskId);
    if (t) {
      if ((t.attachments || []).some((x) => x.id === a.id)) return t.attachments.slice();
      for (const c of t.comments || []) if ((c.attachments || []).some((x) => x.id === a.id)) return c.attachments.slice();
      for (const k of Object.keys(ui.commentFiles || {})) { const l = ui.commentFiles[k] || []; if (l.some((x) => x.id === a.id)) return l.slice(); }
    }
    for (const c of db.clients || []) for (const f of c.folders || []) if (f.files.some((x) => x.id === a.id)) return f.files.slice().sort((x, y) => x.name.localeCompare(y.name));
    return [a];
  }

  const big = (a) => (phone() ? imgUrl(a, 1600) : fileUrl(a));
  const cover = (a) => (a.thumb ? `<img class="fpv-cover" src="${posterUrl(a)}" alt="" draggable="false">` : `<div class="fpv-ph"><span>${esc((fileExt(a.name) || 'file').slice(0, 5))}</span></div>`);
  // what a slide shows: the current one in full; its neighbours light (a picture, or the file's cover)
  function body(a, full) {
    const kind = fileKind(a), ext = fileExt(a.name);
    if (kind === 'image') return `<img class="fpv-img" src="${big(a)}" alt="" draggable="false">`;
    if (!full) return `<div class="fpv-light">${cover(a)}${kind === 'video' ? `<span class="fpv-play">${icon('play')}</span>` : ''}</div>`;
    if (kind === 'video') return `<video class="fpv-video" src="${viewUrl(a)}" controls playsinline preload="metadata"${a.thumb ? ` poster="${posterUrl(a)}"` : ''}></video>`;
    if (kind === 'audio') return `<div class="fv-audio">${icon('play')}<audio src="${fileUrl(a)}" controls></audio></div>`;
    if (Host.isServer && phone() && (kind === 'pdf' || OFFICE_EXT.includes(ext))) return `<div class="fpv-scroll"><div class="fv-pages" id="fv-pages"><p class="fv-wait"><span class="spin"></span>Loading the pages…</p></div></div>`;
    if (kind === 'pdf') return `<iframe class="fv-pdf" src="${fileUrl(a)}" title="${esc(a.name)}"></iframe>`;
    if (kind === 'text') return `<div class="fpv-scroll"><pre class="fv-text" data-text-src="${fileUrl(a)}">Loading…</pre></div>`;
    if (OFFICE_EXT.includes(ext) && Host.isServer) return `<div class="fv-doc" id="fv-office">${thumbImg(a, 'wide')}<p class="fv-wait"><span class="spin"></span>Preparing the full preview…</p></div>`;
    return `<div class="fv-doc">${thumbImg(a, 'wide')}<p>This preview shows the first page. Download it to see the whole file.</p></div>`;
  }
  const thumbOf = (a, k) => {
    const kind = fileKind(a);
    const inner = kind === 'image' ? `<img src="${imgUrl(a, 160)}" alt="" loading="lazy" draggable="false">` : a.thumb ? `<img src="${posterUrl(a)}" alt="" loading="lazy" draggable="false">` : `<span>${esc((fileExt(a.name) || 'file').slice(0, 4))}</span>`;
    return `<button class="fpv-th ${k === at ? 'on' : ''} ${kind === 'image' || a.thumb ? '' : 'doc'}" data-pv="go" data-i="${k}" aria-label="${esc(a.name)}">${inner}</button>`;
  };

  function open(a, group) {
    if (!a) return;
    list = (group && group.length ? group : groupOf(a)).filter(Boolean);
    at = list.findIndex((x) => x.id === a.id);
    if (at < 0) { list = [a]; at = 0; }
    bare = false;
    const many = list.length > 1;
    let host = document.getElementById('pv-root');
    if (!host) { host = document.createElement('div'); host.id = 'pv-root'; document.body.appendChild(host); }   // (its own layer: pop-ups use #overlay-root above it)
    document.body.classList.add('pv-open');
    host.innerHTML = `<div class="fpv ${phone() ? 'fpv-onphone' : 'fpv-oncomputer'} ${many ? 'fpv-many' : ''}" role="dialog" aria-label="File preview">
      <div class="fpv-top">
        <button class="fpv-rb" data-pv="close" aria-label="Close">${icon('x')}</button>
        <div class="fpv-count"></div>
        <div class="fpv-acts">${phone() ? '' : `<button class="fpv-btn" data-pv="copy" title="Paste it into any comment or description">${icon('copy')}Copy</button><button class="fpv-btn" data-pv="dl">${icon('download')}Download</button>`}<button class="fpv-rb" data-pv="more" aria-label="More">${icon('more')}</button></div>
      </div>
      <div class="fpv-stage"><div class="fpv-track"></div></div>
      ${!phone() && many ? `<button class="fpv-arr prev" data-pv="prev" aria-label="Previous">${icon('chev-left')}</button><button class="fpv-arr next" data-pv="next" aria-label="Next">${icon('chev-right')}</button>` : ''}
      <div class="fpv-bot">
        <div class="fpv-meta"></div>
        ${many ? `<div class="fpv-strip">${list.map(thumbOf).join('')}</div>` : ''}
        ${phone() ? `<div class="fpv-btns"><button class="fpv-bb" data-pv="copy">${icon('copy')}<span>Copy</span></button><button class="fpv-bb" data-pv="dl">${icon('download')}<span>Download</span></button></div>` : ''}
        ${!phone() && many ? '<div class="fpv-keys"><kbd>←</kbd><kbd>→</kbd> next · <kbd>esc</kbd> close</div>' : ''}
      </div>
    </div>`;
    root = host.querySelector('.fpv');
    root.addEventListener('click', onClick);
    if (phone()) touch(root.querySelector('.fpv-stage'));
    else { root.addEventListener('mousemove', wake); wake(); }
    if (!keyOn) { document.addEventListener('keydown', onKey, true); keyOn = true; }
    show(at);
  }
  function close() {
    pauseAll();
    const h = document.getElementById('pv-root'); if (h) h.innerHTML = '';
    document.body.classList.remove('pv-open');
    root = null; ui.previewAtt = null; clearTimeout(hideT);
    if (keyOn) { document.removeEventListener('keydown', onKey, true); keyOn = false; }
  }
  const isOpen = () => !!(root && root.isConnected);

  // the three slides (previous, this one, next), the counter, the name line and the strip
  function show(n) {
    if (!isOpen()) return;
    at = Math.max(0, Math.min(list.length - 1, n));
    const a = list[at];
    ui.previewAtt = a;
    const track = root.querySelector('.fpv-track');
    track.style.transition = 'none'; track.style.transform = '';
    track.innerHTML = [-1, 0, 1].map((d) => { const x = list[at + d]; return `<div class="fpv-slide" style="left:${d * 100}%">${x ? body(x, d === 0) : ''}</div>`; }).join('');
    root.querySelector('.fpv-count').textContent = list.length > 1 ? `${at + 1} of ${list.length}` : '';
    const who = a.addedBy ? userName(a.addedBy) : '';
    root.querySelector('.fpv-meta').innerHTML = `<b>${esc(a.name)}</b><span>${[fmtSize(a.size), who, a.addedAt ? timeAgo(a.addedAt) : ''].filter(Boolean).map(esc).join(' · ')}</span>`;
    root.querySelectorAll('.fpv-th').forEach((b) => b.classList.toggle('on', Number(b.dataset.i) === at));
    const on = root.querySelector('.fpv-th.on');
    if (on) on.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' });
    root.classList.toggle('fpv-first', at === 0); root.classList.toggle('fpv-last', at === list.length - 1);
    zoom.reset();
    hydrate(a, track.children[1]);
  }
  function hydrate(a, slide) {
    hydratePreviews(slide);
    hydrateThumbs(slide);
    if (slide.querySelector('#fv-pages')) {
      Host.call('pdfPages', { id: a.id, path: a.path }).then((r) => {
        const el = slide.querySelector('#fv-pages');
        if (!el || ui.previewAtt !== a) return;
        const pages = (r && r.pages) || [];
        if (!pages.length) { el.innerHTML = `<p class="fv-wait">${r && r.unavailable ? 'Full previews of Office files arrive with the next server update.' : 'This file couldn’t be previewed — download it to see it.'}</p>`; return; }
        el.innerHTML = pages.map((p, i) => `<img class="fv-page" src="${'/__file/' + p.split('/').map(encodeURIComponent).join('/')}" alt="Page ${i + 1}" loading="${i < 2 ? 'eager' : 'lazy'}" draggable="false">`).join('')
          + (r.total > pages.length ? `<p class="fv-wait">Showing the first ${pages.length} of ${r.total} pages — download it for the rest.</p>` : '');
        pageChip(slide, pages.length);
      }).catch(() => { const el = slide.querySelector('#fv-pages'); if (el) el.innerHTML = '<p class="fv-wait">This file couldn’t be previewed right now.</p>'; });
    }
    if (slide.querySelector('#fv-office')) {
      Host.call('docPreview', { id: a.id, path: a.path }).then((r) => {
        const el = slide.querySelector('#fv-office');
        if (!el || ui.previewAtt !== a) return;
        if (r && r.pdf) el.outerHTML = `<iframe class="fv-pdf" src="${'/__file/' + r.pdf.split('/').map(encodeURIComponent).join('/')}" title="${esc(a.name)}"></iframe>`;
        else { const w = el.querySelector('.fv-wait'); if (w) w.innerHTML = r && r.unavailable ? 'Full previews of Office files arrive with the next server update. This shows the first page.' : 'This file couldn’t be previewed — download it to see it.'; }
      }).catch(() => { const w = slide.querySelector('#fv-office .fv-wait'); if (w) w.textContent = 'This file couldn’t be previewed right now.'; });
    }
  }
  // "Page 2 of 5" while the pages scroll (phone)
  function pageChip(slide, n) {
    const sc = slide.querySelector('.fpv-scroll'); if (!sc || n < 2) return;
    const chip = document.createElement('div'); chip.className = 'fpv-page'; slide.appendChild(chip);
    let t = null;
    const upd = () => {
      const imgs = [...sc.querySelectorAll('.fv-page')]; const mid = sc.getBoundingClientRect().top + sc.clientHeight / 3;
      let k = 0; imgs.forEach((im, i) => { if (im.getBoundingClientRect().top < mid) k = i; });
      chip.textContent = `Page ${k + 1} of ${n}`; chip.classList.add('on');
      clearTimeout(t); t = setTimeout(() => chip.classList.remove('on'), 1200);
    };
    sc.addEventListener('scroll', upd, { passive: true });
  }

  // to the next / previous file, sliding
  function go(d) {
    if (!isOpen()) return;
    const n = at + d;
    const track = root.querySelector('.fpv-track');
    if (n < 0 || n >= list.length) { bounce(track, d); return; }
    pauseAll();
    track.style.transition = 'transform .24s cubic-bezier(.2,.8,.2,1)';
    track.style.transform = `translate3d(${-d * 100}%,0,0)`;
    let done = false;
    const fin = () => { if (done) return; done = true; show(n); };
    track.addEventListener('transitionend', fin, { once: true });
    setTimeout(fin, 320);
  }
  function bounce(track, d) {
    track.style.transition = 'transform .12s ease-out'; track.style.transform = `translate3d(${-d * 28}px,0,0)`;
    setTimeout(() => { track.style.transition = 'transform .2s ease-out'; track.style.transform = ''; }, 120);
  }
  const pauseAll = () => { if (root) root.querySelectorAll('video, audio').forEach((m) => { try { m.pause(); } catch (e) { /* fine */ } }); };

  // ---- Copy / Download / Open / ⋯ ----
  function onClick(e) {
    const b = e.target.closest('[data-pv]');
    const a = list[at];
    if (!b) {
      // computer: a click on the empty space around the file closes it
      if (!phone() && e.target.closest('.fpv-slide') && !e.target.closest('img, video, iframe, audio, .fv-doc, .fpv-scroll, .fpv-light, pre')) close();
      return;
    }
    e.stopPropagation();
    switch (b.dataset.pv) {
      case 'close': close(); break;
      case 'prev': go(-1); break;
      case 'next': go(1); break;
      case 'go': { const n = Number(b.dataset.i); if (n !== at) { pauseAll(); show(n); } break; }
      case 'copy': copyAttachment(a); break;
      case 'dl': Host.call('revealPath', { path: a.path }).catch((err) => toast(err.cancelled ? 'Download cancelled' : 'Couldn’t download: ' + err.message)); break;
      case 'more': more(b, a); break;
    }
  }
  function more(anchor, a) {
    const client = clientFileById(a.id) === a ? a : null;
    const t = ui.taskId && task(ui.taskId);
    const onTask = !client && t && (t.attachments || []).some((x) => x.id === a.id);
    const items = [{ label: 'Info', icon: 'info', run: () => (client ? caInfo('file', a.id) : info(a)) }];
    if (client && canDelAsset(a)) items.push('-', { label: 'Delete', icon: 'trash', danger: true, run: async () => { const was = list.length; await removeClientFile(a.id); if (!clientFileById(a.id)) afterGone(a, was); } });
    if (onTask) items.push('-', { label: 'Remove from task', icon: 'trash', danger: true, run: () => act('remove-att', a.id, () => { if (!(task(ui.taskId).attachments || []).some((x) => x.id === a.id)) afterGone(a); }) });
    const m = showMenu(anchor, items);
    if (m) m.classList.add('fpv-menu');
  }
  // a file was removed while shown: on to the next one (or close when it was the only one)
  function afterGone(a) {
    list = list.filter((x) => x.id !== a.id);
    if (!list.length || !isOpen()) { close(); return; }
    at = Math.min(at, list.length - 1);
    const s = root.querySelector('.fpv-strip'); if (s) s.innerHTML = list.map(thumbOf).join('');
    if (list.length < 2) root.classList.remove('fpv-many');
    show(at);
  }
  // runs one of the app's own buttons (its rules and its pop-ups), then checks what happened
  function act(action, id, then) {
    const btn = document.createElement('button'); btn.hidden = true; btn.dataset.action = action; btn.dataset.id = id;
    document.body.appendChild(btn); btn.click(); btn.remove();
    const wait = setInterval(() => { if (!document.querySelector('.scrim, .dialog')) { clearInterval(wait); then && then(); } }, 250);
    setTimeout(() => clearInterval(wait), 60000);
  }
  function info(a) {
    const kind = fileKind(a), d = MediaDims.of(a);
    const rows = [['Name', a.name], ['Size', fmtSize(a.size)], ['Type', (fileExt(a.name) || 'file').toUpperCase() + (kind === 'image' || kind === 'video' ? (d ? ` · ${d[0]} × ${d[1]}` : '') : '')],
      a.addedBy ? ['Added by', userName(a.addedBy)] : null, a.addedAt ? ['Added', fmtDateTime(a.addedAt)] : null].filter(Boolean);
    dialog({ title: 'File info', body: `<div class="fpv-info">${rows.map(([k, v]) => `<div><span>${esc(k)}</span><b>${esc(v)}</b></div>`).join('')}</div>`, okText: 'Done', cancelText: '' });
  }

  // ---- computer: keys, and the side arrows showing while the mouse moves ----
  function onKey(e) {
    if (!isOpen()) return;
    if (document.querySelector('.scrim, .dialog, .menu')) return;   // (a pop-up on top takes its own keys)
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); go(1); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); e.stopPropagation(); go(-1); }
    else if (e.key === ' ' && !/INPUT|TEXTAREA/.test((e.target || {}).tagName || '')) { const v = root.querySelector('.fpv-slide:nth-child(2) video'); if (v) { e.preventDefault(); if (v.paused) v.play(); else v.pause(); } }
  }
  function wake() { if (!root) return; root.classList.add('fpv-awake'); clearTimeout(hideT); hideT = setTimeout(() => root && root.classList.remove('fpv-awake'), 2200); }

  // ---- phone: swipe, tap to hide everything, pinch / double-tap zoom, pull down to close ----
  const zoom = (() => {
    let s = 1, x = 0, y = 0, img = null;
    const apply = () => { if (img) { img.style.transform = s === 1 ? '' : `translate3d(${x}px,${y}px,0) scale(${s})`; } if (root) root.classList.toggle('fpv-zoomed', s > 1); };
    return {
      get on() { return s > 1; },
      reset() { s = 1; x = 0; y = 0; if (img) img.style.transform = ''; img = root ? root.querySelector('.fpv-slide:nth-child(2) .fpv-img') : null; if (root) root.classList.remove('fpv-zoomed'); },
      set(ns, nx, ny) {
        if (!img) return;
        s = Math.max(1, Math.min(5, ns));
        if (s === 1) { x = 0; y = 0; } else {
          const mx = Math.max(0, (img.offsetWidth * s - W()) / 2), my = Math.max(0, (img.offsetHeight * s - img.parentElement.clientHeight) / 2);
          x = Math.max(-mx, Math.min(mx, nx)); y = Math.max(-my, Math.min(my, ny));
        }
        apply();
      },
      get s() { return s; }, get x() { return x; }, get y() { return y; },
      get img() { return img; },
    };
  })();
  function touch(stage) {
    let g = null, lastTap = 0, pinch = null;
    const dist = (t) => Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
    stage.addEventListener('touchstart', (e) => {
      if (e.touches.length === 2 && zoom.img) { pinch = { d: dist(e.touches), s: zoom.s, x: zoom.x, y: zoom.y }; g = null; return; }
      if (e.touches.length !== 1) return;
      const t = e.touches[0];
      const sc = e.target.closest('.fpv-scroll');
      g = { x0: t.clientX, y0: t.clientY, t0: Date.now(), dx: 0, dy: 0, mode: null, sc, zx: zoom.x, zy: zoom.y, onVideo: !!e.target.closest('video') };
    }, { passive: true });
    stage.addEventListener('touchmove', (e) => {
      if (pinch && e.touches.length === 2) { e.preventDefault(); zoom.set(pinch.s * (dist(e.touches) / pinch.d), pinch.x, pinch.y); return; }
      if (!g || e.touches.length !== 1) return;
      const t = e.touches[0];
      g.dx = t.clientX - g.x0; g.dy = t.clientY - g.y0;
      if (!g.mode) {
        if (Math.hypot(g.dx, g.dy) < 8) return;
        if (zoom.on) g.mode = 'pan';
        else if (Math.abs(g.dx) > Math.abs(g.dy)) g.mode = list.length > 1 ? 'swipe' : 'none';
        else if (g.dy > 0 && (!g.sc || g.sc.scrollTop <= 0)) g.mode = 'pull';
        else g.mode = 'none';   // (pages scrolling up and down)
      }
      const track = root.querySelector('.fpv-track');
      if (g.mode === 'swipe') {
        e.preventDefault();
        let dx = g.dx;
        if ((at === 0 && dx > 0) || (at === list.length - 1 && dx < 0)) dx *= 0.3;   // the edge: a little give, no further
        track.style.transition = 'none'; track.style.transform = `translate3d(${dx}px,0,0)`;
      } else if (g.mode === 'pull') {
        e.preventDefault();
        const dy = Math.max(0, g.dy);
        track.style.transition = 'none'; track.style.transform = `translate3d(0,${dy}px,0) scale(${1 - Math.min(0.15, dy / 2000)})`;
        root.style.setProperty('--pv-fade', String(Math.max(0.25, 1 - dy / 400)));
        root.classList.add('fpv-pulling');
      } else if (g.mode === 'pan') {
        e.preventDefault();
        zoom.set(zoom.s, g.zx + g.dx, g.zy + g.dy);
      }
    }, { passive: false });
    const end = () => {
      if (pinch) { pinch = null; if (zoom.s < 1.05) zoom.set(1, 0, 0); return; }
      if (!g) return;
      const c = g; g = null;
      const track = root && root.querySelector('.fpv-track');
      if (!track) return;
      if (c.mode === 'swipe') {
        const fast = Math.abs(c.dx) > 30 && Math.abs(c.dx) / Math.max(1, Date.now() - c.t0) > 0.45;
        const d = c.dx < 0 ? 1 : -1;
        if ((Math.abs(c.dx) > W() * 0.25 || fast) && at + d >= 0 && at + d < list.length) {
          pauseAll();
          track.style.transition = 'transform .22s cubic-bezier(.2,.8,.2,1)';
          track.style.transform = `translate3d(${-d * W()}px,0,0)`;
          let done = false; const fin = () => { if (done) return; done = true; show(at + d); };
          track.addEventListener('transitionend', fin, { once: true }); setTimeout(fin, 300);
        } else { track.style.transition = 'transform .22s ease-out'; track.style.transform = ''; }
        return;
      }
      if (c.mode === 'pull') {
        root.classList.remove('fpv-pulling');
        if (c.dy > 110 || (c.dy > 40 && c.dy / Math.max(1, Date.now() - c.t0) > 0.5)) { close(); return; }
        track.style.transition = 'transform .22s ease-out'; track.style.transform = ''; root.style.removeProperty('--pv-fade');
        return;
      }
      if (c.mode) return;
      // a tap: double-tap zooms a picture; a single tap hides / shows everything
      if (c.onVideo) return;
      const now = Date.now();
      if (zoom.img && now - lastTap < 280) {
        lastTap = 0; clearTimeout(tapT);
        if (zoom.on) zoom.set(1, 0, 0);
        else { const r = zoom.img.getBoundingClientRect(); const s = 2.5; zoom.set(s, (r.left + r.width / 2 - c.x0) * (s - 1), (r.top + r.height / 2 - c.y0) * (s - 1)); }
        return;
      }
      lastTap = now;
      clearTimeout(tapT); tapT = setTimeout(() => { bare = !bare; if (root) root.classList.toggle('fpv-bare', bare); }, zoom.img ? 290 : 0);
    };
    let tapT = null;
    stage.addEventListener('touchend', end);
    stage.addEventListener('touchcancel', end);
  }

  return { open, close, isOpen, groupOf };
})();
