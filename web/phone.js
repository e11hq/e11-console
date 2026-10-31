/* E11 Console — phone layout.
   On small screens (iPhone, narrow windows) the sidebar is replaced by a bottom tab bar and the
   lists become simple cards. Everything else — data, sync, permissions, the task page logic —
   is shared with the desktop app in app.js. The Mac app always keeps the desktop layout. */
const Phone = (() => {
  const mq = window.matchMedia('(max-width: 760px)');
  const OWN = new Set(['home', 'today', 'mytasks', 'inbox', 'reviews', 'review', 'me', 'projects', 'project', 'psearch']);
  const TITLES = { calendar: 'Content calendar', plans: 'Content plans', trash: 'Trash', profile: 'My profile', team: 'Team members', updates: 'App updates', clients: 'Client Assets', client: 'Client Assets' };
  const st = { on: false, ibf: 'unread', q: '' };

  const isOn = () => st.on;
  function check() {
    // Finance people use the Finance pages, which are built for every screen size (no phone tabs)
    const v = mq.matches && !(typeof Host !== 'undefined' && Host.isMacApp) && !(typeof db !== 'undefined' && db && currentUserId && typeof isFinUser === 'function' && isFinUser());
    if (v === st.on) return;
    st.on = v;
    document.body.classList.toggle('phone', v);
    document.documentElement.classList.toggle('phone', v);
    noZoom(v);
    if (!v && typeof unpin === 'function') unpin();
    if (typeof db !== 'undefined' && db && currentUserId) render();
  }
  mq.addEventListener ? mq.addEventListener('change', check) : mq.addListener(check);

  // No pinch or double-tap zoom in the phone layout: it should feel like an app, not a web page.
  // iPhone Safari ignores user-scalable=no on its own, so the pinch gesture itself is stopped too.
  const VP_APP = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
  const VP_WEB = 'width=device-width, initial-scale=1, viewport-fit=cover';
  function noZoom(on) {
    const m = document.querySelector('meta[name="viewport"]');
    if (m) m.setAttribute('content', on ? VP_APP : VP_WEB);
  }
  const stopPinch = (e) => { if (st.on) e.preventDefault(); };
  ['gesturestart', 'gesturechange', 'gestureend'].forEach((ev) => document.addEventListener(ev, stopPinch, { passive: false }));
  document.addEventListener('touchmove', (e) => { if (st.on && e.touches && e.touches.length > 1) e.preventDefault(); }, { passive: false });

  // iPhone Home Screen apps can report a page shorter than the screen, which leaves a gap under
  // everything pinned to the bottom. Measure the real height and pin to the true bottom edge.
  // Where does "the bottom" (bottom: 0) really land? A tiny probe pinned there tells us, so the
  // correction is always based on what the phone is doing right now, not on a number it reported once.
  let probe = null, lastKey = '';
  function measure() {
    const root = document.documentElement;
    if (!probe && document.body) { probe = document.createElement('i'); probe.style.cssText = 'position:fixed;left:0;bottom:0;width:0;height:0;padding-top:env(safe-area-inset-top);box-sizing:content-box;pointer-events:none;visibility:hidden'; document.body.appendChild(probe); }
    const standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
    const bottom = probe ? probe.getBoundingClientRect().bottom : window.innerHeight; // where bottom:0 sits now
    let h = Math.max(bottom, window.innerHeight);
    // only an app that draws under the status bar (no space reserved at the top) can come up short
    const underBar = probe && parseFloat(getComputedStyle(probe).paddingTop) > 0;
    root.classList.toggle('ph-underbar', !!(standalone && underBar)); // headers move down past iOS's blurred band
    if (standalone && underBar) {
      const full = window.innerHeight > window.innerWidth ? Math.max(screen.height, screen.width) : Math.min(screen.height, screen.width);
      if (full > h && full - h < 140) h = full; // not when the keyboard is open (that shrinks it a lot more)
    }
    if (typeof Host !== 'undefined' && Host.isIOSApp) h = Math.round(bottom);
    const shift = Math.min(0, Math.round(bottom - h));
    const key = h + '/' + shift;
    if (key === lastKey) return;
    lastKey = key;
    root.style.setProperty('--app-h', h + 'px');
    root.style.setProperty('--ph-shift', shift + 'px');
  }
  measure();
  window.addEventListener('resize', measure);
  window.addEventListener('orientationchange', () => setTimeout(measure, 300));
  window.addEventListener('pageshow', () => { measure(); setTimeout(measure, 300); });
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { measure(); setTimeout(measure, 300); setTimeout(measure, 1000); } });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', measure);
  // the phone can settle on its real size a moment after opening without telling the page: keep checking
  setInterval(() => { if (st.on && !document.hidden) measure(); }, 1000);

  const socialPlans = () => { const u = typeof me === 'function' ? me() : null; return !!u && u.role === 'social' && typeof Plans !== 'undefined' && Plans.canSee(u); };
  const tabOf = (v) => (v === 'home' ? 'today' : v === 'review' ? 'reviews' : v === 'project' ? 'projects' : v === 'plan' ? 'plans' : v);
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;

  /* ---------- Bottom tab bar ---------- */
  function chrome() {
    if (!st.on) return;
    let bar = document.getElementById('ph-tabs');
    if (!bar) { bar = document.createElement('nav'); bar.id = 'ph-tabs'; document.body.appendChild(bar); }
    const unread = myNotifs().filter((n) => !n.read).length;
    const cd = isCD();
    const rv = cd ? activeReviews().length : 0;
    const cur = tabOf(ui.view);
    const tab = (v, ic, label, badge) => `<button class="ph-tab ${cur === v ? 'on' : ''}" data-ph-tab="${v}">${icon(ic)}${badge ? `<i class="ph-badge">${badge > 99 ? '99+' : badge}</i>` : ''}<span>${label}</span></button>`;
    bar.innerHTML = isOffice()      // an Office Admin: no task pages
      ? tab('today', 'home', 'Home') + tab('inbox', 'inbox', 'Inbox', unread) + tab('clients', 'assets', 'Client Assets') + tab('me', 'user', 'Me')
      : tab('today', 'sun', Work.dayTitle())
      + tab('mytasks', 'check-circle', 'My Tasks')
      + tab('inbox', 'inbox', 'Inbox', unread)
      + (cd ? tab('reviews', 'shield', 'Reviews', rv)
        // Social: their month's content plans instead of Clients (while content plans are on)
        : socialPlans() ? tab('plans', 'cal', 'Plans', Plans.waiting()) : tab('projects', 'folder', 'Clients'))
      + tab('me', 'user', 'Me');
    stopFling();
    bar.hidden = !!ui.taskId;
    document.body.classList.toggle('task-open', !!ui.taskId);
    nativeTabs(bar);
    const top = document.getElementById('ph-top'); if (top) { top.hidden = !top.firstElementChild; if (!ui.taskId && top.firstElementChild) document.documentElement.style.setProperty('--ph-head-h', top.offsetHeight + 'px'); }
  }

  // A flick on one page mustn't keep scrolling the next one (the pages share one scrolling box): when the page
  // changes, the scrolling is stopped dead (switching scrolling off for a moment is what stops iPhone's glide)
  let pageKey = '';
  function stopFling() {
    const k = [ui.view, ui.projectId, ui.clientId, ui.folderId].join('|');
    if (k === pageKey) return;
    pageKey = k;
    const c = document.getElementById('content');
    if (!c) return;
    c.style.overflowY = 'hidden';
    void c.offsetHeight;
    c.scrollTop = 0;
    requestAnimationFrame(() => { c.style.overflowY = ''; });
  }

  // The iPhone app draws a real (native) tab bar from the same tabs; tapping one taps the page's own button
  let tabsSent = '';
  function nativeTabs(bar) {
    if (typeof Host === 'undefined' || !Host.isIOSApp) return;
    const tabs = [...bar.querySelectorAll('[data-ph-tab]')].map((b) => ({ v: b.dataset.phTab, label: (b.querySelector('span') || {}).textContent || '', badge: (b.querySelector('.ph-badge') || {}).textContent || '', on: b.classList.contains('on') }));
    // (the native bar sits above the page, so it steps aside for anything that rises from the bottom, and stays
    //  away until the startup animation has gone)
    const ph = mePhoto();
    const u0 = typeof me === 'function' ? me() : null;
    if (ph) tabs.forEach((t) => { if (t.v === 'me') { t.photo = ph; if (u0 && u0.avatar) t.photoUrl = new URL(fileUrl({ path: u0.avatar }), location.href).href; } });
    // (22+: the app's own startup screen is over everything — the bar comes under it, ready when it goes)
    const splashCovers = !window.__e11NativeSplashOn && !!document.querySelector('#splash');
    const msg = JSON.stringify({ tabs, hidden: !!ui.taskId || splashCovers || !!document.querySelector('.scrim, .menu:not(.mention-pop), #ph-sheet-root .ph-scrim:not(.docked), #overlay-root > *, #pv-root > *') });
    if (msg === tabsSent) return;
    tabsSent = msg;
    NativeMac.call('setTabs', JSON.parse(msg)).catch(() => {});
  }
  if (typeof Host !== 'undefined' && Host.isIOSApp) {
    // anything rising from the bottom (sheet, menu, dialog) appears or goes: tell the app again (it only sends on a
    // change). The whole page is watched, since sheets and menus are made and dropped in several places.
    let q = 0;
    const again = () => { if (q) return; q = requestAnimationFrame(() => { q = 0; const bar = document.getElementById('ph-tabs'); if (bar && st.on) nativeTabs(bar); }); };
    const watch = () => new MutationObserver((list) => {
      if (list.some((m) => m.type === 'childList' ? m.target === document.body || (m.target.closest && m.target.closest('#ph-sheet-root, #overlay-root')) : (m.target.classList && m.target.classList.contains('ph-scrim')))) again();
    }).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
    if (document.body) watch(); else document.addEventListener('DOMContentLoaded', watch);
  }
  // the Me tab shows your own picture (or your initials on your colour), drawn here and handed to the app as a PNG
  let photo = { key: '', url: '' };
  function mePhoto() {
    const u = typeof me === 'function' ? me() : null;
    if (!u) return '';
    const key = (u.avatar || '') + '|' + fullName(u);
    if (photo.key === key) return photo.url;
    photo = { key, url: '' };
    const S = 84, c = document.createElement('canvas'); c.width = c.height = S;
    const g = c.getContext('2d');
    const round = () => { g.beginPath(); g.arc(S / 2, S / 2, S / 2, 0, Math.PI * 2); g.closePath(); g.clip(); };
    const initialsPic = () => {
      g.save(); round(); g.fillStyle = avColor(u.id); g.fillRect(0, 0, S, S);
      g.fillStyle = '#fff'; g.font = '600 34px -apple-system, system-ui, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText(initials(fullName(u)), S / 2, S / 2 + 1); g.restore();
      return c.toDataURL('image/png');
    };
    if (!u.avatar) { photo.url = initialsPic(); return photo.url; }
    const img = new Image();
    img.onload = () => {
      if (photo.key !== key) return;
      g.save(); round();
      const k = Math.max(S / img.width, S / img.height), w = img.width * k, h = img.height * k;
      g.drawImage(img, (S - w) / 2, (S - h) / 2, w, h); g.restore();
      try {
        // (a picture that drew nothing — size unknown, not decoded — would leave an empty circle: initials then)
        if (!img.naturalWidth || g.getImageData(S / 2, S / 2, 1, 1).data[3] === 0) throw new Error('blank');
        photo.url = c.toDataURL('image/png');
      } catch (e) { g.clearRect(0, 0, S, S); photo.url = initialsPic(); }
      const bar = document.getElementById('ph-tabs'); if (bar) nativeTabs(bar);
    };
    img.onerror = () => { if (photo.key === key) { photo.url = initialsPic(); const bar = document.getElementById('ph-tabs'); if (bar) nativeTabs(bar); } };
    img.src = fileUrl({ path: u.avatar });
    return '';
  }
  // (then the app's own Home is told at once whether it's on: it stays up while the page draws the other tab, and goes
  //  the moment that tab is there — the page's own Home never shows in between)
  window.__e11Tab = (v) => { const b = document.querySelector(`#ph-tabs [data-ph-tab="${v}"]`); if (b) b.click(); if (typeof NativeHome !== 'undefined') NativeHome.sync(); };

  /* ---------- Pieces ---------- */
  function card(t, o = {}) {
    const p = proj(t.projectId);
    const s = statusInfo(t);
    const open = !t.done && !partDone(t);
    const late = open && t.due && dayDiff(t.due) < 0;
    const bits = [];
    bits.push(p ? `<i class="ph-dot" style="background:${p.color}"></i>${esc(p.name)}` : 'My Tasks');
    if (o.status !== false) bits.push(esc(s.name));
    if (t.due && o.due !== false) bits.push(`<b class="${late ? 'late' : dayDiff(t.due) === 0 && open ? 'today' : ''}">${esc(mwDue(t))}</b>`);
    if (t.comments.length) bits.push(plural(t.comments.length, 'comment'));
    const pr = prioOf(t);
    const badge = isUrgent(t) && !t.done ? '<span class="ph-tag urgent">Urgent</span>'
      : typeof normPrio(pr) === 'number' ? `<span class="ph-tag">${normPrio(pr)}</span>` : '';
    return `<div class="pc ${late ? 'late' : ''} ${t.done ? 'done' : ''}" data-task="${t.id}">
      <span class="pc-ic">${statusIcon(t, 22)}</span>
      <span class="pc-body"><span class="pc-title">${t.title ? (o.mark ? sMark(t.title, o.mark) : esc(t.title)) : '<i>Untitled task</i>'}</span>
        <span class="pc-meta">${bits.join('<em>·</em>')}</span>
        ${t.cdStatus && !t.done ? `<span class="pc-cd">${cdChip(t)}</span>` : ''}</span>
      <span class="pc-side">${badge}${avatarStack(t.assignees, 22, 2, t)}</span>
    </div>`;
  }
  const group = (name, tasks, o = {}) => (tasks.length || o.empty
    ? `<div class="ph-gh">${esc(name)}${tasks.length ? `<span>${tasks.length}</span>` : ''}</div>${tasks.map((t) => card(t, o)).join('') || `<div class="ph-empty">${o.empty}</div>`}`
    : '');
  const fab = () => (can('createTask') ? `<button class="ph-fab" data-ph="quick-add" aria-label="New task">${icon('plus')}</button>` : '');
  function head(title, sub, right = '') {
    return `<header class="ph-head"><div class="ph-hl">${sub ? `<div class="ph-sub">${sub}</div>` : ''}<h1>${title}</h1></div>${right}</header>`;
  }
  const backHead = (title, back, right = '') => `<header class="ph-bar"><button class="ph-back" ${back} aria-label="Back">${icon('chev-left')}</button><b>${title}</b>${right || '<span class="ph-bar-sp"></span>'}</header>`;

  /* ---------- Screens ---------- */
  // what Home shows (also the iPhone app's own Home, 23+: NativeHome)
  // (the rules are shared with the server: web/rules.js — the iPhone app gets the same Home from /api/home)
  function myDayData() { return E11Rules.make(db, currentUserId, todayStr()).myDayData(); }
  function myDay() {
    const { overdue, due, going, done, review } = myDayData();
    const d = new Date();
    return `<div class="ph-page">
      ${head(Work.dayTitle(), esc(d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })),
        `<button class="ph-round" data-ph="search" aria-label="Search">${icon('search')}</button><button class="ph-me" data-ph-tab="me" aria-label="Me">${avatarHTML(currentUserId, 40)}</button>`)}
      <div class="ph-stats">
        <div><b class="g">${due.length}</b><span>Due today</span></div>
        <div><b class="r">${overdue.length}</b><span>Overdue</span></div>
        <div><b class="a">${review}</b><span>In review</span></div>
      </div>
      <div class="ph-list">
        ${group('Overdue', overdue)}
        ${group('Today', due, { empty: overdue.length ? 'Nothing else due today' : 'Nothing due today 🎉' })}
        ${group('In progress', going)}
        ${group('Completed today', done, { status: false })}
      </div>
      ${fab()}
    </div>`;
  }

  // (iPhone app 10+: Pager — every tab's list is drawn side by side and iOS swipes between them)
  const pgOn = () => typeof Pager !== 'undefined' && Pager.lists();
  const pgCols = (key, cur, cols) => `<div class="pg-wrap" data-pg="${key}" data-cur="${cur}">${cols.map(([k, html]) => `<div class="pg-col" data-k="${k}">${html}</div>`).join('')}</div>`;
  function myTasks() {
    const tab = ui.myTasksTab === 'done' ? 'done' : 'todo';
    const L = Work.list(), doneAt = Work.doneAtOf;
    const open = L.filter(Work.openOf);
    const bodyOf = (tb) => {
      if (tb === 'done') {
        const cutoff = Date.now() - AUTO_DELETE_DAYS * 86400000;
        const list = L.filter((t) => doneAt(t) && new Date(doneAt(t)).getTime() > cutoff).sort((a, b) => doneAt(b).localeCompare(doneAt(a)));
        return group('Last 30 days', list, { empty: 'Tasks you complete show here.', status: false });
      }
      return group('Overdue', open.filter((t) => t.due && dayDiff(t.due) < 0).sort(byDayThenPrio))
        + group('Today', open.filter((t) => t.due && dayDiff(t.due) === 0).sort(byDayThenPrio), { empty: 'Nothing due today 🎉' })
        + group('Next', open.filter((t) => t.due && dayDiff(t.due) > 0).sort(byDayThenPrio))
        + group('No due date', open.filter((t) => !t.due).sort((a, b) => byPrio(a, b) || a.createdAt.localeCompare(b.createdAt)));
    };
    const seg = `<div class="ph-seg"><button class="${tab === 'todo' ? 'on' : ''}" data-action="mt-tab" data-tab="todo" data-pg-k="todo">To Do</button><button class="${tab === 'done' ? 'on' : ''}" data-action="mt-tab" data-tab="done" data-pg-k="done">Done</button></div>`;
    if (pgOn()) return `<div class="ph-page pg-page">
      ${head('My Tasks', plural(open.length, 'open task'))}
      ${seg}
      ${workFilterBar()}
      ${pgCols('mytasks', tab, [['todo', `<div class="ph-list">${bodyOf('todo')}</div>`], ['done', `<div class="ph-list">${bodyOf('done')}</div>`]])}
      ${fab()}
    </div>`;
    return `<div class="ph-page">
      ${head('My Tasks', plural(open.length, 'open task'))}
      ${seg}
      ${workFilterBar()}
      <div class="ph-list">${bodyOf(tab)}</div>
      ${fab()}
    </div>`;
  }

  function inbox() {
    const all = myNotifs();
    const unreadN = all.filter((n) => !n.read).length;
    const f = st.ibf;
    const rowsOf = (ff) => {
      const list = all.filter((n) => (ff === 'unread' ? !n.read : ff === 'mentions' ? n.kind === 'mention' : true)).sort((a, b) => b.at.localeCompare(a.at));
      const byTask = new Map();
      list.forEach((n) => { const k = notifKey(n); if (!byTask.has(k)) byTask.set(k, []); byTask.get(k).push(n); });
      const rows = [...byTask.values()].slice(0, 200).map((items) => {
        const n = items[0];
        const t = task(n.taskId);
        const unread = items.some((x) => !x.read);
        const target = ibTarget(items);   // (opens what the row shows: the newest, or an unread one needing action)
        return `<div class="ph-ib ${unread ? 'unread' : ''}" data-action="open-notif" data-id="${target.id}">
        ${avatarHTML(target.from, 40)}
        <span class="ph-ib-b"><span class="ph-ib-m">${notifMsg(target, t)}</span>
          <span class="ph-ib-t">${n.kind === 'sched-cancel' ? `Scheduled ${/scheduled reply/.test(n.text || '') ? 'reply' : 'comment'}` : t ? esc(t.title || 'Untitled task') : n.kind === 'birthday' ? 'Birthday' : n.kind === 'daily' ? 'Morning round-up' : /^claim/.test(n.kind) ? 'Expense claims' : n.kind === 'asset' ? esc(assetTitle(n)) : n.planId ? esc(planTitle(n)) : '<i>Deleted task</i>'}</span>
          <span class="ph-ib-w">${esc(timeAgo(n.at))}${items.length > 1 ? ` · ${items.length} updates` : ''}</span></span>
        ${unread ? '<i class="ph-ib-dot"></i>' : ''}
      </div>`;
      }).join('');
      return `<div class="ph-ibl">${rows || `<div class="ph-empty big">${ff === 'unread' ? 'Inbox zero 🎉<small>New updates and @mentions land here.</small>' : 'Nothing here yet'}</div>`}</div>`;
    };
    const chip = (k, l) => `<button class="${f === k ? 'on' : ''}" data-ph="ibf" data-k="${k}" data-pg-k="${k}"><span>${l}</span></button>`;
    const top = `${head('Inbox', unreadN ? plural(unreadN, 'unread update') : 'All caught up', unreadN ? '<button class="ph-pill" data-action="mark-all-read">Mark all read</button>' : '')}
      <div class="ph-chips">${chip('unread', `Unread${unreadN ? ' ' + unreadN : ''}`)}${chip('all', 'All')}${chip('mentions', 'Mentions')}</div>`;
    if (pgOn()) return `<div class="ph-page pg-page">${top}${pgCols('inbox', f, ['unread', 'all', 'mentions'].map((k) => [k, rowsOf(k)]))}</div>`;
    return `<div class="ph-page">
      ${top}
      ${rowsOf(f)}
    </div>`;
  }


  function reviews() {
    if (!isCD()) return `<div class="ph-page">${head('Reviews')}<div class="ph-empty big">Only the Creative Director sees review requests</div></div>`;
    const list = activeReviews();
    return `<div class="ph-page">
      ${head('Reviews', list.length ? plural(list.length, 'request') + ' waiting' : 'Nothing waiting')}
      <div class="ph-list">${list.map(({ t, r }) => {
        const p = proj(t.projectId);
        const n = (r.files || []).length;
        return `<div class="pc rv" data-ph="open-review" data-id="${r.id}" data-review="${r.id}">
          ${avatarHTML(r.by, 40)}
          <span class="pc-body"><span class="pc-title">${esc(t.title || 'Untitled task')}</span>
            <span class="pc-meta">${p ? `<i class="ph-dot" style="background:${p.color}"></i>${esc(p.name)}<em>·</em>` : ''}${esc(firstName(r.by))} sent ${plural(n, 'file')} · ${esc(timeAgo(r.at))}</span></span>
          ${r.round > 1 ? `<span class="ph-tag amber">Round ${r.round}</span>` : ''}
        </div>`;
      }).join('') || '<div class="ph-empty big">All caught up 🎉<small>New submissions appear here, and you get a notification.</small></div>'}</div>
    </div>`;
  }

  function fileSlide(t, a) {
    const k = fileKind(a), url = fileUrl(a);
    let m;
    if (k === 'image') m = `<img src="${imgUrl(a, 1280)}" alt="" loading="lazy">`;
    else if (k === 'video') m = `<span class="vcover">${videoTag(a, '', `data-thumb-task="${t.id}"`, false)}${videoPlay()}</span>`;   // (plays in the preview)
    else m = a.thumb ? `<img src="${'/__file/' + a.thumb.split('/').map(encodeURIComponent).join('/')}" alt="">`
      : `<span class="ph-ext" ${Host.isNative ? `data-thumb-for="${a.id}" data-thumb-task="${t.id}" data-mode="slide"` : ''}>${esc((fileExt(a.name) || 'file').slice(0, 5))}</span>`;
    return `<div class="ph-slide"><div class="ph-media" data-ph="preview" data-tid="${t.id}" data-id="${a.id}">${m}</div><div class="ph-fname">${esc(a.name)}<small>${fmtSize(a.size)}</small></div></div>`;
  }
  function review() {
    const list = activeReviews();
    const i = list.findIndex((x) => x.r.id === ui.reviewId);
    const f = i >= 0 ? list[i] : findReview(ui.reviewId);
    if (!f || f.r.state !== 'pending') { ui.view = 'reviews'; return reviews(); }
    const { t, r } = f;
    const files = (r.files || []).map((id) => t.attachments.find((a) => a.id === id)).filter(Boolean);
    const desc = t.notesHtml ? notifPlainHTML(t.notesHtml) : t.notes;
    return `<div class="ph-page ph-rv">
      ${backHead(`<span class="ph-kick">Review request${i >= 0 ? ` · ${i + 1} of ${list.length}` : ''}</span>${esc(t.title || 'Untitled task')}`, 'data-ph-tab="reviews"', `<button class="ph-round sm" data-action="rr-open" data-id="${t.id}" aria-label="Open task">${icon('open')}</button>`)}
      <div class="ph-rv-by">${avatarHTML(r.by, 32)}<span><b>${esc(fullName(userById(r.by)))}</b> sent ${plural(files.length, 'file')} · ${esc(timeAgo(r.at))}</span>${r.round > 1 ? `<span class="ph-tag amber">Round ${r.round}</span>` : ''}</div>
      <div class="ph-slides" id="ph-slides">${files.map((a) => fileSlide(t, a)).join('') || '<div class="ph-slide"><div class="ph-media"><span class="ph-ext">No files</span></div></div>'}</div>
      ${files.length > 1 ? `<div class="ph-dots" id="ph-dots">${files.map((_, k) => `<i class="${k ? '' : 'on'}"></i>`).join('')}</div>` : ''}
      ${desc ? `<div class="ph-rv-desc">${esc(desc)}</div>` : ''}
      <div class="ph-rv-note">Swipe through the files. Your notes are posted on the task for ${esc(firstName(r.by))}.</div>
      <div class="ph-rv-acts"><button class="ph-btn amber" data-ph="amend" data-id="${r.id}">Request amendments</button><button class="ph-btn green" data-ph="approve" data-id="${r.id}">${icon('check')}Approve</button></div>
    </div>`;
  }

  function projects() {
    const list = db.projects.filter((p) => !p.inactive && amSidebarOk(p)).sort(byOrder);   // active clients (an AM: their own)
    return `<div class="ph-page">
      ${head('Clients', plural(list.length, 'client'))}
      <div class="ph-list">${list.map((p) => {
        const open = db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length;
        return `<div class="pc pj" data-ph="open-project" data-id="${p.id}"><span class="ph-pj-ic" style="background:${p.color}">${esc(initials(p.name))}</span>
          <span class="pc-body"><span class="pc-title">${esc(p.name)}</span><span class="pc-meta">${plural(open, 'open task')}</span></span>${icon('chev-right')}</div>`;
      }).join('') || '<div class="ph-empty big">No clients yet</div>'}</div>
    </div>`;
  }
  function project() {
    const p = proj(ui.projectId);
    if (!p) { ui.view = 'projects'; return projects(); }
    const showDone = !!ui.showDone[p.id];
    const body = p.sections.map((s) => {
      const all = db.tasks.filter((t) => t.projectId === p.id && t.sectionId === s.id && !t.parentId).sort((a, b) => urgentFirst(a, b) || byOrder(a, b));
      const ts = showDone ? all : all.filter((t) => !t.done);
      if (!ts.length) return '';
      return `<div class="ph-gh"><i class="ph-dot" style="background:${s.color}"></i>${esc(s.name)}<span>${ts.length}</span></div>${ts.map((t) => card(t, { status: false })).join('')}`;
    }).join('');
    const cl = clientOfProject(p);
    return `<div class="ph-page">
      ${backHead(esc(p.name), 'data-ph-tab="projects"', `<button class="ph-round sm" data-action="toggle-show-done" aria-label="${showDone ? 'Hide' : 'Show'} completed">${icon(showDone ? 'check-circle' : 'check')}</button>`)}
      ${cl ? `<button class="ph-client" data-action="open-client" data-id="${cl.id}">${clientLogoHTML(cl, 22)}<span>${esc(cl.name)} brand assets</span>${icon('chev-right')}</button>` : ''}
      <div class="ph-list">${body || `<div class="ph-empty big">No open tasks${showDone ? '' : '<small>Tap ✓ above to show completed tasks.</small>'}</div>`}</div>
      ${fab()}
    </div>`;
  }

  function meScreen() {
    const u = me();
    const admin = isAdm(u);
    const row = (attrs, ic, label, sub = '') => `<button class="ph-row" ${attrs}>${icon(ic)}<span>${label}${sub ? `<small>${sub}</small>` : ''}</span>${icon('chev-right')}</button>`;
    const light = document.documentElement.dataset.theme === 'light';
    return `<div class="ph-page">
      <div class="ph-me-card">${avatarHTML(u.id, 64)}<div><b>${esc(fullName(u))}</b><span>${esc(designationOf(u))}</span><small>${esc(u.email)}</small></div></div>
      <div class="ph-rows">
        ${row('data-nav="profile"', 'user', 'My profile', 'Photo, office and notifications')}
        ${isCD() ? row('data-ph-tab="projects"', 'folder', 'Clients') : ''}
        ${Cal.canSee() && !calendarRetired() ? row('data-nav="calendar"', 'cal', 'Content calendar', 'Posts by day, channel and occasion') : ''}
        ${Plans.canSee() ? row('data-nav="plans"', 'cal', 'Content plans', 'Each client’s month') : ''}
        ${row('data-nav="clients"', 'assets', 'Client Assets', 'Logos, guidelines and fonts')}
        ${row('data-nav="team"', 'users', 'Team members')}
        ${isManager() ? row('data-nav="trash"', 'trash', 'Trash', trashList().length ? `${trashList().length} item${trashList().length === 1 ? '' : 's'} · restore within ${TRASH_DAYS} days` : `Deleted items wait here ${TRASH_DAYS} days`) : ''}
        ${AppIcon.isOwner() && Host.isServer ? row('data-nav="updates"', 'download', 'App updates') : ''}
        ${isTestCopy() && AppIcon.isOwner() && !(typeof ViewAs !== 'undefined' && ViewAs.viewing()) ? row('data-ph="sample"', 'trash', 'Start fresh with sample data', 'Test site only: wipes everything except you') : ''}
      </div>
      <div class="ph-rows">
        ${typeof Push !== 'undefined' ? Push.row() : ''}
        ${Host.isServer && Digest.wants({ ...u, prefs: {} }) ? `<button class="ph-row" data-action="toggle-digest">${icon('sun')}<span>Morning summary<small>10:30 am, Monday to Friday · switch off for holidays</small></span><i class="ph-state ${(u.prefs || {}).digestOff ? '' : 'on'}">${(u.prefs || {}).digestOff ? 'Off' : 'On'}</i></button>` : ''}
        <div class="ph-row ph-theme"><div class="pt-top">${icon(light ? 'sun' : 'moon')}<span>Appearance<small>${Theme.mode() === 'auto' ? 'Follows sunrise and sunset' : 'Always ' + Theme.mode()}</small></span></div>${Theme.picker('ph-seg-sm')}</div>
        ${Host.isServer ? '<button class="ph-row" data-action="whats-new">' + icon('info') + '<span>What’s new</span>' + icon('chev-right') + '</button>' : ''}
      </div>
      ${typeof ViewAs !== 'undefined' && ViewAs.available() ? `<div class="ph-rows"><button class="ph-row" data-va="pick">${icon('users')}<span>View as…<small>Test site only — use the app as a team member</small></span></button>${ViewAs.viewing() ? `<button class="ph-row" data-va="me">${icon('reply')}<span>Back to me</span></button>` : ''}</div>` : ''}
      <div class="ph-rows"><button class="ph-row danger" data-ph="sign-out">${icon('logout')}<span>Sign out</span></button></div>
      ${Host.isServer && Sync.version ? `<div class="ph-ver">E11 Console ${esc(Sync.version)}</div>` : ''}
    </div>`;
  }

  function search() {
    return `<div class="ph-page">
      ${backHead('Search', 'data-ph-tab="today"')}
      <div class="ph-search">${icon('search')}<input id="ph-q" type="search" name="e11-search" aria-autocomplete="none" data-form-type="other" placeholder="Search tasks" value="${esc(st.q)}" autocomplete="off"></div>
      <div class="ph-list" id="ph-results">${results()}</div>
    </div>`;
  }
  function results() {
    const q = st.q.trim();
    if (!q) return '<div class="ph-empty">Search titles, clients, people, tags, descriptions and comments. Try “overdue”, “urgent” or “mine” too.</div>';
    const r = taskSearch(q, { limit: 80 });
    const projects = r.projects.map((p) => `<div class="pc pj" data-ph="open-project" data-id="${p.id}"><span class="ph-pj-ic" style="background:${p.color}">${esc(initials(p.name))}</span>
      <span class="pc-body"><span class="pc-title">${sMark(p.name, r)}</span><span class="pc-meta">Client · ${plural(db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length, 'open task')}</span></span>${icon('chev-right')}</div>`).join('');
    const tasks = r.tasks.map((h) => { const why = searchWhy(h, r); return card(h.t, { mark: r }) + (why ? `<div class="ph-why">${why}</div>` : ''); }).join('');
    return (r.fixed.length ? searchFixedNote(r) : '')
      + (projects ? `<div class="ph-gh">Clients<span>${r.projects.length}</span></div>${projects}` : '')
      + (tasks ? `<div class="ph-gh">Tasks<span>${r.total}</span></div>${tasks}` : (projects ? '' : '<div class="ph-empty">No tasks found. Try a client or person’s name.</div>'));
  }

  /* ---------- Hooks called from app.js ---------- */
  function renderContent(c) {
    if (!st.on || ui.search || !OWN.has(ui.view)) return false;
    const v = ui.view;
    c.innerHTML = v === 'home' || v === 'today' ? (isOffice() ? OfficeHome.view() : myDay()) : v === 'mytasks' ? myTasks() : v === 'inbox' ? inbox()
      : v === 'reviews' ? reviews() : v === 'review' ? review() : v === 'projects' ? projects() : v === 'project' ? project()
      : v === 'psearch' ? search() : meScreen();
    if (ui.view === 'review') { wireSlides(c); hydrateThumbs(c); }
    if (v === 'inbox' && typeof fitWords === 'function') c.querySelectorAll('.ph-ib-t').forEach(fitWords);   // (task names cut at a whole word)
    pinHead(c);
    document.body.classList.toggle('ph-fab-on', !!document.querySelector('#ph-fabslot .ph-fab'));
    document.body.classList.toggle('ph-strip', !c.querySelector('.ph-bar'));
    return true;
  }
  // Pages shared with the desktop (profile, team, Client Assets…) get a phone header with a back button
  function decorate(c) {
    if (!st.on || OWN.has(ui.view)) return;
    document.body.classList.remove('ph-fab-on', 'ph-strip');
    let title = TITLES[ui.view] || 'E11 Console', back = 'data-ph-tab="me"';
    if (ui.view === 'client') {
      const cl = clientById(ui.clientId);
      const f = cl && cl.folders.find((x) => x.id === ui.folderId);
      title = esc(f ? f.name : cl ? cl.name : 'Client Assets');
      const up = f && f.parentId ? cl.folders.find((x) => x.id === f.parentId) : null;
      back = up ? `data-action="open-cfolder" data-id="${up.id}"` : f ? `data-action="open-client" data-id="${cl.id}"` : 'data-nav="clients"';
    }
    if (ui.view === 'plan') { const pl = Plans.planById(ui.planId), p = pl && proj(pl.projectId); title = p ? `${esc(p.name)} · ${esc(Plans.monthLabel(pl.month))}` : 'Content plan'; back = 'data-nav="plans"'; }
    if (ui.search) { title = 'Search'; back = 'data-ph-tab="today"'; }
    // Content plans as a Social person's own tab: a tab's page, so no back button
    if (ui.view === 'plans' && socialPlans() && !ui.search) c.insertAdjacentHTML('afterbegin', `<header class="ph-bar ph-bar-root"><b>${title}</b><span class="ph-bar-sp"></span></header>`);
    else c.insertAdjacentHTML('afterbegin', backHead(title, back));
    pinHead(c);
  }
  // iOS 26 softens the top edge of anything that scrolls, so page headers live in a fixed layer
  // above the scrolling content (like the task page header, which stays sharp).
  function pinHead(c) {
    let top = document.getElementById('ph-top');
    if (!top) { top = document.createElement('div'); top.id = 'ph-top'; document.body.appendChild(top); }
    top.innerHTML = '';
    const h = c.querySelector(':scope > .ph-bar, :scope > .ph-page > .ph-bar, :scope > .ph-page > .ph-head, :scope > .ph-page > .ph-me-card');
    if (h) top.appendChild(h);
    top.hidden = !h; // while a task is open it's only made invisible (CSS), so it can still be measured
    let slot = document.getElementById('ph-fabslot');
    if (!slot) { slot = document.createElement('div'); slot.id = 'ph-fabslot'; document.body.appendChild(slot); }
    slot.innerHTML = '';
    const fabEl = c.querySelector('.ph-fab');
    if (fabEl) slot.appendChild(fabEl);
    const set = () => document.documentElement.style.setProperty('--ph-head-h', (top.firstElementChild ? top.offsetHeight : 0) + 'px');
    set(); requestAnimationFrame(set);
    if (!top._ro && window.ResizeObserver) { top._ro = new ResizeObserver(set); top._ro.observe(top); }
  }
  function unpin() { const top = document.getElementById('ph-top'); if (top) { top.innerHTML = ''; top.hidden = true; } const sl = document.getElementById('ph-fabslot'); if (sl) sl.innerHTML = ''; document.documentElement.style.setProperty('--ph-head-h', '0px'); }
  // The task page header on the phone: back, title and the Details / Comments switch
  function taskHead(t, tab, n) {
    if (!st.on) return '';
    return `<div class="ph-task-head">
      <div class="ph-bar"><button class="ph-back" data-action="close-detail" aria-label="Back">${icon('chev-left')}</button><b>${esc(t.title || 'Untitled task')}</b>
        <button class="ph-round sm" data-ph="task-more" aria-label="More">${icon('more')}</button></div>
      <div class="ph-seg in-task"><button class="${tab === 'details' ? 'on' : ''}" data-action="side-tab" data-tab="details">Details</button><button class="${tab === 'comments' ? 'on' : ''}" data-action="side-tab" data-tab="comments">Comments${n ? ` <i>${n}</i>` : ''}</button></div>
    </div>`;
  }

  function wireSlides(c) {
    const s = c.querySelector('#ph-slides'), dots = c.querySelector('#ph-dots');
    if (!s || !dots) return;
    s.addEventListener('scroll', () => {
      const k = Math.round(s.scrollLeft / Math.max(1, s.clientWidth));
      [...dots.children].forEach((d, i) => d.classList.toggle('on', i === k));
    }, { passive: true });
  }

  /* ---------- Sheets ----------
     A sheet slides up from the bottom. Pulled down by its top:
     - nothing typed yet → it closes
     - something typed   → it tucks into a small bar above the tab bar; the rest of the app stays usable.
       Tap or pull the bar up to carry on; pull the tucked bar down again to throw it away. */
  const sheetRoot = () => {
    let r = document.getElementById('ph-sheet-root');
    if (!r) { r = document.createElement('div'); r.id = 'ph-sheet-root'; document.body.appendChild(r); }
    return r;
  };
  const docked = () => $('#ph-sheet-root .ph-scrim.docked');
  function sheet(html, onWire, o = {}) {
    const root = sheetRoot();
    const old = root.firstElementChild;
    // carry on with the tucked one (only a tucked one: a sheet still sliding away is replaced, or the new one
    // would vanish with it a moment later)
    if (old && old.dataset.kind === o.kind && old._expand && old.classList.contains('docked')) { old._expand(); return; }
    if (!o.quiet) Haptic.light();   // (the same light knock as every other sheet)
    root.innerHTML = `<div class="ph-scrim" data-kind="${o.kind || ''}"><div class="ph-sheet" role="dialog"><div class="ph-handle"><i class="ph-grab"></i></div>${html}<div class="ph-dock-hint">${esc(o.dockLabel || 'Draft')} · <b>Tap to continue</b></div></div></div>`;
    const scrim = root.firstElementChild;
    const box = scrim.firstElementChild;
    let closing = false;
    const setDockClass = () => document.body.classList.toggle('ph-docked', !!docked());
    const close = (discarded) => {
      if (closing || root.firstElementChild !== scrim) return;
      closing = true;
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      box.style.transition = ''; box.style.transform = '';
      scrim.classList.remove('in', 'docked');
      setDockClass();
      setTimeout(() => { if (root.firstElementChild === scrim) root.innerHTML = ''; }, 260);
      if (discarded === true) toast(o.discardedMsg || 'Draft discarded');
    };
    const dock = (instant) => {
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      // instant: the sheet has already slid down to where the bar sits, so swap without animating
      box.style.transition = instant ? 'none' : ''; box.style.transform = '';
      const t = box.querySelector('input:not([type]), input[type="text"], textarea');
      const hint = box.querySelector('.ph-dock-hint');
      hint.innerHTML = `${esc(o.dockLabel || 'Draft')}${t && t.value.trim() ? ` · <span>${esc(t.value.trim())}</span>` : ''} · <b>Tap to continue</b>`;
      scrim.classList.add('docked');
      setDockClass();
    };
    const expand = () => { box.style.transition = ''; box.style.transform = ''; scrim.classList.remove('docked'); scrim.classList.add('in'); setDockClass(); };
    scrim._expand = expand;
    const dirty = () => [...box.querySelectorAll('input:not([type]), input[type="text"], input[type="search"], textarea')].some((x) => x.value.trim());
    scrim.addEventListener('click', (e) => {
      if (scrim.classList.contains('docked')) { if (!e.target.closest('[data-sheet-close]')) { expand(); return; } }
      if (e.target.closest('[data-sheet-close]')) return close();
      if (e.target === scrim) { if (dirty()) dock(); else close(); }
    });
    requestAnimationFrame(() => scrim.classList.add('in'));
    dragSheet(scrim, box, { close, dock, expand, dirty });
    onWire && onWire(scrim, close);
  }
  function dragSheet(scrim, box, f) {
    let d = null;
    box.addEventListener('touchstart', (e) => {
      const t = e.touches[0];
      const isDocked = scrim.classList.contains('docked');
      const top = box.getBoundingClientRect().top;
      const onHandle = e.target.closest('.ph-handle, .ph-sh-head') && !e.target.closest('button');
      if (e.touches.length !== 1 || (!isDocked && !onHandle && (e.target.closest('button, input, select, textarea, label') || t.clientY - top > 64))) { d = null; return; }
      d = { y0: t.clientY, t0: Date.now(), dy: 0, h: box.offsetHeight, docked: isDocked, moved: false };
    }, { passive: true });
    box.addEventListener('touchmove', (e) => {
      if (!d) return;
      const raw = e.touches[0].clientY - d.y0;
      if (Math.abs(raw) > 6) d.moved = true;
      e.preventDefault();
      box.style.transition = 'none';
      if (d.docked) { d.dy = raw; box.style.transform = `translateY(${raw > 0 ? raw : raw / 3}px)`; return; }
      d.dy = Math.max(0, raw);
      box.style.transform = `translateY(${d.dy}px)`;
      scrim.style.background = `rgba(0,0,0,${0.55 * (1 - Math.min(1, d.dy / d.h))})`;
    }, { passive: false });
    const end = () => {
      if (!d) return;
      const cur = d; d = null;
      scrim.style.background = '';
      const fast = Math.abs(cur.dy) > 30 && Math.abs(cur.dy) / Math.max(1, Date.now() - cur.t0) > 0.5;
      const spring = () => { box.style.transition = 'transform .22s cubic-bezier(.2,.8,.2,1)'; box.style.transform = ''; };
      if (cur.docked) {
        if (cur.dy > 40 || (fast && cur.dy > 0)) { box.style.transition = 'transform .2s ease-in'; box.style.transform = 'translateY(140%)'; setTimeout(() => f.close(true), 180); }
        else if (cur.dy < -20 || (fast && cur.dy < 0)) f.expand();
        else spring(); // a tap is handled by the click
        if (cur.moved) scrim._skipClick = true;
        return;
      }
      if (cur.dy > Math.min(140, cur.h * 0.3) || fast) {
        if (f.dirty()) {
          // slide on down until only the top strip shows, then become the tucked bar in that same spot
          // where the tucked bar will sit: measure it without showing it (class on and off in the same frame)
          const now = box.getBoundingClientRect().top - cur.dy;
          scrim.classList.add('docked'); const barTop = box.getBoundingClientRect().top - cur.dy; scrim.classList.remove('docked');
          box.style.transition = 'transform .22s cubic-bezier(.2,.8,.2,1)';
          box.style.transform = `translateY(${Math.max(0, barTop - now)}px)`;
          setTimeout(() => { f.dock(true); requestAnimationFrame(() => requestAnimationFrame(() => { box.style.transition = ''; })); }, 220);
        }
        else { box.style.transition = 'transform .22s ease-in'; box.style.transform = 'translateY(100%)'; scrim.classList.remove('in'); setTimeout(f.close, 200); }
      } else spring();
    };
    box.addEventListener('touchend', end);
    box.addEventListener('touchcancel', end);
    // a drag on the tucked bar shouldn't also count as a tap
    scrim.addEventListener('click', (e) => { if (scrim._skipClick) { scrim._skipClick = false; e.stopImmediatePropagation(); } }, true);
  }

  function quickAdd(web) {
    if (!can('createTask')) return denied();
    const inProject = ui.view === 'project' && proj(ui.projectId) ? ui.projectId : '';
    const mgr = isAdm(me()) || me().role === 'am' || isCD();
    if (web !== true && NativeSheet.fits(15)) { nativeQuickAdd(inProject, mgr); return; }
    const people = activeUsers();
    const projOpts = `<option value="">No client (My Tasks)</option>` + db.projects.filter((p) => (!p.inactive && amClientOk(p)) || p.id === inProject).sort(byOrder).map((p) => `<option value="${p.id}" ${p.id === inProject ? 'selected' : ''}>${esc(p.name)}</option>`).join('');
    // (only Production, Social, Freelancers and the Creative Director can be assigned)
    const meOk = assignable(me());
    const userOpts = (meOk ? `<option value="${currentUserId}">Me</option>` : '<option value="">Nobody yet</option>') + people.filter((u) => u.id !== currentUserId && assignable(u)).map((u) => `<option value="${u.id}">${esc(fullName(u))}</option>`).join('') + (meOk ? '<option value="">Nobody yet</option>' : '');
    sheet(`<div class="ph-sh-head"><h2>New task</h2><button class="ph-link" data-sheet-close>Cancel</button></div>
      <label class="ph-field"><span>Title</span><input id="qa-title" name="e11-task-title" type="text" placeholder="What needs doing?" autocomplete="off" aria-autocomplete="none" data-1p-ignore data-lpignore="true" data-form-type="other" enterkeyhint="next"></label>
      <label class="ph-field"><span>Description <i>(optional)</i></span><textarea id="qa-desc" name="e11-task-notes" autocomplete="off" aria-autocomplete="none" data-form-type="other" rows="3" placeholder="Details, links or notes for the team"></textarea></label>
      <div class="ph-form">
        <label><span>Client</span><select id="qa-proj">${projOpts}</select></label>
        ${can('assign') ? `<label><span>Assign to</span><select id="qa-who">${userOpts}</select></label>` : ''}
        <label><span>Due</span><input type="date" id="qa-due" value="${ui.view === 'today' || ui.view === 'home' || ui.view === 'mytasks' ? todayStr() : ''}"></label>
        ${mgr ? `<label class="ph-sw"><span>CD review</span><em>Needs CD review</em><input type="checkbox" id="qa-cd" ${inProject ? 'checked' : ''}><i></i></label>` : ''}
      </div>
      <button class="ph-btn primary wide" id="qa-go">Create task</button>`, (scrim, close) => {
      const ti = $('#qa-title', scrim), pj = $('#qa-proj', scrim), cd = $('#qa-cd', scrim);
      setTimeout(() => ti.focus(), 250);
      if (cd) pj.addEventListener('change', () => { cd.checked = !!pj.value; });
      const go = () => {
        const title = ti.value.trim();
        if (!title) { ti.focus(); toast('Give the task a name'); return; }
        const who = $('#qa-who', scrim) ? $('#qa-who', scrim).value : assignable(me()) ? currentUserId : '';
        if (cd && cd.checked && who && who === cdUserId()) { toast('A task that needs CD review can’t be assigned to the Creative Director. Turn off CD review or choose someone else.'); return; }
        const desc = $('#qa-desc', scrim).value.trim();
        const t = createTask({ title, projectId: pj.value || null, due: $('#qa-due', scrim).value || null, notes: desc, ...(desc ? { notesHtml: linkify(esc(desc)).replace(/\n/g, '<br>') } : {}) });
        if (cd) t.needsCD = !!(cd.checked && t.projectId);
        if (who) {
          t.assignees = [who];
          if (who !== currentUserId) { logActivity(t, `assigned <b>${esc(fullName(userById(who)))}</b>`); pushNotif(who, t, 'assigned', 'assigned you to'); }
        }
        commit({ delay: 0 });
        close();
        toast(`Created “${title}”`, { label: 'Open', run: () => openTask(t.id) });
      };
      $('#qa-go', scrim).addEventListener('click', go);
      ti.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); $('#qa-desc', scrim).focus(); } });
    }, { kind: 'new-task', dockLabel: 'New task', discardedMsg: 'New task discarded' });
  }

  // iPhone app 15+: the same form as iOS's own sheet, with iPhone's own fields (tucks into a bar like a Mail draft)
  async function nativeQuickAdd(inProject, mgr) {
    const key = 'new-task';
    // (Assign to: several people can be picked — Haris, 2026-10-31)
    const st = { client: inProject || '', who: assignable(me()) ? [currentUserId] : [] };
    const clientName = (id) => (id && proj(id) ? proj(id).name : 'No client (My Tasks)');
    const nameOf = (uid) => (uid === currentUserId ? 'Me' : fullName(userById(uid)));
    const whoOf = async (ids) => {
      if (!ids.length) return { label: 'Nobody yet' };
      const label = ids.length === 1 ? nameOf(ids[0]) : ids.length === 2 ? `${nameOf(ids[0])}, ${nameOf(ids[1])}` : `${nameOf(ids[0])} + ${ids.length - 1} others`;
      return { label, person: await NativeSheet.personFor(ids[0]) };
    };
    const pickClient = () => {
      const list = db.projects.filter((p) => (!p.inactive && amClientOk(p)) || p.id === inProject).sort(byOrder);
      // (picking a client turns CD review on, no client turns it off — as on the page)
      const set = (id) => { st.client = id; NativeForm.set(key, { client: clientName(id), ...(mgr ? { cd: !!id } : {}) }); };
      const items = [{ label: 'No client (My Tasks)', checked: !st.client, run: () => set('') }, '-',
        ...list.map((p) => ({ label: p.name, checked: st.client === p.id, find: p.name, run: () => set(p.id) }))];
      showMenu(document.body, items, { native: 14, ...(list.length > 7 ? { search: 'Search clients', empty: 'No client matches “%@”' } : {}) });
    };
    const pickWho = () => {
      const show = async () => NativeForm.set(key, { assign: await whoOf(st.who) });
      // (each tick adds or removes that person; the sheet stays open for the next)
      const toggle = (uid) => { st.who = st.who.includes(uid) ? st.who.filter((x) => x !== uid) : [...st.who, uid]; show(); };
      const row = (u) => ({ label: u.id === currentUserId ? 'Me' : fullName(u), hint: roleOf(u), person: u.id, checked: st.who.includes(u.id), multi: true,
        find: `${fullName(u)} ${u.email} ${roleOf(u)}`, run: () => toggle(u.id) });
      // (only Production, Social, Freelancers and the Creative Director can be assigned — in their groups)
      const items = assignable(me()) ? [row(me())] : [];
      assignGroups(activeUsers().filter((u) => u.id !== currentUserId && assignable(u))).forEach(([l, us]) => items.push({ html: `<div class="menu-label">${esc(l)}</div>` }, ...us.map(row)));
      items.push('-', { label: 'Nobody yet', checked: !st.who.length, run: () => { st.who = []; show(); } });
      showMenu(document.body, items, { native: 14, search: 'Search people', empty: 'No one matches “%@”' });
    };
    const due = ui.view === 'today' || ui.view === 'home' || ui.view === 'mytasks' ? todayStr() : '';
    NativeForm.open({ kind: 'task', key, title: 'New task', titleHint: 'What needs doing?', descHint: 'Details, links or notes for the team',
      client: clientName(st.client), ...(can('assign') ? { assign: await whoOf(st.who) } : {}), due, ...(mgr ? { cd: !!inProject } : {}),
      button: 'Create task', color: 'blue', dock: 'New task', required: 'title' }, {
      pick: (field) => (field === 'client' ? pickClient() : pickWho()),
      submit: (ev) => {
        const title = ev.title;
        const who = can('assign') ? st.who : assignable(me()) ? [currentUserId] : [];
        const cdOn = mgr && ev.cd;
        if (cdOn && who.includes(cdUserId())) { NativeForm.set(key, { alert: 'A task that needs CD review can’t be assigned to the Creative Director. Turn off CD review or choose someone else.' }); return; }
        const desc = ev.desc || '';
        const t = createTask({ title, projectId: st.client || null, due: ev.due || null, notes: desc, ...(desc ? { notesHtml: linkify(esc(desc)).replace(/\n/g, '<br>') } : {}) });
        if (mgr) t.needsCD = !!(cdOn && t.projectId);
        if (who.length) {
          t.assignees = [...who];
          who.filter((u) => u !== currentUserId).forEach((u) => { logActivity(t, `assigned <b>${esc(fullName(userById(u)))}</b>`); pushNotif(u, t, 'assigned', 'assigned you to'); });
        }
        commit({ delay: 0 });
        NativeForm.close(key);
        toast(`Created “${title}”`, { label: 'Open', run: () => openTask(t.id) });
      },
      closed: (r) => { if (r.closed === 'discard') toast('New task discarded'); },
    }, () => quickAdd(true));
  }

  function amendSheet(id, web) {
    const f = findReview(id);
    if (!f || !isCD()) return;
    if (web !== true && NativeSheet.fits(15)) {
      const key = 'amend-' + id;
      NativeForm.open({ kind: 'amend', key, title: 'Request amendments', note: `Tell ${firstName(f.r.by)} what to change. It's posted as a comment on the task.`,
        descHint: 'e.g. Use the new logo lockup and make the date bigger', button: 'Send back', color: 'amber', dock: 'Amendments for ' + firstName(f.r.by), required: 'desc' }, {
        submit: (ev) => {
          const g = findReview(id);
          NativeForm.close(key);
          if (!g) return;
          decideReview(g.t, g.r, 'amend', esc(ev.desc).replace(/\n/g, '<br>'));
          toast(`Sent back to ${firstName(g.r.by)} with your notes`);
          nextReview();
        },
        closed: (r) => { if (r.closed === 'discard') toast('Amendment notes discarded'); },
      }, () => amendSheet(id, true));
      return;
    }
    sheet(`<div class="ph-sh-head"><h2>Request amendments</h2><button class="ph-link" data-sheet-close>Cancel</button></div>
      <p class="ph-sh-p">Tell ${esc(firstName(f.r.by))} what to change. It's posted as a comment on the task.</p>
      <textarea id="am-note" name="e11-amend-notes" autocomplete="off" aria-autocomplete="none" data-form-type="other" rows="5" placeholder="e.g. Use the new logo lockup and make the date bigger"></textarea>
      <button class="ph-btn amber wide" id="am-go">Send back</button>`, (scrim, close) => {
      const ta = $('#am-note', scrim);
      setTimeout(() => ta.focus(), 250);
      $('#am-go', scrim).addEventListener('click', () => {
        const v = ta.value.trim();
        if (!v) { ta.focus(); toast('Describe the changes required'); return; }
        close();
        decideReview(f.t, f.r, 'amend', esc(v).replace(/\n/g, '<br>'));
        toast(`Sent back to ${firstName(f.r.by)} with your notes`);
        nextReview();
      });
    }, { kind: 'amend-' + id, dockLabel: 'Amendments for ' + firstName(f.r.by), discardedMsg: 'Amendment notes discarded' });
  }
  function nextReview() {
    const left = activeReviews();
    if (left.length) { ui.reviewId = left[0].r.id; ui.view = 'review'; } else ui.view = 'reviews';
    $('#content').scrollTop = 0;
    render();
  }

  function taskMore() {
    const t = task(ui.taskId);
    if (!t) return;
    const items = [
      { label: 'Attach files', icon: 'clip', run: () => attachFiles('task') },
      ...(t.projectId ? [{ label: 'Open client', icon: 'folder', run: () => { closeDetail(); go('project', t.projectId); } }] : []),
      ...(can('deleteTask') ? ['-', { label: 'Delete task', icon: 'trash', danger: true, run: () => deleteTaskFlow(t.id) }] : []),
    ];
    showMenu(document.body, items, { native: true });
  }

  /* ---------- Taps ---------- */
  document.addEventListener('click', (e) => {
    if (!st.on || !db || !currentUserId) return;
    // a task tapped in a list always opens on Details
    const pc = e.target.closest('.pc[data-task]');
    if ((pc && !e.target.closest('button')) || e.target.closest('.ph-ib')) { ui.sideTab = 'details'; ui.activityFilter = 'comments'; }
    const tab = e.target.closest('[data-ph-tab]');
    if (tab) {
      e.stopPropagation();
      if (ui.taskId) closeDetail();
      closeMenus();
      const v = tab.dataset.phTab;
      if (v === 'reviews') ui.rrTab = 'active';
      if (v === 'mytasks') { ui.workF = null; ui.myTasksTab = 'todo'; }
      go(v);
      return;
    }
    const el = e.target.closest('[data-ph]');
    if (!el) return;
    e.stopPropagation();
    const id = el.dataset.id;
    switch (el.dataset.ph) {
      case 'quick-add': quickAdd(); break;
      case 'search': go('psearch'); setTimeout(() => { const q = $('#ph-q'); if (q) q.focus(); }, 50); break;
      case 'ibf': st.ibf = el.dataset.k; render(); break;
      case 'open-review': ui.reviewId = id; go('review'); break;
      case 'approve': {
        const f = findReview(id);
        if (!f) return;
        decideReview(f.t, f.r, 'approve');
        toast(`Approved — ${firstName(f.r.by)} has been notified`);
        nextReview();
        break;
      }
      case 'amend': amendSheet(id); break;
      case 'preview': { const t = task(el.dataset.tid); const a = t && findAttachment(t, id); if (a) previewFile(a); break; }
      case 'open-project': go('project', id); break;
      case 'task-more': taskMore(); break;
      case 'sample': resetSampleData(); break;
      case 'sign-out': dialog({ title: 'Sign out?', body: window.E11_REVIEW ? 'You’ll need the App Review password to sign in again.' : 'You’ll need the code from your email to sign in again.', okText: 'Sign out' }).then((ok) => { if (ok) signOut(); }); break;
      default: break;
    }
  }, true);
  document.addEventListener('input', (e) => {
    if (e.target.id !== 'ph-q') return;
    st.q = e.target.value;
    const r = $('#ph-results');
    if (r) r.innerHTML = results();
  });

  check();
  return { get on() { return st.on; }, isOn, myDayData, renderContent, decorate, chrome, taskHead, quickAdd, check, sheet, resetInbox: () => { st.ibf = 'unread'; }, setIbf: (k) => { st.ibf = k; } };
})();

/* Phone notifications (Web Push): the switch on the Me page, and opening a task from a notification */
const Push = (() => {
  const st = { state: 'unknown', busy: false };
  const ios = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const standalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const supported = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  const keyBytes = (k) => { const s = atob(k.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((k.length + 3) % 4)); return Uint8Array.from(s, (c) => c.charCodeAt(0)); };

  // the native iPhone app (ios/): Apple's own notifications instead of Web Push
  const iosApp = () => typeof Host !== 'undefined' && Host.isIOSApp;
  st.lock = null;
  async function refresh() {
    if (!Host.isServer) { st.state = 'none'; return paint(); }
    if (iosApp()) {
      try {
        const r = await NativeMac.call('pushStatus');
        st.state = r.state === 'on' ? 'on' : r.state === 'denied' ? 'denied' : 'off';
        if (st.state === 'on') NativeMac.call('pushRegister').catch(() => {});   // (the address can change: the app sends it again)
        st.lock = (await NativeMac.call('appInfo')).faceID || null;
      } catch (e) { st.state = 'off'; }
      return paint();
    }
    if (!supported()) { st.state = ios && !standalone() ? 'install' : 'unsupported'; return paint(); }
    if (Notification.permission === 'denied') { st.state = 'denied'; return paint(); }
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (!sub) st.state = 'off';
      else {
        const r = await api('POST', '/api/push/status', { endpoint: sub.endpoint });
        if (!r.on) await api('POST', '/api/push/subscribe', { subscription: sub.toJSON() }); // the server forgot it: tell it again
        st.state = 'on';
      }
    } catch (e) { st.state = 'off'; }
    paint();
  }
  function paint() {
    const el = document.getElementById('ph-push');
    if (el) el.outerHTML = row('button');
    document.querySelectorAll('#ph-lock ~ #ph-lock, #ph-lock + .ph-row[data-ph-lock]').forEach((x) => x.remove());
    const lk = document.getElementById('ph-lock');
    if (lk) lk.outerHTML = lockRow();
    const pf = document.getElementById('pf-push');
    if (pf) pf.outerHTML = profileRow(true);
  }
  // My profile on a computer: the same notifications, for this browser (the Mac app shows its own while it's open)
  function profileRow(noRefresh) {
    if (Host.isMacApp) return `<div class="pf-opt" id="pf-push"><div><b>Notifications</b><span>The Mac app shows a banner for every Inbox update while it’s running — closing its window keeps it running (⌘Q quits), and <b>Open at Login</b> in its app menu starts it with your Mac.</span></div></div>`;
    if (!noRefresh) setTimeout(refresh, 0);
    if (st.state === 'none') return '';
    const sub = { on: 'A banner for every Inbox update, even when this tab is closed', off: 'Get a banner for every Inbox update, even when this tab is closed', denied: 'Blocked in this browser — allow notifications for this site in the browser’s settings', unsupported: 'This browser can’t show notifications', unknown: '' }[st.state] || '';
    const ctl = st.state === 'on' || st.state === 'off'
      ? `<div class="pf-opt-btns">${st.state === 'on' ? '<button class="btn sm" data-pf-push="test">Send test</button>' : ''}<button class="switch ${st.state === 'on' ? 'on' : ''}" data-pf-push="toggle" aria-label="Notifications on this computer" ${st.busy ? 'disabled' : ''}><i></i></button></div>` : '';
    return `<div class="pf-opt" id="pf-push"><div><b>Notifications on this computer</b><span>${sub}</span></div>${ctl}</div>`;
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-pf-push]'); if (!b || st.busy) return;
    if (b.dataset.pfPush === 'test') api('POST', '/api/push/test', { token: lastToken || '' }).then((r) => toast(testSaid(r, 'computer'))).catch((er) => toast(er.message));
    else if (st.state === 'on') turnOff(); else if (st.state === 'off') turnOn();
  });
  function row(noRefresh) {
    if (!noRefresh) setTimeout(refresh, 0);
    if (st.state === 'none') return '';
    const label = { on: 'On', off: 'Off', denied: 'Blocked', install: 'Set up', unsupported: 'Not available', unknown: '' }[st.state];
    const sub = { on: 'A banner for every Inbox update', off: 'Get a banner even when the app is closed', denied: 'Allow them in iPhone Settings → Notifications → E11 Console', install: 'Add E11 Console to your Home Screen first', unsupported: 'This browser can’t show notifications', unknown: '' }[st.state];
    const btn = `<button class="ph-row" id="ph-push" data-ph-push>${icon('bell')}<span>Notifications on this phone<small>${sub}</small></span><i class="ph-state ${st.state === 'on' ? 'on' : ''}">${st.busy ? '…' : label}</i></button>`;
    // (a repaint replaces just this button: the lock row has its own repaint, so it never doubles up)
    return noRefresh === 'button' ? btn : btn + (iosApp() ? lockRow() : '');
  }
  // iPhone app: lock the app with Face ID (asked when it opens, and after 10 minutes away)
  function lockRow() {
    if (!iosApp() || !st.lock) return iosApp() ? '<i id="ph-lock" hidden></i>' : '';
    return `<button class="ph-row" id="ph-lock" data-ph-lock>${icon('lock')}<span>Lock with ${esc(st.lock.kind || 'Face ID')}<small>Asks for your face when E11 Console opens</small></span><i class="ph-state ${st.lock.on ? 'on' : ''}">${st.lock.on ? 'On' : 'Off'}</i></button>`;
  }
  document.addEventListener('click', (e) => {
    const el = e.target.closest && e.target.closest('[data-ph-lock]');
    if (!el || !st.lock) return;
    e.stopPropagation();
    NativeMac.call('setLock', { on: !st.lock.on }).then((r) => { st.lock = { ...st.lock, on: !!r.on }; paint(); }).catch((er) => toast(er.message));
  }, true);
  // the iPhone / Mac App Store app's notification address arrives from the app (after it's allowed, and on each start)
  let lastToken = null;
  // what a test notification did, in words: for the iPhone app, this phone's own answer from Apple
  function testSaid(r, where) {
    const me = r && r.thisPhone;
    if (me) {
      if (me.status === 200) return 'Sent to this phone — Apple accepted it. Nothing showing? Check Focus and Settings → Notifications → E11 Console';
      if (r.apnsWhy === 'no-key') return 'This site can’t send Apple notifications yet (its Apple push key isn’t set up)';
      if (me.reason === 'not registered on this site') return 'This phone isn’t registered on this site — turn notifications off and on here';
      return `Apple didn’t accept it for this phone (${me.status || 'no answer'}${me.reason ? ' · ' + me.reason : ''})`;
    }
    // (no answer for this phone itself: what each Apple device on this site got)
    const ds = (r && r.devices) || [];
    if (ds.length) {
      const name = (d) => (d.platform === 'mac' ? 'Mac' : 'iPhone');
      return 'Apple devices on this site: ' + ds.map((d) => `${name(d)} ${d.status === 200 ? '✓ accepted' : `✗ ${d.status || 'no answer'}${d.reason ? ' ' + d.reason : ''}`}`).join(' · ');
    }
    if (r && r.apnsWhy === 'no-key') return 'This site can’t send Apple notifications (its Apple push key isn’t set up)';
    if (r && r.apnsWhy === 'no-devices') return 'No iPhone is registered on this site — turn notifications off and on on the phone';
    return r && r.sent ? 'Sent — it may take a few seconds' : `Couldn’t reach this ${where} — switch it off and on again`;
  }
  window.__e11ApnsToken = (d) => { if (!d || !d.token) return; lastToken = d.token; api('POST', '/api/apns/register', { token: d.token, env: d.env, ack: d.ack === true, platform: d.platform || 'ios' }).catch(() => {}); };
  // tapping an iPhone app notification
  window.__e11PushTap = (d) => { d = d || {}; if (d.view) { if (typeof openView === 'function') openView(d.view); return; } openFrom(d.taskId || null, d.nid || null, { kind: d.kind || null, clientId: d.clientId || null, folderId: d.folderId || null, commentId: d.commentId || null, planId: d.planId || null }); };

  async function turnOn() {
    st.busy = true; paint();
    if (iosApp()) {
      try {
        const r = await NativeMac.call('pushEnable');
        st.state = r.state === 'on' ? 'on' : r.state === 'denied' ? 'denied' : 'off';
        if (st.state === 'on') toast('Notifications are on for this phone');
      } catch (e) { toast('Couldn’t turn on notifications: ' + e.message); } finally { st.busy = false; paint(); }
      return;
    }
    try {
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') { st.state = perm === 'denied' ? 'denied' : 'off'; return; }
      const reg = await navigator.serviceWorker.ready;
      const { key } = await api('GET', '/api/push/key');
      const sub = (await reg.pushManager.getSubscription()) || await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(key) });
      await api('POST', '/api/push/subscribe', { subscription: sub.toJSON() });
      st.state = 'on';
      toast(`Notifications are on for this ${Phone.on ? 'phone' : 'computer'}`);
    } catch (e) { toast('Couldn’t turn on notifications: ' + e.message); } finally { st.busy = false; paint(); }
  }
  async function turnOff() {
    if (iosApp()) {
      try {
        const r = await NativeMac.call('pushDisable');
        const tk = r.token || lastToken;
        if (tk) await api('POST', '/api/apns/unregister', { token: tk }).catch(() => {});
        st.state = 'off'; paint(); toast('Notifications are off for this phone');
      } catch (e) { toast(e.message); }
      return;
    }
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (sub) { await api('POST', '/api/push/unsubscribe', { endpoint: sub.endpoint }).catch(() => {}); await sub.unsubscribe(); }
      st.state = 'off'; paint();
      toast(`Notifications are off for this ${Phone.on ? 'phone' : 'computer'}`);
    } catch (e) { toast(e.message); }
  }
  function installHelp() {
    dialog({
      title: 'Add E11 Console to your Home Screen',
      body: 'iPhone only sends notifications to apps on the Home Screen. In Safari, tap the Share button (the square with an arrow), choose “Add to Home Screen”, then open E11 Console from its new icon and come back here.',
      okText: 'Got it', cancelText: null,
    });
  }

  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-ph-push]');
    if (!el || st.busy) return;
    e.stopPropagation();
    if (st.state === 'install') return installHelp();
    if (st.state === 'denied') {
      if (iosApp()) return dialog({ title: 'Notifications are off in Settings', body: 'Turn on Allow Notifications for E11 Console in the iPhone’s Settings.', okText: 'Open Settings' }).then((ok) => { if (ok) NativeMac.call('openSettings').catch(() => {}); });
      return dialog({ title: 'Notifications are blocked', body: 'Open iPhone Settings → Notifications → E11 Console and turn on Allow Notifications. Then come back here.', okText: 'OK', cancelText: null });
    }
    if (st.state === 'off') return turnOn();
    if (st.state === 'on') {
      showMenu(el, [
        { label: 'Send a test notification', icon: 'bell', run: () => api('POST', '/api/push/test', { token: lastToken || '' }).then((r) => toast(testSaid(r, 'phone'))).catch((err) => toast(err.message)) },
        { label: 'Turn off on this phone', icon: 'x', danger: true, run: turnOff },
      ], { native: true });
    }
  }, true);

  // Opening the app from a notification
  // The update a notification is about may not have reached the app yet (it was asleep, or is still catching up):
  // go to the right kind of page straight away, then open the update itself as soon as it arrives (up to ~8 s).
  function openFrom(taskId, nid, hint = {}) {
    const has = () => nid && db.notifications.some((n) => n.id === nid);
    const byKind = () => {
      const k = hint.kind || '';
      if ((k === 'review' || k === 'review-wd') && isCD()) { if (ui.taskId) closeDetail(); go('reviews'); return true; }
      if (k === 'asset' && hint.clientId && clientById(hint.clientId)) { const c = clientById(hint.clientId); openClient(c.id, c.folders.some((x) => x.id === hint.folderId) ? hint.folderId : null); return true; }
      if (/^claim/.test(k)) { Claims.openNotif({ kind: k }); return true; }
      if (/^plan/.test(k) && hint.planId && Plans.planById(hint.planId)) { Plans.open(hint.planId); return true; }
      return false;
    };
    const start = () => {
      ui.sideTab = 'details';
      if (has()) { openNotif(nid); return; }
      if (taskId && !nid) return TaskLink.open(taskId); // a shared link: may hand over to the Mac app
      // meanwhile: the right page for its kind, or the task (on Comments for a comment, @mention or amendments)
      if (!byKind() && taskId && task(taskId)) {
        if (['comment', 'mention', 'review-amend'].includes(hint.kind) && hint.commentId) ui.sideTab = ui.forceTab = 'comments';
        openTask(taskId);
      }
      if (!nid) return;
      const t0 = Date.now(), here = () => `${ui.view}|${ui.taskId || ''}`, was = here();
      const wait = setInterval(() => {
        if (here() !== was || Date.now() - t0 > 8000) clearInterval(wait);   // (they moved on themselves, or it never came)
        else if (has()) { clearInterval(wait); openNotif(nid); }
      }, 250);
    };
    if (typeof db !== 'undefined' && db && currentUserId) return start();
    const iv = setInterval(() => { if (typeof db !== 'undefined' && db && currentUserId) { clearInterval(iv); setTimeout(start, 300); } }, 250);
    setTimeout(() => clearInterval(iv), 30000);
  }
  // a notification that opens a page (occasion reminders open the Content calendar)
  function openView(view) {
    const ok = { calendar: 1, home: 1, plans: 1, 'fin-dash': 1 };   // (home / plans / fin-dash: a tap on the widget)
    if (!ok[view]) return;
    const run = () => go(view === 'fin-dash' && !finLevel() ? 'home' : view);
    if (typeof db !== 'undefined' && db && currentUserId) return run();
    const iv = setInterval(() => { if (typeof db !== 'undefined' && db && currentUserId) { clearInterval(iv); setTimeout(run, 300); } }, 250);
    setTimeout(() => clearInterval(iv), 30000);
  }
  const q = new URLSearchParams(location.search);
  if (q.get('task') || q.get('n')) { openFrom(q.get('task'), q.get('n'), { kind: q.get('k'), clientId: q.get('c'), folderId: q.get('f'), planId: q.get('pl') }); history.replaceState(null, '', '/'); }   // (an update without a task, e.g. Client Assets, has only n)
  else if (q.get('view')) { openView(q.get('view')); history.replaceState(null, '', '/'); }
  if ('serviceWorker' in navigator) navigator.serviceWorker.addEventListener('message', (e) => { if (e.data && e.data.type === 'open-task') openFrom(e.data.taskId, e.data.nid, e.data.hint || {}); if (e.data && e.data.type === 'open-view') openView(e.data.view); });

  // Send test (My profile): to every device, and the iPhone app hears what Apple said for this phone
  const test = () => api('POST', '/api/push/test', { token: lastToken || '' }).then((r) => toast(testSaid(r, 'phone'))).catch((err) => toast(err.message));
  return { row, refresh, profileRow, test };
})();

/* Swipe from the left edge to go back, like a native iPhone app (only in the Home Screen app —
   in Safari the browser's own edge swipe would fight it). The page you're going back to is already there
   underneath, a little to the left and dimmed, and slides in more slowly than your finger (parallax).
   - an open task: the list behind it is live, so it simply moves with the swipe
   - a page: a still copy of this page slides away while the real previous page is drawn underneath
     straight away (so what comes into view is exactly where you land); letting go early puts it all back
   - a comment thread: the thread slides away to the comments */
(() => {
  const EDGE = 28, DONE = 0.33, PAR = 0.3, DIM = 0.22;
  let g = null;
  // iPhone app 10+: tuned — the let-go follows the finger's speed (a flick finishes, a flick back cancels), the
  // glide takes as long as the distance needs, moving layers are readied for the GPU, the header dims with a
  // see-through layer instead of a filter, and the page coming off casts a soft edge shadow (as iOS does)
  const tuned = () => typeof Pager !== 'undefined' && Pager.lists();
  const standalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true || window.__phSwipeAlways || (typeof Host !== 'undefined' && Host.isIOSApp);
  function target() {
    if (window.__e11CommentsOnly) return null;   // (the comments screen: the app's own swipe — __e11CmBack)
    if ($('#overlay-root').firstElementChild || $('.menu:not(.ph-out)') || $('#ph-sheet-root .ph-scrim:not(.docked)')) return null; // a sheet or menu is open
    if (ui.taskId) {
      const pane = $('#detail');
      if (ui.thread && pane.dataset.tab === 'comments') return { kind: 'thread', btn: $('.th-back', pane), layer: $('.tm-activity', pane) };
      return { kind: 'task', btn: $('.ph-task-head .ph-back', pane), layer: $('.tm', pane) };
    }
    const btn = $('#ph-top .ph-back') || $('#content .ph-back');
    return btn ? { kind: 'page', btn, layer: $('#content') } : null;
  }
  const move = (el, x, anim) => {
    if (!el) return;
    el.style.transition = anim ? `transform ${typeof anim === 'number' ? anim : 220}ms cubic-bezier(.2,.8,.2,1)` : 'none';
    el.style.transform = x ? `translate3d(${x}px,0,0)` : '';
  };
  const fade = (el, o, anim) => { if (!el) return; el.style.transition = anim ? `opacity ${typeof anim === 'number' ? anim : 220}ms cubic-bezier(.2,.8,.2,1)` : 'none'; el.style.opacity = String(o); };
  const dimLayer = (parent, before, z) => {
    const d = document.createElement('div');
    d.className = 'ph-swipe-dim';
    d.style.cssText = `position:${parent === document.body ? 'fixed' : 'absolute'};left:0;right:0;top:0;bottom:0;background:#000;opacity:${DIM};pointer-events:none;${z != null ? 'z-index:' + z + ';' : ''}`;
    parent.insertBefore(d, before || null);
    return d;
  };
  // set up what sits underneath, the first time the finger really moves
  function begin(c) {
    const w = window.innerWidth;
    c.w = w;
    if (c.kind === 'task') {
      // the task pane lives inside #main, so move the list itself (not its parents); the page header sits
      // above the pane in the stacking order, so it is cut off where the pane starts and dimmed with a filter
      c.under = [$('#content')].filter(Boolean);
      const top = $('#ph-top'); if (top) { top.style.visibility = 'visible'; c.top = top; }
      c.dim = dimLayer($('#detail'), c.layer);
    } else if (c.kind === 'page') {
      // a still copy of this page (and its header) on top, then the real previous page drawn underneath
      const app = $('#app'), top = $('#ph-top'), content = $('#content');
      const scroll = content ? content.scrollTop : 0;
      const fg = document.createElement('div');
      fg.className = 'ph-swipe-fg';
      fg.style.cssText = 'position:fixed;left:0;right:0;top:0;height:var(--app-h,100%);z-index:22;pointer-events:none;background:var(--ph-bg)';
      fg.appendChild(app.cloneNode(true));
      if (top && !top.hidden) fg.appendChild(top.cloneNode(true));
      document.body.appendChild(fg);                       // after the originals, so their ids still find the real ones
      const cc = fg.querySelector('#content'); if (cc) cc.scrollTop = scroll;
      c.fg = fg; c.layer = fg;
      c.saved = { ui: { ...ui }, scroll };
      c.btn.click();                                       // draw the page we're going back to, underneath
      c.under = [$('#app'), $('#ph-top')].filter(Boolean);
      c.dim = dimLayer(document.body, fg, 21);          // above the real header (z 20), below the copy
    } else c.under = [];
    c.under.forEach((el) => move(el, -w * PAR, false));
    if (tuned()) {
      c.tuned = true;
      [c.layer, ...c.under, c.dim].forEach((el) => { if (el) el.style.willChange = el === c.dim ? 'opacity' : 'transform'; });
      if (c.layer && c.kind !== 'page') c.layer.style.boxShadow = '-6px 0 22px rgba(0,0,0,.28)';
      if (c.top) {
        c.topDim = document.createElement('div');
        c.topDim.className = 'ph-swipe-dim';
        c.topDim.style.cssText = `position:absolute;inset:0;background:#000;opacity:${DIM};pointer-events:none;will-change:opacity;z-index:5`;
        c.top.appendChild(c.topDim);
        c.top.style.willChange = 'transform';
      }
    }
    if (c.top) track(c, 0);
  }
  function track(c, dx) {
    move(c.layer, dx, false);
    const p = Math.min(1, dx / c.w);
    c.under.forEach((el) => move(el, -c.w * PAR * (1 - p), false));
    fade(c.dim, DIM * (1 - p), false);
    if (c.top) {
      const tx = -c.w * PAR * (1 - p);
      move(c.top, tx, false);
      c.top.style.clipPath = `inset(0 ${Math.max(0, c.w - (dx - tx))}px 0 0)`;
      if (c.topDim) fade(c.topDim, DIM * (1 - p), false); else c.top.style.filter = `brightness(${1 - DIM * (1 - p)})`;
    }
  }
  function cleanup(c) {
    [...c.under, c.top].forEach((el) => { if (el) { el.style.transition = 'none'; el.style.transform = ''; } });
    [c.layer, ...c.under, c.top].forEach((el) => { if (el) { el.style.willChange = ''; el.style.boxShadow = ''; } });
    if (c.topDim) c.topDim.remove();
    const top = $('#ph-top'); if (top) { top.style.visibility = ''; top.style.clipPath = ''; top.style.filter = ''; }
    if (c.dim) c.dim.remove();
    if (c.fg) c.fg.remove();
  }
  // iOS stops sending a touch's events to the page once the element under the finger is removed (going back
  // redraws the page), so listen on that element too; each event is handled once
  let held = null;
  const hold = (el) => { release(); held = el; if (el) { el.addEventListener('touchmove', onMove, { passive: false }); el.addEventListener('touchend', end); el.addEventListener('touchcancel', end); } };
  const release = () => { if (held) { held.removeEventListener('touchmove', onMove); held.removeEventListener('touchend', end); held.removeEventListener('touchcancel', end); held = null; } };
  // leftovers from a swipe that never got its end (shouldn't happen, but never leave the page stuck)
  const sweep = () => {
    document.querySelectorAll('.ph-swipe-fg, .ph-swipe-dim').forEach((n) => n.remove());
    [$('#app'), $('#content'), $('#ph-top')].forEach((el) => { if (el) { el.style.transition = ''; el.style.transform = ''; el.style.clipPath = ''; el.style.filter = ''; } });
    const top = $('#ph-top'); if (top) top.style.visibility = '';
  };
  document.addEventListener('touchstart', (e) => {
    if (!g && document.querySelector('.ph-swipe-fg, .ph-swipe-dim')) sweep();
    g = null;
    if (!Phone.on || !standalone() || e.touches.length !== 1) return;
    const t = e.touches[0];
    if (t.clientX > EDGE) return;
    const tg = target();
    if (!tg || !tg.btn || !tg.layer) return;
    g = { x0: t.clientX, y0: t.clientY, t0: Date.now(), dx: 0, on: false, under: [], ...tg };
    hold(e.target);
  }, { passive: true });
  function onMove(e) {
    if (!g || e.__phSwipe) return;
    e.__phSwipe = true;
    const t = e.touches[0];
    const dx = t.clientX - g.x0, dy = t.clientY - g.y0;
    if (!g.on) {
      if (Math.abs(dy) > 12 && Math.abs(dy) > Math.abs(dx)) { g = null; return; } // scrolling, not swiping
      if (dx < 10) return;
      g.on = true;
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      begin(g);
    }
    e.preventDefault();
    g.dx = Math.max(0, dx);
    const now = performance.now();
    (g.trail = g.trail || []).push([now, g.dx]);
    while (g.trail.length > 2 && now - g.trail[0][0] > 100) g.trail.shift();   // (the last ~0.1 s: the speed at let-go)
    track(g, g.dx);
    clearTimeout(g.idle); const me = g;
    g.idle = setTimeout(() => { if (g === me) end(); }, 4000); // no word from the finger for a while: settle
  }
  document.addEventListener('touchmove', onMove, { passive: false });
  function end(e) {
    if (e) { if (e.__phSwipe) return; e.__phSwipe = true; }
    release();
    if (g) clearTimeout(g.idle);
    if (!g || !g.on) { g = null; return; }
    const c = g; g = null;
    const w = c.w;
    let fast = c.dx > 50 && c.dx / Math.max(1, Date.now() - c.t0) > 0.5;
    let dur = 220, back = false;
    if (c.tuned) {
      const tr = c.trail || [], a0 = tr[0], a1 = tr[tr.length - 1];
      const v = a0 && a1 && a1[0] > a0[0] ? (a1[1] - a0[1]) / (a1[0] - a0[0]) : 0;   // px per ms (+ = towards back)
      fast = v > 0.35 && c.dx > 20;
      back = v < -0.35;                                                                 // flicked back: stay
      const done = !back && (c.dx > w * DONE || fast);
      const left = done ? w - c.dx : c.dx;
      dur = Math.round(Math.max(170, Math.min(340, left / Math.max(Math.abs(v), 1.1))));
      c.done = done;
    }
    const glide = (to) => { // the header has no transform-only path, so walk it along with the release
      if (!c.top) return;
      const from = c.dx, t0 = performance.now();
      const step = (now) => { const k = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - k, 3);
        if (c.top.style.visibility !== 'visible') return;
        const dx = from + (to - from) * e, p = dx / w, tx = -w * PAR * (1 - p);
        c.top.style.transition = 'none'; c.top.style.transform = `translate3d(${tx}px,0,0)`;
        c.top.style.clipPath = `inset(0 ${Math.max(0, w - (dx - tx))}px 0 0)`;
        if (c.topDim) { c.topDim.style.transition = 'none'; c.topDim.style.opacity = String(DIM * (1 - p)); } else c.top.style.filter = `brightness(${1 - DIM * (1 - p)})`;
        if (k < 1) requestAnimationFrame(step); };
      requestAnimationFrame(step);
    };
    if (c.tuned ? c.done : (c.dx > w * DONE || fast)) {
      glide(w);
      move(c.layer, w, dur); c.under.forEach((el) => move(el, 0, dur)); fade(c.dim, 0, dur);
      setTimeout(() => {
        if (c.kind !== 'page') { c.btn.click(); move(c.layer, 0, false); } // (a page already went back underneath)
        cleanup(c);
      }, dur);
    } else {
      glide(0);
      move(c.layer, 0, dur); c.under.forEach((el) => move(el, -w * PAR, dur)); fade(c.dim, DIM, dur);
      setTimeout(() => {
        if (c.kind === 'page' && c.saved) {
          // let go early: put the page we were on back (still hidden under its copy), then lift the copy
          Object.assign(ui, c.saved.ui); render();
          const content = $('#content'); if (content) content.scrollTop = c.saved.scroll;
        }
        cleanup(c);
      }, dur);
    }
  }
  document.addEventListener('touchend', end);
  document.addEventListener('touchcancel', end);
})();

/* Swipe left / right on a page to move between its tabs: To Do ↔ Done, Details ↔ Comments,
   Unread ↔ All ↔ Mentions. (A swipe that starts at the very left edge is "back" instead.) */
(() => {
  let g = null;
  const SKIP = 'input, textarea, select, [contenteditable="true"], .ph-slides, .ph-chips, .wf-bar, .tr-chips, .fin-chips, .fin-tabs, .fa-tabs, .menu, .ph-sheet, .ap-video, video, .board, .cb-files, .tm-composer, .fpv';
  function tabsHere() {
    if ($('#overlay-root').firstElementChild || $('#ph-sheet-root .ph-scrim:not(.docked)') || $('.menu:not(.ph-out)')) return null;
    if (ui.taskId) {
      if (ui.thread || (typeof Pager !== 'undefined' && Pager.on())) return null;   // (iPhone app 9+: iOS swipes the task's tabs)
      const btns = $$('#detail .ph-task-head .ph-seg button');
      return btns.length > 1 ? { btns, area: () => [$('#detail .tm-body')].filter(Boolean) } : null;
    }
    if ($('#content .pg-page')) return null;   // (iPhone app 10+: iOS swipes these lists itself)
    const btns = $$('#content .ph-seg button').length ? $$('#content .ph-seg button') : $$('#content .ph-chips button');
    return btns.length > 1 ? { btns, area: () => below($$('#content .ph-seg button, #content .ph-chips button')[0], $('#content > .ph-page')) } : null;
  }
  // What moves with the swipe: only the content under the tabs (the tabs and the heading stay put)
  function below(btn, root) {
    if (!root) return [];
    if (!btn || !root.contains(btn)) return [root];
    let h = btn;
    while (h.parentElement && h.parentElement !== root) h = h.parentElement;
    const out = [];
    for (let n = h.nextElementSibling; n; n = n.nextElementSibling) if (!n.classList.contains('wf-bar')) out.push(n);
    return out.length ? out : [root];
  }
  const each = (els, fn) => (Array.isArray(els) ? els : els ? [els] : []).forEach(fn);
  document.addEventListener('touchstart', (e) => {
    g = null;
    if (!Phone.on || e.touches.length !== 1) return;
    const t = e.touches[0];
    if (t.clientX <= 28 || e.target.closest(SKIP)) return;
    const tabs = tabsHere();
    if (!tabs) return;
    g = { x0: t.clientX, y0: t.clientY, dx: 0, on: false, tabs, el: tabs.area(), ctx: here() };
  }, { passive: true });
  // the page changed under the finger (a task opened from a tap just before, or one closed): the swipe is dropped,
  // and whatever it moved is put back, so it never switches tabs on a page that isn't showing any more
  const here = () => `${ui.view}|${ui.taskId || ''}|${ui.thread || ''}`;
  const drop = () => { const cur = g; g = null; if (cur) each(cur.el, (el) => { el.style.transition = ''; el.style.transform = ''; el.style.opacity = ''; }); };
  document.addEventListener('touchmove', (e) => {
    if (!g) return;
    if (g.ctx !== here()) { drop(); return; }
    const t = e.touches[0];
    const dx = t.clientX - g.x0, dy = t.clientY - g.y0;
    if (!g.on) {
      if (Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx)) { g = null; return; } // scrolling
      if (Math.abs(dx) < 14 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
      g.on = true;
    }
    e.preventDefault();
    g.dx = dx;
    each(g.el, (el) => { el.style.transition = 'none'; el.style.transform = `translateX(${dx * 0.25}px)`; el.style.opacity = String(1 - Math.min(0.35, Math.abs(dx) / 900)); });
  }, { passive: false });
  const end = () => {
    if (g && g.ctx !== here()) { drop(); return; }
    if (!g || !g.on) { g = null; return; }
    const cur = g; g = null;
    const reset = (els) => each(els, (el) => { el.style.transition = 'transform .2s ease, opacity .2s ease'; el.style.transform = ''; el.style.opacity = ''; });
    const btns = cur.tabs.btns;
    const i = btns.findIndex((b) => b.classList.contains('on'));
    const j = cur.dx < -60 ? i + 1 : cur.dx > 60 ? i - 1 : i;
    if (j === i || j < 0 || j >= btns.length) { reset(cur.el); return; }
    btns[j].click();
    const now = cur.tabs.area();
    each(now, (el) => { el.classList.remove('ph-in-l', 'ph-in-r'); void el.offsetWidth; el.classList.add(cur.dx < 0 ? 'ph-in-r' : 'ph-in-l'); el.style.transform = ''; el.style.opacity = ''; });
    reset((cur.el || []).filter((el) => !now.includes(el)));
  };
  document.addEventListener('touchend', end);
  document.addEventListener('touchcancel', end);
})();


/* iPhone app 10+: bottom-sheet menus move like iOS sheets — they rise on Apple's sheet curve, and when closed (an
   option picked, a tap on the dark area, dragged down) they slide down from where they are while the dark area
   fades, instead of vanishing. The closing sheet stays on screen as .menu.ph-out for that moment; nothing counts it
   as an open menu. */
const SheetMotion = (() => {
  const OUT = 300, EASE = 'cubic-bezier(.32, .72, 0, 1)';
  const tuned = () => typeof Pager !== 'undefined' && Pager.lists() && Phone.on;
  function out(m) {
    const pan = m && m.parentElement && m.parentElement.classList.contains('ph-pan') ? m.parentElement : null;
    if (pan) {
      // already dragged off the bottom: just gone; otherwise it slides on down from where it is
      const rest = pan.scrollHeight - pan.clientHeight - pan.scrollTop;
      pan.style.pointerEvents = 'none';
      if (!tuned() || rest >= m.offsetHeight - 2) { pan.remove(); document.dispatchEvent(new Event('ph-menu-change')); return true; }
      setTimeout(() => pan.remove(), OUT + 30);
    } else if (!tuned() || !m || m.parentElement !== document.body || m.classList.contains('mention-pop')) return false;
    const from = getComputedStyle(m).transform;           // (mid-opening or mid-drag: carry on from there)
    m.classList.add('ph-out');
    m.style.pointerEvents = 'none';
    m.style.animation = 'none';
    m.style.transition = 'none';
    m.style.transform = from && from !== 'none' ? from : 'translate3d(0, 0, 0)';
    void m.offsetHeight;
    m.style.transition = `transform ${OUT}ms ${EASE}`;
    m.style.transform = 'translate3d(0, 100%, 0)';
    setTimeout(() => m.remove(), OUT + 30);
    document.dispatchEvent(new Event('ph-menu-change'));   // (the dark area fades out together with it)
    return true;
  }
  /* The sheet sits at the bottom of its own full-screen scrolling layer (.ph-pan), under an empty screen-high gap.
     Open = scrolled to the end; dragging it down is iOS scrolling that layer back (its own finger tracking, flick
     and spring), snapping to open or closed. Come to rest closed: the menu is closed. Lists inside the sheet scroll
     first and hand over at their top, as in iOS. Sheets with a search box or text field keep the page's own drag
     (they must stay above the keyboard). */
  function pan(m) {
    if (!tuned() || !m || m.parentElement !== document.body || m.classList.contains('mention-pop') || m.querySelector('input, textarea, [contenteditable="true"]')) return;
    const p = document.createElement('div');
    p.className = 'ph-pan';
    p.innerHTML = '<div class="ph-pan-gap"></div>';
    document.body.appendChild(p);
    p.appendChild(m);
    p.style.overflowY = 'hidden';
    p.scrollTop = p.scrollHeight;
    // (iPhone registers a new scrolling area only after the next layout: switch scrolling on a moment later)
    setTimeout(() => requestAnimationFrame(() => { p.style.overflowY = ''; p.scrollTop = p.scrollHeight; }), 60);
    let touching = false, settleT = null, moved = false;
    p.addEventListener('touchstart', () => { touching = true; moved = true; }, { passive: true });
    const lift = () => { touching = false; clearTimeout(settleT); settleT = setTimeout(settle, 120); };
    p.addEventListener('touchend', lift, { passive: true });
    p.addEventListener('touchcancel', lift, { passive: true });
    const open = () => p.scrollHeight - p.clientHeight;
    function settle() {
      if (touching || !p.isConnected || m.classList.contains('ph-out')) return;
      if (p.scrollTop <= 2) closeMenus();
    }
    // pulled up past open, iOS lifts the sheet off the bottom with its bounce: the sheet's colour fills in under it
    const fill = document.createElement('div');
    fill.className = 'ph-pan-fill';
    fill.style.background = getComputedStyle(m).backgroundColor;
    p.appendChild(fill);   // (over the sheet's own shadow, so the fill and the sheet read as one piece)
    // At rest the sheet floats: a gap on the sides and below, every corner rounded like the screen's. Pulled up past
    // open it grows to the edges and its bottom corners square off, following the finger; let go, it springs back.
    // (Only its outline changes — clip-path — so nothing inside moves or reflows.) The fill under a lifted sheet has
    // the same sides and bottom corners, so the two read as one piece.
    // (now the same floating card as the iPhone's own sheets — its gap and corners come from the page's styles —
    //  so the outline no longer changes as it's pulled: that part glitched)
    const shape = () => {};
    const GAP = 8, R = 44, GROW = 70;
    const shapeOld = (over) => {
      const k = Math.max(0, Math.min(1, over / GROW)), g = GAP * (1 - k), rb = R * (1 - k);
      if (over > 0) {
        m.style.clipPath = `inset(0 ${g}px 0 ${g}px round ${R}px ${R}px 0 0)`;
        fill.style.left = fill.style.right = fill.style.bottom = g + 'px';
        fill.style.borderRadius = `0 0 ${rb}px ${rb}px`;
        fill.style.height = Math.ceil(over + 30 - g) + 'px';   // (reaching up into the sheet's empty bottom padding)
      } else {
        m.style.clipPath = `inset(0 ${GAP}px ${GAP}px ${GAP}px round ${R}px)`;
        fill.style.height = '0';
      }
    };
    shape(0);
    let filled = false;
    p.addEventListener('scroll', () => {
      const over = p.scrollTop - open();
      if (over > 0) { shape(over); filled = true; }
      else if (filled) { shape(0); filled = false; }
      if (m.classList.contains('ph-out') || !moved) return;   // (not the opening itself: the dark area fades in on its own)
      const k = Math.max(0, Math.min(1, p.scrollTop / Math.max(1, open())));
      const s = document.getElementById('ph-menu-scrim');
      if (s) { s.style.transition = 'none'; s.style.animation = 'none'; s.style.opacity = String(k); }
      clearTimeout(settleT);
      settleT = setTimeout(settle, 120);
    }, { passive: true });
  }
  // an option lights up the moment a finger is on it (not when it lifts); a drag or scroll takes the light off
  let lit = null, y0 = 0;
  const unlit = () => { if (lit) { lit.classList.remove('ph-press'); lit = null; } };
  document.addEventListener('touchstart', (e) => {
    unlit();
    if (!tuned() || e.touches.length !== 1) return;
    const mi = e.target.closest && e.target.closest('.menu:not(.ph-out) .mi');
    if (!mi) return;
    lit = mi; y0 = e.touches[0].clientY;
    mi.classList.add('ph-press');
  }, { passive: true, capture: true });
  document.addEventListener('touchmove', (e) => { if (lit && Math.abs(e.touches[0].clientY - y0) > 8) unlit(); }, { passive: true, capture: true });
  document.addEventListener('touchend', () => setTimeout(unlit, 60), { passive: true, capture: true });
  document.addEventListener('touchcancel', unlit, { passive: true, capture: true });
  return { tuned, out, pan, OUT, EASE };
})();

/* Phone pop-up menus (reactions, ••• menus, priority, people…): darken everything behind and stop the
   page scrolling underneath. Tapping the dark area closes the menu. (The @mention list while typing is left alone.) */
(() => {
  let scrim = null;
  const open = () => !!document.querySelector('body > .menu:not(.mention-pop):not(.ph-out):not(.ns-probe), .ph-pan > .menu:not(.ph-out)');
  const sync = () => {
    const on = Phone.on && open();
    document.body.classList.toggle('ph-menu-open', on);
    if (on && !scrim) {
      scrim = document.createElement('div');
      scrim.id = 'ph-menu-scrim';
      const shut = (e) => { e.preventDefault(); e.stopPropagation(); closeMenus(); sync(); };
      scrim.addEventListener('touchstart', shut, { passive: false });
      scrim.addEventListener('click', shut);
      document.body.appendChild(scrim);
    } else if (!on && scrim) {
      const sc = scrim; scrim = null;
      if (SheetMotion.tuned()) {
        // (fading out under its own id, so a menu opened straight after gets a fresh dark area)
        const cs = getComputedStyle(sc);
        sc.style.cssText += `;position:fixed;inset:0;z-index:${cs.zIndex};background:${cs.backgroundColor};opacity:${cs.opacity};pointer-events:none`;
        sc.id = 'ph-menu-scrim-out';
        void sc.offsetHeight;
        sc.style.transition = `opacity ${SheetMotion.OUT}ms ${SheetMotion.EASE}`; sc.style.opacity = '0';
        setTimeout(() => sc.remove(), SheetMotion.OUT + 30);
      }
      else sc.remove();
    }
  };
  // iPhone only registers a newly shown scrolling area after it next lays the page out, so the first swipe
  // in a fresh menu did nothing. Show each new menu's scrolling parts as not scrollable for a moment,
  // then switch scrolling on: that change makes iPhone register them straight away.
  const wake = (m) => {
    const els = [m, ...m.querySelectorAll('.ap-list')];
    els.forEach((el) => { el.style.overflowY = 'hidden'; });
    setTimeout(() => requestAnimationFrame(() => els.forEach((el) => { el.style.overflowY = ''; })), 60);
  };
  new MutationObserver((recs) => {
    recs.forEach((r) => r.addedNodes.forEach((n) => { if (Phone.on && n.nodeType === 1 && n.classList.contains('menu')) wake(n); }));
    // every sheet that opens gives the same light knock as the task's ⋯ (people pickers, search lists… made outside
    // showMenu); a sheet that already knocked isn't knocked twice (taps closer than 0.15 s count as one)
    recs.forEach((r) => r.addedNodes.forEach((n) => { if (Phone.on && n.nodeType === 1 && n.classList.contains('menu') && !n.classList.contains('mention-pop') && !n.classList.contains('ns-probe')) Haptic.light(); }));
    sync();
  }).observe(document.body, { childList: true });
  document.addEventListener('ph-menu-change', sync);
  document.addEventListener('touchmove', (e) => {
    if (!document.body.classList.contains('ph-menu-open')) return;
    const inMenu = e.target.closest && e.target.closest('.menu');
    if (!inMenu) { e.preventDefault(); return; }
    // inside the menu: allow scrolling only where there is something to scroll
    if (inMenu.parentElement && inMenu.parentElement.classList.contains('ph-pan')) return;   // (iOS drags the sheet itself)
    let el = e.target;
    while (el && el !== inMenu.parentElement) { if (el.scrollHeight > el.clientHeight + 1 && /(auto|scroll)/.test(getComputedStyle(el).overflowY)) return; el = el.parentElement; }
    e.preventDefault();
  }, { passive: false });
})();

/* Phone pop-ups as bottom sheets: drag down by the handle (or from the top of a scrolled-up list) to close,
   and keep the sheet above the keyboard when a search box in it is being typed in. */
(() => {
  const root = document.documentElement;
  const fit = () => {
    const v = window.visualViewport;
    if (!v) return;
    const kb = Math.max(0, Math.round(window.innerHeight - v.height - v.offsetTop));
    root.style.setProperty('--ph-kb', kb + 'px');
    // (an iPhone Home Screen app shrinks the whole page for the keyboard, so this number can stay 0 there;
    //  the comment box uses the typing check below instead)
    root.style.setProperty('--ph-vh', Math.round(v.height) + 'px');
  };
  if (window.visualViewport) { visualViewport.addEventListener('resize', fit); visualViewport.addEventListener('scroll', fit); }
  fit();
  // (the iPhone app's page can start tiny and grow without telling visualViewport: a stale small height here made
  //  every sheet a short strip at the bottom; so also on resizes, when a sheet opens, and every second)
  window.addEventListener('resize', fit);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) fit(); });
  setInterval(() => { if (!document.hidden) fit(); }, 1000);
  new MutationObserver(() => { if (document.querySelector('body > .menu:not(.ph-out)')) fit(); }).observe(document.body || document.documentElement, { childList: true });
  // typing on a phone means the on-screen keyboard is up: drop the home-bar spacing under the comment box then
  const typing = () => { const a = document.activeElement; root.classList.toggle('ph-typing', !!(Phone.on && a && a.closest && a.closest('#detail .tm-composer') && (a.isContentEditable || /^(INPUT|TEXTAREA)$/.test(a.tagName)))); };
  document.addEventListener('focusin', typing); document.addEventListener('focusout', () => setTimeout(typing, 50));
  // Same feel as the review / New task sheets: the sheet follows the finger from its first movement
  // (taking over before iPhone starts scrolling or bouncing the list), and springs or slides on release.
  let drag = null;
  const scroller = (el, menu) => { while (el && el !== menu.parentElement) { if (el.scrollHeight > el.clientHeight + 1 && /(auto|scroll)/.test(getComputedStyle(el).overflowY)) return el; el = el.parentElement; } return null; };
  const scrimEl = () => document.getElementById('ph-menu-scrim');
  document.addEventListener('touchstart', (e) => {
    drag = null;
    if (!Phone.on || e.touches.length !== 1) return;
    const m = e.target.closest && e.target.closest('body > .menu:not(.mention-pop):not(.ph-out)');
    if (!m) return;
    const y = e.touches[0].clientY, top = m.getBoundingClientRect().top;
    const handle = y - top <= 44 && !e.target.closest('input, textarea, [contenteditable="true"]');
    const sc = scroller(e.target, m);
    if (!handle && sc && sc.scrollTop > 0) return;          // a scrolled list scrolls; it never drags the sheet
    if (!handle && e.target.closest('input, textarea, [contenteditable="true"], .react-pick')) return;
    drag = { m, y0: y, t0: Date.now(), dy: 0, h: m.offsetHeight, handle, decided: handle, live: handle };
  }, { passive: true });
  document.addEventListener('touchmove', (e) => {
    if (!drag) return;
    const raw = e.touches[0].clientY - drag.y0;
    if (!drag.decided) {                                     // from the middle: a clear move down drags, up scrolls, a tap stays a tap
      if (Math.abs(raw) < 8) return;
      drag.decided = true;
      if (raw < 0) { drag = null; return; }
      drag.live = true; drag.y0 += 8;
    }
    if (!drag.live) return;
    e.preventDefault();
    if (!drag.started) {
      drag.started = true;
      drag.m.style.animation = 'none'; drag.m.style.transition = 'none';
      const s = scrimEl(); if (s) s.style.transition = 'none';
      const inp = drag.m.querySelector('input:focus'); if (inp) inp.blur();
    }
    drag.dy = Math.max(0, e.touches[0].clientY - drag.y0);
    drag.m.style.transform = `translate3d(0, ${drag.dy}px, 0)`;
    const s = scrimEl(); if (s) s.style.opacity = String(1 - Math.min(1, drag.dy / drag.h));
  }, { passive: false });
  const end = () => {
    if (!drag) return;
    const d = drag; drag = null;
    if (!d.started) return;                                  // a tap on the handle does nothing special
    const s = scrimEl();
    const fast = d.dy > 30 && d.dy / Math.max(1, Date.now() - d.t0) > 0.5;
    if ((d.dy > Math.min(140, d.h * 0.3) || fast) && SheetMotion.tuned()) { closeMenus(); return; }   // (slides on from where the finger left it)
    if (d.dy > Math.min(140, d.h * 0.3) || fast) {
      d.m.style.transition = 'transform .22s ease-in'; d.m.style.transform = 'translate3d(0, 100%, 0)';
      if (s) { s.style.transition = 'opacity .22s ease-in'; s.style.opacity = '0'; }
      setTimeout(() => { if (d.m.isConnected) closeMenus(); }, 200);
    } else {
      d.m.style.transition = 'transform .22s cubic-bezier(.2,.8,.2,1)'; d.m.style.transform = '';
      if (s) { s.style.transition = 'opacity .22s ease'; s.style.opacity = ''; }
    }
  };
  document.addEventListener('touchend', end, { passive: true });
  document.addEventListener('touchcancel', end, { passive: true });
})();

/* Phone: touch and hold a comment for one sheet with reactions, Reply, Edit comment, Copy text and
   Delete comment (instead of the small buttons on each comment). A short buzz confirms the hold:
   phones that support vibration vibrate; on iPhone (iOS 18 and later) a hidden switch gives a haptic tap. */
(() => {
  const HOLD = 450;
  let timer = null, el = null, x0 = 0, y0 = 0, swallow = 0, lifted = true, held = null;
  const buzz = () => {
    if (Haptic.on()) return Haptic.medium();   // (iPhone app 8+: iOS's own tap)
    try { if (navigator.vibrate && navigator.vibrate(12)) return; } catch (e) { /* no vibration */ }
    try {
      const l = document.createElement('label');
      l.style.cssText = 'position:fixed;left:-200px;top:0;opacity:0;pointer-events:none';
      l.innerHTML = '<input type="checkbox" switch>';
      l.addEventListener('click', (e) => e.stopPropagation());   // (its tap never reaches the page: it would close a sheet)
      document.body.appendChild(l); l.click();
      setTimeout(() => l.remove(), 400);
    } catch (e) { /* no haptics */ }
  };
  const cancel = () => { clearTimeout(timer); timer = null; if (el) el.classList.remove('ph-pressing'); el = null; };
  function sheet(id) {
    const t = task(ui.taskId);
    const c = t && (t.comments || []).find((x) => x.id === id);
    if (!c) return;
    const mine = c.authorId === currentUserId || isAdm(me());
    const isReply = !!c.parentId;
    const on = c.reactions || {};
    const items = [{ html: `<div class="react-pick">${REACTIONS.map((e) => `<button data-swatch="${e}" class="${on[e] ? 'on' : ''}" aria-label="React ${e}">${e}</button>`).join('')}</div>` }];
    if (!isReply && ui.thread !== id) items.push({ label: 'Reply', icon: 'reply', run: () => { const b = document.querySelector(`.cm[data-comment="${id}"] [data-action="reply"]`); if (b) b.click(); } });
    if (mine) items.push(...editCommentItem(t, c));
    items.push({ label: 'Copy text', icon: 'copy', run: () => { try { navigator.clipboard.writeText(c.text || ''); toast('Copied'); } catch (e) { toast('Could not copy'); } } });
    if (mine) items.push('-', { label: 'Delete comment', icon: 'trash', danger: true, run: () => deleteComment(id) });
    const m = showMenu(document.body, items, { native: 12 });
    m.classList.add('cm-sheet');
    m._onSwatch = (emoji) => toggleReaction(id, emoji);
  }
  document.addEventListener('touchstart', (e) => {
    if (!Phone.on || e.touches.length !== 1) return;
    const cm = e.target.closest && e.target.closest('.cm[data-comment]');
    if (!cm || e.target.closest('a, button, [contenteditable="true"], .c-files, .composer')) return;
    cancel();
    el = cm; x0 = e.touches[0].clientX; y0 = e.touches[0].clientY;
    cm.classList.add('ph-pressing');
    timer = setTimeout(() => {
      const id = cm.dataset.comment;
      cancel(); buzz();
      cm.classList.add('ph-held'); setTimeout(() => cm.classList.remove('ph-held'), 450);
      // the finger is still down where the sheet now appears: lifting it mustn't tap (or highlight) what's under it.
      // The sheet ignores touches until the finger is up, and taps are swallowed for a moment after.
      swallow = Infinity; lifted = false;
      sheet(id);
      const m = document.querySelector('.menu.cm-sheet:not(.ph-out)');
      if (m) { m.style.pointerEvents = 'none'; held = m; }
    }, HOLD);
  }, { passive: true });
  document.addEventListener('touchmove', (e) => { if (timer && Math.hypot(e.touches[0].clientX - x0, e.touches[0].clientY - y0) > 10) cancel(); }, { passive: true });
  const lift = (e) => {
    if (swallow === Infinity && !lifted) {
      e.preventDefault(); lifted = true;
      swallow = Date.now() + 400;
      const m = held; held = null;
      setTimeout(() => { if (m) m.style.pointerEvents = ''; }, 350);
    }
    cancel();
  };
  document.addEventListener('touchend', lift, { passive: false });
  document.addEventListener('touchcancel', lift, { passive: false });
  document.addEventListener('click', (e) => { if (Date.now() < swallow) { e.preventDefault(); e.stopPropagation(); } }, true);
  document.addEventListener('contextmenu', (e) => { if (Phone.on && e.target.closest && e.target.closest('.cm[data-comment]')) e.preventDefault(); });
})();

/* Phone comment box: open while typing, or while it holds a draft, files or a reply; the handle tucks it away */
(() => {
  let raf = 0;
  const sync = () => {
    raf = 0;
    if (!Phone.on) return;
    document.querySelectorAll('#detail .tm-composer').forEach((c) => {
      const ed = c.querySelector('.rt-editor');
      const has = ed && (ed.textContent.trim() || ed.querySelector('img, .mention'));
      const busy = c.contains(document.activeElement) || has || c.querySelector('.cb-files, .cb-replying');
      c.classList.toggle('ph-open', !!busy && !c.classList.contains('ph-min'));
    });
  };
  const soon = () => { if (!raf) raf = requestAnimationFrame(sync); };
  document.addEventListener('focusin', (e) => { const c = e.target.closest && e.target.closest('#detail .tm-composer'); if (c) c.classList.remove('ph-min'); soon(); });
  document.addEventListener('focusout', () => setTimeout(soon, 150));
  document.addEventListener('input', (e) => { if (e.target.closest && e.target.closest('#detail .tm-composer')) soon(); });
  new MutationObserver(soon).observe(document.documentElement, { childList: true, subtree: true });
  // the handle: tap it or pull it down to tuck the box away (the draft is kept)
  let y0 = null, box = null;
  document.addEventListener('touchstart', (e) => {
    const c = e.target.closest && e.target.closest('#detail .tm-composer.ph-open');
    if (!c || e.touches[0].clientY - c.getBoundingClientRect().top > 26) return;
    y0 = e.touches[0].clientY; box = c;
  }, { passive: true });
  document.addEventListener('touchend', (e) => {
    if (box === null) return;
    const dy = (e.changedTouches[0] || {}).clientY - y0, c = box; box = null;
    if (dy > 24 || Math.abs(dy) < 6) {
      c.classList.add('ph-min');
      const ed = c.querySelector('.rt-editor'); if (ed) ed.blur();
      if (document.activeElement && c.contains(document.activeElement)) document.activeElement.blur();
      sync();
    }
  }, { passive: true });
})();


/* Phone: a task's date wheel. iPhone fills an empty date with today the moment its wheel opens and reports it as
   a change, which saved today straight away (and closed the wheel). Changes are held while the wheel is open and
   saved once when it closes, only if the date really changed. (Picking today, which iPhone already shows, can't be
   told apart from just closing it, so a closed wheel keeps what it shows.) */
(() => {
  const SEL = '#d-due, #d-start, #d-golive';
  const was = new WeakMap(), moves = new WeakMap();
  let replay = false;
  document.addEventListener('focusin', (e) => { const el = e.target; if (Phone.on && el.matches && el.matches(SEL)) was.set(el, el.value); }, true);
  document.addEventListener('change', (e) => {
    const el = e.target;
    if (replay || !Phone.on || !el.matches || !el.matches(SEL) || !was.has(el) || document.activeElement !== el) return;
    moves.set(el, (moves.get(el) || 0) + 1);
    e.stopImmediatePropagation();
  }, true);
  document.addEventListener('input', (e) => { const el = e.target; if (!replay && Phone.on && el.matches && el.matches(SEL) && was.has(el) && document.activeElement === el) e.stopImmediatePropagation(); }, true);
  document.addEventListener('focusout', (e) => {
    const el = e.target;
    if (!el.matches || !el.matches(SEL) || !was.has(el)) return;
    const before = was.get(el); was.delete(el); moves.delete(el);
    if (el.value === before) return;
    replay = true;
    try { el.dispatchEvent(new Event('change', { bubbles: true })); } finally { replay = false; }
  }, true);
})();

/* Phone: touch and hold a file or a folder in Client Assets for its sheet (the same as its ⋯), like a comment.
   A short buzz confirms the hold, and lifting the finger doesn't also open what's under it. */
(() => {
  const HOLD = 450, SEL = '.ca-tile[data-id], .cf-card[data-id]:not(.add), #detail .tile[data-id]';
  // a task's attachments: the sheet is made from the tile's own buttons
  const NAMES = { 'copy-att': ['Copy', 'copy', 'Paste into a comment or description'], quicklook: ['Preview', 'search'], 'reveal-att': ['Download', 'download'], 'remove-att': ['Remove', 'trash'] };
  function tileSheet(card) {
    const btns = [...card.querySelectorAll('.tile-actions [data-action]')].filter((b) => NAMES[b.dataset.action]);
    if (!btns.length) return false;
    const items = [];
    btns.forEach((b) => {
      const [label, ic, hint] = NAMES[b.dataset.action];
      const danger = b.dataset.action === 'remove-att';
      if (danger) items.push('-');
      items.push({ label, icon: ic, hint, danger, run: () => b.click() });
    });
    showMenu(card, items, { native: true });
    return true;
  }
  let timer = null, el = null, x0 = 0, y0 = 0, swallow = 0;
  const cancel = () => { clearTimeout(timer); timer = null; if (el) el.classList.remove('ph-pressing'); el = null; };
  const buzz = () => {
    if (Haptic.on()) return Haptic.medium();   // (iPhone app 8+: iOS's own tap)
    try { if (navigator.vibrate && navigator.vibrate(12)) return; } catch (e) { /* none */ }
    try { const l = document.createElement('label'); l.style.cssText = 'position:fixed;left:-200px;top:0;opacity:0;pointer-events:none'; l.innerHTML = '<input type="checkbox" switch>'; l.addEventListener('click', (e) => e.stopPropagation()); document.body.appendChild(l); l.click(); setTimeout(() => l.remove(), 400); } catch (e) { /* none */ }
  };
  document.addEventListener('touchstart', (e) => {
    if (!Phone.on || e.touches.length !== 1) return;
    const card = e.target.closest && e.target.closest(SEL);
    if (!card || e.target.closest('button, a, input')) return;
    cancel();
    el = card; x0 = e.touches[0].clientX; y0 = e.touches[0].clientY;
    card.classList.add('ph-pressing');
    t0 = Date.now();
    timer = setTimeout(fire, HOLD);
  }, { passive: true });
  let t0 = 0;
  function fire() {
    const c = el; cancel();
    if (!c) return;
    const more = c.querySelector('.ca-more, .cf-more');
    if (!more && !c.querySelector('.tile-actions [data-action]')) return;
    buzz();   // (first: its hidden switch's tap would otherwise close the sheet that just opened)
    if (more) more.click(); else tileSheet(c);
    swallow = Infinity;   // (until the finger is lifted, however long it stays down: lifting it mustn't tap the picture or close the sheet)
    const m = document.querySelector('body > .menu:not(.ph-out), .ph-pan > .menu:not(.ph-out)'); if (m) { m.style.pointerEvents = 'none'; heldMenu = m; }
  }
  // iPhone takes over a held picture (its own drag) and cancels the touch just before the hold time: a hold that
  // far along counts
  document.addEventListener('touchcancel', () => { if (timer && Date.now() - t0 > 250) fire(); }, true);
  document.addEventListener('dragstart', (e) => { if (Phone.on && e.target.closest && e.target.closest(SEL)) e.preventDefault(); }, true);
  document.addEventListener('touchmove', (e) => { if (timer && Math.hypot(e.touches[0].clientX - x0, e.touches[0].clientY - y0) > 10) cancel(); }, { passive: true });
  let heldMenu = null;
  const letGo = () => { const m = heldMenu; heldMenu = null; if (m) setTimeout(() => { m.style.pointerEvents = ''; }, 350); };
  document.addEventListener('touchend', (e) => { if (Date.now() < swallow) { e.preventDefault(); if (swallow === Infinity) { swallow = Date.now() + 400; letGo(); } } cancel(); }, { passive: false });
  document.addEventListener('touchcancel', () => { if (swallow === Infinity) { swallow = Date.now() + 400; letGo(); } }, true);
  document.addEventListener('touchcancel', cancel, { passive: true });
  document.addEventListener('click', (e) => { if (Date.now() < swallow && !(e.target.closest && e.target.closest('.menu'))) { e.preventDefault(); e.stopPropagation(); } }, true);
})();

/* Phone: a box being typed in stays in sight when the keyboard comes up (in the iPhone app the page gets shorter
   instead of iPhone pushing the whole page up, so the page itself brings the box into view) */
(() => {
  const typingIn = () => { const a = document.activeElement; return a && a !== document.body && (a.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName)) && a.type !== 'date' ? a : null; };
  const reveal = () => {
    const a = typingIn();
    if (!a || !Phone.on) return;
    const r = a.getBoundingClientRect(), vh = window.visualViewport ? window.visualViewport.height : innerHeight;
    if (r.top >= 60 && r.bottom <= vh - 12) return;   // already in sight
    // (the comment box sits at the bottom by itself; anything else scrolls into the middle of what's left)
    if (a.closest && a.closest('.tm-composer')) return;
    try { a.scrollIntoView({ block: 'center', behavior: 'smooth' }); } catch (e) { a.scrollIntoView(); }
  };
  let t = 0;
  const soon = () => { clearTimeout(t); t = setTimeout(reveal, 120); };
  window.addEventListener('resize', soon);
  if (window.visualViewport) visualViewport.addEventListener('resize', soon);
  document.addEventListener('focusin', () => { setTimeout(reveal, 450); });
})();

/* Phone: a message card at the top (a new update, Good morning…) swipes away — to the right, or up — like iPhone's
   own banners. A short drag springs back; a tap still opens it. */
(() => {
  let g = null;
  document.addEventListener('touchstart', (e) => {
    g = null;
    const c = e.touches.length === 1 && e.target.closest && e.target.closest('#notif-root .notif-card');
    if (!c || !Phone.on) return;
    g = { c, x0: e.touches[0].clientX, y0: e.touches[0].clientY, t0: Date.now(), dx: 0, dy: 0, on: false };
  }, { passive: true });
  document.addEventListener('touchmove', (e) => {
    if (!g) return;
    g.dx = e.touches[0].clientX - g.x0; g.dy = e.touches[0].clientY - g.y0;
    if (!g.on && Math.hypot(g.dx, g.dy) < 8) return;
    g.on = true;
    e.preventDefault();
    const x = Math.max(g.dx, -g.dx * 0.15), y = Math.min(g.dy, g.dy * 0.15);   // (right and up move freely; the other ways resist)
    g.c.style.transition = 'none';
    g.c.style.transform = `translate(${x}px, ${y}px)`;
    g.c.style.opacity = String(1 - Math.min(0.6, Math.max(x, -y) / 400));
  }, { passive: false });
  document.addEventListener('touchend', (e) => {
    if (!g || !g.on) { g = null; return; }
    const { c, dx, dy, t0 } = g; g = null;
    e.preventDefault();   // (a swipe isn't a tap: it doesn't open the update)
    const ms = Math.max(1, Date.now() - t0);
    const right = dx > 70 || (dx > 25 && dx / ms > 0.45), up = -dy > 40 || (-dy > 15 && -dy / ms > 0.4);
    c.style.transition = 'transform .22s cubic-bezier(.2,.8,.2,1), opacity .22s';
    if (right || up) {
      c.style.transform = right ? `translate(${innerWidth}px, 0)` : `translate(0, -160px)`;
      c.style.opacity = '0';
      c.style.pointerEvents = 'none';
      setTimeout(() => c.remove(), 230);
    } else { c.style.transform = ''; c.style.opacity = ''; }
  }, { passive: false });
})();

/* Phone: a tap on a task (Home, My Tasks, lists, the Trash) or in Client Assets acts as the finger lifts. iPhone sometimes makes no
   click at all from a clean tap (seen with the tap trace: several taps in a row on Home after closing a task did
   nothing), so the page doesn't wait for it. A finger that moved (scrolling, swiping), a hold, a second finger, or a
   tap that only stops a gliding list does nothing extra. */
(() => {
  // (and Client Assets: client cards, folders and files — there a first tap sometimes only "hovered" and a second
  //  was needed)
  const SEL = '.pc[data-task], #content .task-row[data-task], .tr-row.tr-open[data-action="tr-view"], #content .ca-card[data-action="open-client"], #content .cf-card[data-action="open-cfolder"], #content .ca-tile[data-action="tile-open"]';
  let g = null, lastScroll = 0;
  document.addEventListener('scroll', () => { lastScroll = Date.now(); }, { capture: true, passive: true });
  document.addEventListener('touchstart', (e) => {
    g = null;
    if (!Phone.on || e.touches.length !== 1 || Date.now() - lastScroll < 120) return;
    const row = e.target.closest && e.target.closest(SEL);
    if (!row || e.target.closest('input, textarea, select, label, [contenteditable="true"], .tr-file')) return;
    g = { row, target: e.target, x0: e.touches[0].clientX, y0: e.touches[0].clientY, t0: Date.now() };
  }, { passive: true });
  document.addEventListener('touchmove', (e) => { if (g && (e.touches.length !== 1 || Math.hypot(e.touches[0].clientX - g.x0, e.touches[0].clientY - g.y0) > 10)) g = null; }, { passive: true });
  document.addEventListener('touchcancel', () => { g = null; }, { passive: true });
  document.addEventListener('touchend', (e) => {
    const cur = g; g = null;
    if (!cur || e.defaultPrevented || e.touches.length || Date.now() - cur.t0 > 400 || !cur.row.isConnected || !cur.target.isConnected) return;
    e.preventDefault();   // (iPhone makes no click of it now: it's done here, once)
    if (cur.row.matches('.tr-row')) { trashTaskView(cur.row.dataset.id); return; }
    cur.target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window, clientX: cur.x0, clientY: cur.y0 }));
  }, { passive: false });
})();

/* iPhone app 5+: the page stays full height under the keyboard and is told how much of it the keyboard covers
   (window.__e11Kb from the app). The open task, sheets and pop-ups end at the keyboard's top (--ios-kb); the list
   behind never changes size, so nothing has to be redrawn when the keyboard goes. Something typed into on a page
   itself is scrolled into view above the keyboard. */
(() => {
  const root = document.documentElement;
  // stepped (iPhone app 7+): the app moves --ios-kb itself every frame with the keyboard's own timing (__e11KbStep),
  // so the comment box rides with the keyboard instead of racing ahead of it on a CSS curve of its own
  window.__e11Kb = (px, ms, stepped) => {
    root.classList.add('ios-kb');
    if (stepped) root.style.setProperty('--ios-kb-t', '0ms');
    else {
      root.style.setProperty('--ios-kb-t', Math.max(0, Math.min(600, Number(ms) || 250)) + 'ms');
      root.style.setProperty('--ios-kb', Math.max(0, Number(px) || 0) + 'px');
    }
    root.classList.toggle('ios-kb-up', px > 0);
    if (px > 0) reveal();
  };
  window.__e11KbStep = (px) => { root.style.setProperty('--ios-kb', Math.max(0, Number(px) || 0) + 'px'); };
  function reveal() {
    const a = document.activeElement;
    if (!a || !a.closest || a.closest('#detail, .ph-scrim, .scrim, .menu') || !a.closest('#content')) { root.classList.remove('ios-kb-content'); return; }
    root.classList.add('ios-kb-content');
    setTimeout(() => { try { a.scrollIntoView({ block: 'center', behavior: 'smooth' }); } catch (e) { /* fine */ } }, 280);
  }
  document.addEventListener('focusin', () => { if (root.classList.contains('ios-kb-up')) reveal(); });
  document.addEventListener('focusout', () => setTimeout(() => { if (!root.classList.contains('ios-kb-up')) root.classList.remove('ios-kb-content'); }, 300));
})();

/* Phone: the comment box's + and its Photos · Camera · Files bar don't take the focus from the text, so the keyboard
   stays up while the bar is open; typing again closes the bar */
(() => {
  const keep = (e) => { if (Phone.on && e.target.closest && e.target.closest('#detail .tm-composer [data-action="attach-comment"], #detail .tm-composer .ph-attach-bar button, #detail .tm-composer .cb-x')) e.preventDefault(); };
  document.addEventListener('mousedown', keep, true);
  document.addEventListener('pointerdown', keep, true);
  document.addEventListener('input', (e) => { const c = e.target.closest && e.target.closest('#detail .tm-composer .composer.ph-attach-on'); if (c) c.classList.remove('ph-attach-on'); }, true);
})();

/* Where the finger last went down: the file picker's menu opens on that button (app.js pickFiles) */
(() => {
  const note = (e) => { const t = e.touches ? e.touches[0] : e; if (t) { window.__e11LastDown = { x: t.clientX, y: t.clientY }; window.__e11LastDownEl = e.target; } };
  document.addEventListener('touchstart', note, { capture: true, passive: true });
  document.addEventListener('mousedown', note, true);
})();

/* iPhone app 9+: a task's Details and Comments sit side by side and iOS itself swipes between them (snap-to-page,
   iOS's own flick and spring, no work for the page while the finger moves). The highlighted pill slides with the
   finger; the tab changes when the page settles (no redraw). A tap on Details / Comments glides there. A swipe from
   the very left edge is still "back". Older apps, the browser and the Mac app keep the swipe below (JS). */
const Pager = (() => {
  let on = false, lists = false;   // on: a task's Details / Comments (app 9+) · lists: My Tasks, Inbox, Team (app 10+)
  const root = document.documentElement;
  if (typeof Host !== 'undefined' && Host.isIOSApp) {
    NativeMac.call('appInfo').then((r) => {
      on = Number(r && r.shell) >= 9;
      lists = Number(r && r.shell) >= 10;
      root.classList.toggle('ph-pager', on);
      if (on && ui.taskId) sync(true);
      if (lists && Phone.on && ['mytasks', 'inbox', 'team'].includes(ui.view)) renderContent();
    }).catch(() => {});
  }
  const body = () => document.querySelector('#detail .tm-body');
  const seg = () => document.querySelector('#detail .ph-seg.in-task');
  const width = (b) => b.clientWidth || 1;
  let tapped = false, settleT = null, lastNear = null;
  // the pill: one highlight that slides between the two buttons (--pg: 0 = Details, 1 = Comments)
  function paintPill(p) {
    const s = seg();
    if (!s) return;
    if (!s.querySelector('.ph-seg-ind')) s.insertAdjacentHTML('afterbegin', '<span class="ph-seg-ind" aria-hidden="true"></span>');
    p = Math.max(0, Math.min(1, p));
    const btns = s.querySelectorAll('button');
    if (btns.length < 2) return;
    const a = btns[0], z = btns[1], ind = s.querySelector('.ph-seg-ind');
    ind.style.width = a.offsetWidth + 'px'; ind.style.top = a.offsetTop + 'px'; ind.style.height = a.offsetHeight + 'px'; ind.style.left = a.offsetLeft + 'px';
    ind.style.transform = `translate3d(${(z.offsetLeft - a.offsetLeft) * p}px, 0, 0)`;
    btns.forEach((b, i) => b.classList.toggle('pg-near', Math.round(p) === i));
  }
  // after every redraw of the open task: show the current tab's page straight away, wire the scroll once
  function sync(force) {
    if (!on || !Phone.on) return;
    const b = body();
    if (!b) return;
    const want = ui.sideTab === 'comments' ? 1 : 0;
    if (force || !b.__pg) b.scrollLeft = want * width(b);
    paintPill(want);
    lastNear = Math.round(b.scrollLeft / width(b));
    if (b.__pg) return;
    b.__pg = true;
    b.addEventListener('scroll', () => {
      const p = b.scrollLeft / width(b);
      paintPill(p);
      if (typeof NativeComment !== 'undefined') NativeComment.slide(Math.max(0, Math.min(1, p)));   // (the native comment box slides along)
      // the tick comes the moment the swipe passes halfway (as iOS does), not when the page has come to rest
      const near = Math.round(p);
      if (near !== lastNear && !tapped) Haptic.select();
      lastNear = near;
      clearTimeout(settleT);
      settleT = setTimeout(() => settle(b), 90);
    }, { passive: true });
  }
  // the page came to rest on Details or Comments: that's the tab now (same as tapping it, without a redraw)
  function settle(b) {
    if (!b.isConnected) return;
    const p = b.scrollLeft / width(b);
    if (Math.abs(p - Math.round(p)) > 0.02) return;
    const tab = Math.round(p) === 1 ? 'comments' : 'details';
    const was = ui.sideTab === 'comments' ? 'comments' : 'details';
    if (tab === was) { tapped = false; return; }   // (sprang back)
    const pane = document.getElementById('detail');
    const sc0 = detailScroller(); ui.tabScroll = ui.tabScroll || {};
    if (sc0) ui.tabScroll[was] = sc0.scrollTop;
    ui.sideTab = tab; ui.thread = null; ui.replyTo = null;
    if (tab === 'comments') ui.activityFilter = 'comments';
    if (pane) pane.dataset.tab = tab;
    const s = seg();
    if (s) s.querySelectorAll('button').forEach((x) => x.classList.toggle('on', x.dataset.tab === tab));
    tapped = false;
    if (tab === 'comments' && ui.tabScroll.comments == null) { const f = document.querySelector('#detail .tm-feed'); if (f) stickFeedToBottom(f); }
  }
  // a tap on Details / Comments: glide there (the tab changes when it arrives)
  document.addEventListener('click', (e) => {
    if (!on || !Phone.on) return;
    const btn = e.target.closest && e.target.closest('#detail .ph-seg.in-task [data-action="side-tab"]');
    const b = body();
    if (!btn || !b) return;
    e.preventDefault(); e.stopImmediatePropagation();
    tapped = true;
    b.scrollTo({ left: (btn.dataset.tab === 'comments' ? 1 : 0) * width(b), behavior: 'smooth' });
  }, true);
  // a swipe from the very left edge is "back": the pages don't move under it
  document.addEventListener('touchstart', (e) => {
    if (!on || !Phone.on) return;
    const t = e.touches[0];
    const edge = !!t && t.clientX <= 28;
    ['detail', 'content'].forEach((id) => { const d = document.getElementById(id); if (d) d.classList.toggle('pg-lock', edge); });
  }, { passive: true, capture: true });
  const unlock = () => ['detail', 'content'].forEach((id) => { const d = document.getElementById(id); if (d) d.classList.remove('pg-lock'); });
  document.addEventListener('touchend', unlock, true);
  document.addEventListener('touchcancel', unlock, true);

  /* My Tasks (To Do / Done), Inbox (Unread / All / Mentions), Team (Active / Past): every tab's list sits side by side
     in .pg-wrap and iOS scrolls between them; the highlight under the tabs follows the finger */
  const vScroll = {};   // each list's own up/down position, kept across redraws ("mytasks:done" → px)
  const lw = () => document.querySelector('#content .pg-page .pg-wrap');
  const ltabs = () => [...document.querySelectorAll('#content .pg-page [data-pg-k]')];
  let lTapped = false, lSettleT = null, lNear = null;
  function paintList(p) {
    const btns = ltabs();
    if (btns.length < 2) return;
    const box = btns[0].parentElement;
    let ind = box.querySelector(':scope > .pg-ind');
    if (!ind) { box.insertAdjacentHTML('afterbegin', '<span class="pg-ind" aria-hidden="true"></span>'); ind = box.querySelector(':scope > .pg-ind'); }
    p = Math.max(0, Math.min(btns.length - 1, p));
    const i = Math.min(btns.length - 2, Math.floor(p)), f = p - i;
    const a = btns[i], z = btns[i + 1];
    const x = a.offsetLeft + (z.offsetLeft - a.offsetLeft) * f, w = a.offsetWidth + (z.offsetWidth - a.offsetWidth) * f;
    const a0 = btns[0];
    ind.style.left = a0.offsetLeft + 'px'; ind.style.top = a0.offsetTop + 'px'; ind.style.height = a0.offsetHeight + 'px';
    ind.style.width = w + 'px';
    ind.style.transform = `translate3d(${x - a0.offsetLeft}px, 0, 0)`;
    btns.forEach((b, j) => b.classList.toggle('pg-near', Math.round(p) === j));
  }
  function syncLists() {
    if (!lists || !Phone.on) return;
    const w = lw();
    if (!w) return;
    const key = w.dataset.pg;
    const cols = [...w.children];
    const idx = Math.max(0, cols.findIndex((c) => c.dataset.k === w.dataset.cur));
    cols.forEach((c) => {
      const y = vScroll[key + ':' + c.dataset.k];
      if (y) c.scrollTop = y;
      c.addEventListener('scroll', () => { vScroll[key + ':' + c.dataset.k] = c.scrollTop; }, { passive: true });
    });
    w.scrollLeft = idx * width(w);
    paintList(idx);
    lNear = idx; lTapped = false;
    w.addEventListener('scroll', () => {
      const p = w.scrollLeft / width(w);
      paintList(p);
      const near = Math.round(p);
      if (near !== lNear && !lTapped) Haptic.select();
      lNear = near;
      clearTimeout(lSettleT);
      lSettleT = setTimeout(() => settleList(w), 90);
    }, { passive: true });
  }
  function settleList(w) {
    if (!w.isConnected) return;
    const p = w.scrollLeft / width(w);
    if (Math.abs(p - Math.round(p)) > 0.02) return;
    const col = w.children[Math.round(p)];
    lTapped = false;
    if (!col || col.dataset.k === w.dataset.cur) return;
    const k = col.dataset.k;
    w.dataset.cur = k;
    if (w.dataset.pg === 'mytasks') ui.myTasksTab = k;
    else if (w.dataset.pg === 'inbox') Phone.setIbf(k);
    else if (w.dataset.pg === 'team') ui.teamTab = k;
    ltabs().forEach((b) => { b.classList.toggle('on', b.dataset.pgK === k); if (b.hasAttribute('aria-selected')) b.setAttribute('aria-selected', String(b.dataset.pgK === k)); });
  }
  document.addEventListener('click', (e) => {
    if (!lists || !Phone.on) return;
    const btn = e.target.closest && e.target.closest('#content .pg-page [data-pg-k]');
    const w = lw();
    if (!btn || !w) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const i = [...w.children].findIndex((c) => c.dataset.k === btn.dataset.pgK);
    if (i < 0) return;
    lTapped = true;
    w.scrollTo({ left: i * width(w), behavior: 'smooth' });
  }, true);
  return { on: () => on, lists: () => lists, sync, syncLists };
})();

/* Touch screens: no "hover" looks at all. iPhone keeps the last tapped thing "hovered" (a grey box stays behind a
   button after its menu or sheet opens) until something else is tapped, so on a screen without a mouse every
   :hover rule of the page's styles is taken out once they've loaded. (Pressed looks — :active — stay.) */
(() => {
  if (!(window.matchMedia && matchMedia('(hover: none)').matches)) return;
  const strip = (list, owner) => {
    for (let i = list.length - 1; i >= 0; i--) {
      const r = list[i];
      if (r.cssRules && !r.selectorText) { try { strip(r.cssRules, r); } catch (e) { /* fine */ } continue; }
      if (!r.selectorText || r.selectorText.indexOf(':hover') < 0) continue;
      // (split at the top-level commas only: ":is(a, b):hover" is one selector)
      const parts = []; let depth = 0, cur = '';
      for (const ch of r.selectorText) { if (ch === '(') depth++; else if (ch === ')') depth--; if (ch === ',' && !depth) { parts.push(cur); cur = ''; } else cur += ch; }
      parts.push(cur);
      const keep = parts.filter((x) => x.indexOf(':hover') < 0);
      try { if (keep.length) r.selectorText = keep.join(','); else owner.deleteRule(i); } catch (e) { /* fine */ }
    }
  };
  const run = () => [...document.styleSheets].forEach((sh) => { try { if (!sh.__noHover) { strip(sh.cssRules, sh); sh.__noHover = true; } } catch (e) { /* another site's sheet */ } });
  run();
  window.addEventListener('load', run);
  document.addEventListener('DOMContentLoaded', run);
})();

/* iPhone app 17+: the comment box on a task's Comments is iPhone's own, on the keyboard (CommentBar.swift) — it moves
   with the keyboard itself, so the page never jumps. The page's own box is hidden (html.ph-cbar); the comments end
   above the native one (--ph-cbar). What's typed comes here as runs ({ t, b, i, u } / { m: userId, t: "@Name" }) and
   is kept as the draft (ui.commentDraft) and sent by addComment, as before; files go through the same attach and
   upload as before, shown in the native box as tiles. */
const NativeComment = (() => {
  let on = false, last = '', lastKey = null, peopleSent = false, timer = null, lastP = -1, raf = 0;
  let nf = false, nmove = false;   // 19+: iOS moves the comments list with the keyboard (nmove: while it does)
  const root = document.documentElement;
  const thumbs = new Map();   // file id → small picture (data URL) for its tile
  if (typeof Host !== 'undefined' && Host.isIOSApp) {
    NativeMac.call('appInfo').then((r) => {
      on = Number(r && r.shell) >= 17;
      nf = Number(r && r.shell) >= 19;
      root.classList.toggle('ph-cbar', on);
      if (on) { timer = setInterval(() => sync(), 400); sync(); }
    }).catch(() => {});
  }
  const call = (args) => NativeMac.call('commentBar', args).catch(() => {});
  const openTaskNow = () => (Phone.on && ui.taskId && task(ui.taskId) && document.querySelector('#detail.open') ? task(ui.taskId) : null);
  // (anything drawn over the task — a file preview, a sheet, a pop-up — hides the box)
  const covered = () => document.body.classList.contains('pv-open') || !!document.querySelector('#ph-sheet-root .ph-scrim:not(.docked), #overlay-root .scrim, #tv-root .scrim, .lightbox, .fv');

  function htmlToRuns(html) {
    const d = document.createElement('div'); d.innerHTML = html || '';
    const out = [];
    const walk = (n, st) => {
      if (n.nodeType === 3) { if (n.nodeValue) out.push({ t: n.nodeValue.replace(/ /g, ' '), ...st }); return; }
      if (n.nodeType !== 1) return;
      const tag = n.tagName;
      if (tag === 'BR') { out.push({ t: '\n' }); return; }
      if (n.classList.contains('mention') && n.dataset.user) { out.push({ m: n.dataset.user, t: n.textContent }); return; }
      const s2 = { ...st };
      if (tag === 'B' || tag === 'STRONG') s2.b = 1;
      if (tag === 'I' || tag === 'EM') s2.i = 1;
      if (tag === 'U') s2.u = 1;
      if (/^(DIV|P|LI|BLOCKQUOTE|PRE|UL|OL|H\d)$/.test(tag) && out.length && !/\n$/.test(out[out.length - 1].t || '')) out.push({ t: '\n' });
      [...n.childNodes].forEach((c) => walk(c, s2));
    };
    [...d.childNodes].forEach((c) => walk(c, {}));
    return out;
  }
  function runsToHtml(runs) {
    return (runs || []).map((r) => {
      if (r.m) return `<span class="mention" data-user="${esc(r.m)}" contenteditable="false">${esc(r.t || '')}</span>`;
      let h = esc(r.t || '').replace(/\n/g, '<br>');
      if (r.u) h = `<u>${h}</u>`;
      if (r.i) h = `<i>${h}</i>`;
      if (r.b) h = `<b>${h}</b>`;
      return h;
    }).join('');
  }
  function fileOf(a) {
    const kind = fileKind(a);
    const src = kind === 'image' && Host.isNative ? imgUrl(a, 240) : a.thumb ? posterUrl(a) : '';
    if (src && !thumbs.has(a.id)) { thumbs.set(a.id, null); NativeSheet.thumb(src).then((v) => { thumbs.set(a.id, v); last = ''; sync(); }); }
    return { id: a.id, name: a.name, ext: (fileExt(a.name) || 'file').slice(0, 4), video: kind === 'video', ...(thumbs.get(a.id) ? { thumb: thumbs.get(a.id) } : {}) };
  }
  function sendPeople() {
    if (peopleSent) return;
    peopleSent = true;
    const us = activeUsers();
    Promise.all(us.map((u) => NativeSheet.personFor(u.id).then((person) => ({ id: u.id, name: fullName(u), email: u.email || '', role: roleOf(u), person }))))
      .then((people) => call({ people })).catch(() => { peopleSent = false; });
  }
  // the box's state from the open task (called after every redraw, on upload progress, and every so often)
  function sync(force) {
    if (!on) return;
    const t = openTaskNow();
    const show = !!t && !covered();
    if (!t) { const s = JSON.stringify({ show: false }); if (s !== last) { last = s; lastKey = null; call({ show: false, task: null }); } return; }   // (task: null — 20+: no task open, so opened again it starts at the latest comment)
    sendPeople();
    const thread = ui.thread ? t.comments.find((c) => c.id === ui.thread) : null;
    const cid = thread ? thread.id : (ui.replyTo && t.comments.some((c) => c.id === ui.replyTo) ? ui.replyTo : null);
    const key = draftKey(t, cid);
    const target = cid && t.comments.find((c) => c.id === cid);
    const inThread = !!cid && ui.thread === cid;
    const up = ui.commentUp && ui.commentUp[key];
    const st = {
      show, key,
      placeholder: inThread ? 'Reply to this thread' : cid ? 'Write a reply' : 'Write a comment',
      replying: target && !inThread ? { name: target.authorId === currentUserId ? 'your comment' : firstName(target.authorId) } : null,
      files: (ui.commentFiles[key] || []).map(fileOf),
      uploading: up ? { n: up.total || 1, frac: up.frac || 0 } : null,
      accent: NativeSheet.colorRGB(getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#5b4bf0'),
      // (20+: which task — the comments screen shows its comments; "task~comment~n~person": a comment opened from the
      // Inbox, to flash, or a person to @mention in the box — each once per n)
      task: (() => { if (ui.cmFocus && ui.cmFocus.task !== ui.taskId) ui.cmFocus = null; const f = ui.cmFocus; return ui.taskId ? (f ? `${ui.taskId}~${f.id || ''}~${f.n}~${f.mention || ''}` : ui.taskId) : null; })(),
      // (19+: where the comments list is, so iOS can find its scroll view and move it with the keyboard)
      feed: (() => { const f = !window.__e11CommentsOnly && nf && root.classList.contains('ph-cb-on') ? feed() : null; if (!f) return null; const r = f.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(f.clientWidth), Math.round(f.clientHeight)]; })(),
      // (19+: the "jump to the latest" button, tapped through iOS so the keyboard stays)
      jump: (() => { const b = nf && root.classList.contains('ph-cb-on') ? document.querySelector('#detail .jl') : null; if (!b) return null; const r = b.getBoundingClientRect(); return r.width ? [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)] : null; })(),
    };
    if (lastP < 0) slide(window.__e11CommentsOnly ? 1 : ui.sideTab === 'comments' ? 1 : 0, true);
    const s = JSON.stringify(st);   // (what's typed isn't part of the comparison: it's only sent for a new box)
    const fresh = key !== lastKey || force;
    if (s === last && !fresh) return;
    last = s;
    if (fresh) { st.runs = htmlToRuns(ui.commentDraft[key] || ''); lastKey = key; }
    call(st);
  }
  // Details / Comments: the box shows only while Comments is at rest (0 = Details, 1 = Comments). The moment a swipe
  // leaves Comments it goes (and the keyboard with it); it comes back once Comments is reached — following the finger
  // frame by frame across the bridge lagged (Haris, 2026-10-30)
  function slide(p, now) {
    if (!on) return;
    // (it comes in as the swipe nears Comments — not after it has come to rest — and goes as soon as it leaves)
    const at = lastP === 1 ? (p > 0.8 ? 1 : 0) : (p > 0.9 ? 1 : 0);
    root.classList.toggle('ph-cb-on', at === 1);
    if (at === lastP && !now) return;
    lastP = at;
    call({ p: at });
    if (at === 1) setTimeout(() => sync(), 0);   // (where the list is, straight away: the keyboard may come at once)
  }
  const feed = () => document.querySelector('#detail .tm-feed');
  const atEnd = (f) => !!f && f.scrollHeight - f.scrollTop - f.clientHeight < 60;
  // from the native box
  window.__e11CBar = (ev) => {
    const t = openTaskNow();
    if (!ev || !t) return;
    const cid = ev.key && String(ev.key).includes(':') ? String(ev.key).split(':')[1] : null;
    const setDraft = () => {
      const html = runsToHtml(ev.runs);
      ui.commentDraft[ev.key] = html;
      const box = document.querySelector(`#detail [data-draft-key="${CSS.escape(ev.key)}"]`);
      if (box) box.innerHTML = html;
      Unsent.save();
    };
    if (ev.ev === 'draft') { setDraft(); return; }
    if (ev.ev === 'send') {
      setDraft();
      const f = feed(); const end = atEnd(f);
      if (addComment(cid)) { lastKey = null; sync(true); if (window.__e11CommentsOnly) setTimeout(() => NativeMac.call('cmEnd', { animated: true }).catch(() => {}), 60); else if (end) setTimeout(() => { const g = feed(); if (g) g.scrollTop = g.scrollHeight; }, 60); }
      return;
    }
    if (ev.ev === 'attach') { attachFiles('comment', cid, null, ev.source || null); return; }   // (Photos / Camera / Files straight away)
    if (ev.ev === 'removeFile') {
      const list = ui.commentFiles[ev.key] || [];
      const a = list.find((x) => x.id === ev.id);
      ui.commentFiles[ev.key] = list.filter((x) => x.id !== ev.id);
      if (a) safeTrash([a.path]);
      Unsent.save();
      if (!refreshComposerFiles(ev.key)) renderDetail();
      sync();
      return;
    }
    if (ev.ev === 'cancelReply') { ui.replyTo = null; renderDetail(); call({ focus: true }); }
  };
  // the box's height (it grows as lines are typed): the comments keep that much room, and stay at the latest
  window.__e11CBarH = (h) => { const f = feed(), end = atEnd(f); root.style.setProperty('--ph-cbar', Math.max(0, Number(h) || 0) + 'px'); if (end && f && !nmove && !window.__e11CommentsOnly) f.scrollTop = f.scrollHeight; };
  // 19+: iOS moves the list with the keyboard itself (start); once it's up the page keeps that room (up, the same
  // picture); once it's down the page lets go of it (down). Nothing here moves the list meanwhile.
  window.__e11FeedKb = (k, T) => {
    if (k === 'start') { nmove = true; return; }
    const f = feed();
    if (f) f.style.transform = '';
    if (k === 'up') { kbPad = kbTarget = Math.max(0, Number(T) || 0); root.style.setProperty('--ph-kbpad', kbPad + 'px'); }
    if (k === 'down') { kbPad = 0; root.style.setProperty('--ph-kbpad', '0px'); }
    nmove = false;
  };
  /* The keyboard sliding up / down on Comments: only the comments list moves, by a transform — no page redraw on every
     frame (the page re-laid itself out each frame and it stuttered, Haris 2026-10-30). Once the keyboard is up, the
     transform becomes padding + scroll (looks the same, lets the whole list be scrolled); going down, the other way. */
  const safeB = (() => { let v = null; return () => { if (v == null) { const d = document.createElement('div'); d.style.cssText = 'position:fixed;visibility:hidden;padding-bottom:env(safe-area-inset-bottom)'; document.body.appendChild(d); v = parseFloat(getComputedStyle(d).paddingBottom) || 0; d.remove(); } return v; }; })();
  let kbTarget = 0, kbPad = 0, kbGap = 0;
  // how far the list really has to move: a short list (empty room under its last comment) moves only by what the
  // keyboard would cover of it — moving it the whole way and back made it jump (Haris, 2026-10-30)
  const roomUnder = (f) => {
    const last = f.lastElementChild;
    if (!last) return f.clientHeight;
    const r = f.getBoundingClientRect(), pad = parseFloat(getComputedStyle(f).paddingBottom) || 0;
    return Math.max(0, (r.bottom - pad) - last.getBoundingClientRect().bottom);
  };
  const comments = () => on && root.classList.contains('ph-cb-on') && openTaskNow() ? feed() : null;
  const kb0 = window.__e11Kb;
  window.__e11Kb = (px, ms, stepped) => {
    if (nmove && comments()) { if (kb0) kb0(px, ms, stepped); return; }   // (iOS is moving the list itself)
    const f = comments();
    kbTarget = Math.max(0, Number(px) || 0);
    if (f && kbTarget > 0 && kbPad === 0) kbGap = roomUnder(f);   // (coming up: measured once, before anything moves)
    if (f && kbTarget === 0 && kbPad > 0) {
      // going down: padding back to a transform, so the list can ride down with the keyboard
      const T = kbPad, st = f.scrollTop; kbPad = 0;
      root.style.setProperty('--ph-kbpad', '0px');
      kbGap = roomUnder(f);
      const shift = Math.max(0, T - kbGap);
      f.scrollTop = Math.max(0, st - shift);
      f.style.transform = shift ? `translate3d(0, ${-shift}px, 0)` : '';
    }
    if (kb0) kb0(px, ms, stepped);
  };
  const step0 = window.__e11KbStep;
  window.__e11KbStep = (px) => {
    if (nmove && comments()) return;
    const f = comments();
    if (!f) { if (step0) step0(px); return; }
    const T = Math.max(0, (Number(px) || 0) - safeB());
    const shift = Math.max(0, T - kbGap);
    if (kbTarget > 0 && Number(px) >= kbTarget) {
      // up and resting: the transform becomes padding + scroll (the same picture)
      const st = f.scrollTop;
      kbPad = T;
      root.style.setProperty('--ph-kbpad', T + 'px');
      f.scrollTop = st + shift;
      f.style.transform = '';
      return;
    }
    f.style.transform = shift ? `translate3d(0, ${-shift}px, 0)` : '';
  };
  // the page's own box asked for the keyboard (Reply, after Send, after Cancel reply…): the native box takes it
  const focus0 = HTMLElement.prototype.focus;
  HTMLElement.prototype.focus = function (...a) {
    if (on && this.id === 'd-comment' && openTaskNow()) { call({ focus: true }); return; }
    return focus0.apply(this, a);
  };
  // redraws, uploads and the files row: the box follows
  if (typeof renderDetail === 'function') { const rd = renderDetail; renderDetail = function (...a) { const r = rd.apply(this, a); if (on) setTimeout(() => sync(), 0); return r; }; }
  if (typeof refreshComposerFiles === 'function') { const rf = refreshComposerFiles; refreshComposerFiles = function (...a) { const r = rf.apply(this, a); if (on) setTimeout(() => sync(), 0); return r; }; }
  if (typeof closeDetail === 'function') { const cd = closeDetail; closeDetail = function (...a) { if (on) { call({ show: false, blur: true }); last = JSON.stringify({ show: false }); lastKey = null; lastP = -1; nmove = false; root.classList.remove('ph-cb-on'); kbPad = 0; root.style.setProperty('--ph-kbpad', '0px'); } return cd.apply(this, a); }; }
  if (typeof Unsent !== 'undefined' && Unsent.progress) { const pg = Unsent.progress; Unsent.progress = function (...a) { const r = pg.apply(this, a); if (on) sync(); return r; }; }
  // an @mention added to the end of what's in the box (the creator's name on Details), then the keyboard
  // (keep: false — the main page while the app's comments screen may take the box over: the name goes into the box but
  // not into this page's saved draft, which would otherwise be left behind once the comments screen has sent it)
  function mention(uid, keep = true) {
    const t = openTaskNow(), u = userById(uid);
    if (!on || !t || !u) return false;
    const thread = ui.thread ? t.comments.find((c) => c.id === ui.thread) : null;
    const cid = thread ? thread.id : (ui.replyTo && t.comments.some((c) => c.id === ui.replyTo) ? ui.replyTo : null);
    const key = draftKey(t, cid);
    const cur = ui.commentDraft[key] || '';
    const d = document.createElement('div'); d.innerHTML = cur;
    const txt = d.textContent || '';
    const html = `${cur}${txt && !/\s$/.test(txt) ? '&nbsp;' : ''}<span class="mention" data-user="${esc(u.id)}" contenteditable="false">@${esc(fullName(u))}</span>&nbsp;`;
    ui.commentDraft[key] = html;
    lastKey = null; sync(true);
    if (keep) {
      const box = document.querySelector(`#detail [data-draft-key="${CSS.escape(key)}"]`);
      if (box) box.innerHTML = html;
      Unsent.save();
    } else if (cur) ui.commentDraft[key] = cur; else delete ui.commentDraft[key];
    // (once the box is up on Comments)
    [350, 700].forEach((ms) => setTimeout(() => call({ focus: true }), ms));
    return true;
  }
  window.NativeComment = { get on() { return on; }, sync, mention };
  return { get on() { return on; }, sync, slide, htmlToRuns, runsToHtml, mention };
})();

/* ================= iPhone app 20+: a task's Comments on a screen of their own (Haris, 2026-10-31) =================
   The app keeps a second page (window.__e11CommentsOnly, html.cm-only) that shows only the open task's comments, as
   its whole page, over the task below its header — so they're scrolled by iOS itself (the keyboard, staying at the
   latest comment, the jump button), with nothing here moving them. The app says which task; once it's drawn, the app
   hears so (cmReady) and shows it. */
const CommentsOnly = (() => {
  const on = window.__e11CommentsOnly === true;
  if (on) document.documentElement.classList.add('cm-only', 'ph-cb-on');
  // a comment on this screen: brought into view (a little above the middle) and flashed; kept there while pictures
  // above it load, until a finger touches the screen (here the page itself scrolls, not .tm-feed)
  const place = (el) => {
    let stick = true;
    const go = () => {
      if (!stick || !el.isConnected) return;
      const vh = window.innerHeight, r = el.getBoundingClientRect();
      window.scrollTo(0, Math.max(0, window.scrollY + r.top - Math.max(16, Math.min(vh * 0.3, vh - r.height - 120))));
    };
    go();
    window.addEventListener('touchstart', () => { stick = false; }, { once: true, passive: true });
    [120, 400, 900, 1600].forEach((ms) => setTimeout(go, ms));
  };
  const flash = (el) => { el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash'); setTimeout(() => el.classList.remove('flash'), 2600); };
  window.__e11CmPlace = place;
  let lastFocus = '';
  window.__e11ShowComments = (arg) => {
    const [id, fid, fn, mu] = String(arg || '').split('~');
    if (!on || typeof task !== 'function' || !task(id)) return 'no';
    // opened from the Inbox: that comment (in its thread, for a reply), once per tap in the Inbox; or a person to @mention
    const fkey = fid || mu ? `${fid}~${fn}~${mu}` : '';
    const fresh = !!fkey && fkey !== lastFocus;
    const fc = fresh && fid ? (task(id).comments || []).find((c) => c.id === fid) : null;
    const mention = fresh && mu ? mu : null;
    if (fkey) lastFocus = fkey;
    const same = ui.taskId === id && !!document.querySelector('#detail.open .tm-feed') && !fc;
    if (!same) { ui.thread = fc ? fc.parentId || null : null; ui.replyTo = null; }
    ui.sideTab = 'comments'; ui.activityFilter = 'comments';
    if (ui.taskId !== id || !document.querySelector('#detail.open')) { ui.pendingThread = ui.thread; openTask(id); } else if (!same) renderDetail();
    requestAnimationFrame(() => requestAnimationFrame(() => {
      NativeMac.call('cmReady', { id }).catch(() => {});
      // (after the app has shown the screen at the latest comment)
      if (fc) setTimeout(() => { const el = document.querySelector(`#detail .cm[data-comment="${fc.id}"]`); if (el) { place(el); flash(el); } }, 220);
      if (mention) setTimeout(() => { if (window.NativeComment) NativeComment.mention(mention); }, 220);
    }));
    return 'ok';
  };
  // a swipe right on the comments screen: out of a thread first ('thread'); otherwise the app goes back to Details
  window.__e11CmBack = () => { if (!on || !ui.thread) return ''; const b = document.querySelector('#detail .th-back'); if (b) b.click(); return 'thread'; };
  return { on };
})();

/* ================= iPhone app 23+: Home (E11 Day / My Day) drawn by the app itself (Haris, 2026-10-31) =================
   Same design and the same lists as the page's Home (Phone.myDayData); the page stays the engine: it sends what to show
   (the "home" command) whenever it changes, and the app's taps come back here (window.__e11Home). The colours are read
   from the page's own Home, drawn under it, so the two always match (light / dark). Not here: the Office Admin's Home.
   NATIVE_HOME = false: the page's own Home again (no app build needed). */
const NATIVE_HOME = true;
const NativeHome = (() => {
  let on = false, last = '', shown = false, toastAction = null;
  const people = new Map(), asked = new Set();
  let peopleSent = '';
  if (NATIVE_HOME && window.__e11CommentsOnly !== true && typeof Host !== 'undefined' && Host.isIOSApp) {
    NativeMac.call('appInfo').then((r) => { on = Number(r && r.shell) >= 23; if (on) { setInterval(sync, 350); sync(); } }).catch(() => {});
  }
  const call = (a) => NativeMac.call('home', a).catch(() => {});
  const rgba = (c) => { const m = /rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?/.exec(c || ''); return m ? [+m[1], +m[2], +m[3], m[4] == null ? 1 : +m[4]] : null; };
  const rgbOfCss = (css) => { try { return NativeSheet.colorRGB(css); } catch (e) { return null; } };
  // a person's round picture for the app (photo or initials), fetched once
  function person(uid) {
    if (!uid) return;
    if (!people.has(uid) && !asked.has(uid)) {
      asked.add(uid);
      NativeSheet.personFor(uid).then((v) => { people.set(uid, v); }).catch(() => { asked.delete(uid); });
    }
  }
  const visible = () => {
    if (!Phone.on || !(ui.view === 'home' || ui.view === 'today') || ui.search || (typeof isOffice === 'function' && isOffice())) return false;
    if (ui.taskId || document.querySelector('#detail.open')) return false;
    if (document.querySelector('#ph-sheet-root .ph-scrim:not(.docked), #overlay-root .scrim, #tv-root .scrim, .menu, .lightbox, .fv')) return false;
    return !!document.querySelector('#content .ph-page .ph-stats');
  };
  // the page's own Home's colours (drawn under the app's), so the app's match them exactly
  function look() {
    const pg = document.querySelector('#content .ph-page');
    // (the header is pinned outside the page itself: looked for anywhere on the page)
    const g = (sel, prop) => { const el = (pg && pg.querySelector(sel)) || document.querySelector('#content ' + sel) || document.querySelector(sel); return el ? rgba(getComputedStyle(el)[prop]) : null; };
    const anyBg = (el) => { while (el) { const c = rgba(getComputedStyle(el).backgroundColor); if (c && c[3] > 0) return c; el = el.parentElement; } return null; };
    const fab = document.querySelector('.ph-fab');
    const fr = fab && fab.getBoundingClientRect();
    const top = document.getElementById('ph-top'), tr = top && !top.hidden ? top.getBoundingClientRect() : null;
    return {
      headH: tr ? Math.round(tr.bottom) : null, headBg: top ? anyBg(top) : null,
      light: document.documentElement.dataset.theme === 'light',
      bg: anyBg(pg), sub: g('.ph-sub', 'color'), h1: g('.ph-head h1', 'color'),
      round: g('.ph-round', 'backgroundColor'), roundIc: g('.ph-round', 'color'), roundLine: g('.ph-round', 'borderTopColor'),
      statBg: g('.ph-stats > div', 'backgroundColor'), statLine: g('.ph-stats > div', 'borderTopColor'), statLabel: g('.ph-stats span', 'color'),
      statG: g('.ph-stats b.g', 'color'), statR: g('.ph-stats b.r', 'color'), statA: g('.ph-stats b.a', 'color'),
      gh: g('.ph-gh', 'color'), empty: g('.ph-empty', 'color'),
      card: g('.pc', 'backgroundColor'), cardLine: g('.pc:not(.late)', 'borderTopColor'), lateLine: g('.pc.late', 'borderTopColor'),
      title: g('.pc-title', 'color'), meta: g('.pc-meta', 'color'), sep: g('.pc-meta em', 'color'),
      late: g('.pc-meta b.late', 'color'), today: g('.pc-meta b.today', 'color'), doneTitle: g('.pc.done .pc-title', 'color'),
      tag: g('.ph-tag:not(.urgent)', 'color'), tagBg: g('.ph-tag:not(.urgent)', 'backgroundColor'),
      urgent: g('.ph-tag.urgent', 'color'), urgentBg: g('.ph-tag.urgent', 'backgroundColor'),
      more: g('.av.more', 'color'), moreBg: g('.av.more', 'backgroundColor'),
      fab: fab ? { bg: rgba(getComputedStyle(fab).backgroundColor), line: rgba(getComputedStyle(fab).borderTopColor), rect: [fr.left, fr.top, fr.width, fr.height] } : null,
    };
  }
  // the cards and groups: the shared rules (web/rules.js), the same the server sends the app (/api/home)
  const rules = () => E11Rules.make(db, currentUserId, todayStr());
  function cardOf(t, o = {}) { const c = rules().cardOf(t, o); c.av.forEach((a) => person(a.id)); return c; }
  function model() {
    const m = E11Rules.home(db, currentUserId, todayStr());
    if (!m) return null;
    Object.keys(m.people || {}).forEach(person);
    delete m.people;   // (the page sends the pictures apart, once loaded)
    m.look = look();
    return m;
  }
  function sync() {
    if (!on) return;
    let m;
    try { m = visible() ? model() : null; } catch (e) { m = null; }
    if (!m) { if (shown) { shown = false; last = ''; call({ show: false }); } return; }
    // the pictures of the people on it, once each has loaded (sent apart: they're big and don't change)
    const ps = [...people.keys()].sort().join(',');
    if (ps !== peopleSent) { peopleSent = ps; call({ people: Object.fromEntries(people) }); }
    const s = JSON.stringify(m);
    if (s === last) return;
    last = s; shown = true;
    call(m);
  }
  // taps on the app's Home: what the page's own would do
  window.__e11Home = (ev) => {
    if (!ev) return;
    const click = (sel) => { const el = document.querySelector(sel); if (el) el.click(); };
    // (nothing on the page is scrolled to follow the app's Home: that left the page's other screens scrolled away —
    //  only their titles showed, Haris 2026-10-31)
    const pageScroller = document.scrollingElement; if (pageScroller && pageScroller.scrollTop) pageScroller.scrollTop = 0;
    if (ev.ev === 'open' && ev.id && task(ev.id)) openTask(ev.id);
    // swipe left on a card: Copy link / Delete (the app has asked "Delete this task?" first); long press: Attach Files
    else if (ev.ev === 'copy' && ev.id) TaskLink.copy(ev.id);
    else if (ev.ev === 'delete' && ev.id && task(ev.id)) { if (can('deleteTask')) deleteTaskFlow(ev.id); }
    else if (ev.ev === 'attach' && ev.id && task(ev.id)) attachFiles('task', null, null, ev.source || null, ev.id);
    // the In review box: My Tasks, waiting for the CD's review — for those who see everyone's (E11 Day), all Account
    // Managers & Admins too; an AM sees their own as usual (Haris, 2026-10-31)
    else if (ev.ev === 'review') {
      ui.workF = null; ui.myTasksTab = 'todo';
      if (Work.lead()) { const F = Work.f(); F.cd = true; if (seesAll()) F.team = true; }
      go('mytasks');
    }
    // swipe right: Done (as the page's own tick: not ready → why; done → toast with Undo; a done task → reopened)
    else if (ev.ev === 'done' && ev.id && task(ev.id)) {
      const t = task(ev.id);
      if (!ev.done) { if (t.done) { setDone(t, false); commit({ delay: 0 }); } }
      else if (!t.done) {
        // (the app's toasts are short — Haris, 2026-10-31: the page's longer ones were cut off)
        if (!canComplete(t)) {
          const s = sectionOf(t), needDone = !(s && isDoneName(s.name)), needCD = !cdOK(t);
          toast(needDone && needCD ? 'Set to Done and get CD approval first' : needCD ? 'Waiting for CD approval' : 'Set the status to Done first');
          return;
        }
        (async () => {
          if (!(await askClientApproval(t))) return;
          setDone(t, true);
          commit({ delay: 0 });
          if (t.done) toast('Task completed', { label: 'Undo', run: () => { setDone(t, false); commit(); } });
        })();
      }
    }
    // … and Due: the date sheet the task page uses (iPhone's own calendar; Today / Clear)
    else if (ev.ev === 'due' && ev.id && task(ev.id)) {
      const t = task(ev.id);
      if (!can('editDates', t)) { denied(); return; }
      NativeMac.call('pickDate', { value: t.due || '', min: '', max: '', clearable: !!t.due, md: false })
        .then((r) => {
          if (!r || r.ok === false || r.cancel) return;
          const v = r.clear ? '' : r.date || '';
          if (v === (t.due || '')) return;
          setDue(t, v || null); commit();
        })
        .catch(() => {});
    }
    else if (ev.ev === 'toast') { const a = toastAction; toastAction = null; if (a && a.run) a.run(); }
    // the app's own search bar (from the search circle): its results, as the page's Search finds them
    else if (ev.ev === 'find') {
      const q = String(ev.q || '').trim();
      let res = { q: ev.q || '', clients: [], tasks: [], total: 0 };
      if (q) {
        const r = taskSearch(q, { limit: 80 });
        res = {
          q: ev.q, total: r.total,
          clients: r.projects.map((p) => ({ id: p.id, name: p.name, ini: initials(p.name), rgb: rgbOfCss(p.color), open: db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length })),
          tasks: r.tasks.map((h) => cardOf(h.t)),
        };
      }
      call({ search: res });
      return;
    }
    else if (ev.ev === 'client' && ev.id) go('project', ev.id);
    else if (ev.ev === 'search') click('#content [data-ph="search"]');
    else if (ev.ev === 'me') click('#content [data-ph-tab="me"], [data-ph-tab="me"]');
    else if (ev.ev === 'add') click('.ph-fab');
    setTimeout(sync, 0);
  };
  // a toast while the app's Home is showing (the page's own would be under it)
  function toastOut(msg, action, ms) {
    toastAction = action || null;
    call({ toast: { t: String(msg || ''), a: action ? action.label : '', ms: ms || (action ? 6000 : 3000) } });
  }
  return { sync, toast: toastOut, get on() { return on; }, get shown() { return shown; } };
})();
