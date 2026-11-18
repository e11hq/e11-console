/* ================= The Mac app's Search (canvas "Search — Mac" S1–S5, Haris 2026-11-18) =================
   The Mac app only (html.mac-chrome); browsers and the iPhone keep app.js's own search page (viewSearch).
   S2 typing: a quick list under the top bar's field — people, clients, five tasks, "See all results" — the page stays.
   S1 / S3 the Search page: the website's own search (taskSearch, its typo note and "found in" lines), the tasks as Home's rows,
   people found, clients found, the filter words shown as chips. S5 a person clicked: the same page, only the tasks they're
   assigned to (that you can see). S4 nothing found: the website's words. Right-click a task: Apple's own menu
   (app.js taskContextMenu). Drawn again: only what changed (data-key, as the Mac Inbox and Client Assets). */
const MacSearch = (() => {
  const on = () => typeof Host !== 'undefined' && Host.isMacApp && document.documentElement.classList.contains('mac-chrome');
  const st = { person: null, sel: -1, items: [] };
  const plural = (n, w, ws) => `${n} ${n === 1 ? w : ws || w + 's'}`;
  // ---- Home's row, as Home draws it (home.js) — the client's colour, the title, Urgent / P tag, the line under it with the CD chip,
  //      comments and files, the people, the status pill ----
  const projOf = (t) => proj(t.projectId) || (t.parentId && task(t.parentId) ? proj(task(t.parentId).projectId) : null);
  const pColor = (t) => (projOf(t) || {}).color || 'var(--text-3)';
  const pName = (t) => (projOf(t) || {}).name || 'No client';
  const tag = (t) => { const p = t.done ? 'none' : prioOf(t); return p === 'urgent' ? '<span class="hm-tag urgent">Urgent</span>' : typeof p === 'number' ? `<span class="hm-tag">P${p}</span>` : ''; };
  const cdTag = (t) => { const c = !t.done && CD[t.cdStatus]; return c ? `<span class="hm-cd ${t.cdStatus === 'approved' ? 'ok' : ''}" style="--c:${c.color}" title="CD Status: ${esc(c.label)}">${t.cdStatus === 'approved' ? '✓ ' : ''}CD</span>` : ''; };
  const late = (t) => (!t.done && t.due && t.due < todayStr() ? 'late' : '');
  const svg = (d, w = 1.5) => `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${d}"/></svg>`;
  const IC = {
    chat: 'M3.2 2.9h9.6c.6 0 1 .4 1 1v6.6c0 .6-.4 1-1 1H7.4l-3 2.4v-2.4H3.2c-.6 0-1-.4-1-1V3.9c0-.6.4-1 1-1z',
    clip: 'M10.5 4.5 5.6 9.4a1.4 1.4 0 0 0 2 2l5-5a2.8 2.8 0 0 0-4-4l-5 5a4.2 4.2 0 0 0 6 6l4.4-4.4',
    sub: 'M4 2.8v6.4a2 2 0 0 0 2 2h6.5M10 8.8l2.5 2.4-2.5 2.4',
  };
  const ik = (k, w = 1.5) => svg(IC[k], w).replace('<svg ', `<svg data-i="hm-${k}" `);
  const seenOk = (t) => !amReadOnly(t) && searchOwnOk(t);
  function row(t, r, why) {
    const par = t.parentId ? task(t.parentId) : null;
    const subs = subtasksOf(t.id);
    const by = t.createdBy && t.createdBy !== currentUserId && userById(t.createdBy);
    const ttl = t.title ? (r ? sMark(t.title, r) : esc(t.title)) : '<span class="ph">Untitled task</span>';
    return `<div class="hm-row ${late(t)}" data-task="${t.id}" data-key="t-${t.id}">
      <i class="hm-pc" style="background:${pColor(t)}"></i>
      <span class="hm-main"><span class="hm-tl">${par ? `<span class="mcs-par">${esc(par.title || 'Untitled task')} ›</span>` : ''}<span class="hm-t ${t.done ? 'struck' : ''}">${ttl}</span>${tag(t)}${subs.length ? `<span class="mcs-subs" title="Subtasks">${subs.filter((s) => s.done).length}/${subs.length}${ik('sub')}</span>` : ''}</span><span class="hm-sub">${esc(pName(t))}${by ? ` · by ${esc(fullName(by))}` : ''}${t.due ? ` · due <span class="due ${dueClass(t)}">${esc(fmtDue(t.due))}</span>` : ''}${cdTag(t)}</span>${why ? `<span class="mcs-why">${why}</span>` : ''}</span>
      <span class="hm-counts"><span title="Comments">${ik('chat', 1.4)}${(t.comments || []).length}</span><span title="Files">${ik('clip', 1.4)}${shownAtts(t).length}</span></span>
      <span class="hm-who">${(t.assignees || []).length ? avatarStack(t.assignees, 26, 3, t) : '<span class="hm-mute">Unassigned</span>'}</span>
      <span class="hm-st">${statusPill(t)}</span>
    </div>`;
  }

  // ---- people found: the team, by name (every word of what's typed that isn't a filter word) ----
  const FLAG = { overdue: 'Overdue', today: 'Today', tomorrow: 'Tomorrow', urgent: 'Urgent', done: 'Done', completed: 'Done', open: 'Open', mine: 'Mine', me: 'Mine', unassigned: 'Unassigned', review: 'Review', approved: 'Approved' };
  function people(q) {
    const terms = sWords(q).filter((w) => !FLAG[w]);
    if (!terms.length) return [];
    return (db.users || []).filter((u) => u.active !== false && !u.deleted).filter((u) => {
      const ws = sWords(fullName(u));
      return terms.every((tm) => ws.some((w) => w.startsWith(tm)));
    }).slice(0, 12);
  }
  const theirs = (u) => db.tasks.filter((t) => (t.assignees || []).includes(u.id) && seenOk(t));
  const openOf = (u) => theirs(u).filter((t) => !t.done).length;
  const roleOf = (u) => (typeof ROLES !== 'undefined' && ROLES[u.role]) || '';
  const markName = (name, q) => { const ts = sWords(q).filter((w) => !FLAG[w]); return esc(name).split(/(\s+)/).map((p) => (ts.some((x) => sNorm(p).startsWith(x)) ? `<mark>${p}</mark>` : p)).join(''); };
  const clientOpen = (p) => { const S = Work.seen(); return db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done && S.has(t.id)).length; };

  // ---------- the Search page ----------
  function view() {
    const q = ui.search.trim();
    const u = st.person && userById(st.person);
    if (u) return personView(u, q);
    const r = taskSearch(q), ppl = people(q);
    const flags = [...new Set((r.terms || []).filter((pt) => pt.flag && FLAG[pt.term]).map((pt) => FLAG[pt.term]))];
    const parts = [`<b>${plural(r.total || 0, 'task')}</b>`];
    if (ppl.length) parts.push(plural(ppl.length, 'person', 'people'));
    if (r.projects.length) parts.push(plural(r.projects.length, 'client'));
    const head = parts.length > 2 ? `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}` : parts.join(' and ');
    const rows = r.tasks.map((h) => row(h.t, r, searchWhy(h, r))).join('');
    return `<div class="hm mcs" data-key="mcs-all">
      <div class="mcs-head" data-key="head">${head} for “${esc(q)}”</div>
      ${r.fixed.length ? `<div class="mcs-fix" data-key="fix">Showing results for ${r.fixed.map((f) => `<b>${esc(f.to)}</b>`).join(', ')} <span>(you typed ${r.fixed.map((f) => `“${esc(f.from)}”`).join(', ')})</span></div>` : ''}
      ${flags.length ? `<div class="mcs-flt" data-key="flt">Filters from your words:${flags.map((f) => `<span class="mcs-fc">${f}</span>`).join('')}</div>` : ''}
      ${ppl.length ? `<h2 class="mcs-gh" data-key="gh-p">People <span>${ppl.length}</span></h2><div class="mcs-cards" data-key="ppl">${ppl.map((x) => `<button type="button" class="mcs-card" data-mcs="person" data-id="${x.id}" data-key="p-${x.id}">${avatarStack([x.id], 32, 1)}<span class="mcs-ct"><b>${markName(fullName(x), q)}</b><small>${esc([roleOf(x), plural(openOf(x), 'open task')].filter(Boolean).join(' · '))}</small></span><span class="mcs-chev">›</span></button>`).join('')}</div>` : ''}
      ${r.projects.length ? `<h2 class="mcs-gh" data-key="gh-c">Clients <span>${r.projects.length}</span></h2><div class="mcs-cards" data-key="cls">${r.projects.map((p) => `<button type="button" class="mcs-card" data-action="go-project" data-id="${p.id}" data-key="c-${p.id}"><span class="mcs-ini" style="background:${p.color}">${esc(initials(p.name))}</span><span class="mcs-ct"><b>${sMark(p.name, r)}</b><small>${plural(clientOpen(p), 'open task')}${clientOfProject(p) && clientOfProject(p).name !== p.name ? ' · ' + esc(clientOfProject(p).name) : ''}</small></span><span class="mcs-chev">›</span></button>`).join('')}</div>` : ''}
      ${r.tasks.length ? `<h2 class="mcs-gh" data-key="gh-t">Tasks <span>${r.total}</span></h2><section class="hm-card mcs-list" data-key="list">${rows}</section>`
        : ppl.length || r.projects.length ? '' : `<div class="mcs-empty" data-key="empty">${svg('M7 2.5a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9zM10.5 10.5l3 3', 1.2)}<b>No Matching Tasks</b><span>Try a client name, a person, a tag — or words like “overdue”, “urgent” or “mine”.</span></div>`}
    </div>`;
  }
  // S5: a person clicked — their tasks you can see, open first (as search orders them), then done
  function personView(u, q) {
    const ts = theirs(u).sort((a, b) => (a.done - b.done) || (a.parentId ? 1 : 0) - (b.parentId ? 1 : 0) || String(a.due || '9').localeCompare(String(b.due || '9')));
    const open = ts.filter((t) => !t.done).length, done = ts.length - open;
    return `<div class="hm mcs" data-key="mcs-p-${u.id}">
      <div data-key="back"><button type="button" class="mcs-back" data-mcs="back">‹ All results for “${esc(q)}”</button></div>
      <div class="mcs-who" data-key="who">${avatarStack([u.id], 40, 1)}<div><h1>${esc(fullName(u))}’s tasks</h1><div class="mcs-head">${esc([roleOf(u), `${open} open`, `${done} done`].filter(Boolean).join(' · '))} — the tasks you can see</div></div></div>
      ${ts.length ? `<section class="hm-card mcs-list" data-key="list">${ts.map((t) => row(t, null, '')).join('')}</section>` : `<div class="mcs-empty" data-key="empty"><b>No Tasks You Can See</b></div>`}
    </div>`;
  }

  // ---------- drawn again: only what changed (the Mac Inbox's and Client Assets' way); what comes fades in ----------
  const keyOf = (n) => (n.nodeType === 1 ? n.getAttribute('data-key') : null);
  function morph(a, b) {
    if (a.nodeType !== b.nodeType || a.nodeName !== b.nodeName) { a.replaceWith(b); return; }
    if (a.nodeType !== 1) { if (a.nodeValue !== b.nodeValue) a.nodeValue = b.nodeValue; return; }
    if (a.isEqualNode(b)) return;
    if (a.nodeName === 'IMG') { a.replaceWith(b); return; }
    [...a.attributes].forEach((x) => { if (!b.hasAttribute(x.name) && !x.name.startsWith('data-live')) a.removeAttribute(x.name); });
    [...b.attributes].forEach((x) => { if (a.getAttribute(x.name) !== x.value) a.setAttribute(x.name, x.value); });
    const byKey = new Map();
    [...a.childNodes].forEach((x) => { const k = keyOf(x); if (k) byKey.set(k, x); });
    const neu = [...b.childNodes];
    neu.forEach((nb, i) => {
      const k = keyOf(nb), cur = a.childNodes[i] || null, had = k ? byKey.get(k) : null;
      if (had) { if (had !== cur) a.insertBefore(had, cur); byKey.delete(k); morph(had, nb); }
      else if (cur && !k && !keyOf(cur)) morph(cur, nb);
      else { if (k) nb.classList.add('mcs-in'); a.insertBefore(nb, cur); }
    });
    while (a.childNodes.length > neu.length) a.lastChild.remove();
  }
  function draw(c) {
    const cur = c.firstElementChild;
    const t = document.createElement('template');
    t.innerHTML = view().trim();
    const nb = t.content.firstElementChild;
    if (cur && c.children.length === 1 && cur.classList.contains('mcs') && keyOf(nb) === keyOf(cur)) morph(cur, nb);
    else { c.innerHTML = ''; c.appendChild(nb); }
  }

  // ---------- S2: the quick list while typing (the page stays where it is) ----------
  let pop = null, popQ = '';
  function quick(q) {
    const r = taskSearch(q, { limit: 5 }), ppl = people(q).slice(0, 3), cls = r.projects.slice(0, 3);
    const items = [];
    const html = [];
    const item = (kind, id, lead, a, b) => { const i = items.length; items.push({ kind, id }); return `<button type="button" class="mcs-qi ${st.sel === i ? 'on' : ''}" data-qi="${i}" data-key="q-${kind}-${id}">${lead}<span class="mcs-qt"><span>${a}</span><small>${b}</small></span></button>`; };
    if (ppl.length) html.push('<div class="mcs-qh" data-key="qh-p">People</div>', ...ppl.map((u) => item('person', u.id, avatarStack([u.id], 26, 1), markName(fullName(u), q), esc([roleOf(u), plural(openOf(u), 'open task')].filter(Boolean).join(' · ')))));
    if (cls.length) html.push('<div class="mcs-qh" data-key="qh-c">Clients</div>', ...cls.map((p) => item('client', p.id, `<span class="mcs-ini sm" style="background:${p.color}">${esc(initials(p.name))}</span>`, sMark(p.name, r), plural(clientOpen(p), 'open task'))));
    if (r.tasks.length) html.push('<div class="mcs-qh" data-key="qh-t">Tasks</div>', ...r.tasks.map((h) => { const t = h.t, par = t.parentId && task(t.parentId); const why = searchWhy(h, r); return item('task', t.id, `<i class="hm-pc" style="background:${pColor(t)}"></i>`, `${par ? esc(par.title || 'Untitled task') + ' › ' : ''}${t.title ? sMark(t.title, r) : 'Untitled task'}`, why || `${esc(pName(t))}${t.due ? ' · due ' + esc(fmtDue(t.due)) : ''}`); }));
    // (nothing found — S2c: said in the list itself, the website's hint under it; no "See all results", nothing more to see)
    if (!items.length) html.push(`<div class="mcs-none" data-key="q-none"><b>No results for “${esc(q)}”</b><span>Try a client name, a person, a tag — or words like “overdue”, “urgent” or “mine”.</span></div>`);
    else {
      items.push({ kind: 'all' });
      html.push(`<div class="mcs-qs" data-key="q-sep"></div><button type="button" class="mcs-qi all ${st.sel === items.length - 1 ? 'on' : ''}" data-qi="${items.length - 1}" data-key="q-all">See all results for “${esc(q)}”<kbd>↩</kbd></button>`);
    }
    st.items = items;
    return `<div class="mcs-pop" data-key="pop">${html.join('')}</div>`;
  }
  // the list hangs from the field (S2b): right under it, its right edge on the field's (the field grows to the left, to the
  // list's width, 400 — home.css)
  const field = () => document.querySelector('#topbar .search');
  function place() {
    const f = field();
    if (!pop || !f) return;
    const r = f.getBoundingClientRect();
    // (to the exact pixel, halves too: no seam between the field and the list)
    pop.style.top = `${r.bottom}px`;
    pop.style.right = `${innerWidth - r.right}px`;   // (its right edge: the field grows to the left)
  }
  function showQuick(q) {
    popQ = q;
    const f = field(); if (f) f.classList.add('mcs-open');
    const t = document.createElement('template');
    t.innerHTML = quick(q).trim();
    const nb = t.content.firstElementChild;
    if (pop && pop.isConnected && !pop.classList.contains('out')) { morph(pop, nb); pop.classList.add('shown'); }   // (its fade-in kept)
    else { if (pop) pop.remove(); pop = nb; document.body.appendChild(pop); place(); requestAnimationFrame(() => pop && pop.classList.add('shown')); }
    place();
  }
  function closeQuick() {
    if (!pop) return;
    const p = pop; pop = null; st.sel = -1; st.items = [];
    const f = field(); if (f) f.classList.remove('mcs-open');
    p.classList.add('out'); p.classList.remove('shown');
    setTimeout(() => p.remove(), 160);
  }
  // the top bar's field typed in (app.js): true — handled here (the quick list); false — the page's own way (already on Search)
  function typed(v) {
    if (!on()) return false;
    if (ui.search) { st.person = null; return false; }   // (on the Search page: it follows what's typed, as the website)
    st.sel = -1;
    if (!v.trim()) { closeQuick(); return true; }
    showQuick(v.trim());
    return true;
  }
  function seeAll(q) {
    closeQuick();
    st.person = null;
    if (!ui.search) ui.prevView = { view: ui.view, projectId: ui.projectId };
    ui.search = q;
    renderSidebar(); renderTitle(); renderContent();
  }
  function pick(i) {
    const it = st.items[i];
    if (!it) return;
    const f = document.getElementById('search');
    if (it.kind === 'all') return seeAll(popQ);
    if (it.kind === 'person') { seeAll(popQ); st.person = it.id; renderContent(); return; }
    closeQuick();
    if (f) { f.value = ''; f.blur(); }
    if (it.kind === 'client') go('project', it.id);
    else if (it.kind === 'task') openTask(it.id);
  }
  // keys in the field while the list is open: ↑ ↓ move, ↩ opens the one picked (nothing picked: See all results), Esc closes
  document.addEventListener('keydown', (e) => {
    if (!pop || !e.target || e.target.id !== 'search') return;
    const n = st.items.length;
    if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && n) {
      e.preventDefault();
      st.sel = e.key === 'ArrowDown' ? (st.sel + 1) % n : (st.sel <= 0 ? n - 1 : st.sel - 1);
      showQuick(popQ);
      const on1 = pop && pop.querySelector('.mcs-qi.on'); if (on1) on1.scrollIntoView({ block: 'nearest' });
    } else if (e.key === 'Enter') {
      e.preventDefault(); e.stopImmediatePropagation();
      if (n) pick(st.sel >= 0 ? st.sel : n - 1);
    }
  }, true);
  // a click in the list: the field keeps its focus; a click anywhere else closes it
  document.addEventListener('mousedown', (e) => {
    if (!pop) return;
    if (pop.contains(e.target)) { e.preventDefault(); return; }
    if (!e.target.closest('#topbar .search')) closeQuick();
  }, true);
  document.addEventListener('click', (e) => {
    const q = pop && e.target.closest('.mcs-pop [data-qi]');
    if (q) { e.preventDefault(); e.stopImmediatePropagation(); pick(+q.dataset.qi); return; }
    const m = e.target.closest('[data-mcs]');
    if (!m || !on()) return;
    e.preventDefault(); e.stopImmediatePropagation();
    if (m.dataset.mcs === 'person') { st.person = m.dataset.id; renderContent(); document.getElementById('content').scrollTop = 0; }
    else if (m.dataset.mcs === 'back') { st.person = null; renderContent(); }
  }, true);
  addEventListener('resize', place);
  // the field's own ✕ (Apple's clear button) while something is typed — in place of ⌘K (shown by home.css: the field not empty)
  function clearBtn() {
    const f = field(), i = document.getElementById('search');
    if (!f || !i || !on()) return;
    if (!f.querySelector('.mcs-x')) f.insertAdjacentHTML('beforeend', '<button type="button" class="mcs-x" title="Clear" aria-label="Clear the search"><svg viewBox="0 0 10 10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M2 2l6 6M8 2l-6 6"/></svg></button>');
  }
  document.addEventListener('focusin', (e) => { if (e.target && e.target.id === 'search') clearBtn(); });
  document.addEventListener('mousedown', (e) => {
    const x = e.target.closest && e.target.closest('.mcs-x');
    if (!x) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const i = document.getElementById('search');
    i.value = ''; i.dispatchEvent(new Event('input', { bubbles: true })); i.focus();
  }, true);
  // the field left (Tab, another window): the list goes
  document.addEventListener('focusout', (e) => { if (e.target && e.target.id === 'search') setTimeout(() => { if (document.activeElement && document.activeElement.id !== 'search') closeQuick(); }, 0); });
  // a task right-clicked on the Search page: the iPhone's choices (app.js taskContextMenu) — on Home, Home's own listener does it
  document.addEventListener('contextmenu', (e) => {
    if (!on() || typeof ui === 'undefined' || !ui.search || ui.view === 'home') return;
    const el = e.target.closest && e.target.closest('.mcs [data-task]');
    if (el && typeof taskContextMenu === 'function') taskContextMenu(e, el.dataset.task);
  });
  // leaving search (cleared, Esc, another page): the person picked is forgotten
  const reset = () => { st.person = null; closeQuick(); };

  return { on, draw, typed, reset };
})();
