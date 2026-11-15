/* The Mac app's Inbox — Mail's way (canvas "E11 Console for Mac", boards I1 B – I17, approved by Haris 2026-11-15 21:40:
   "Follow the other pages on colors and button styles"). Only in the Mac app (html.mac-chrome); browsers and the iPhone keep
   the website's Inbox (app.js viewInbox). Everything the website's Inbox does, nothing missed: Primary · All · Cleared, the
   filter, Clear All, one row per task (its newest update, how many), Today · Last 7 days · Earlier this month · a month, the
   unread dot, Clear / Mark Unread, the website's own wording. Mail's way on top of it: the list on the left, the row picked
   read in full on the right — with only what the website opens for it (Open Task, Open Plan, Review decision, Open Folder,
   Open Claims, the greeting); picking a row reads it (as Mail); ↑ ↓ move, Esc picks none; Clear on the one being read picks
   the next. Added by Haris (21:26–21:37): a comment or mention answered right there — on a main comment the reply starts a
   thread under it, on one already in a thread it goes into that thread — or reacted to with the website's six reactions
   from the ☺︎ under it (Y); either way the row keeps "↳ You replied: …" / "↳ You reacted 👍" for good (kept on the update
   itself: n.mine). */
const MacInbox = (() => {
  const on = () => typeof Host !== 'undefined' && Host.isMacApp && document.documentElement.classList.contains('mac-chrome');
  let pick;                 // the picked row's key; undefined = not chosen yet (the first is picked), null = none (Esc)
  let order = [];           // the rows' keys as last drawn (to pick the next after Clear)
  let shown = null;         // the key the right side showed last (it crossfades only when this changes)
  let tabSeen = null;       // Primary keeps the rows read while you're on it (as Mail), until the tab changes
  const stay = new Set();
  const COMMENTS = new Set(['comment', 'mention']);

  const time = (iso) => ibTime(iso);
  const clock = (iso) => { const d = new Date(iso); const today = new Date().toDateString() === d.toDateString();
    return (today ? 'Today ' : fmtDay(d.toISOString().slice(0, 10)) + ' ') + d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }); };
  const nameOf = (id) => fullName(userById(id));
  const mentionMark = (s) => s.replace(/@([A-Z][\w.'-]*(?: [A-Z][\w.'-]*){0,2})/g, '<span class="mention">@$1</span>');

  // the rows, exactly as the website's Inbox makes them (one per task: its newest update, and how many)
  function rows() {
    const tab = ['all', 'cleared'].includes(ui.inboxTab) ? ui.inboxTab : 'primary';
    if (tabSeen !== tab) { stay.clear(); tabSeen = tab; }
    const f = ui.inboxFilter || 'all';
    const mine = myNotifs().filter((n) => ibMatch(n, f));
    const byKey = new Map();
    mine.slice().sort((a, b) => b.at.localeCompare(a.at)).forEach((n) => {
      const k = notifKey(n);
      if (!byKey.has(k)) byKey.set(k, { key: k, latest: n, items: [] });
      byKey.get(k).items.push(n);
    });
    const all = [...byKey.values()];
    const list = tab === 'primary' ? all.filter((g) => g.items.some((x) => !x.read) || stay.has(g.key))
      : tab === 'cleared' ? all.filter((g) => g.items.every((x) => x.read)) : all;
    return { tab, f, list: list.slice(0, 300) };
  }

  function view() {
    // (a fresh visit to the Inbox: the newest picked again, Primary's kept rows let go)
    if (!document.querySelector('#content > .mib')) { pick = undefined; shown = null; stay.clear(); }
    const { tab, f, list } = rows();
    const keys = list.map((g) => g.key);
    // the one picked: the first as the Inbox opens; after Clear, the next in its place; Esc: none
    if (pick === undefined) pick = keys[0] || null;
    else if (pick && !keys.includes(pick)) { const i = order.indexOf(pick); pick = keys[Math.min(Math.max(i, 0), keys.length - 1)] || null; if (pick) markRead(list.find((g) => g.key === pick), false); }
    order = keys;
    const unreadN = myNotifs().filter((n) => !n.read).length;
    const groups = [];
    list.forEach((g) => { const name = ibGroup(g.latest.at); let grp = groups.find((x) => x.name === name); if (!grp) { grp = { name, rows: [] }; groups.push(grp); } grp.rows.push(g); });
    const seg = [['primary', 'Primary', unreadN], ['all', 'All', 0], ['cleared', 'Cleared', 0]]
      .map(([k, l, n]) => `<button type="button" class="mib-tab ${tab === k ? 'on' : ''}" data-action="inbox-tab" data-tab="${k}">${l}${n ? ` <i>${n}</i>` : ''}</button>`).join('');
    const g = list.find((x) => x.key === pick) || null;
    const fresh = shown !== (g ? g.key : null);
    shown = g ? g.key : null;
    return `<div class="mib">
      <header class="mib-head"><div><div class="mib-line">${unreadN ? `${unreadN} unread` : 'All caught up'}</div><h1>Inbox</h1></div>
        <div class="mib-tools"><span class="mib-seg">${seg}</span>
          <button type="button" class="mib-btn" data-action="ib-filter">${esc(f === 'all' ? 'All updates' : IB_FILTERS[f])}<span class="mib-chev">⌄</span></button>
          ${unreadN ? `<button type="button" class="mib-btn" data-action="mark-all-read">✓ Clear All</button>` : ''}</div></header>
      <div class="mib-body">
        <div class="mib-list">${groups.map((x) => `<div class="mib-group">${x.name}</div><div class="mib-card">${x.rows.map(rowHTML).join('')}</div>`).join('')
          || `<div class="mib-none"><b>${tab === 'primary' ? 'Inbox zero 🎉' : 'Nothing here yet'}</b><span>${tab === 'primary' ? 'You’re all caught up. New updates on your tasks and @mentions land here.' : 'Updates on tasks you’re assigned to or created will appear here.'}</span></div>`}</div>
        <div class="mib-pane ${fresh ? 'fresh' : ''}">${g ? paneHTML(g) : emptyHTML()}</div>
      </div></div>`;
  }

  // a row: the website's own (its title, who did what, the time, how many), two lines, the unread dot; your answer under it
  function rowHTML(g) {
    const n = g.latest, t = task(n.taskId), items = g.items;
    const unread = items.some((x) => !x.read);
    const shownN = ibTarget(items);
    const lead = ['comment', 'mention', 'review-amend', 'review-ok', 'review', 'claim', 'claim-ok', 'claim-paid', 'claim-hand', 'asset', 'plan', 'plan-ok', 'plan-changes', 'plan-tasks', 'plan-client', 'birthday', 'signin'].includes(shownN.kind)
      ? avatarHTML(shownN.from, 26) : `<span class="mib-kic">${icon(NOTIF_ICON[shownN.kind] || 'bell')}</span>`;
    const mineN = items.find((x) => x.mine);
    const mine = mineN ? (mineN.mine.react ? `<b>You reacted</b> ${esc(mineN.mine.react)}` : `<b>You replied:</b> ${esc(trunc(mineN.mine.reply || '', 120))}`) : '';
    return `<div class="mib-row ${unread ? 'unread' : ''} ${g.key === pick ? 'sel' : ''}" data-mib="pick" data-k="${esc(g.key)}">
      <span class="mib-dot"></span><span class="mib-lead">${lead}</span>
      <span class="mib-t"><span class="mib-tt">${titleIcon(n, t)}<span>${esc(titleOf(n, t))}</span></span>
        <span class="mib-msg">${notifMsg(shownN, t)}</span>${mine ? `<span class="mib-mine">↳ ${mine}</span>` : ''}</span>
      <span class="mib-r"><span class="mib-time">${time(n.at)}</span>${items.length > 1 ? `<i class="mib-n">${items.length}</i>` : ''}</span></div>`;
  }
  function titleOf(n, t) {
    if (n.kind === 'sched-cancel') return `Scheduled ${n.text && /scheduled reply/.test(n.text) ? 'reply' : 'comment'}`;
    if (n.kind === 'signin') return 'Sign-in';
    if (n.kind === 'birthday') return 'Birthday';
    if (n.kind === 'daily') return 'Morning round-up';
    if (/^plan/.test(n.kind)) return planTitle(n);
    if (n.kind === 'asset') return assetTitle(n);
    if (t) return t.title || 'Untitled task';
    return /^claim/.test(n.kind) ? 'Expense claims' : 'Deleted task';
  }
  function titleIcon(n, t) {
    const k = n.kind;
    const ic = k === 'sched-cancel' ? 'clock' : k === 'signin' ? 'lock' : k === 'birthday' ? 'gift' : k === 'daily' ? 'sun' : /^plan/.test(k) ? 'cal' : k === 'asset' ? 'assets' : (!t && /^claim/.test(k)) ? 'coin' : null;
    if (ic) return `<span class="st-ic ib-coin">${icon(ic)}</span>`;
    return t ? statusIcon(t) : `<span class="st-ic">${statusIconSVG('#87909e', 'todo', 0)}</span>`;
  }

  function emptyHTML() {
    return `<div class="mib-empty">${icon('inbox')}<b>Nothing Selected</b><span>Pick an update on the left to read it here.</span></div>`;
  }

  // ---------- the right side: what the website would open for the row, with its own buttons ----------
  const btn = (label, attrs, primary) => `<button type="button" class="mib-btn ${primary ? 'primary' : ''}" ${attrs}>${label}</button>`;
  function head(ic, title, line, buttons) {
    return `<div class="mib-ph"><div class="mib-ph-t"><div class="mib-ph-h">${ic}<h2>${esc(title)}</h2></div><div class="mib-ph-l">${line}</div></div><div class="mib-ph-b">${buttons}</div></div>`;
  }
  const unreadBtn = (g) => btn('Mark Unread', `data-action="notif-clear" data-id="${esc(g.key)}" data-read="1"`);
  const openBtn = (g, label) => btn(label, `data-action="open-notif" data-id="${esc(ibTarget(g.items).id)}"`, true);

  function paneHTML(g) {
    const n = ibTarget(g.items), t = task(n.taskId), k = n.kind;
    if (k === 'birthday') return `<div class="mib-greet">${avatarHTML(n.from, 88)}<span>Today is</span><b>${esc(firstName(n.from))}’s birthday</b><span>Wish them a happy birthday</span></div>`;
    if (k === 'daily') return dailyHTML(g);
    if (k === 'signin') return `${head(`<span class="mib-hic">${icon('lock')}</span>`, 'Sign-in code used', esc(clock(n.at)), '')}<div class="mib-ups">${upd(n, notifMsg(n, null))}</div>`;
    if (n.planId) return planHTML(g, n);
    if (k === 'asset') return assetHTML(g, n);
    if (/^claim/.test(k)) return claimHTML(g, n);
    if (k === 'sched-cancel') return schedHTML(g, n);
    return taskHTML(g, t);
  }
  // one update: who, when, what — a comment in full, in its thread, its files and reactions
  function upd(n, body, extra = '', faded = false) {
    return `<div class="mib-u ${faded ? 'faded' : ''}">${avatarHTML(n.from, 30)}<div class="mib-u-b"><div class="mib-u-h"><b>${esc(nameOf(n.from))}</b><span>${esc(clock(n.at))}</span></div><div class="mib-u-t">${body}</div>${extra}</div></div>`;
  }
  function bodyOf(n, t) {
    const who = `<b>${esc(fullName(userById(n.from)))}</b> `;
    const m = notifMsg(n, t);
    return m.startsWith(who) ? m.slice(who.length) : m;
  }
  function taskHTML(g, t) {
    const items = g.items.slice().sort((a, b) => a.at.localeCompare(b.at));
    const p = t ? proj(t.projectId) : null;
    const st = t ? statusList(t).find((x) => x.name === t.status) : null;
    const line = t ? `${p ? `<i class="mib-cdot" style="background:${esc(p.color || '#87909e')}"></i>${esc(p.name)}` : ''}${t.due ? ` · due ${esc(fmtDay(t.due))}` : ''}${st ? ` · <span class="ib-chip" style="background:${st.color};color:${textOn(st.color)}">${esc(st.name)}</span>` : ''}` : 'This task is no longer here';
    // the CD's review request: the website's own "Review decision" and the request's files
    const n0 = ibTarget(g.items);
    let review = '';
    if (t && (n0.kind === 'review') && isCD()) {
      const rs = (t.reviews || []).filter((r) => r.by === n0.from && r.state !== 'withdrawn');
      const r = rs.filter((x) => x.at <= n0.at).pop() || rs[rs.length - 1];
      if (r) {
        const files = (t.attachments || []).filter((a) => a.reviewId === r.id);
        review = `<div class="mib-review">${r.message ? `<p>“${esc(r.message)}”</p>` : ''}<div class="mib-files">${files.map((a) => `<button type="button" class="mib-file" data-action="rr-file" data-id="${esc(a.id)}" data-task-id="${esc(t.id)}">${esc(a.name)}</button>`).join('')}</div>
          ${r.state === 'pending' ? `<div class="mib-review-b">${btn('Review decision', `data-action="rr-decide" data-id="${esc(r.id)}"`, true)}</div>` : ''}</div>`;
      }
    }
    let lastComment = null;
    const ups = items.map((n, i) => {
      const c = t && n.commentId && COMMENTS.has(n.kind) ? (t.comments || []).find((x) => x.id === n.commentId) : null;
      if (c) lastComment = c;
      const faded = i < items.length - 1;
      if (!c) return upd(n, bodyOf(n, t), '', faded);
      const parent = c.parentId ? (t.comments || []).find((x) => x.id === c.parentId) : null;
      const text = mentionMark(esc(fullComment(n, t) || n.snippet || ''));
      const files = (c.attachments || []).length ? `<div class="mib-files">${c.attachments.map((a) => `<button type="button" class="mib-file" data-mib="file" data-tid="${esc(t.id)}" data-cid="${esc(c.id)}" data-id="${esc(a.id)}">${esc(a.name)}</button>`).join('')}</div>` : '';
      const reacts = Object.entries(c.reactions || {}).filter(([, v]) => v);
      const rx = `<div class="mib-rx">${reacts.map(([e]) => `<button type="button" class="mib-pill ${mineReact(g) === e ? 'mine' : ''}" data-mib="react" data-tid="${esc(t.id)}" data-cid="${esc(c.id)}" data-e="${esc(e)}">${e}</button>`).join('')}<button type="button" class="mib-smile" data-mib="react-menu" data-tid="${esc(t.id)}" data-cid="${esc(c.id)}" title="React">☺︎</button></div>`;
      const box = upd({ ...n, from: c.authorId, at: c.at }, text, files + rx, faded);
      return parent ? `<div class="mib-thread"><div class="mib-thread-l">In ${esc(nameOf(parent.authorId))}’s thread</div>${box}</div>` : box;
    }).join('');
    const minen = g.items.find((x) => x.mine && x.mine.reply);
    const yours = minen ? `<div class="mib-yours">${upd({ from: currentUserId, at: minen.mine.at }, esc(minen.mine.reply))}</div>` : '';
    let reply = '';
    if (lastComment) {
      const root = lastComment.parentId || lastComment.id;
      const rootC = (t.comments || []).find((x) => x.id === root);
      const to = firstName(lastComment.authorId);
      const where = lastComment.parentId ? `Replies in ${esc(nameOf(rootC ? rootC.authorId : lastComment.authorId))}’s thread` : `Starts a thread under ${esc(to)}’s comment`;
      reply = `<div class="mib-reply"><div class="mib-where">↳ ${where}</div><div class="mib-box"><textarea rows="1" class="mib-in" placeholder="Reply to ${esc(to)}…" data-tid="${esc(t.id)}" data-root="${esc(root)}"></textarea>
        <button type="button" class="mib-send" data-mib="send" title="Send" disabled><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M5.5 11.5 12 5l6.5 6.5"/></svg></button></div></div>`;
    }
    return head(t ? statusIcon(t, 18) : '', t ? (t.title || 'Untitled task') : 'Deleted task', line, unreadBtn(g) + openBtn(g, 'Open Task'))
      + `<div class="mib-cap">${items.length} update${items.length === 1 ? '' : 's'} · newest last</div><div class="mib-ups">${review}${ups}${yours}</div>${reply}`;
  }
  const mineReact = (g) => { const x = g.items.find((n) => n.mine && n.mine.react); return x ? x.mine.react : null; };

  function planHTML(g, n) {
    const pl = Plans.planById(n.planId), p = pl ? proj(pl.projectId) : null;
    const posts = pl ? (pl.posts || []).slice().sort((a, b) => String(a.day).localeCompare(String(b.day))) : [];
    const body = pl ? `<div class="mib-cap">${posts.length} post${posts.length === 1 ? '' : 's'} · by day</div><div class="mib-posts">${posts.slice(0, 40).map((x) => `<div class="mib-post"><b>${esc(String(x.day || '').slice(8, 10) || '–')}</b><span>${esc(x.title || 'Untitled post')}</span></div>`).join('')}</div>`
      : '<p class="mib-dim">Content skeleton not found</p>';
    return head(`<span class="mib-hic">${icon('cal')}</span>`, planTitle(n), p ? `<i class="mib-cdot" style="background:${esc(p.color || '#87909e')}"></i>${esc(p.name)}` : '', unreadBtn(g) + openBtn(g, 'Open Plan'))
      + `<div class="mib-ups">${upd(n, bodyOf(n, null))}</div>${body}`;
  }
  function assetHTML(g, n) {
    const c = clientById(n.clientId), f = c && (c.folders || []).find((x) => x.id === n.folderId);
    const names = String(n.snippet || '').split(', ').filter(Boolean);
    return head(`<span class="mib-hic">${icon('assets')}</span>`, f ? f.name : assetTitle(n), c ? esc(c.name + (f ? ' › ' + folderPath(c, f) : '')) : '', unreadBtn(g) + openBtn(g, 'Open Folder'))
      + `<div class="mib-ups">${g.items.slice().sort((a, b) => a.at.localeCompare(b.at)).map((x) => upd(x, bodyOf(x, null))).join('')}</div>`
      + (names.length ? `<div class="mib-files">${names.map((x) => `<span class="mib-file static">${esc(x)}</span>`).join('')}</div>` : '');
  }
  function claimHTML(g, n) {
    const c = n.claimId && typeof Claims !== 'undefined' ? Claims.byId(n.claimId) : null;
    const items = c ? (c.groups || []).flatMap((gr) => (gr.items || []).map((i) => ({ d: gr.date, x: i.desc || gr.title || '', a: i.amount }))) : [];
    const amt = (v) => '⃃' + (Number(v) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    return head(`<span class="mib-hic">${icon('coin')}</span>`, 'Expense claims', c ? Claims.pill(c) : '', unreadBtn(g) + openBtn(g, 'Open Claims'))
      + `<div class="mib-ups">${g.items.slice().sort((a, b) => a.at.localeCompare(b.at)).map((x) => upd(x, bodyOf(x, null))).join('')}</div>`
      + (items.length ? `<div class="mib-claim">${items.map((i) => `<div><span>${esc(i.d ? fmtDay(i.d) : '')}</span><span>${esc(i.x)}</span><b>${amt(i.a)}</b></div>`).join('')}<div class="tot"><span></span><span>Total</span><b>${amt(Claims.totalOf(c))}</b></div></div>` : '');
  }
  function schedHTML(g, n) {
    return head(`<span class="mib-hic">${icon('clock')}</span>`, titleOf(n, null), esc(clock(n.at)), unreadBtn(g) + openBtn(g, 'Open Task'))
      + `<div class="mib-ups">${upd(n, String(n.text || '').replace(/<(?!\/?b>)/g, '&lt;'))}</div>${n.snippet ? `<div class="mib-quote">${esc(n.snippet)}</div>` : ''}`;
  }
  function dailyHTML(g) {
    const n = g.items[0];
    if (typeof Daily === 'undefined' || !Daily.wants()) return `${head(`<span class="mib-hic">${icon('sun')}</span>`, n.title || 'Good morning', '', unreadBtn(g))}<div class="mib-ups">${upd(n, String(n.text || '').replace(/<(?!\/?b>)/g, '&lt;'))}</div>`;
    const S = Daily.sections();
    const cnt = (s) => (s.sched ? s.sched.length : s.tasks.length);
    const first = S.find((s) => cnt(s));
    const when = new Date().toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long' });
    return head(`<span class="mib-hic sun">${icon('sun')}</span>`, `Good morning, ${firstName(currentUserId)}`, esc(when), unreadBtn(g))
      + `<div class="mib-daily">${S.map((s) => `<div class="mib-dsec ${cnt(s) ? '' : 'none'}"><div class="mib-dh">${icon(s.ic)}<span>${esc(s.l)}</span><b>${cnt(s)}</b></div>
        ${s === first && !s.sched ? s.tasks.slice(0, 6).map((t) => `<button type="button" class="mib-drow" data-mib="task" data-id="${esc(t.id)}"><span>${esc(t.title || 'Untitled task')}</span><span>${esc((proj(t.projectId) || {}).name || '')}${t.due ? ` · ${esc(fmtDay(t.due))}` : ''}</span></button>`).join('') : ''}</div>`).join('')}</div>
        <div class="mib-dim mib-asof">Up to date as of ${new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}</div>`;
  }

  // ---------- picking, replying, reacting ----------
  function markRead(g, draw = true) {
    if (!g) return;
    const n = ibTarget(g.items);
    let changed = false;
    // what the website marks read when it's opened: a task's updates, a plan's, a folder's, a claim's, or that one
    myNotifs().forEach((x) => { if (notifKey(x) === g.key && !x.read) { x.read = true; changed = true; } });
    if (n && !changed && !n.read) { n.read = true; changed = true; }
    if (changed) { stay.add(g.key); persist(); renderSidebar(); if (draw) renderContent(); }
  }
  function choose(k) {
    pick = k;
    const g = rows().list.find((x) => x.key === k);
    if (g && g.items.some((x) => !x.read)) markRead(g); else renderContent();
  }
  function send(btnEl) {
    const box = btnEl.closest('.mib-box'), ta = box && box.querySelector('.mib-in');
    const text = ta ? ta.value.trim() : '';
    if (!text) return;
    const t = task(ta.dataset.tid);
    if (!t) return;
    const html = esc(text).replace(/\n/g, '<br>');
    postComment(t, ta.dataset.root, text, html, []);
    t.updatedAt = nowISO();
    const g = rows().list.find((x) => x.key === pick);
    if (g) g.items.forEach((x) => { x.mine = { reply: text, at: nowISO() }; });
    commit();
  }
  function react(tid, cid, e) {
    const t = task(tid), c = t && (t.comments || []).find((x) => x.id === cid);
    if (!c) return;
    c.reactions = c.reactions || {};
    c.reactions[e] = c.reactions[e] ? 0 : 1;
    if (!c.reactions[e]) delete c.reactions[e];
    const g = rows().list.find((x) => x.key === pick);
    if (g) g.items.forEach((x) => { if (c.reactions[e]) x.mine = { ...(x.mine && x.mine.reply ? x.mine : {}), react: e, at: nowISO() }; else if (x.mine && x.mine.react === e) { const { react: _r, ...rest } = x.mine; x.mine = rest.reply ? rest : undefined; if (!x.mine) delete x.mine; } });
    commit();
  }
  // the six reactions popping up just above the ☺︎ (Y)
  function reactMenuAt(el) {
    document.querySelectorAll('.mib-pop').forEach((x) => x.remove());
    const pop = document.createElement('div');
    pop.className = 'mib-pop';
    pop.innerHTML = REACTIONS.map((e) => `<button type="button" data-e="${e}">${e}</button>`).join('');
    document.body.appendChild(pop);
    const r = el.getBoundingClientRect();
    pop.style.left = Math.max(8, r.left - 8) + 'px';
    pop.style.top = (r.top - pop.offsetHeight - 6) + 'px';
    const close = (ev) => { if (ev && pop.contains(ev.target)) return; pop.remove(); document.removeEventListener('mousedown', close, true); };
    setTimeout(() => document.addEventListener('mousedown', close, true), 0);
    pop.addEventListener('click', (ev) => { const b = ev.target.closest('button'); if (!b) return; close(); react(el.dataset.tid, el.dataset.cid, b.dataset.e); });
  }

  document.addEventListener('click', (e) => {
    if (!on() || ui.view !== 'inbox') return;
    const el = e.target.closest('[data-mib]');
    if (!el) return;
    const a = el.dataset.mib;
    if (a === 'pick') { if (e.target.closest('button, a')) return; choose(el.dataset.k); }
    else if (a === 'send') send(el);
    else if (a === 'react') react(el.dataset.tid, el.dataset.cid, el.dataset.e);
    else if (a === 'react-menu') reactMenuAt(el);
    else if (a === 'task') { if (typeof Daily !== 'undefined') Daily.close && Daily.close(); openTask(el.dataset.id); }
    else if (a === 'file') { const t = task(el.dataset.tid), c = t && (t.comments || []).find((x) => x.id === el.dataset.cid); const f = c && (c.attachments || []).find((x) => x.id === el.dataset.id); if (f) previewFile(f, c.attachments); }
  });
  document.addEventListener('input', (e) => {
    const ta = e.target.closest && e.target.closest('.mib-in');
    if (!ta) return;
    ta.style.height = 'auto'; ta.style.height = Math.min(ta.scrollHeight, 140) + 'px';
    const b = ta.parentElement.querySelector('.mib-send'); if (b) b.disabled = !ta.value.trim();
  });
  document.addEventListener('keydown', (e) => {
    if (!on() || ui.view !== 'inbox' || ui.taskId) return;
    const ta = e.target.closest && e.target.closest('.mib-in');
    if (ta) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(ta.parentElement.querySelector('.mib-send')); } return; }
    if (e.target.closest && e.target.closest('input, textarea, [contenteditable="true"], .dialog, .menu')) return;
    if (document.getElementById('overlay-root') && document.getElementById('overlay-root').children.length) return;
    if (e.key === 'Escape') { if (pick) { pick = null; renderContent(); e.preventDefault(); } return; }
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
    e.preventDefault();
    const i = order.indexOf(pick);
    const j = e.key === 'ArrowDown' ? Math.min(order.length - 1, i + 1) : Math.max(0, i < 0 ? 0 : i - 1);
    if (order[j] && order[j] !== pick) { choose(order[j]); const r = document.querySelector('.mib-row.sel'); if (r) r.scrollIntoView({ block: 'nearest' }); }
  });

  return { on, view, reset: () => { pick = undefined; shown = null; } };
})();
