/* ================= Home page =================
   Account Managers and Admins: the tasks they created and how their team is doing (layout A).
   Production, Social and everyone else: what to work on next, their pipeline and week (layout C).
   Everything comes from task data the app already keeps. The phone has its own Home. */
const Home = (() => {
  // how long ago the page came on show (the startup screen gone): 0 until then — what grows waits, held at its start, and
  // drawn again while growing it carries on where it was rather than starting over
  const grown = () => (window.__e11ShownAt ? Date.now() - window.__e11ShownAt : 0);
  // a ring's green arc (viewBox 36, r 15.9): in the Mac app it fills from 0 once as the page shows, then stays still (Haris
  // 2026-11-15 15:28: "where ever there will be a green ring … will go from 0 to current")
  const ringArc = (p, C, cls) => {
    const e = grown(), go = Host.isMacApp && e < 1200 && p > 0;
    return `<circle cx="18" cy="18" r="15.9" class="${cls} hm-arc${go ? ' hm-grow' : ''}" style="--c:${C.toFixed(1)};stroke-dasharray:${C.toFixed(1)};stroke-dashoffset:${(C * (1 - p)).toFixed(1)};${go && e > 0 ? `animation-delay:-${e}ms` : ''}" transform="rotate(-90 18 18)"/>`;
  };
  const st = { range: 'today', metric: 'done', day: null, next: 0, lane: null };
  const DAY = 86400000;
  const WD = ['Mo', 'Tu', 'We', 'Th', 'Fr'];
  const first = (u) => fullName(u).split(' ')[0];
  // "Good morning, Haris"; National Day's "Eshi Biladi" is said on its own
  const hello = (name) => { const g = greeting(); return typeof Occasions !== 'undefined' && Occasions.alone(g) ? esc(g) : `${esc(g)}, ${esc(name)}`; };
  const greeting = () => { const o = typeof Occasions !== 'undefined' && Occasions.greeting(todayStr()); if (o) return o; const h = new Date().getHours(); return h < 5 ? 'Good evening' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'; };
  const dateLine = () => new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
  const ymdOf = (iso) => (iso ? ymd(new Date(iso)) : null);
  const pColor = (t) => (proj(t.projectId) || {}).color || 'var(--text-3)';
  const pName = (t) => (proj(t.projectId) || {}).name || 'No client';
  const title = (t) => (t.title ? esc(t.title) : '<span class="ph">Untitled task</span>');
  const nComments = (t) => (t.comments || []).length;
  // as the iPhone's task rows (Mac page by page, Haris 2026-11-15 10:41): the Urgent / P1 (any number) tag after the title, the CD chip
  // on the line under it (✓ once approved), an overdue row's faint red
  const tag = (t) => { const p = t.done ? 'none' : prioOf(t); return p === 'urgent' ? '<span class="hm-tag urgent">Urgent</span>' : typeof p === 'number' ? `<span class="hm-tag">P${p}</span>` : ''; };   // (any number, as the iPhone: P1, P2…)
  const cdTag = (t) => { const c = !t.done && CD[t.cdStatus]; return c ? `<span class="hm-cd ${t.cdStatus === 'approved' ? 'ok' : ''}" style="--c:${c.color}" title="CD Status: ${esc(c.label)}">${t.cdStatus === 'approved' ? '✓ ' : ''}CD</span>` : ''; };
  const late = (t) => (!t.done && t.due && t.due < todayStr() ? 'late' : '');
  const nFiles = (t) => shownAtts(t).length;
  const svg = (d, w = 1.5) => `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${d}"/></svg>`;
  const IC = {
    clock: 'M8 2.2a5.8 5.8 0 1 0 0 11.6A5.8 5.8 0 0 0 8 2.2zM8 4.8V8l2.2 1.4',
    check: 'M8 2.2a5.8 5.8 0 1 0 0 11.6A5.8 5.8 0 0 0 8 2.2zM5.6 8.1l1.7 1.7 3.2-3.4',
    shield: 'M8 1.8 13 4v4c0 3-2.2 5.2-5 6.2C5.2 13.2 3 11 3 8V4z',
    chat: 'M3.2 2.9h9.6c.6 0 1 .4 1 1v6.6c0 .6-.4 1-1 1H7.4l-3 2.4v-2.4H3.2c-.6 0-1-.4-1-1V3.9c0-.6.4-1 1-1z',
    clip: 'M10.5 4.5 5.6 9.4a1.4 1.4 0 0 0 2 2l5-5a2.8 2.8 0 0 0-4-4l-5 5a4.2 4.2 0 0 0 6 6l4.4-4.4',
    flag: 'M3.5 13.5V3h7l-1.5 2.5 1.5 2.5h-7',
    tick: 'm3.5 8.4 3 3 6-6.6',
    doc: 'M4 1.8h5l3 3v9.4H4z',
    cal: 'M4.5 4.2h7a1.3 1.3 0 0 1 1.3 1.3v6.4a1.3 1.3 0 0 1-1.3 1.3h-7a1.3 1.3 0 0 1-1.3-1.3V5.5a1.3 1.3 0 0 1 1.3-1.3zM3.2 7.2h9.6M5.8 2.6v2.6M10.2 2.6v2.6',   // (the Mac app's "due today", as its board — Haris 2026-11-15)
  };
  // an icon by its name (data-i): in the Mac app 13 it shows as Apple's SF Symbol (app.js MacSF), elsewhere as drawn here
  const ik = (k, w = 1.5) => svg(IC[k], w).replace('<svg ', `<svg data-i="hm-${k}" `);
  const tick = `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.6" aria-hidden="true"><path d="${IC.tick}"/></svg>`;
  const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);
  const delta = (now, before) => {
    if (!before) return now ? { t: 'New', up: true } : null;
    const d = Math.round(((now - before) / before) * 100);
    return { t: `${d >= 0 ? '+' : ''}${d}%`, up: d >= 0 };
  };
  const chip = (d, goodUp = true) => (d ? `<span class="hm-delta ${d.up === goodUp ? 'good' : 'bad'}">${d.t}</span>` : '');
  const onTime = (t, doneAt) => !t.due || ymdOf(doneAt) <= t.due;

  // ---- this week (Monday to Friday) ----
  function week() {
    const now = new Date();
    const wd = (now.getDay() + 6) % 7; // 0 = Monday
    const mon = addDays(todayStr(), wd > 4 ? 7 - wd : -wd); // at the weekend, show next week
    return WD.map((w, i) => ({ w, d: addDays(mon, i) }));
  }
  function pickedDay(days) {
    if (st.day && days.some((x) => x.d === st.day)) return st.day;
    const t = todayStr();
    return days.some((x) => x.d === t) ? t : days[0].d;
  }
  const dayStrip = (days, sel, dot) => `<div class="hm-days">${days.map((x) => `<button type="button" class="hm-day ${x.d === sel ? 'on' : ''} ${x.d === todayStr() ? 'today' : ''}" data-hm="day" data-v="${x.d}">${x.w}<b>${parseYmd(x.d).getDate()}</b>${dot && dot(x.d) ? '<i class="hm-dot"></i>' : ''}</button>`).join('')}</div>`;

  // ---- activity ----
  function actRow(a) {
    const t = task(a.taskId);
    return `<div class="hm-act" ${t ? `data-hm="act" data-v="${t.id}" ${a.nid ? `data-nid="${a.nid}"` : ''} ${a.cid ? `data-cid="${a.cid}"` : ''}` : ''}>${avatarHTML(a.from, 32)}
      <span class="hm-act-txt"><b>${esc(fullName(userById(a.from)))}</b> <span class="hm-mute">${a.html}</span> ${t ? `<span class="hm-link">${title(t)}</span>` : ''}
        ${a.quote ? `<span class="hm-quote">“${esc(a.quote)}”</span>` : ''}
        ${a.file ? `<span class="hm-file">${ik('doc', 1.4)}<span><b>${esc(a.file.name)}</b><small>${fmtSize(a.file.size)}</small></span></span>` : ''}</span>
      <span class="hm-when">${esc(timeAgo(a.at))}</span></div>`;
  }
  const actCard = (list, empty, extra = '') => `<section class="hm-card hm-acts ${extra}">
      <div class="hm-h"><h2>Recent activity</h2><a class="hm-a" data-nav="inbox">Open Inbox</a></div>
      ${list.length ? list.map(actRow).join('') : `<div class="hm-empty">${empty}</div>`}
    </section>`;

  /* ================= A · Account Manager / Admin ================= */
  function viewLead() {
    // An Admin sees every Account Manager's and Admin's created tasks (same as E11 Day); an AM sees their own
    const admin = seesAll();   // (the Creative Director sees what an Admin sees)
    // (an AM: every task in the clients they look after; see Work.leadSet)
    const mine = Work.leadSet(admin ? db.users.filter((x) => x.role === 'am' || isAdm(x)).map((x) => x.id) : [currentUserId]);
    const open = mine.filter((t) => !t.done);
    const today = todayStr();
    const due0 = open.filter((t) => t.due === today);
    const overdue = open.filter((t) => t.due && t.due < today);
    const weekAgo = Date.now() - 7 * DAY, twoWeeks = Date.now() - 14 * DAY;
    const doneIn = (a, b) => mine.filter((t) => t.done && t.completedAt && +new Date(t.completedAt) > a && +new Date(t.completedAt) <= b).length;
    const doneWeek = doneIn(weekAgo, Date.now()), donePrev = doneIn(twoWeeks, weekAgo);
    const inReview = open.filter(reviewPending);
    const since = inReview.length ? inReview.map((t) => (t.reviews || []).filter((r) => r.state === 'pending').map((r) => r.at).sort()[0]).sort()[0] : null;

    // created tasks list
    // Overdue = past its due date; Today = due today; This week = due from today to Sunday; All open = everything open
    const wd0 = (new Date().getDay() + 6) % 7; // 0 = Monday
    const wkEnd = addDays(today, 6 - wd0);
    const RANGES = {
      late: (t) => !!t.due && t.due < today,
      today: (t) => t.due === today,
      week: (t) => !!t.due && t.due >= today && t.due <= wkEnd,
      all: () => true,
    };
    if (!RANGES[st.range]) st.range = 'today';
    const ranged = open.filter(RANGES[st.range]).sort((a, b) => (a.due || '9999').localeCompare(b.due || '9999') || byPrio(a, b));
    const rows = ranged.slice(0, 6);
    const rangeTabs = [['late', 'Overdue'], ['today', 'Today'], ['week', 'This week'], ['all', 'All open']].map(([k, l]) => { const n = open.filter(RANGES[k]).length; return `<button type="button" class="hm-tab ${st.range === k ? 'on' : ''} ${k === 'late' && n ? 'red' : ''}" data-hm="range" data-v="${k}">${l}<i>${n}</i></button>`; }).join('');
    const emptyMsg = { late: 'Nothing overdue — nice.', today: 'Nothing due today.', week: 'Nothing else due this week.', all: admin ? 'Tasks your team creates will show up here.' : 'Tasks you create will show up here.' }[st.range];

    // this month chart
    const now = new Date(), y = now.getFullYear(), m = now.getMonth();
    const nDays = new Date(y, m + 1, 0).getDate(), todayN = now.getDate();
    const inMonth = (iso, yy = y, mm = m) => { if (!iso) return false; const d = new Date(iso); return d.getFullYear() === yy && d.getMonth() === mm; };
    const ly = m ? y : y - 1, lm = m ? m - 1 : 11;
    const doneM = mine.filter((t) => t.done && inMonth(t.completedAt)), doneL = mine.filter((t) => t.done && inMonth(t.completedAt, ly, lm));
    const onT = pct(doneM.filter((t) => onTime(t, t.completedAt)).length, doneM.length);
    const onTL = pct(doneL.filter((t) => onTime(t, t.completedAt)).length, doneL.length);
    const reviewsOn = mine.flatMap((t) => (t.reviews || []).filter((r) => r.state !== 'withdrawn'));
    const M = {
      done: { l: 'Completed by the team', big: 'tasks completed', at: doneM.map((t) => t.completedAt) },
      created: { l: 'Tasks created', big: 'tasks created', at: mine.filter((t) => inMonth(t.createdAt)).map((t) => t.createdAt) },
      reviews: { l: 'Sent for CD review', big: 'sent for CD review', at: reviewsOn.filter((r) => inMonth(r.at)).map((r) => r.at) },
    };
    const cur = M[st.metric] || M.done;
    const vals = Array.from({ length: nDays }, () => 0);
    cur.at.forEach((iso) => { vals[new Date(iso).getDate() - 1]++; });
    const max = Math.max(1, ...vals);
    const X = (i) => ((i + 0.5) / nDays) * 100, Y = (v) => 100 - (v / max) * 88;
    const avg = vals.slice(0, todayN).map((_, i) => { const w = vals.slice(Math.max(0, i - 2), Math.min(todayN, i + 3)); return w.reduce((a, b) => a + b, 0) / w.length; });
    let line = avg.length ? `M${X(0)},${Y(avg[0])}` : '';
    for (let i = 1; i < avg.length; i++) { const mx = (X(i - 1) + X(i)) / 2; line += ` C${mx},${Y(avg[i - 1])} ${mx},${Y(avg[i])} ${X(i)},${Y(avg[i])}`; }
    const past = vals.slice(0, todayN), pk = past.indexOf(Math.max(...past));
    const mName = now.toLocaleDateString('en-US', { month: 'short' });
    const bars = vals.map((v, i) => `<div class="hm-bar ${i < todayN ? '' : 'future'}" style="height:${Math.max(3, (v / max) * 100)}%"><span class="hm-tip">${mName} ${i + 1} · ${v} ${esc(cur.l.toLowerCase())}</span></div>`).join('');
    const ticks = [1, 8, 15, 22, nDays].map((d) => `<span>${mName} ${d}</span>`).join('');
    const metricTabs = Object.entries(M).map(([k, v]) => `<button type="button" class="hm-tab ${st.metric === k ? 'on' : ''}" data-hm="metric" data-v="${k}">${v.l}</button>`).join('');

    // activity on tasks I created, by other people
    const acts = mine.flatMap((t) => (t.activity || []).filter((a) => a.actor && a.actor !== currentUserId).map((a) => ({ from: a.actor, html: a.text, taskId: t.id, at: a.at })))
      .concat(mine.flatMap((t) => (t.comments || []).filter((c) => c.authorId !== currentUserId).map((c) => ({ from: c.authorId, html: mentionsIn(c.html).has(currentUserId) ? 'mentioned you on' : 'commented on', quote: c.text, taskId: t.id, at: c.at, cid: c.id }))))
      .sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, 7);

    // schedule
    const days = week(), sel = pickedDay(days);
    const agenda = mine.filter((t) => t.due === sel).sort((a, b) => Number(a.done) - Number(b.done) || byPrio(a, b));
    const lateOn = (d) => d < today && mine.some((t) => !t.done && t.due === d);

    // checklist items still to do on tasks I created
    // every checklist item on the open tasks, counted all together (Haris 2026-11-15 15:28): open ones first as Home opens, and
    // the order then kept until Home is left — a ticked one stays where it is, struck through, instead of jumping away
    const allItems = open.flatMap((t) => (t.checklist || []).map((c) => ({ t, c })));
    if (!st.clOrder) st.clOrder = new Map();
    allItems.filter((x) => !st.clOrder.has(x.c.id)).sort((a, b) => Number(a.c.done) - Number(b.c.done)).forEach((x) => st.clOrder.set(x.c.id, st.clOrder.size));
    const items = allItems.sort((a, b) => st.clOrder.get(a.c.id) - st.clOrder.get(b.c.id));
    const itemsDone = items.filter((x) => x.c.done).length;

    // projects: an AM sees the projects their tasks are in, an Admin sees them all
    // (an AM also sees the clients they're Account Manager for; inactive clients are left out)
    const pSet = admin ? null : new Set(mine.map((t) => t.projectId).concat(db.projects.filter((p) => (p.ams || []).some((a) => a.id === currentUserId)).map((p) => p.id)));
    const projects = db.projects.filter((p) => !p.inactive).sort(byOrder).filter((p) => !pSet || pSet.has(p.id)).map((p) => {
      const ts = topTasks().filter((t) => t.projectId === p.id);
      const d = ts.filter((t) => t.done).length;
      return { p, open: ts.length - d, pc: pct(d, ts.length) };
    });
    // each client's line grows once as the app opens, its colour easing a little lighter to the right (Haris 2026-11-15
    // 14:08); drawn again in that first moment, it carries on where it was rather than starting over — after that, still
    const growing = grown();
    const grow = growing < 900 ? ` class="hm-grow"` : '', growDelay = growing > 0 && growing < 900 ? `animation-delay:-${growing}ms;` : '';
    const projCard = `<section class="hm-card">
        <div class="hm-h"><h2>${admin ? 'Clients' : 'My clients'}</h2><span class="hm-mute">${projects.length}</span></div>
        ${projects.length ? `<div class="hm-projs">${projects.map(({ p, open: o, pc }) => `<div class="hm-proj" data-project="${p.id}"><span class="hm-pi" style="background:${p.color}">${esc(initials(p.name))}</span><span class="hm-main"><b>${esc(p.name)}</b><span class="hm-sub">${o} open · ${pc}% done</span><span class="hm-pbar"><i${grow} style="width:${pc}%;--pc:${p.color};${growDelay}"></i></span></span></div>`).join('')}</div>` : '<div class="hm-empty">Projects with your tasks show up here.</div>'}
      </section>`;

    // team on time this month
    const team = [...new Set(doneM.flatMap((t) => t.assignees || []))].filter((u) => userById(u));

    // Team goals achieved — the Mac app's card above Schedule (Haris 2026-11-15 14:10 / 14:12: board T1's C with B's soft
    // purple tint, the +N solid): Apple's activity ring, filling from 0 once as the app opens, then still
    const goalCard = () => {
      const e = grown(), R = 30, C = 2 * Math.PI * R, p = doneM.length ? onT / 100 : 0;
      const d = doneM.length && doneL.length ? onT - onTL : null, lmName = new Date(ly, lm, 1).toLocaleDateString('en-US', { month: 'long' });
      return `<section class="hm-card hm-goal">
            <h2>Team goals achieved</h2>
            <div class="hm-gr"><svg viewBox="0 0 76 76" width="76" height="76" aria-hidden="true"><circle cx="38" cy="38" r="${R}" class="hm-ring-bg"/>${p > 0 ? `<circle cx="38" cy="38" r="${R}" class="hm-ring${e < 1200 ? ' hm-grow' : ''}" style="--c:${C.toFixed(1)};stroke-dasharray:${C.toFixed(1)};stroke-dashoffset:${(C * (1 - p)).toFixed(1)};${e > 0 && e < 1200 ? `animation-delay:-${e}ms` : ''}" transform="rotate(-90 38 38)"/>` : ''}<text x="38" y="43" text-anchor="middle">${doneM.length ? onT + '%' : '–'}</text></svg>
              <div><b>On time this month</b><span class="${d == null || d >= 0 ? 'ok' : 'warn'}">${d == null ? 'this month' : `${d >= 0 ? '↑' : '↓'} ${d >= 0 ? '+' : ''}${d}% vs ${esc(lmName)}`}</span></div></div>
            ${team.length ? `<div class="hm-avs">${avatarStack(team, 30, 5)}</div>` : ''}
            <p>${admin ? 'Team tasks' : 'Tasks you created'} finished by their due date this month</p>
          </section>`;
    };

    const statCard = (cls, ic, l, n, note, noteCls, kind) => `<button type="button" class="hm-stat" data-hm="stat" data-v="${kind}"><span class="hm-ic ${cls}">${ik(ic, 1.5)}</span><span><span class="hm-sl">${l}</span><span class="hm-sn"><b>${n}</b><span class="${noteCls}">${note}</span></span></span></button>`;

    return `<div class="hm hm-lead">
      <header class="hm-head"><div><div class="hm-date">${dateLine()}</div><h1>${hello(first(me()))}</h1></div>
        <div class="hm-btns">${Host.isMacApp ? '' : `<button type="button" class="hm-btn" data-nav="today">${esc(Work.dayTitle())}</button>`}<button type="button" class="hm-btn primary" data-action="new-task">+ New task</button></div></header>
      <section class="hm-stats">
        ${statCard('blue', Host.isMacApp ? 'cal' : 'clock', admin ? 'Team tasks due today' : 'Your tasks due today', due0.length, overdue.length ? `${overdue.length} overdue` : 'none overdue', overdue.length ? 'warn' : 'ok', 'today')}
        ${statCard('green', 'check', 'Finished by your team', doneWeek, doneWeek - donePrev >= 0 ? `↑ ${doneWeek - donePrev} vs last week` : `↓ ${donePrev - doneWeek} vs last week`, doneWeek >= donePrev ? 'ok' : 'warn', 'finished')}
        ${statCard('orange', 'shield', 'Waiting for CD review', inReview.length, since ? `oldest ${timeAgo(since)}` : 'nothing waiting', 'orange', 'cd')}
      </section>
      <div class="hm-grid">
        <div class="hm-col">
          <section class="hm-card">
            <div class="hm-h"><div class="hm-hl"><h2>${admin ? 'Team’s tasks' : Work.hasClients(currentUserId) ? 'Your clients’ tasks' : 'Your created tasks'}</h2><span class="hm-seg">${rangeTabs}</span></div><a class="hm-a" data-hm="see-all">See all</a></div>
            ${rows.length ? rows.map((t) => `<div class="hm-row ${late(t)}" data-task="${t.id}">
                <i class="hm-pc" style="background:${pColor(t)}"></i>
                <span class="hm-main"><span class="hm-tl"><span class="hm-t">${title(t)}</span>${tag(t)}</span><span class="hm-sub">${esc(pName(t))}${admin && t.createdBy !== currentUserId && userById(t.createdBy) ? ` · by ${esc(fullName(userById(t.createdBy)))}` : ''}${t.due ? ` · due <span class="due ${dueClass(t)}">${esc(fmtDue(t.due))}</span>` : ''}${cdTag(t)}</span></span>
                <span class="hm-counts"><span title="Comments">${ik('chat', 1.4)}${nComments(t)}</span><span title="Files">${ik('clip', 1.4)}${nFiles(t)}</span></span>
                <span class="hm-who">${(t.assignees || []).length ? avatarStack(t.assignees, 26, 3, t) : '<span class="hm-mute">Unassigned</span>'}</span>
                <span class="hm-st">${statusPill(t)}</span>
              </div>`).join('') + (ranged.length > rows.length ? `<button type="button" class="hm-more-btn" data-hm="see-all">+${ranged.length - rows.length} more · See all</button>` : '') : `<div class="hm-empty">${emptyMsg}</div>`}
          </section>
          <section class="hm-card">
            <div class="hm-kpis">
              <div class="hm-kpi-row">
                <div><div class="hm-sl">Completed</div><div class="hm-kv"><b>${doneM.length}</b>${chip(delta(doneM.length, doneL.length))}</div></div>
                <div><div class="hm-sl">On time</div><div class="hm-kv"><b>${doneM.length ? onT + '%' : '–'}</b>${doneM.length && doneL.length ? chip(delta(onT, onTL)) : ''}</div></div>
                <div><div class="hm-sl">Overdue</div><div class="hm-kv"><b>${overdue.length}</b></div></div>
              </div>
              <div class="hm-big"><b>${cur.at.length}</b><span>${esc(cur.big)} · ${now.toLocaleDateString('en-US', { month: 'long' })}</span></div>
            </div>
            <div class="hm-tabs">${metricTabs}</div>
            <div class="hm-chart">
              <div class="hm-bars">${bars}</div>
              <svg viewBox="0 0 100 100" preserveAspectRatio="none" class="hm-line" aria-hidden="true"><path d="${line}" vector-effect="non-scaling-stroke"/></svg>
              ${past[pk] ? `<div class="hm-peak" style="left:${X(pk)}%;top:${44 + Y(past[pk]) * 1.48}px"><span>${ik('flag', 1.6)}</span><em>Busiest day</em></div>` : ''}
              <div class="hm-ticks">${ticks}</div>
            </div>
          </section>
          ${actCard(acts, admin ? 'When people work on the team’s tasks, it shows up here.' : 'When your team works on the tasks you created, it shows up here.', 'grow')}
        </div>
        <aside class="hm-col">
          ${Host.isMacApp ? goalCard() : ''}
          <section class="hm-card">
            <div class="hm-h"><h2>Schedule</h2><span class="hm-mute">${sel === today ? 'Today' : parseYmd(sel).toLocaleDateString('en-US', { weekday: 'long' })}</span></div>
            ${dayStrip(days, sel, lateOn)}
            <div class="hm-agenda">${agenda.length ? agenda.slice(0, 5).map((t) => `<div class="hm-ag ${t.done ? 'done' : ''}" data-task="${t.id}"><i style="background:${pColor(t)}"></i><span class="hm-main"><b>${title(t)}</b><span class="hm-sub">${t.done ? 'Done' : statusInfo(t).name}${t.update ? ' · ' + esc(t.update) : ''}</span></span>${avatarStack(t.assignees || [], 22, 2, t)}</div>`).join('') : '<div class="hm-empty">Nothing due this day</div>'}${agenda.length > 5 ? `<div class="hm-mute">+${agenda.length - 5} more due this day</div>` : ''}</div>
          </section>
          ${projCard}
          <section class="hm-card">
            <div class="hm-h"><h2>Checklist</h2><span class="hm-mute">${items.length ? `${itemsDone} of ${items.length} done` : ''}</span></div>
            ${items.length ? '<div class="hm-cl-list">' + items.map(({ t, c }) => `<div class="hm-cl"><button type="button" class="hm-chk ${c.done ? 'on' : ''}" data-hm="cl" data-task-id="${t.id}" data-v="${c.id}" aria-label="Done">${tick}</button><span class="hm-main" data-task="${t.id}"><b class="${c.done ? 'struck' : ''}">${esc(c.text)}</b><span class="hm-sub">${title(t)}</span></span></div>`).join('') + '</div>' : `<div class="hm-empty">Checklist items on ${admin ? 'the team’s tasks' : 'the tasks you created'} show up here.</div>`}
          </section>
          ${Host.isMacApp ? '' : `<section class="hm-hero">
            <h2>Team on time</h2>
            <div class="hm-hn"><b>${doneM.length ? onT + '%' : '–'}</b><span>${doneM.length && doneL.length ? `${onT - onTL >= 0 ? '+' : ''}${onT - onTL}% vs<br>${new Date(ly, lm, 1).toLocaleDateString('en-US', { month: 'long' })}` : 'this month'}</span></div>
            ${team.length ? `<div class="hm-avs">${avatarStack(team, 32, 5)}</div>` : ''}
            <p>${admin ? 'Team tasks' : 'Tasks you created'} that were finished by their due date this month</p>
          </section>`}
        </aside>
      </div>
    </div>`;
  }

  /* ================= C · Production / Social ================= */
  function viewMember() {
    const u = me();
    const today = todayStr();
    const mineAll = topTasks().filter(isMine);
    const open = myTop().filter(myOpen).sort((a, b) => (a.due || '9999').localeCompare(b.due || '9999') || byPrio(a, b));

    // Up next
    const h = open.length ? open[st.next % open.length] : null;
    let hero = `<section class="hm-next empty"><div><span class="hm-pill acc">All caught up</span><h2>Nothing open on your list</h2><div class="hm-nsub">New tasks assigned to you will show up here.</div></div></section>`;
    if (h) {
      const pr = prioOf(h), rs = reviewState(h);
      const main = iReview(h) ? (rs === 'pending' ? '<button type="button" class="hm-btn primary" disabled>With the CD for review</button>' : `<button type="button" class="hm-btn primary" data-hm="submit" data-v="${h.id}">${rs === 'amend' ? 'Submit amended files' : 'Submit files for review'}</button>`)
        : `<button type="button" class="hm-btn primary" data-hm="part" data-v="${h.id}">Mark my part done</button>`;
      const cl = h.checklist || [];
      const cd = cl.filter((c) => c.done).length;
      hero = `<section class="hm-next">
        <div class="hm-nl">
          <div class="hm-chips"><span class="hm-pill acc">Up next</span>${pr !== 'none' ? `<span class="hm-pill ${pr === 'urgent' ? 'red' : ''}">${esc(prioLabel(pr))}</span>` : ''}${h.due ? `<span class="hm-pill amber">${h.due < today ? 'Overdue · ' : 'Due '}${esc(fmtDue(h.due))}</span>` : ''}${h.update ? `<span class="hm-pill" style="color:${UPDATE_COLOR(h.update)}">${esc(h.update)}</span>` : ''}<span class="hm-pill">${esc(statusInfo(h).name)}</span></div>
          <h2>${title(h)}</h2>
          <div class="hm-nsub">${esc(pName(h))}${h.createdBy && userById(h.createdBy) ? ` · Created by ${esc(fullName(userById(h.createdBy)))}` : ''} · ${nFiles(h)} files · ${nComments(h)} comments${needsCD(h) ? ' · needs CD review' : ''}</div>
          <div class="hm-nbtns">${main}<button type="button" class="hm-btn ghost" data-hm="open" data-v="${h.id}">Open task</button>${open.length > 1 ? `<button type="button" class="hm-btn text" data-hm="next">Next task → <small>${(st.next % open.length) + 1} of ${open.length}</small></button>` : ''}</div>
        </div>
        <div class="hm-ncl">
          <div class="hm-ncl-h"><span>Checklist</span><span class="mono">${cd}/${cl.length}</span></div>
          <div class="hm-prog"><i style="width:${pct(cd, cl.length)}%"></i></div>
          ${cl.length ? cl.slice(0, 5).map((c) => `<button type="button" class="hm-sub-i ${c.done ? 'on' : ''}" data-hm="cl" data-task-id="${h.id}" data-v="${c.id}"><span class="hm-box">${tick}</span><span>${esc(c.text)}</span></button>`).join('') + (cl.length > 5 ? `<div class="hm-ncl-more">+${cl.length - 5} more in the task</div>` : '') : '<div class="hm-ncl-more">No checklist on this task</div>'}
        </div>
      </section>`;
    }

    // Pipeline: my open tasks by Task Update, most used first
    const groups = new Map();
    open.forEach((t) => { const k = t.update || ''; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(t); });
    const lanes = [...groups.entries()].sort((a, b) => (a[0] === '') - (b[0] === '') || b[1].length - a[1].length).slice(0, 5);
    const laneK = lanes.some(([k]) => k === st.lane) ? st.lane : lanes.length ? lanes[0][0] : null;
    const laneC = (k) => (k ? UPDATE_COLOR(k) : 'var(--text-3)');
    const sel = laneK != null ? groups.get(laneK) : [];
    const pipeline = `<section class="hm-card">
      <div class="hm-h"><div><h2>My pipeline</h2><p class="hm-note">Your open tasks grouped by their Task Update · click one</p></div><span class="hm-mute mono">${open.length} open</span></div>
      ${lanes.length ? `<div class="hm-lanes" style="grid-template-columns:repeat(${Math.max(lanes.length, 3)},minmax(0,1fr))">${lanes.map(([k, ts]) => `<button type="button" class="hm-lane ${k === laneK ? 'on' : ''}" data-hm="lane" data-v="${esc(k)}">
          <span class="hm-lh"><span><i style="background:${laneC(k)}"></i>${esc(k || 'No Task Update')}</span><b class="mono">${ts.length}</b></span>
          ${ts.slice(0, 2).map((t) => `<span class="hm-mini" style="border-left-color:${pColor(t)}">${title(t)}</span>`).join('')}${ts.length > 2 ? `<span class="hm-more">+${ts.length - 2} more</span>` : ''}
        </button>`).join('')}</div>
        <div class="hm-lane-list">${sel.map((t) => `<div class="hm-lrow ${late(t)}" data-task="${t.id}"><i style="background:${pColor(t)}"></i><span class="hm-t">${title(t)}</span>${tag(t)}${cdTag(t)}<span class="hm-sub">${esc(pName(t))}</span><span class="due ${dueClass(t)}">${esc(fmtDue(t.due))}</span></div>`).join('')}</div>`
        : '<div class="hm-empty">No open tasks right now.</div>'}
    </section>`;

    // My week
    const days = week();
    const cal = `<section class="hm-card">
      <div class="hm-h"><div><h2>My week</h2><p class="hm-note">Your tasks on their due date (and start date) · grey = already done</p></div><span class="hm-mute">${esc(parseYmd(days[0].d).toLocaleDateString('en-US', { day: 'numeric', month: 'short' }))} – ${esc(parseYmd(days[4].d).toLocaleDateString('en-US', { day: 'numeric', month: 'short' }))}</span></div>
      <div class="hm-cal">${days.map((x) => {
        const due = mineAll.filter((t) => t.due === x.d).map((t) => ({ t, k: 'Due' }));
        const start = mineAll.filter((t) => t.start === x.d && t.due !== x.d).map((t) => ({ t, k: 'Starts' }));
        const list = due.concat(start).sort((a, b) => Number(myDoneAt(a.t) != null) - Number(myDoneAt(b.t) != null));
        return `<div><div class="hm-cal-d ${x.d === today ? 'today' : ''}">${x.d === today ? 'Today · ' : ''}${parseYmd(x.d).toLocaleDateString('en-US', { weekday: 'short', day: 'numeric' })}</div>
          <div class="hm-slot ${x.d === today ? 'today' : ''}">${list.map(({ t, k }) => { const dn = myDoneAt(t) != null; return `<div class="hm-post ${dn ? 'done' : ''} ${!dn && k === 'Due' && x.d < today ? 'late' : ''}" data-task="${t.id}" style="border-left-color:${pColor(t)}"><span>${dn ? 'Done' : k}${t.update ? ' · ' + esc(t.update) : ''}</span>${title(t)}</div>`; }).join('')}</div></div>`;
      }).join('')}</div>
    </section>`;

    // Recent activity: my Inbox
    const acts = (db.notifications || []).filter((n) => n.to === currentUserId && n.from).sort((a, b) => String(b.at).localeCompare(String(a.at))).slice(0, 4)
      .map((n) => ({ from: n.from, html: esc(n.text).replace(/&lt;(\/?)b&gt;/g, '<$1b>'), quote: n.snippet, taskId: n.taskId, at: n.at, nid: n.id }));

    // CD reviews this month
    const now = new Date();
    const thisMonth = (iso) => { if (!iso) return false; const d = new Date(iso); return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth(); };
    const myRev = db.tasks.flatMap((t) => (t.reviews || []).filter((r) => r.by === currentUserId && r.state !== 'withdrawn').map((r) => ({ t, r })));
    const monthRev = myRev.filter(({ r }) => thisMonth(r.decidedAt || r.at));
    const approved = monthRev.filter(({ r }) => r.state === 'approved').length;
    const amended = monthRev.filter(({ r }) => r.state === 'amend').length;
    const waiting = myRev.filter(({ t, r }) => r.state === 'pending' && !t.done).length;
    const firstTime = monthRev.filter(({ r }) => r.state === 'approved' && (r.round || 1) === 1).length;
    const decidedTasks = new Set(monthRev.filter(({ r }) => r.state === 'approved' || r.state === 'amend').map(({ t }) => t.id)).size;
    const ft = pct(firstTime, decidedTasks);
    const ring = 2 * Math.PI * 15.9;

    // Amendments to fix
    const amends = open.filter((t) => needsCD(t) && reviewState(t) === 'amend').map((t) => ({ t, r: lastReview(t, currentUserId) }));

    // Latest files on my tasks
    const files = mineAll.flatMap((t) => shownAtts(t).map((a) => ({ t, a }))).sort((x, y) => String(y.a.addedAt || '').localeCompare(String(x.a.addedAt || ''))).slice(0, 4);
    const thumb = ({ t, a }) => {
      const img = fileKind(a) === 'image' && Host.isNative ? `<img src="${imgUrl(a, 320)}" alt="" loading="lazy">` : '';
      return `<div class="hm-thumb" data-hm="file" data-v="${esc(a.id || a.path || a.name)}" title="${esc(a.name)} · ${esc(t.title || '')}" style="--pc:${pColor(t)}">${img}<span class="hm-kind">${esc((fileExt(a.name) || 'file').toUpperCase().slice(0, 4))}</span><span class="hm-fname">${esc(a.name)}</span></div>`;
    };

    st.files = files;   // (a file opened: the viewer, its next / previous the other files here — Haris 2026-11-15 15:28)

    // On-time streak: my finished tasks, newest first, until one was late
    const finished = mineAll.filter((t) => myDoneAt(t) && t.due).sort((a, b) => String(myDoneAt(b)).localeCompare(String(myDoneAt(a))));
    let streak = 0;
    for (const t of finished) { if (onTime(t, myDoneAt(t))) streak++; else break; }

    // the Mac app: On-time streak as Team goals achieved (Haris 2026-11-15 15:28) — the soft purple card, the ring the share of
    // your recent finished tasks that were on time with the streak in it, the rows under it, the line saying what it counts
    const streakCard = () => {
      const recent = finished.slice(0, 12), okN = recent.filter((t) => onTime(t, myDoneAt(t))).length, C = 2 * Math.PI * 15.9;
      return `<section class="hm-card hm-goal hm-streak">
            <h2>On-time streak</h2>
            <div class="hm-gr"><svg viewBox="0 0 36 36" width="76" height="76" aria-hidden="true"><circle cx="18" cy="18" r="15.9" class="hm-ring-bg"/>${recent.length ? ringArc(okN / recent.length, C, 'hm-ring') : ''}<text x="18" y="21" text-anchor="middle">${streak}</text></svg>
              <div><b>${streak === 1 ? 'Task' : 'Tasks'} in a row on time</b><span class="${!recent.length || okN === recent.length ? 'ok' : 'warn'}">${recent.length ? `${okN} of your last ${recent.length} on time` : 'nothing finished yet'}</span></div></div>
            ${recent.length ? `<div class="hm-hlist" aria-label="Recently finished">${recent.map((t) => { const ok = onTime(t, myDoneAt(t)); return `<div class="hm-hrow" data-task="${t.id}"><i class="${ok ? 'ok' : 'late'}" title="${ok ? 'On time' : 'Late'}">${icon(ok ? 'check' : 'clock')}</i><span>${esc(t.title || 'Untitled task')}</span><em>${esc(fmtDay(ymdOf(myDoneAt(t))))}</em></div>`; }).join('')}</div>` : ''}
            <p>Your tasks finished by their due date, newest first</p>
          </section>`;
    };

    const roleL = roleOf(u);
    return `<div class="hm hm-member">
      <header class="hm-head"><div><div class="hm-date">${dateLine()}${roleL ? ' · ' + esc(roleL) : ''}</div><h1>${hello(first(u))}</h1></div>
        <div class="hm-btns">${Host.isMacApp ? '' : '<button type="button" class="hm-btn" data-nav="today">My Day</button>'}${can('createTask') ? '<button type="button" class="hm-btn primary" data-action="new-task">+ New task</button>' : ''}</div></header>
      <div class="hm-grid">
        <div class="hm-col">
          ${hero}
          ${pipeline}
          ${cal}
          ${actCard(acts, 'Mentions, approvals and new assignments show up here.', 'grow')}
        </div>
        <aside class="hm-col">
          <section class="hm-card">
            <h2>My CD reviews</h2>
            <div class="hm-rev">
              <svg viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="18" r="15.9" class="trk"/>${ringArc(ft / 100, ring, 'val')}<text x="18" y="20.6" text-anchor="middle">${decidedTasks ? ft + '%' : '–'}</text></svg>
              <div><b>Approved first time</b><br><span class="mono">${approved}</span> approved · <span class="mono">${amended}</span> amended<br><span class="mono">${waiting}</span> waiting with the CD<br><small>Your submissions in ${now.toLocaleDateString('en-US', { month: 'long' })}</small></div>
            </div>
          </section>
          <section class="hm-card">
            <div class="hm-h"><h2>Amendments to fix</h2>${amends.length ? `<span class="hm-pill red solid">${amends.length}</span>` : ''}</div>
            ${amends.length ? amends.map(({ t, r }) => `<div class="hm-am" data-task="${t.id}"><b>${title(t)}</b>${r && r.noteHtml ? `<div class="hm-am-n">${avatarHTML(r.decidedBy || cdUserId(), 26)}<span>“${esc(notifPlainHTML(r.noteHtml))}”</span></div>` : ''}</div>`).join('') : '<div class="hm-empty">Nothing to fix — the CD hasn’t asked for changes.</div>'}
          </section>
          <section class="hm-card">
            <div class="hm-h"><h2>Latest files</h2><span class="hm-mute">on your tasks</span></div>
            ${files.length ? `<div class="hm-files">${files.map(thumb).join('')}</div>` : '<div class="hm-empty">Files on your tasks show up here.</div>'}
          </section>
          ${Host.isMacApp ? streakCard() : `<section class="hm-hero">
            <h2>On-time streak</h2>
            <div class="hm-hn"><b>${streak}</b><span>task${streak === 1 ? '' : 's'} in a row finished by their due date</span></div>
            ${finished.length ? `<div class="hm-hlist" aria-label="Recently finished">${finished.slice(0, 12).map((t) => { const ok = onTime(t, myDoneAt(t)); return `<div class="hm-hrow" data-task="${t.id}"><i class="${ok ? 'ok' : 'late'}" title="${ok ? 'On time' : 'Late'}">${icon(ok ? 'check' : 'clock')}</i><span>${esc(t.title || 'Untitled task')}</span><em>${esc(fmtDay(ymdOf(myDoneAt(t))))}</em></div>`; }).join('')}</div>` : ''}
          </section>`}
        </aside>
      </div>
    </div>`;
  }

  // Home left: the checklist's order is worked out afresh the next time
  function left() { st.clOrder = null; }
  function view() {
    if (Host.isNative) setTimeout(() => hydrateThumbs($('#content')), 0);
    return Work.lead() ? viewLead() : viewMember();
  }

  document.addEventListener('click', (e) => {
    if (typeof ui === 'undefined' || ui.view !== 'home') return;   // (a click before app.js has loaded)
    const el = e.target.closest('[data-hm]');
    if (!el) return;
    // home.js loads before app.js: stop the app's own click handler (it would close the task just opened)
    e.stopImmediatePropagation();
    const k = el.dataset.hm, v = el.dataset.v;
    if (k === 'range') st.range = v;
    else if (k === 'metric') st.metric = v;
    else if (k === 'day') st.day = v;
    else if (k === 'lane') st.lane = v;
    else if (k === 'next') st.next++;
    else if (k === 'all') { ui.workF = null; ui.myTasksTab = 'todo'; return go('mytasks'); }
    else if (k === 'stat') {
      // the three cards open My Tasks with the matching filter (an Admin: across the whole team)
      ui.workF = null;
      const F = Work.f();
      if (seesAll()) F.team = true;
      if (v === 'today') F.due = 'today';
      if (v === 'finished') F.finished = true;
      if (v === 'cd') F.cd = true;
      ui.myTasksTab = v === 'finished' ? 'done' : 'todo';
      return go('mytasks');
    }
    else if (k === 'see-all') {
      // My Tasks with the same list as the Home card: the team's tasks for an Admin, and the same due filter
      ui.workF = null; ui.myTasksTab = 'todo';
      const F = Work.f();
      if (seesAll()) F.team = true;
      F.due = st.range === 'all' ? null : st.range;
      return go('mytasks');
    }
    else if (k === 'open') return openTask(v);
    else if (k === 'file') {
      const list = (st.files || []).map((x) => x.a), a = list.find((x) => (x.id || x.path || x.name) === v);
      if (a) previewFile(a, list); return;
    }
    else if (k === 'act') {
      // the same as the Inbox: a mention or comment opens the task on that comment (highlighted), a review opens Review Requests
      if (el.dataset.nid && db.notifications.some((n) => n.id === el.dataset.nid)) return openNotif(el.dataset.nid);
      const t = task(v); if (!t) return;
      const c = el.dataset.cid && (t.comments || []).find((x) => x.id === el.dataset.cid);
      if (c) { ui.sideTab = ui.forceTab = 'comments'; ui.activityFilter = 'comments'; ui.pendingThread = c.parentId || null; ui.replyTo = null; ui.focusComment = c.id; }
      return openTask(t.id);
    }
    else if (k === 'submit') { const t = task(v); if (t) submitDialog(t); return; }
    else if (k === 'part') { const t = task(v); if (t) setMyPart(t, true); return; }
    else if (k === 'cl') {
      const t = task(el.dataset.taskId); const c = t && (t.checklist || []).find((x) => x.id === v);
      if (!c) return;
      c.done = !c.done; logActivity(t, `${c.done ? 'checked' : 'unchecked'} <b>${esc(c.text)}</b>`); t.updatedAt = nowISO(); commit(); return;
    }
    renderContent();
  });

  // a task right-clicked anywhere on Home: the iPhone's choices (app.js taskContextMenu)
  document.addEventListener('contextmenu', (e) => {
    if (typeof ui === 'undefined' || ui.view !== 'home') return;
    const el = e.target.closest && e.target.closest('.hm [data-task]');
    if (el && typeof taskContextMenu === 'function') taskContextMenu(e, el.dataset.task);
  });

  return { view, st, left };
})();
