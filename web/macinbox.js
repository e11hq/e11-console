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
    return `<div class="mib-ph"><div class="mib-ph-t"><div class="mib-ph-h">${ic}<h2>${esc(title)}</h2></div>${line ? `<div class="mib-ph-l">${line}</div>` : ''}</div>${buttons ? `<div class="mib-ph-b">${buttons}</div>` : ''}</div>`;
  }
  const hic = (name, tone) => `<span class="mib-hic ${tone || ''}">${icon(name)}</span>`;
  const cap = (s) => `<div class="mib-cap">${s}</div>`;
  const soft = (label, color) => `<span class="mib-sp" style="--c:${color}">${esc(label)}</span>`;
  const solid = (label, bg) => `<span class="mib-solid" style="background:${bg};color:${textOn(bg)}">${esc(label)}</span>`;
  const foot = (buttons) => `<div class="mib-foot"><span></span>${buttons}</div>`;
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
      const pic = u ? `<img src="${u}" alt="" loading="lazy">` : page ? '<span class="mib-page"><i></i><i></i><i></i><i></i><i></i><i></i></span>'
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
    return `<div class="mib-u ${faded ? 'faded' : ''}">${avatarHTML(n.from, 30)}<div class="mib-u-b"><div class="mib-u-h"><b>${esc(nameOf(n.from))}</b><span>${esc(clock(n.at))}</span></div><div class="mib-u-t">${body}</div>${extra}</div></div>${after}`;
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
    const ups = items.map((n, i) => {
      const c = t && n.commentId && COMMENTS.has(n.kind) ? (t.comments || []).find((x) => x.id === n.commentId) : null;
      if (c) lastComment = c;
      const faded = i < items.length - 1;
      if (!c) return upd(n, bodyOf(n, t), '', faded);
      const parent = c.parentId ? (t.comments || []).find((x) => x.id === c.parentId) : null;
      const text = mentionMark(esc(fullComment(n, t) || n.snippet || ''));
      const reacts = Object.entries(c.reactions || {}).filter(([, v]) => v);
      const live = !!notifiedC && c === notifiedC;
      const rx = !live ? (reacts.length ? `<div class="mib-rx">${reacts.map(([e, v]) => `<span class="mib-pill still">${e} <b>${typeof v === 'number' ? v : 1}</b></span>`).join('')}</div>` : '')
        : `<div class="mib-rx">${reacts.map(([e, v]) => `<button type="button" class="mib-pill ${mineReact(g) === e ? 'mine' : ''}" data-mib="react" data-tid="${esc(t.id)}" data-cid="${esc(c.id)}" data-e="${esc(e)}">${e} <b>${typeof v === 'number' ? v : 1}</b></button>`).join('')}<button type="button" class="mib-smile" data-mib="react-menu" data-tid="${esc(t.id)}" data-cid="${esc(c.id)}" title="React" aria-label="React">${icon('smile')}</button></div>`;
      const box = upd({ ...n, from: c.authorId, at: c.at }, text, commentFiles(c.attachments || []), faded, rx);
      return parent ? `<div class="mib-thread"><div class="mib-thread-l">In ${esc(nameOf(parent.authorId))}’s thread</div>${box}</div>` : box;
    }).join('');
    const minen = g.items.find((x) => x.mine && x.mine.reply);
    const yours = minen ? `<div class="mib-yours">${upd({ from: currentUserId, at: minen.mine.at }, esc(minen.mine.reply)).replace(`<b>${esc(nameOf(currentUserId))}</b>`, '<b>You replied</b>')}</div>` : '';
    let reply = '';
    if (lastComment) {
      const root = lastComment.parentId || lastComment.id;
      const rootC = (t.comments || []).find((x) => x.id === root);
      const to = firstName(lastComment.authorId);
      const where = lastComment.parentId ? `Replies in ${esc(nameOf(rootC ? rootC.authorId : lastComment.authorId))}’s thread` : `Starts a thread under ${esc(to)}’s comment`;
      reply = `<div class="mib-reply"><div class="mib-where">↳ ${where}</div><div class="mib-up" hidden></div><div class="mib-box"><button type="button" class="mib-add" data-mib="attach" title="Attach files" aria-label="Attach files">${icon('plus')}</button><textarea rows="1" class="mib-in" placeholder="Reply to ${esc(to)}…" data-tid="${esc(t.id)}" data-root="${esc(root)}"></textarea>
        <button type="button" class="mib-send" data-mib="send" title="Send" disabled><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M5.5 11.5 12 5l6.5 6.5"/></svg></button></div></div>`;
    }
    return head(t ? statusIcon(t, 16) : '', t ? (t.title || 'Untitled task') : 'Deleted task', taskLine(t), unreadBtn(g) + openBtn(g, 'Open Task'))
      + cap(`${items.length} update${items.length === 1 ? '' : 's'} · newest last`) + `<div class="mib-ups">${ups}${yours}</div>${reply}`;
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
    const pic = (x) => { const gr = Plans.progress(x); const img = (gr.files || []).find((r) => fileKind(r) === 'image') || (x.refs || []).find((r) => r.path && fileKind(r) === 'image'); return img ? `<img src="${imgUrl(img, 160)}" alt="" loading="lazy">` : ''; };
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
    if (k !== pick) { dyOpen = null; pending = []; }
    pick = k;
    const g = rows().list.find((x) => x.key === k);
    if (g && g.items.some((x) => !x.read)) markRead(g); else renderContent();
  }
  function send(btnEl) {
    const box = btnEl.closest('.mib-box'), ta = box && box.querySelector('.mib-in');
    const text = ta ? ta.value.trim() : '';
    if (!text && !pending.length) return;
    const t = task(ta.dataset.tid);
    if (!t) return;
    const html = esc(text).replace(/\n/g, '<br>');
    const files = pending.splice(0);
    files.forEach((a) => { if (!(t.attachments || []).some((x) => x.path === a.path)) (t.attachments = t.attachments || []).push(a); });
    postComment(t, ta.dataset.root, text, html, files);
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
  // + in the reply box: the Mac's own file picker, as a comment's (the files go up first, then with the reply)
  let pending = [];
  async function attach(el) {
    const ta = document.querySelector('.mib-in'), t = ta && task(ta.dataset.tid);
    if (!t) return;
    try {
      const res = await Host.call('pickAttachments', { taskId: t.id });
      const got = (res.files || []).filter(Boolean).map((f) => ({ ...f, addedAt: nowISO(), addedBy: currentUserId }));
      if (!got.length) return;
      pending = pending.concat(got);
      const up = document.querySelector('.mib-up');
      if (up) { up.hidden = false; up.innerHTML = pending.map((a) => `<span class="mib-file static">${esc(a.name)}</span>`).join(''); }
      const b = document.querySelector('.mib-send'); if (b) b.disabled = false;
    } catch (e) { toast('Upload failed — try again'); }
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
    else if (a === 'task') { if (task(el.dataset.id)) openTask(el.dataset.id); else toast('That task isn’t there anymore'); }
    else if (a === 'pv') { const list = tileSets[Number(el.dataset.set)] || []; const f = list[Number(el.dataset.i)]; if (f) previewFile(f, list); }
    else if (a === 'attach') attach(el);
    else if (a === 'rv-ok') { const f = findReview(el.dataset.id); if (f) { decideReview(f.t, f.r, 'approve'); toast(`Approved — ${firstName(f.r.by)} told`); renderContent(); } }
    else if (a === 'rv-amend') { decisionDialog(el.dataset.id); const b = document.querySelector('#overlay-root [data-d="amend"]'); if (b) b.click(); }
    else if (a === 'plan-ok') { const pl = Plans.planById(el.dataset.id); if (pl) Promise.resolve(Plans.approve(pl)).then(() => renderContent()); }
    else if (a === 'plan-back') { const pl = Plans.planById(el.dataset.id); if (pl) Plans.sendBack(pl); }
    else if (a === 'dy-sec') { dyOpen = dyOpen === el.dataset.k ? '' : el.dataset.k; renderContent(); }
    else if (a === 'dy-all') { if (window.__e11Daily) window.__e11Daily({ ev: 'all', k: el.dataset.k }); }
    else if (a === 'file') { const t = task(el.dataset.tid), c = t && (t.comments || []).find((x) => x.id === el.dataset.cid); const f = c && (c.attachments || []).find((x) => x.id === el.dataset.id); if (f) previewFile(f, c.attachments); }
  });
  document.addEventListener('input', (e) => {
    const ta = e.target.closest && e.target.closest('.mib-in');
    if (!ta) return;
    ta.style.height = 'auto'; ta.style.height = Math.min(ta.scrollHeight, 140) + 'px';
    const b = ta.parentElement.querySelector('.mib-send'); if (b) b.disabled = !ta.value.trim() && !pending.length;
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
