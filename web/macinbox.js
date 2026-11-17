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
  // (an @ followed by a real person's name only — "@Areej Masri Print" marks Areej Masri, not the word after)
  const mentionMark = (s) => {
    const names = [...new Set((db.users || []).flatMap((u) => u.name ? [u.name, u.name.split(' ')[0]] : []).filter((x) => x && /^[A-Z]/i.test(x)))].sort((a, b) => b.length - a.length).map((n) => esc(n).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    return names.length ? s.replace(new RegExp(`@(${names.join('|')})(?![\\w])`, 'gi'), '<span class="mention">@$1</span>') : s;
  };
  // (the shared line marks any capitalised words after @ — marked again here with the real names)
  const msgOf = (n, t) => mentionMark(String(notifMsg(n, t)).replace(/<span class="mention">(.*?)<\/span>/g, '$1'));

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
    wasFresh = fresh;
    shown = g ? g.key : null;
    return `<div class="mib">
      <header class="mib-head"><div><div class="mib-line">${unreadN ? `${unreadN} unread` : 'All caught up'}</div><h1>Inbox</h1></div>
        <div class="mib-tools"><span class="mib-seg">${seg}</span>
          <button type="button" class="mib-btn" data-action="ib-filter">${esc(f === 'all' ? 'All updates' : IB_FILTERS[f])}<span class="mib-chev">${icon('chev')}</span></button>
          ${unreadN ? `<button type="button" class="mib-btn" data-action="mark-all-read">✓ Clear All</button>` : ''}</div></header>
      <div class="mib-body">
        <div class="mib-list">${groups.map((x) => `<div class="mib-group" data-key="g:${x.name}">${x.name}</div><div class="mib-card" data-key="c:${x.name}">${x.rows.map(rowHTML).join('')}</div>`).join('')
          || `<div class="mib-none"><b>${tab === 'primary' ? 'Inbox zero 🎉' : 'Nothing here yet'}</b><span>${tab === 'primary' ? 'You’re all caught up. New updates on your tasks and @mentions land here.' : 'Updates on tasks you’re assigned to or created will appear here.'}</span></div>`}</div>
        <div class="mib-pane ${fresh ? 'fresh' : ''}">${paneParts(g ? paneHTML(g) : emptyHTML())}</div>
      </div></div>`;
  }

  // (the pane: what it says scrolls in its own box; the reply box or a decision's buttons sit under that box, outside it —
  //  so the scroll's spring at either end never moves them: Haris 2026-11-17 "dont have the comment stuck box spring")
  //  The header too (the title, its line and buttons — and a task's "N updates" line) stays above that box, never sprung.
  function paneParts(html) {
    let top = '';
    const b = html.indexOf('<!--body-->'), h = html.indexOf('<!--head-->');
    const cut = b >= 0 ? b + 11 : h >= 0 ? h + 11 : 0;
    if (cut) { top = `<div class="mib-top">${html.slice(0, cut).replace(/<!--(head|body)-->/g, '')}</div>`; html = html.slice(cut).replace(/<!--(head|body)-->/g, ''); }
    const at = html.indexOf('<!--foot-->');
    return top + (at < 0 ? `<div class="mib-scroll">${html}</div>` : `<div class="mib-scroll">${html.slice(0, at)}</div>${html.slice(at + 11)}`);
  }
  // a row: the website's own (its title, who did what, the time, how many), two lines, the unread dot; your answer under it
  function rowHTML(g) {
    const n = g.latest, t = task(n.taskId), items = g.items;
    const unread = items.some((x) => !x.read);
    const shownN = ibTarget(items);
    const lead = ['comment', 'mention', 'review-amend', 'review-ok', 'review', 'claim', 'claim-ok', 'claim-paid', 'claim-hand', 'asset', 'plan', 'plan-ok', 'plan-changes', 'plan-tasks', 'plan-client', 'birthday', 'signin'].includes(shownN.kind)
      ? avatarHTML(shownN.from, 26) : `<span class="mib-kic">${icon(NOTIF_ICON[shownN.kind] || 'bell')}</span>`;
    const mineN = items.find((x) => x.mine);
    const myLast = mineN && !mineN.mine.react ? myReplies(g, t).pop() : null;   // (only your latest reply, as it now reads)
    const mine = mineN ? (mineN.mine.react ? `<b>You reacted</b> ${esc(mineN.mine.react)}` : myLast ? `<b>You replied:</b> ${esc(trunc(myLast.c ? myLast.c.text || '' : myLast.text || '', 120))}` : '') : '';
    return `<div class="mib-row ${unread ? 'unread' : ''} ${g.key === pick ? 'sel' : ''}" data-mib="pick" data-k="${esc(g.key)}" data-key="r:${esc(g.key)}">
      <span class="mib-dot"></span><span class="mib-lead">${lead}</span>
      <span class="mib-t"><span class="mib-tt">${titleIcon(n, t)}<span>${esc(titleOf(n, t))}</span></span>
        <span class="mib-msg">${msgOf(shownN, t)}</span>${mine ? `<span class="mib-mine">↳ ${mine}</span>` : ''}</span>
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
  // (each kind exactly as its board — I1 B, I5–I17; Haris 2026-11-17 12:37: "not like the mockups")
  const btn = (label, attrs, primary) => `<button type="button" class="mib-btn ${primary ? 'primary' : ''}" ${attrs}>${label}</button>`;
  function head(ic, title, line, buttons) {
    return `<div class="mib-ph"><div class="mib-ph-t"><div class="mib-ph-h">${ic}<h2>${esc(title)}</h2></div>${line ? `<div class="mib-ph-l">${line}</div>` : ''}</div>${buttons ? `<div class="mib-ph-b">${buttons}</div>` : ''}</div><!--head-->`;
  }
  const hic = (name, tone) => `<span class="mib-hic ${tone || ''}">${icon(name)}</span>`;
  const cap = (s) => `<div class="mib-cap">${s}</div>`;
  const soft = (label, color) => `<span class="mib-sp" style="--c:${color}">${esc(label)}</span>`;
  const solid = (label, bg) => `<span class="mib-solid" style="background:${bg};color:${textOn(bg)}">${esc(label)}</span>`;
  const foot = (buttons) => `<!--foot--><div class="mib-foot"><span></span>${buttons}</div>`;
  const cdot = (p) => (p ? `<i class="mib-cdot" style="background:${esc(p.color || '#87909e')}"></i>${esc(p.name)}` : '');
  const unreadBtn = (g) => btn('Mark Unread', `data-action="notif-clear" data-id="${esc(g.key)}" data-read="1"`);
  const openBtn = (g, label, primary = true) => btn(label, `data-action="open-notif" data-id="${esc(ibTarget(g.items).id)}"`, primary);

  // files as the boards draw them: a picture (a photo its own, a video its cover with ▶, a PDF a page), its name, its size
  let tileSets = [];
  function picOf(a) {
    const k = fileKind(a);
    if (k === 'image') return imgUrl(a, 480);
    if (a.thumb) return posterUrl(a);
    if (k === 'video' && a.path) return '/api/fthumb?path=' + encodeURIComponent(a.path) + '&id=' + encodeURIComponent(a.id || '');
    return '';
  }
  function tiles(list, big) {
    const set = tileSets.push(list) - 1;
    return `<div class="mib-tiles ${big ? 'big' : ''}">${list.map((a, i) => {
      const k = fileKind(a), u = picOf(a);
      const ext = fileExt(a.name), page = k === 'pdf' || k === 'text' || ['doc', 'docx', 'pages', 'rtf'].includes(ext);
      const pic = u ? `<img src="${u}" alt="" decoding="sync">` : page ? '<span class="mib-page"><i></i><i></i><i></i><i></i><i></i><i></i></span>'
        : `<span class="mib-ficon">${icon(k === 'image' ? 'image' : k === 'video' ? 'play' : 'clip')}<b>${esc(ext.slice(0, 4).toUpperCase() || 'FILE')}</b></span>`;
      return `<button type="button" class="mib-tile" data-mib="pv" data-set="${set}" data-i="${i}" data-att="${esc(a.id || '')}"><span class="mib-tpic">${pic}${k === 'video' ? '<span class="mib-play">▶</span>' : ''}</span><span class="mib-tn">${esc(a.name)}</span><span class="mib-ts">${esc(fmtSize(a.size) || '')}</span></button>`;
    }).join('')}</div>`;
  }
  // a comment's files: the same tiles as everywhere — one size, the name under, an icon when there's no picture
  function commentFiles(list) { return list.length ? tiles(list, false) : ''; }


  function paneHTML(g) {
    tileSets = [];
    const n = ibTarget(g.items), t = task(n.taskId), k = n.kind;
    if (k === 'birthday') return `<div class="mib-greet">${avatarHTML(n.from, 88)}<span>Today is</span><b>${esc(firstName(n.from))}’s birthday</b><span>Wish them a happy birthday</span></div>`;
    if (k === 'daily') return dailyHTML(g);
    if (k === 'signin') return head(hic('lock', 'dim'), 'Sign-in code used', esc(clock(n.at)), '')
      + `<div class="mib-ups"><div class="mib-u">${avatarHTML(n.from, 30)}<div class="mib-u-t"><b>${esc(nameOf(n.from))}</b> ${String(n.text || '').replace(/<(?!\/?b>)/g, '&lt;')}${n.snippet ? `<div class="mib-dim2">${esc(n.snippet)}</div>` : ''}</div></div></div>`;
    if (n.planId) return planHTML(g, n);
    if (k === 'asset') return assetHTML(g, n);
    if (/^claim/.test(k)) return claimHTML(g, n);
    if (k === 'sched-cancel') return schedHTML(g, n);
    // (the CD's review request shows as I6 — unless a comment came after it: then the comments, so none is hidden behind it)
    let rq = t && isCD() ? g.items.filter((x) => x.kind === 'review').sort((a, b) => a.at.localeCompare(b.at)).pop() : null;
    if (rq && g.items.some((x) => COMMENTS.has(x.kind) && x.at > rq.at)) rq = null;
    if (rq) { const r = reviewOf(t, rq); if (r) return reviewHTML(g, t, r); }
    return taskHTML(g, t);
  }
  // one update: who, when, what — a comment in full, in its thread, its files and reactions
  function upd(n, body, extra = '', faded = false, after = '') {
    return `<div class="mib-u ${faded ? 'faded' : ''}"${n.id ? ` data-key="u:${esc(n.id)}"` : ''}>${avatarHTML(n.from, 30)}<div class="mib-u-b"><div class="mib-u-h"><b>${esc(nameOf(n.from))}</b><span>${esc(clock(n.at))}</span></div><div class="mib-u-t">${body}</div>${extra}</div></div>${after}`;
  }
  function bodyOf(n, t) {
    const who = `<b>${esc(fullName(userById(n.from)))}</b> `;
    const m = msgOf(n, t);
    return m.startsWith(who) ? m.slice(who.length) : m;
  }
  // a task's line: its client, when it's due, its status and its priority (the board's coloured pills)
  function taskLine(t) {
    if (!t) return 'This task is no longer here';
    const st = statusInfo(t), pr = t.done ? 'none' : prioOf(t);
    return [cdot(proj(t.projectId)), t.due ? `due ${esc(fmtDue(t.due))}` : '', t.done ? 'completed' : ''].filter(Boolean).join(' · ')
      + (st && !t.done ? ` · ${solid(st.name, st.color)}` : '') + (pr === 'urgent' ? solid('Urgent', '#e5484d') : typeof pr === 'number' ? solid('P' + pr, '#636366') : '');
  }
  function reviewOf(t, n0) {
    const rs = (t.reviews || []).filter((r) => r.by === n0.from && r.state !== 'withdrawn');
    return rs.filter((x) => x.at <= n0.at).pop() || rs[rs.length - 1] || null;
  }
  // I6 — a review request, as the CD sees it: the note, the files, Request Amendments… · Approve
  function reviewHTML(g, t, r) {
    const files = (r.files || []).map((id) => (t.attachments || []).find((a) => a.id === id)).filter(Boolean);
    const all = files.length ? files : (t.attachments || []).filter((a) => a.reviewId === r.id);
    const pending = r.state === 'pending';
    const pill = pending ? solid('Waiting for CD review', '#bf5af2') : r.state === 'approved' ? soft('Approved', '#30d158') : soft('Amendments asked', '#ff9f0a');
    return head(statusIcon(t, 16), t.title || 'Untitled task', `${cdot(proj(t.projectId))} · submitted by ${esc(nameOf(r.by))} · ${esc(clock(r.at))} · ${pill}`, openBtn(g, 'Open Review Requests', false))
      + (r.message ? `<div class="mib-note">“${esc(r.message)}”</div>` : '')
      + (all.length ? cap(`${all.length} FILE${all.length === 1 ? '' : 'S'}`) + tiles(all, true) : '')
      + (pending ? foot(btn('Request Amendments…', `data-mib="rv-amend" data-id="${esc(r.id)}"`) + btn('Approve', `data-mib="rv-ok" data-id="${esc(r.id)}"`, true)) : '');
  }
  function taskHTML(g, t) {
    const items = g.items.slice().sort((a, b) => a.at.localeCompare(b.at));
    let lastComment = null;
    const cOf = (n) => (t && n.commentId && COMMENTS.has(n.kind) ? (t.comments || []).find((x) => x.id === n.commentId) : null);
    const notifiedC = cOf(ibTarget(g.items));   // (only the comment this notification is about takes a reaction — the others show theirs, still)
    // (a reply sits in its thread, as the task page's: the comment it answers above it — in full when it's one of these
    //  updates, else a faded two-line lead — and a line from that comment's picture curving into each reply's; Haris
    //  2026-11-17 "have a similar design for the threaded notifications and replies")
    const blocks = [];
    const lead = (pc) => upd({ id: 'lead-' + pc.id, from: pc.authorId, at: pc.at }, mentionMark(esc(pc.text || '')), '', true).replace('class="mib-u faded"', 'class="mib-u faded mib-lead"');
    items.forEach((n, i) => {
      const c = cOf(n), html = one(n, i);
      const pid = c && c.parentId, last = blocks[blocks.length - 1];
      if (!pid) { blocks.push({ cid: c ? c.id : null, html }); return; }
      if (last && last.pid === pid) { last.replies.push(html); return; }
      if (last && last.cid === pid) { blocks[blocks.length - 1] = { pid, head: last.html, replies: [html] }; return; }
      const pc = (t.comments || []).find((x) => x.id === pid);
      blocks.push(pc ? { pid, head: lead(pc), replies: [html] } : { cid: c.id, html });
    });
    function one(n, i) {
      const c = t && n.commentId && COMMENTS.has(n.kind) ? (t.comments || []).find((x) => x.id === n.commentId) : null;
      if (c) lastComment = c;
      const faded = i < items.length - 1;
      if (!c) return upd(n, bodyOf(n, t), '', faded);
      const text = mentionMark(esc(fullComment(n, t) || n.snippet || ''));
      const reacts = Object.entries(c.reactions || {}).filter(([, v]) => v);
      const live = !!notifiedC && c === notifiedC;
      const rx = !live ? (reacts.length ? `<div class="mib-rx">${reacts.map(([e, v]) => `<span class="mib-pill still">${e} <b>${typeof v === 'number' ? v : 1}</b></span>`).join('')}</div>` : '')
        : `<div class="mib-rx">${reacts.map(([e, v]) => `<button type="button" class="mib-pill ${mineReact(g) === e ? 'mine' : ''}" data-mib="react" data-tid="${esc(t.id)}" data-cid="${esc(c.id)}" data-e="${esc(e)}">${e} <b>${typeof v === 'number' ? v : 1}</b></button>`).join('')}<button type="button" class="mib-smile" data-mib="react-menu" data-tid="${esc(t.id)}" data-cid="${esc(c.id)}" title="React" aria-label="React">${icon('smile')}</button></div>`;
      return upd({ ...n, from: c.authorId, at: c.at }, text, commentFiles(c.attachments || []), faded, rx);
    }
    // your answers from here — each one a reply in the same thread, in order, the newest last (Haris 2026-11-17: "if you
    // comment twice, both will be added"); Edit while the website allows it (10 minutes, the minutes left beside it), and
    // Delete (the website's own: to the Trash, with Undo)
    const mineAll = myReplies(g, t);
    mineAll.forEach((m) => {
      const myC = m.c, editing = myC && editingId === myC.id;
      const acts = myC && !editing ? `<span class="mib-acts">${canEditComment(myC) ? `<button type="button" class="mib-btn sm" data-mib="my-edit" data-cid="${esc(myC.id)}">Edit <i>${esc(editLeftText(myC))}</i></button>` : ''}<button type="button" class="mib-btn sm" data-mib="my-del" data-tid="${esc(t.id)}" data-cid="${esc(myC.id)}">Delete</button></span>` : '';
      const body = editing ? `<div class="mib-edit"><textarea rows="2" class="mib-ein" data-tid="${esc(t.id)}" data-cid="${esc(myC.id)}">${esc(myC.text || '')}</textarea><div class="mib-ebtns"><button type="button" class="mib-btn" data-mib="my-cancel">Cancel</button><button type="button" class="mib-btn primary" data-mib="my-save" data-tid="${esc(t.id)}" data-cid="${esc(myC.id)}">Save</button></div></div>`
        : mentionMark(esc(myC ? myC.text || '' : m.text)) + (myC && myC.editedAt ? ' <span class="mib-dim">(edited)</span>' : '');
      const yours = `<div class="mib-yours">${upd({ id: 'mine-' + (myC ? myC.id : m.at), from: currentUserId, at: myC ? myC.at : m.at }, body, myC ? commentFiles(myC.attachments || []) : '')
        .replace(`<b>${esc(nameOf(currentUserId))}</b>`, '<b>You replied</b>').replace('</span></div><div class="mib-u-t">', `</span>${acts}</div><div class="mib-u-t">`)}</div>`;
      const last = blocks[blocks.length - 1];
      if (last && last.replies) last.replies.push(yours);
      else if (last && last.cid) blocks[blocks.length - 1] = { pid: last.cid, head: last.html, replies: [yours] };
      else blocks.push({ html: yours });
    });
    // (the minutes left counted down, and Edit gone when the time's up — only that line changes)
    const soonest = mineAll.map((m) => m.c).filter((c) => c && canEditComment(c)).map(editLeft).sort((a, b) => a - b)[0];
    clearTimeout(tick);
    if (soonest) tick = setTimeout(() => { if (ui.view === 'inbox') renderContent(); }, (soonest % 60000 || 60000) + 200);
    // (a long thread: the comment it's under, then only the reply before the newest (faded) and the newest — "+ N more" over
    //  them opens the rest, no closing it; picking a notification in the list again closes it. Your replies all show, last —
    //  Haris 2026-11-17)
    const thread = (b) => {
      const mineAt = b.replies.findIndex((r) => r.startsWith('<div class="mib-yours">'));
      const others = mineAt < 0 ? b.replies : b.replies.slice(0, mineAt), mine = mineAt < 0 ? [] : b.replies.slice(mineAt);
      const hide = openAll ? 0 : Math.max(0, others.length - 2);
      const rows = [...(hide ? [`<button type="button" class="mib-moreb" data-mib="more-ups">+ ${hide} more</button>`] : []), ...others.slice(hide), ...mine];
      return `<div class="mib-th" data-key="th:${esc(b.pid)}"><div class="mib-th-head">${b.head}</div>${rows.map((r) => `<div class="mib-th-r${r.startsWith('<button') ? ' more' : ''}">${r}</div>`).join('')}</div>`;
    };
    const ups = blocks.map((b) => (b.replies ? thread(b) : b.html)).join('');
    let reply = '';
    if (lastComment) {
      const root = lastComment.parentId || lastComment.id;
      const rootC = (t.comments || []).find((x) => x.id === root);
      const to = firstName(lastComment.authorId);
      const where = lastComment.parentId || mineAll.length ? `Replies in ${esc(nameOf(rootC ? rootC.authorId : lastComment.authorId))}’s thread` : `Starts a thread under ${esc(to)}’s comment`;
      reply = `<!--foot--><div class="mib-reply"><div class="mib-where">↳ ${where}</div>${upHTML()}<div class="mib-box"><button type="button" class="mib-add" data-mib="attach" title="Attach files" aria-label="Attach files">${icon('plus')}</button><textarea rows="1" class="mib-in" placeholder="Reply to ${esc(to)}…" data-tid="${esc(t.id)}" data-root="${esc(root)}"></textarea>
        <button type="button" class="mib-send" data-mib="send" title="Send" disabled><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M5.5 11.5 12 5l6.5 6.5"/></svg></button></div></div>`;
    }
    return head(t ? statusIcon(t, 16) : '', t ? (t.title || 'Untitled task') : 'Deleted task', taskLine(t), unreadBtn(g) + openBtn(g, 'Open Task'))
      + cap(`${items.length} update${items.length === 1 ? '' : 's'} · newest last`) + `<!--body--><div class="mib-ups">${ups}</div>${reply}`;
  }
  let editingId = null, tick = null, openAll = false;
  // your replies from this pane, still there (each comment's id kept; an older one without, its words)
  function myReplies(g, t) {
    const x = g.items.find((n) => n.mine && n.mine.reply);
    if (!x || !t) return [];
    const ids = x.mine.cids || (x.mine.cid ? [x.mine.cid] : []);
    if (!ids.length) return [{ c: null, text: x.mine.reply, at: x.mine.at }];
    return ids.map((id) => (t.comments || []).find((c) => c.id === id)).filter(Boolean).map((c) => ({ c, at: c.at }));
  }
  // your reply saved as the website saves an edit: within its 10 minutes (and the server's minute of grace), new @mentions told
  function saveMine(tid, cid) {
    const t = task(tid), c = t && (t.comments || []).find((x) => x.id === cid), ein = document.querySelector('.mib-ein');
    if (!c || !ein) return;
    const v = ein.value.trim();
    if (!v && !(c.attachments || []).length) return;
    editingId = null;
    if (Date.now() - Date.parse(c.at) > EDIT_WINDOW + 60000) { renderContent(); toast('Too late to edit'); return; }
    const html = esc(v).replace(/\n/g, '<br>');
    if (v !== c.text) {
      const before = mentionsIn(c.html);
      mentionsIn(html).forEach((u) => { if (!before.has(u)) pushNotif(u, t, 'mention', 'mentioned you in a comment on', { snippet: trunc(v, 160), commentId: c.id }); });
      c.text = v; c.html = html; c.editedAt = nowISO();
    }
    commit();
  }
  const mineReact = (g) => { const x = g.items.find((n) => n.mine && n.mine.react); return x ? x.mine.react : null; };

  // I5 — a content skeleton: its occasions, its posts by day; Send Back · Approve when it's waiting for you
  const POST_ST = { ok: ['Ready', '#30d158'], changes: ['Changes asked', '#ff9f0a'] };
  function planHTML(g, n) {
    const pl = Plans.planById(n.planId), p = pl ? proj(pl.projectId) : null;
    if (!pl) return head(hic('cal', 'purple'), planTitle(n), '', openBtn(g, 'Open Plan', false)) + '<p class="mib-dim">Content skeleton not found</p>';
    const posts = (pl.posts || []).slice().sort((a, b) => String(a.day).localeCompare(String(b.day)));
    const waiting = pl.status === 'review' && Plans.canApprove(pl);
    const st = waiting ? soft('Waiting for you', '#ff9f0a') : pl.status === 'approved' ? soft('Approved', '#30d158') : pl.status === 'changes' ? soft('Changes asked', '#ff9f0a') : pl.status === 'review' ? soft('Waiting for approval', '#0a84ff') : soft('Draft', '#98989d');
    const m = String(pl.month || '');
    const occ = m && typeof Occasions !== 'undefined' ? Occasions.between(m + '-01', m + '-31').filter((o) => String(o.date || '').slice(0, 7) === m) : [];
    const fmt = Object.fromEntries((Plans.FORMATS || []).map(([k, name]) => [k, name]));
    const chName = Object.fromEntries((typeof Cal !== 'undefined' && Cal.CHANNELS ? Cal.CHANNELS : []).map(([k, name]) => [k, name]));
    const pic = (x) => { const gr = Plans.progress(x); const img = (gr.files || []).find((r) => fileKind(r) === 'image') || (x.refs || []).find((r) => r.path && fileKind(r) === 'image'); return img ? `<img src="${imgUrl(img, 160)}" alt="" decoding="sync">` : ''; };
    const shownPosts = posts.slice(0, 3);
    const row = (x) => { const d = x.day ? parseYmd(x.day) : null; const s = x.check && POST_ST[x.check.state];
      return `<div class="mib-post ${x.check && x.check.state === 'changes' ? 'chg' : ''}"><span class="mib-pday"><b>${d ? d.getDate() : '–'}</b><span>${d ? d.toLocaleDateString('en-US', { month: 'short' }).toUpperCase() : ''}</span></span><span class="mib-ppic">${pic(x)}</span><span class="mib-pt"><b>${esc(x.title || 'Untitled post')}</b><span>${esc([fmt[x.format] || 'Post', (x.channels || []).map((k) => chName[k] || k).join(', ')].filter(Boolean).join(' · '))}</span></span>${s ? soft(s[0], s[1]) : ''}</div>`; };
    const dot = p ? `<i class="mib-cdot" style="background:${esc(p.color || '#87909e')}"></i>` : '';
    return head(hic('cal', 'purple'), Plans.nameOf(pl), `${dot}content skeleton by ${esc(nameOf(pl.createdBy))} · ${st}`, openBtn(g, 'Open Plan', false))
      + (occ.length ? cap('OCCASIONS') + `<div class="mib-occ">${occ.map((o) => soft(`${o.name} · ${parseYmd(String(o.date).slice(0, 10)).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`, '#0a84ff')).join('')}</div>` : '')
      + cap(`${posts.length} POST${posts.length === 1 ? '' : 'S'} · BY DAY`) + `<div class="mib-posts">${shownPosts.map(row).join('')}${posts.length > shownPosts.length ? `<div class="mib-more">+ ${posts.length - shownPosts.length} more</div>` : ''}</div>`
      + (waiting ? foot(btn('Send Back', `data-mib="plan-back" data-id="${esc(pl.id)}"`) + `<span class="${(pl.posts || []).some((x) => x.check && x.check.state === 'changes') ? 'mib-faded' : ''}">${btn('Approve', `data-mib="plan-ok" data-id="${esc(pl.id)}"`, true)}</span>`) : '');
  }
  // I8 — files added to Client Assets: the folder, and the files the update names; Open Folder
  function assetHTML(g, n) {
    const c = clientById(n.clientId), f = c && (c.folders || []).find((x) => x.id === n.folderId);
    const names = String(n.snippet || '').split(', ').map((x) => x.replace(/ \+\d+ more$/, '')).filter(Boolean);
    const inFolder = f ? (f.files || []) : [];
    let files = names.map((nm) => inFolder.find((a) => a.name === nm)).filter(Boolean);
    const m = String(n.text || '').match(/^(added|replaced|removed) (?:a file|(\d+) files)/);
    const fin = String(n.snippet || '').match(/^(\d+) files?$/);   // (the task's final files filed in the client's Files)
    const count = m ? Number(m[2] || 1) : fin ? Number(fin[1]) : files.length;
    if (!files.length && fin) files = inFolder.slice().sort((a, b) => String(b.addedAt || '').localeCompare(String(a.addedAt || ''))).slice(0, count);
    const verb = m ? m[1] : 'added';
    const pc = c ? ((db.projects.find((x) => x.clientId === c.id) || {}).color || '#6e717a') : '';
    const line = `${c ? `<i class="mib-cdot" style="background:${esc(pc)}"></i>${esc(c.name + (f ? ' › ' + folderPath(c, f) : ''))}` : ''} · ${esc(verb)} by ${esc(nameOf(n.from))} · ${esc(clock(n.at))}`;
    return head(hic('folder'), f ? f.name : assetTitle(n), line, openBtn(g, 'Open Folder'))
      + cap(`${count} FILE${count === 1 ? '' : 'S'} ${esc(verb.toUpperCase())}`) + (files.length ? tiles(files) : `<div class="mib-files">${names.map((x) => `<span class="mib-file static">${esc(x)}</span>`).join('')}</div>`);
  }
  // I9 — a claim: its items and total; Open Claims
  const CLAIM_DID = { 'claim-ok': 'MARKED HR APPROVED', 'claim-paid': 'MARKED PAID', 'claim-hand': 'ADDED', claim: 'SUBMITTED' };
  function claimHTML(g, n) {
    const c = n.claimId && typeof Claims !== 'undefined' ? Claims.byId(n.claimId) : null;
    const items = c ? (c.groups || []).flatMap((gr) => (gr.items || []).map((i) => ({ d: gr.date, x: i.desc || gr.title || '', a: i.amount }))) : [];
    const amt = (v) => '⃃ ' + (Number(v) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const month = c && c.month ? new Date(c.month + '-01T00:00:00').toLocaleDateString('en-US', { month: 'long' }) : '';
    const whose = c && c.userId === currentUserId ? 'Your' : c ? `${firstName(c.userId)}’s` : '';
    const title = c ? `${whose} ${month} expense claim` : 'Expense claims';
    const line = c ? `${items.length} item${items.length === 1 ? '' : 's'} · ${amt(Claims.totalOf(c))} · ${Claims.pill(c)}` : '';
    return head(hic('coin', 'green'), title, line, openBtn(g, 'Open Claims'))
      + cap(`${CLAIM_DID[n.kind] || 'UPDATED'} BY ${esc(nameOf(n.from).toUpperCase())} · ${esc(clock(n.at).toUpperCase())}`)
      + (items.length ? `<div class="mib-claim">${items.map((i) => `<div><span>${esc(i.d ? parseYmd(i.d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) : '')}</span><span>${esc(i.x)}</span><b>${amt(i.a)}</b></div>`).join('')}<div class="tot"><span>Total</span><b>${amt(Claims.totalOf(c))}</b></div></div>` : '');
  }
  // I12 — a scheduled comment that wasn't sent: its text and files; Open Task
  function schedHTML(g, n) {
    const t = task(n.taskId), s = (db.scheduled || []).find((x) => x.id === n.schedId) || {};
    const when = s.sendAt ? new Date(s.sendAt).toLocaleString('en-US', { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).replace(/, (\d+:\d+)/, ' · $1') : '';
    const what = s.replyTo || /scheduled reply/.test(n.text || '') ? 'REPLY' : 'COMMENT';
    const files = (s.attachments || []).map((a) => `<span class="mib-qf"><b>${esc(a.name)}</b><span>${esc(fmtSize(a.size) || '')}</span></span>`).join('');
    const title = t ? (t.title || 'Untitled task') : (String(n.text || '').match(/<b>(.*?)<\/b>/) || [])[1] || titleOf(n, null);
    const line = t ? [cdot(proj(t.projectId)), t.done ? 'completed' : esc(statusInfo(t).name)].filter(Boolean).join(' · ') : esc(n.reason || '');
    return head(t ? statusIcon(t, 16) : hic('clock'), title, line, n.taskId ? openBtn(g, 'Open Task') : '')
      + cap(`YOUR SCHEDULED ${what}${when ? ` · WAS FOR ${esc(when.toUpperCase())}` : ''}`)
      + `<div class="mib-quote">${esc(s.text || n.snippet || '')}${files ? `<span class="mib-qfs">${files}</span>` : ''}</div>`;
  }
  // I11 — the morning round-up, worked out again: its sections, the first with tasks open
  const DY_TONE = { red: '#ff453a', amber: '#ff9f0a', accent: '#0a84ff' };
  let dyOpen = null;
  function dailyHTML(g) {
    const n = g.items[0];
    if (typeof Daily === 'undefined' || !Daily.wants()) return `${head(hic('sun', 'sun'), n.title || 'Good morning', '', '')}<div class="mib-ups">${upd(n, String(n.text || '').replace(/<(?!\/?b>)/g, '&lt;'))}</div>`;
    const S = Daily.sections();
    const cnt = (s) => (s.sched ? s.sched.length : s.tasks.length);
    if (dyOpen === null) { const f = S.find((s) => cnt(s)); dyOpen = f ? f.k : ''; }
    const when = new Date().toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long' });
    const scope = isSuper() ? 'the whole team’s tasks' : Work.hasClients(currentUserId) ? 'your clients’ tasks' : 'your tasks';
    const today = todayStr();
    return head(hic('sun', 'sun'), `Good morning, ${firstName(currentUserId)}`, `${esc(when)} · ${scope}`, '')
      + `<div class="mib-daily">${S.map((s) => { const c = cnt(s), on = dyOpen === s.k && c;
        const rows = !on ? '' : s.sched ? s.sched.map((x) => `<button type="button" class="mib-drow" data-mib="task" data-id="${esc(x.taskId)}"><span>${esc(trunc(x.text || 'Files', 70))}</span><span>${esc(new Date(x.sendAt).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }))}</span></button>`).join('')
          : s.tasks.slice(0, 6).map((t) => `<button type="button" class="mib-drow" data-mib="task" data-id="${esc(t.id)}"><span>${esc(t.title || 'Untitled task')}</span><span>${esc((proj(t.projectId) || {}).name || '')}${t.due ? ` · <i class="${t.due < today ? 'late' : ''}">${esc(parseYmd(t.due).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }))}</i>` : ''}</span></button>`).join('')
            + (s.filter ? `<button type="button" class="mib-dall" data-mib="dy-all" data-k="${s.k}">See them in My Tasks</button>` : '');
        return `<div class="mib-dsec ${c ? '' : 'none'}"><button type="button" class="mib-dh" data-mib="dy-sec" data-k="${s.k}" ${c ? '' : 'disabled'} style="--c:${DY_TONE[s.tone] || DY_TONE.accent}">${icon(s.ic)}<span>${esc(s.l)}</span><b>${c}</b><i>${on ? '⌄' : c ? '›' : ''}</i></button>${rows}</div>`; }).join('')}</div>
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
    openAll = false;   // (every pick in the list starts a long run closed again)
    mClose(); picked = new Set();
    if (k !== pick) { dyOpen = null; pending.forEach((x) => { if (x.linked) return; if (x.att) api('POST', '/api/host/trashMany', { paths: [x.att.path] }).catch(() => {}); else x.sig.cancelled = true; }); pending = []; }
    pick = k;
    const g = rows().list.find((x) => x.key === k);
    if (g && g.items.some((x) => !x.read)) markRead(g); else renderContent();
  }
  function send(btnEl) {
    const box = btnEl.closest('.mib-box'), ta = box && box.querySelector('.mib-in');
    const text = ta ? ta.value.trim() : '';
    if (pending.some((x) => !x.att)) return;   // (still going up: Send waits — its button is dimmed)
    if (!text && !pending.length) return;
    const t = task(ta.dataset.tid);
    if (!t) return;
    // (@ names picked from the list become the website's mentions, so they're told)
    let html = esc(text);
    picked.forEach((id) => { const u = userById(id); if (!u) return; const n = esc('@' + fullName(u)); html = html.split(n).join(`<span class="mention" data-user="${esc(u.id)}" contenteditable="false">${n}</span>`); });
    html = html.replace(/\n/g, '<br>'); picked = new Set();
    const files = pending.splice(0).map((x) => { if (x.url) URL.revokeObjectURL(x.url); return x.att; });
    files.forEach((a) => { if (!(t.attachments || []).some((x) => x.path === a.path)) (t.attachments = t.attachments || []).push(a); });
    const cid = postComment(t, ta.dataset.root, text, html, files);
    t.updatedAt = nowISO();
    const g = rows().list.find((x) => x.key === pick);
    if (g) { const was = g.items.find((x) => x.mine && x.mine.reply), cids = was ? (was.mine.cids || (was.mine.cid ? [was.mine.cid] : [])) : []; g.items.forEach((x) => { x.mine = { reply: text, at: nowISO(), cid, cids: [...cids, cid] }; }); }
    // (sent: the box empty again, and the reply just added scrolled into view, smoothly — Haris 2026-11-17)
    ta.value = ''; ta.style.height = 'auto';
    commit();
    if (ui.view === 'inbox') renderContent();
    requestAnimationFrame(() => {
      const sc = document.querySelector('.mib-scroll'), el = sc && sc.querySelector(`[data-key="u:mine-${cid}"]`);
      if (el) sc.scrollTo({ top: sc.scrollTop + el.getBoundingClientRect().bottom - sc.getBoundingClientRect().bottom + 18, behavior: 'smooth' });
    });
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
  // + in the reply box (the Mac's own file picker) or files dropped on the pane: each goes up at once as a square tile under
  // the reply box, its own ring showing how far it is, ✕ to take it off (stopping it, or putting an uploaded one in the Trash);
  // only here — every other upload shows as it always has (Haris 2026-11-17)
  let pending = [], upN = 0;
  const ring = (x) => x.att ? '' : `<svg class="mib-ring" viewBox="0 0 36 36"><circle cx="18" cy="18" r="15"/><circle class="on" cx="18" cy="18" r="15" style="stroke-dashoffset:${(94.25 * (1 - (x.p || 0))).toFixed(1)}"/></svg>`;
  function upHTML() {
    if (!pending.length) return '<div class="mib-up" hidden></div>';
    return `<div class="mib-up">${pending.map((x) => {
      const pic = x.url || (x.att && fileKind(x.att) === 'image' ? imgUrl(x.att, 160) : x.att && x.att.thumb ? posterUrl(x.att) : '');
      return `<span class="mib-upt ${x.att ? 'done' : ''}" data-key="up:${x.k}">${pic ? `<img src="${esc(pic)}" alt="">` : `<span class="mib-ficon">${icon(fileKind(x) === 'video' ? 'play' : 'clip')}<b>${esc((fileExt(x.name) || 'file').slice(0, 4).toUpperCase())}</b></span>`}${ring(x)}<button type="button" class="mib-upx" data-mib="up-x" data-k="${x.k}" title="Remove" aria-label="Remove ${esc(x.name)}">${icon('x')}</button></span>`;
    }).join('')}</div>`;
  }
  function sendState() { const ta = document.querySelector('.mib-in'), b = document.querySelector('.mib-send'); if (ta && b) b.disabled = pending.some((x) => !x.att) || (!ta.value.trim() && !pending.length); }
  function upDraw() { if (ui.view === 'inbox') renderContent(); }
  function addFiles(files, t) {
    files.forEach((f) => {
      const x = { k: ++upN, name: f.name, size: f.size, p: 0, sig: { cancelled: false }, url: f instanceof Blob && /^image\//.test(f.type) ? URL.createObjectURL(f) : '' };
      pending.push(x);
      let last = 0;
      ServerHost.uploadFile(f, { taskId: t.id }, (p) => {
        x.p = p;
        const el = document.querySelector(`.mib-upt[data-key="up:${x.k}"] .on`);   // (only the ring moves — nothing drawn again)
        if (el && p - last > 0.01) { last = p; el.style.strokeDashoffset = (94.25 * (1 - p)).toFixed(1); }
      }, x.sig).then((att) => {
        if (x.sig.cancelled || !pending.includes(x)) return;
        x.att = { ...att, addedAt: nowISO(), addedBy: currentUserId }; x.p = 1;
        upDraw(); sendState();
      }).catch((e) => {
        if (e && e.cancelled) return;
        pending = pending.filter((y) => y !== x); upDraw(); sendState();
        toast(`Upload failed: ${x.name}`);
      });
    });
    upDraw(); sendState();
  }
  async function attach() {
    const ta = document.querySelector('.mib-in'), t = ta && task(ta.dataset.tid);
    if (!t) return;
    try {
      const files = Host.isMacApp ? await ServerHost.pickMacFiles({ multiple: true, prompt: 'Attach' }) : await ServerHost.pickFiles({ multiple: true });
      if (files && files.length) addFiles([...files], t);
    } catch (e) { toast('Couldn’t add the files — try again'); }
  }
  function unAdd(k) {
    const x = pending.find((y) => String(y.k) === String(k));
    if (!x) return;
    pending = pending.filter((y) => y !== x);
    if (x.url) URL.revokeObjectURL(x.url);
    if (x.att && !x.linked) api('POST', '/api/host/trashMany', { paths: [x.att.path] }).catch(() => {});   // (up already, never sent: to the Trash — a # file of the task stays)
    else x.sig.cancelled = true;                                                              // (still going up: stopped)
    upDraw(); sendState();
  }
  // @ and # in the reply box, as the website's: @ the team (picked: "@Name", told when it's sent), # this task's files
  // (picked: added to the reply as the same file — no upload). Apple's menu look; ↑ ↓, Enter or Tab, Esc.
  let mpop = null, mItems = [], mIdx = 0, mQ = null, picked = new Set();
  function mClose() { if (mpop) mpop.remove(); mpop = null; mQ = null; }
  function mQuery(ta) {
    const before = ta.value.slice(0, ta.selectionStart);
    const m = before.match(/(?:^|[\s(])([@#])([^\s@#]{0,30})$/);
    return m ? { kind: m[1], q: m[2].toLowerCase(), start: ta.selectionStart - m[2].length - 1, end: ta.selectionStart } : null;
  }
  function mUpdate(ta) {
    const q = mQuery(ta), t = task(ta.dataset.tid);
    if (!q || !t) return mClose();
    mItems = q.kind === '@'
      ? activeUsers().filter((u) => u.id !== currentUserId && (fullName(u).toLowerCase().includes(q.q) || u.email.toLowerCase().includes(q.q))).slice(0, 8).map((u) => ({ u }))
      : taskFilesList(t).filter((a) => (a.name || '').toLowerCase().includes(q.q)).slice(0, 8).map((a) => ({ a }));
    if (!mItems.length) return mClose();
    if (!mQ || mQ.kind !== q.kind) mIdx = 0;
    mQ = q; if (mIdx >= mItems.length) mIdx = 0;
    if (!mpop) { mpop = document.createElement('div'); mpop.className = 'menu mention-pop mib-mpop'; document.body.appendChild(mpop); }
    mpop.innerHTML = `<div class="menu-label">${q.kind === '@' ? 'Mention someone' : 'Add a file of this task'}</div>` + mItems.map((it, i) => it.u
      ? `<div class="mi asg-mi ${i === mIdx ? 'hl' : ''}" data-mib-m="${i}">${avatarHTML(it.u.id, 22)}<span class="asg-n">${esc(fullName(it.u))}<small>${esc(it.u.email)}</small></span></div>`
      : `<div class="mi asg-mi ${i === mIdx ? 'hl' : ''}" data-mib-m="${i}"><i class="fr-ic fk-${chipKind(it.a.name)}"></i><span class="asg-n">${esc(it.a.name)}<small>${esc(fmtSize(it.a.size) || '')}</small></span></div>`).join('');
    const box = ta.closest('.mib-box').getBoundingClientRect(), h = mpop.offsetHeight;
    mpop.style.left = box.left + 'px'; mpop.style.top = Math.max(8, box.top - h - 6) + 'px';
  }
  function mPick(i) {
    const ta = document.querySelector('.mib-in'), it = mItems[i], q = mQ;
    mClose();
    if (!ta || !it || !q) return;
    const t = task(ta.dataset.tid);
    if (it.u) {
      const ins = '@' + fullName(it.u) + ' ';
      ta.value = ta.value.slice(0, q.start) + ins + ta.value.slice(q.end);
      ta.selectionStart = ta.selectionEnd = q.start + ins.length;
      picked.add(it.u.id);
    } else if (t) {
      ta.value = ta.value.slice(0, q.start) + ta.value.slice(q.end);
      ta.selectionStart = ta.selectionEnd = q.start;
      if (pending.some((x) => x.att && x.att.path === it.a.path)) toast('That file is already added');
      else { pending.push({ k: ++upN, name: it.a.name, size: it.a.size, p: 1, linked: true, sig: { cancelled: false }, att: { ...it.a, id: uid(), linked: true, addedAt: nowISO() } }); upDraw(); }
    }
    ta.focus(); ta.dispatchEvent(new Event('input', { bubbles: true }));
  }
  document.addEventListener('mousedown', (e) => {
    const it = e.target.closest && e.target.closest('[data-mib-m]');
    if (it) { e.preventDefault(); mPick(+it.dataset.mibM); return; }
    if (mpop && !e.target.closest('.mib-mpop')) mClose();
  }, true);
  // files dragged onto a comment's pane go up as if picked with +
  const dropPane = (e) => { const p = e.target.closest && e.target.closest('.mib-pane'); return p && p.querySelector('.mib-in') && [...((e.dataTransfer && e.dataTransfer.types) || [])].includes('Files') ? p : null; };
  ['dragenter', 'dragover'].forEach((ev) => document.addEventListener(ev, (e) => {
    if (!on() || ui.view !== 'inbox') return;
    const p = dropPane(e);
    document.querySelectorAll('.mib-pane[data-live-drop]').forEach((x) => { if (x !== p) x.removeAttribute('data-live-drop'); });
    if (!p) return;
    e.preventDefault(); e.stopPropagation(); e.dataTransfer.dropEffect = 'copy'; p.setAttribute('data-live-drop', '');
  }, true));
  document.addEventListener('dragleave', (e) => { const p = e.target.closest && e.target.closest('.mib-pane'); if (p && !p.contains(e.relatedTarget)) p.removeAttribute('data-live-drop'); }, true);
  document.addEventListener('drop', (e) => {
    if (!on() || ui.view !== 'inbox') return;
    const p = dropPane(e);
    if (!p) return;
    e.preventDefault(); e.stopPropagation(); p.removeAttribute('data-live-drop');
    const t = task(p.querySelector('.mib-in').dataset.tid), files = [...(e.dataTransfer.files || [])].filter((f) => f.size || f.type);
    if (t && files.length) addFiles(files, t);
  }, true);
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
    else if (a === 'task') { if (task(el.dataset.id)) openTask(el.dataset.id); else toast('That task isn’t there anymore'); }
    else if (a === 'pv') { const list = tileSets[Number(el.dataset.set)] || []; const f = list[Number(el.dataset.i)]; if (f) previewFile(f, list); }
    else if (a === 'attach') attach(el);
    else if (a === 'rv-ok') { const f = findReview(el.dataset.id); if (f) { decideReview(f.t, f.r, 'approve'); toast(`Approved — ${firstName(f.r.by)} told`); renderContent(); } }
    else if (a === 'rv-amend') { decisionDialog(el.dataset.id); const b = document.querySelector('#overlay-root [data-d="amend"]'); if (b) b.click(); }
    else if (a === 'plan-ok') { const pl = Plans.planById(el.dataset.id); if (pl) Promise.resolve(Plans.approve(pl)).then(() => renderContent()); }
    else if (a === 'plan-back') { const pl = Plans.planById(el.dataset.id); if (pl) Plans.sendBack(pl); }
    else if (a === 'dy-sec') { dyOpen = dyOpen === el.dataset.k ? '' : el.dataset.k; renderContent(); }
    else if (a === 'more-ups') { openAll = true; renderContent(); }
    else if (a === 'up-x') unAdd(el.dataset.k);
    else if (a === 'my-edit') { editingId = el.dataset.cid; renderContent(); setTimeout(() => { const x = document.querySelector('.mib-ein'); if (x) { x.focus(); x.setSelectionRange(x.value.length, x.value.length); } }, 0); }
    else if (a === 'my-cancel') { editingId = null; renderContent(); }
    else if (a === 'my-save') saveMine(el.dataset.tid, el.dataset.cid);
    else if (a === 'my-del') { const t = task(el.dataset.tid); if (t) deleteComment(el.dataset.cid, t); }
    else if (a === 'dy-all') { if (window.__e11Daily) window.__e11Daily({ ev: 'all', k: el.dataset.k }); }
    else if (a === 'file') { const t = task(el.dataset.tid), c = t && (t.comments || []).find((x) => x.id === el.dataset.cid); const f = c && (c.attachments || []).find((x) => x.id === el.dataset.id); if (f) previewFile(f, c.attachments); }
  });
  document.addEventListener('input', (e) => {
    const ta = e.target.closest && e.target.closest('.mib-in');
    if (!ta) return;
    ta.style.height = 'auto'; ta.style.height = Math.min(ta.scrollHeight, 140) + 'px';
    mUpdate(ta);
    sendState();
  });
  document.addEventListener('keydown', (e) => {
    if (!on() || ui.view !== 'inbox' || ui.taskId) return;
    const ta = e.target.closest && e.target.closest('.mib-in');
    if (ta && mpop) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); mIdx = (mIdx + (e.key === 'ArrowDown' ? 1 : -1) + mItems.length) % mItems.length; mUpdate(ta); return; }
      if ((e.key === 'Enter' || e.key === 'Tab') && !e.metaKey) { e.preventDefault(); mPick(mIdx); return; }
      if (e.key === 'Escape') { e.preventDefault(); mClose(); return; }
    }
    if (ta) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); mClose(); send(ta.parentElement.querySelector('.mib-send')); } return; }
    const ein = e.target.closest && e.target.closest('.mib-ein');
    if (ein) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); saveMine(ein.dataset.tid, ein.dataset.cid); } else if (e.key === 'Escape') { e.preventDefault(); editingId = null; renderContent(); } return; }
    if (e.target.closest && e.target.closest('input, textarea, [contenteditable="true"], .dialog, .menu')) return;
    if (document.getElementById('overlay-root') && document.getElementById('overlay-root').children.length) return;
    if (e.key === 'Escape') { if (pick) { pick = null; renderContent(); e.preventDefault(); } return; }
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
    e.preventDefault();
    const i = order.indexOf(pick);
    const j = e.key === 'ArrowDown' ? Math.min(order.length - 1, i + 1) : Math.max(0, i < 0 ? 0 : i - 1);
    if (order[j] && order[j] !== pick) { choose(order[j]); const r = document.querySelector('.mib-row.sel'); if (r) r.scrollIntoView({ block: 'nearest' }); }
  });

  // ---------- drawn again: only what changed (Haris 2026-11-17: "dont redraw the page unless anything has changed") ----------
  // The page asks for the Inbox again on every change anywhere; instead of putting it all back (every picture loaded again,
  // blank for a moment), the new one is laid over the one on show: a row, an update or a tile stays as it is unless what it
  // shows changed — the same picture never loads again, a reply being typed stays, the lists keep their scroll.
  let wasFresh = false;
  const keyOf = (n) => (n.nodeType === 1 ? n.getAttribute('data-key') : null);
  function morph(a, b) {
    if (a.nodeType !== b.nodeType || a.nodeName !== b.nodeName) { a.replaceWith(b); return; }
    if (a.nodeType !== 1) { if (a.nodeValue !== b.nodeValue) a.nodeValue = b.nodeValue; return; }
    if (a.isEqualNode(b)) return;
    if (a.nodeName === 'IMG') { a.replaceWith(b); return; }
    [...a.attributes].forEach((x) => { if (!b.hasAttribute(x.name) && !x.name.startsWith('data-live')) a.removeAttribute(x.name); });   // (data-live-…: set by the page itself, kept)
    [...b.attributes].forEach((x) => { if (a.getAttribute(x.name) !== x.value) a.setAttribute(x.name, x.value); });
    if (a.nodeName === 'TEXTAREA') return;   // (what's being typed stays)
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
  // (pictures kept once seen: each one held in memory, so a notification picked again shows its pictures at once, not
  //  loaded and drawn again — Haris 2026-11-17 "images are loading again … cache them"; the newest 300)
  const held = new Map();
  function hold(root) {
    root.querySelectorAll('.mib img').forEach((im) => {
      const u = im.getAttribute('src');
      if (!u || held.has(u)) { if (u) { const x = held.get(u); held.delete(u); held.set(u, x); } return; }
      const keep = new Image(); keep.decoding = 'async'; keep.src = u; held.set(u, keep);
      if (held.size > 300) held.delete(held.keys().next().value);
    });
  }
  // (the list's foot fades only while there's more under it)
  function more(l) { if (!l) return; const m = l.scrollTop + l.clientHeight < l.scrollHeight - 2; if (m !== l.hasAttribute('data-live-more')) l.toggleAttribute('data-live-more', m); }
  // (the pane's header fades what's under it once something has scrolled under it)
  function under(sc) { const p = sc && sc.parentElement; if (!p) return; const u = sc.scrollTop > 1; if (u !== p.hasAttribute('data-live-under')) p.toggleAttribute('data-live-under', u); }
  document.addEventListener('scroll', (e) => { const t = e.target; if (!t || !t.classList) return; if (t.classList.contains('mib-list')) more(t); else if (t.classList.contains('mib-scroll')) under(t); }, true);
  function patch(c) {
    const cur = c.firstElementChild;
    hold(c);
    if (!cur || c.children.length !== 1 || !cur.classList.contains('mib')) return false;
    const t = document.createElement('template');
    t.innerHTML = view().trim();
    const nb = t.content.firstElementChild;
    if (!nb) return false;
    morph(cur, nb);
    hold(c);
    // (another notification picked: its pane fades in, as when it was drawn afresh)
    const pane = wasFresh && cur.querySelector('.mib-pane');
    if (pane) { pane.classList.remove('fresh'); void pane.offsetWidth; pane.classList.add('fresh'); }
    return true;
  }
  return { on, view, patch, drawn: (c) => {
    const sc = c.querySelector('.mib-scroll');
    // (a notification opened: a long run opens at its end, the newest update in view — Haris 2026-11-17)
    if (wasFresh && sc && sc.scrollHeight > sc.clientHeight) sc.scrollTop = sc.scrollHeight;
    more(c.querySelector('.mib-list')); under(sc); sendState();
  }, reset: () => { pick = undefined; shown = null; } };
})();
