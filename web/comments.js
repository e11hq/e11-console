/* Comments: read receipts for @mentions and link previews.

   Read receipts (Seen): when someone @mentioned in a comment has it in view in the task (opening the update scrolls to
   it), their app tells the server (/api/seen), which saves the time on the comment (comment.seen[userId]). Everyone
   who can see the task sees "Seen by …" under the comment, with the faces and times on hover.

   Link previews: links in a comment get a card under it (up to 3) with the site, page title, description and picture,
   read by the server (/api/link, server/src/links.js) so the site never sees who is looking. WeTransfer cards show
   the files, total size and expiry when WeTransfer shares them, and warn when the link expires soon. The person who
   wrote the comment can remove a card (the link stays): comment.noPreview = [url]. */
const Cmx = (() => {
  const MAX_CARDS = 3;
  const urlsOf = (c) => {
    const found = [];
    const add = (u) => { u = String(u || '').replace(/[),.;:!?'"\]]+$/, ''); if (/^https?:\/\//i.test(u) && !found.includes(u)) found.push(u); };
    String(c.text || '').replace(/https?:\/\/[^\s<>"']+/gi, (m) => { add(m); return m; });
    String(c.html || '').replace(/href="(https?:\/\/[^"]+)"/gi, (_, m) => { add(m.replace(/&amp;/g, '&')); return _; });
    const own = (u) => { try { return new URL(u).host === location.host; } catch (e) { return true; } };   // (links to this app, e.g. a task)
    const off = new Set(c.noPreview || []);
    return found.filter((u) => !own(u) && !off.has(u)).slice(0, MAX_CARDS);
  };

  /* ---------- link cards ---------- */
  const cache = new Map();      // url → preview (or null while loading)
  const imgSrc = (u) => (u ? `/api/link/img?u=${encodeURIComponent(u)}` : '');
  const daysLeft = (iso) => Math.ceil((Date.parse(iso) - Date.now()) / 86400000);
  function wtLine(w) {
    if (!w) return '';
    const bits = [];
    if (w.files) bits.push(`${w.files} file${w.files === 1 ? '' : 's'}`);
    if (w.size) bits.push(w.size >= 1e9 ? `${(w.size / 1e9).toFixed(1).replace(/\.0$/, '')} GB` : w.size >= 1e6 ? `${Math.round(w.size / 1e6)} MB` : fmtSize(w.size));   // (as WeTransfer counts)
    let warn = '';
    if (w.expires) {
      const d = daysLeft(w.expires);
      if (d <= 0 || /expired|deleted/i.test(w.state || '')) { bits.push('Expired'); warn = 'gone'; }
      else { bits.push(d === 1 ? 'Expires tomorrow' : `Expires in ${d} days`); if (d <= 2) warn = 'soon'; }
    } else if (/expired|deleted/i.test(w.state || '')) { bits.push('Expired'); warn = 'gone'; }
    return bits.length ? `<div class="lk-wt ${warn}">${warn ? icon('clock') : ''}<span>${esc(bits.join(' · '))}</span></div>${(w.names || []).length ? `<div class="lk-desc">${esc(w.names.join(', '))}${w.files > w.names.length ? '…' : ''}</div>` : ''}` : '';
  }
  function cardHTML(c, url) {
    const p = cache.get(url);
    const mine = c.authorId === currentUserId;
    const x = mine ? `<button type="button" class="lk-x" data-lk-x="${esc(url)}" data-cid="${esc(c.id)}" title="Remove preview (the link stays)">${icon('x')}</button>` : '';
    let host = url;
    try { host = new URL(url).hostname.replace(/^www\./, ''); } catch (e) { /* keep */ }
    if (!p) return `<div class="lk-card loading" data-lk-u="${esc(url)}" data-action="open-url" data-url="${esc(url)}"><div class="lk-main"><div class="lk-site">${esc(host)}</div><div class="lk-bar"></div><div class="lk-bar short"></div></div>${x}</div>`;
    if (!p.ok || (p.error && !p.title && !p.wt)) return '';   // nothing to show: the link alone does
    const wt = p.key === 'wetransfer';
    return `<div class="lk-card ${wt ? 'wt' : ''} ${p.key ? 'k-' + esc(p.key) : ''}" data-lk-u="${esc(url)}" data-action="open-url" data-url="${esc(url)}" title="${esc(url)}">
      <div class="lk-main">
        <div class="lk-site">${p.icon ? `<img class="lk-ic" src="${imgSrc(p.icon)}" alt="" loading="lazy">` : ''}<span>${esc(p.site || host)}</span></div>
        ${p.title ? `<div class="lk-title">${esc(p.title)}</div>` : ''}
        ${wt ? wtLine(p.wt) : p.desc ? `<div class="lk-desc">${esc(p.desc)}</div>` : ''}
      </div>
      ${p.image && !wt ? `<img class="lk-pic" src="${imgSrc(p.image)}" alt="" loading="lazy">` : ''}${x}</div>`;
  }
  function cardsHTML(t, c) {
    if (ui.editingComment === c.id || !Host.isServer) return '';
    const urls = urlsOf(c);
    if (!urls.length) return '';
    return `<div class="lk-cards" data-lk-c="${esc(c.id)}">${urls.map((u) => cardHTML(c, u)).join('')}</div>`;
  }
  function load(url) {
    if (cache.has(url)) return;
    cache.set(url, null);
    api('GET', '/api/link?u=' + encodeURIComponent(url)).then((p) => { cache.set(url, p || { ok: false }); paint(url); })
      .catch(() => { cache.set(url, { ok: false }); paint(url); });
  }
  function paint(url) {
    document.querySelectorAll('.lk-card[data-lk-u]').forEach((el) => {
      if (el.dataset.lkU !== url) return;
      const cid = el.closest('[data-lk-c]') && el.closest('[data-lk-c]').dataset.lkC;
      const t = ui.taskId && task(ui.taskId);
      const c = t && (t.comments || []).find((x) => x.id === cid);
      if (!c) return;
      const tmp = document.createElement('div');
      tmp.innerHTML = cardHTML(c, url);
      if (tmp.firstElementChild) el.replaceWith(tmp.firstElementChild); else el.remove();
    });
    hideBroken();
  }
  // a picture or icon that didn't load: hidden (no inline handlers in the page)
  function hideBroken() {
    document.querySelectorAll('.lk-card img:not([data-w])').forEach((img) => {
      img.dataset.w = '1';
      const gone = () => { img.remove(); };
      if (img.complete && !img.naturalWidth && img.src) gone(); else img.addEventListener('error', gone, { once: true });
    });
  }
  // removing a card (the comment's writer): the link stays in the words
  document.addEventListener('click', (e) => {
    const b = e.target.closest && e.target.closest('[data-lk-x]');
    if (!b) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const t = ui.taskId && task(ui.taskId);
    const c = t && (t.comments || []).find((x) => x.id === b.dataset.cid);
    if (!c || c.authorId !== currentUserId) return;
    c.noPreview = [...new Set([...(c.noPreview || []), b.dataset.lkX])];
    commit();
    renderDetail();
  }, true);

  /* ---------- Seen ---------- */
  const mentioned = (c) => [...mentionsIn(c.html)].filter((id) => id !== c.authorId && userById(id));
  const timeOf = (iso) => new Date(iso).toLocaleString('en-US', { weekday: 'short', hour: 'numeric', minute: '2-digit' });
  function seenHTML(t, c) {
    if (ui.editingComment === c.id) return '';
    const who = mentioned(c);
    if (!who.length) return '';
    const seen = c.seen || {};
    const yes = who.filter((id) => seen[id]).sort((a, b) => String(seen[a]).localeCompare(String(seen[b])));
    const no = who.filter((id) => !seen[id]);
    const nm = (id) => (id === currentUserId ? 'You' : firstName(id));
    const tip = [...yes.map((id) => `Seen by ${fullName(userById(id))} · ${timeOf(seen[id])}`), ...(no.length ? [`Not seen yet: ${no.map((id) => fullName(userById(id))).join(', ')}`] : [])].join('\n');
    const label = !yes.length ? (who.length === 1 ? `Not seen by ${nm(who[0])} yet` : 'Not seen yet')
      : who.length === 1 ? `Seen${who[0] === currentUserId ? '' : ` by ${nm(who[0])}`} · ${timeOf(seen[who[0]])}`
        : no.length ? `Seen by ${yes.length} of ${who.length}` : 'Seen by everyone mentioned';
    return `<div class="cm-seen ${yes.length ? 'on' : ''}" title="${esc(tip)}">${icon('eye')}<span>${esc(label)}</span>${yes.length ? `<span class="cm-seen-avs">${yes.slice(0, 5).map((id) => avatarHTML(id, 16)).join('')}</span>` : ''}</div>`;
  }
  // tell the server which comments that mention you are now in view (once each)
  const told = new Set(), queue = new Map();
  let flushT = null, io = null;
  function flush() {
    flushT = null;
    for (const [tid, ids] of queue) {
      queue.delete(tid);
      api('POST', '/api/seen', { taskId: tid, ids: [...ids] }).catch(() => { ids.forEach((id) => told.delete(id)); });
    }
  }
  function mark(tid, cid) {
    if (told.has(cid)) return;
    told.add(cid);
    if (!queue.has(tid)) queue.set(tid, new Set());
    queue.get(tid).add(cid);
    // (sent a moment later, so the task doesn't redraw while a comment opened from the Inbox is still highlighted)
    clearTimeout(flushT); flushT = setTimeout(flush, 2000);
  }
  const awake = () => document.visibilityState === 'visible';
  function watch(pane, t) {
    if (!Host.isServer || !currentUserId || (typeof ViewAs !== 'undefined' && ViewAs.viewing && ViewAs.viewing())) return;
    if (io) io.disconnect();
    const mine = (t.comments || []).filter((c) => c.authorId !== currentUserId && !(c.seen || {})[currentUserId] && !told.has(c.id) && mentionsIn(c.html).has(currentUserId));
    if (!mine.length || !('IntersectionObserver' in window)) return;
    const want = new Set(mine.map((c) => c.id));
    const dwell = new Map();   // a comment counts as seen after a second in view
    const obs = io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        const cid = en.target.dataset.comment;
        if (!want.has(cid)) return;
        if (!en.isIntersecting || en.intersectionRatio < 0.5) { clearTimeout(dwell.get(cid)); dwell.delete(cid); return; }
        if (dwell.has(cid)) return;
        dwell.set(cid, setTimeout(() => { dwell.delete(cid); if (io !== obs || !awake() || ui.taskId !== t.id) return; mark(t.id, cid); obs.unobserve(en.target); }, 1000));
      });
    }, { threshold: [0, 0.5] });
    pane.querySelectorAll('.cm[data-comment]').forEach((el) => { if (want.has(el.dataset.comment)) io.observe(el); });
  }
  // back to the app with the task open: what's in view counts
  document.addEventListener('visibilitychange', () => { if (awake() && ui.taskId && db) { const p = document.getElementById('detail'); const t = task(ui.taskId); if (p && t) watch(p, t); } });

  function afterDetail(pane, t) {
    if (!pane || !t) return;
    pane.querySelectorAll('.lk-card.loading[data-lk-u]').forEach((el) => load(el.dataset.lkU));
    hideBroken();
    watch(pane, t);
  }
  return { cardsHTML, seenHTML, afterDetail, urlsOf, _cache: cache };
})();
