/* ================= Occasions and the content calendar =================
   Occasions: the year's big days (UAE, Islamic, global, Dubai marketing). Fixed-date ones every year; moon-based
   ones (Ramadan, the Eids, Hijri New Year, Mawlid) and DSF from a table of expected dates, marked as estimates.
   Admins and Account Managers can correct a date (db.meta.occDates[id] = { date, end }) and add their own
   (db.meta.occasions = [{ id, name, date, end, greet }]). Some occasions change the greeting on the startup
   screen and Home ("Ramadan Kareem, Muhammad").

   Content calendar (Social, Account Managers and Admins): a post is a normal task with
     t.channels = ['ig', 'tt', …]   where it goes out
     t.golive   = 'YYYY-MM-DD'      the day it goes live (the calendar falls back to the due date)
     t.occasion = '<occasion id>'   what it's for
   so it keeps its assignees, files, comments and CD review. Month and Week (rows by project) views. */

const Occasions = (() => {
  const FIXED = [
    ['newyear', 'New Year’s Day', '01-01', null, 'Happy New Year'],
    ['valentine', 'Valentine’s Day', '02-14', null, null],
    ['womensday', 'International Women’s Day', '03-08', null, 'Happy Women’s Day'],
    ['mothersday', 'Mother’s Day (UAE)', '03-21', null, 'Happy Mother’s Day'],
    ['halloween', 'Halloween', '10-31', null, 'Happy Halloween'],
    ['commemoration', 'Commemoration Day', '11-30', null, null],
    ['nationalday', 'UAE National Day', '12-02', '12-03', 'Happy National Day'],
    ['christmas', 'Christmas', '12-25', null, 'Merry Christmas'],
    ['nye', 'New Year’s Eve', '12-31', null, null],
  ];
  // [key, name, greeting, estimate?, extra days after the start, { year: start | [start, end] }]
  const TABLE = [
    ['ramadan', 'Ramadan', 'Ramadan Kareem', true, 0, { 2026: ['2026-02-18', '2026-03-19'], 2027: ['2027-02-08', '2027-03-09'], 2028: ['2028-01-28', '2028-02-26'] }],
    ['eidfitr', 'Eid al-Fitr', 'Eid Mubarak', true, 2, { 2026: '2026-03-20', 2027: '2027-03-10', 2028: '2028-02-27' }],
    ['arafat', 'Arafat Day', null, true, 0, { 2026: '2026-05-26', 2027: '2027-05-15', 2028: '2028-05-04' }],
    ['eidadha', 'Eid al-Adha', 'Eid Mubarak', true, 3, { 2026: '2026-05-27', 2027: '2027-05-16', 2028: '2028-05-05' }],
    ['hijri', 'Islamic New Year', 'Happy Hijri New Year', true, 0, { 2026: '2026-06-16', 2027: '2027-06-06', 2028: '2028-05-25' }],
    ['mawlid', 'Prophet’s Birthday', null, true, 0, { 2026: '2026-08-25', 2027: '2027-08-15', 2028: '2028-08-03' }],
    ['cny', 'Chinese New Year', 'Happy Lunar New Year', false, 0, { 2026: '2026-02-17', 2027: '2027-02-06', 2028: '2028-01-26' }],
    ['easter', 'Easter', 'Happy Easter', false, 0, { 2026: '2026-04-05', 2027: '2027-03-28', 2028: '2028-04-16' }],
    ['diwali', 'Diwali', 'Happy Diwali', false, 0, { 2026: '2026-11-08', 2027: '2027-10-29', 2028: '2028-10-17' }],
    ['dsf', 'Dubai Shopping Festival', null, true, 0, { 2025: ['2025-12-05', '2026-01-11'], 2026: ['2026-12-04', '2027-01-10'], 2027: ['2027-12-03', '2028-01-09'] }],
  ];
  const p2 = (n) => String(n).padStart(2, '0');
  const ymd0 = (d) => `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}`;
  const plus = (s, n) => { const [y, m, d] = s.split('-').map(Number); return ymd0(new Date(y, m - 1, d + n)); };
  // nth weekday of a month (wd: 0 = Sunday), e.g. 2nd Sunday of May
  const nth = (y, m, wd, n) => { const d = new Date(y, m - 1, 1); d.setDate(1 + ((wd - d.getDay() + 7) % 7) + (n - 1) * 7); return ymd0(d); };
  const RULES = [
    ['mothersday-us', 'Mother’s Day (US & Europe)', (y) => nth(y, 5, 0, 2), null],
    ['fathersday', 'Father’s Day', (y) => nth(y, 6, 0, 3), 'Happy Father’s Day'],
    ['blackfriday', 'Black Friday', (y) => plus(nth(y, 11, 4, 4), 1), null],
  ];
  /* After the table runs out, the dates are worked out:
     - Islamic dates from the Umm al-Qura calendar built into every browser (the UAE confirms by moon sighting,
       so they stay "Expected" and can be corrected in the app)
     - Chinese New Year from the browser's Chinese calendar (can be a day off: also "Expected")
     - Easter by the usual church calculation; DSF from its usual pattern (first Friday from 3 Dec, about 5 weeks)
     - Diwali from a short list of published dates (it follows the Hindu calendar, which browsers don't have) */
  const DIWALI = { 2029: '2029-11-05', 2030: '2030-10-26', 2031: '2031-11-14', 2032: '2032-11-02', 2033: '2033-10-22', 2034: '2034-11-10', 2035: '2035-10-30' };
  const scans = {};
  // every day of a Gregorian year in another calendar: 'month-day' → [dates]
  function scan(cal, y) {
    const k = cal + y;
    if (scans[k]) return scans[k];
    const out = {};
    try {
      const f = new Intl.DateTimeFormat('en-u-ca-' + cal, { day: 'numeric', month: 'numeric', timeZone: 'UTC' });
      for (let t = Date.UTC(y, 0, 1); t < Date.UTC(y + 1, 0, 1); t += 864e5) {
        const p = Object.fromEntries(f.formatToParts(new Date(t)).map((x) => [x.type, x.value]));
        const key = `${parseInt(p.month, 10)}-${parseInt(p.day, 10)}`;
        (out[key] = out[key] || []).push(new Date(t).toISOString().slice(0, 10));
      }
    } catch (e) { /* this browser lacks that calendar */ }
    return (scans[k] = out);
  }
  const hijri = (y, m, d) => scan('islamic-umalqura', y)[`${m}-${d}`] || [];
  function easter(y) {
    const a = y % 19, b = Math.floor(y / 100), c = y % 100, d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3);
    const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451);
    const month = Math.floor((h + l - 7 * m + 114) / 31), day = ((h + l - 7 * m + 114) % 31) + 1;
    return `${y}-${p2(month)}-${p2(day)}`;
  }
  // [start, end] pairs for a year (a moon-based one can happen twice in one year, e.g. Ramadan 2030)
  function computed(k, y) {
    const ends = (start) => { // Ramadan ends the day before 1 Shawwal
      for (let i = 28; i <= 31; i++) { const d = plus(start, i), yy = Number(d.slice(0, 4)); if ((hijri(yy, 10, 1)).includes(d)) return plus(d, -1); }
      return plus(start, 29);
    };
    switch (k) {
      case 'ramadan': return hijri(y, 9, 1).map((d) => [d, ends(d)]);
      case 'eidfitr': return hijri(y, 10, 1).map((d) => [d, null]);
      case 'arafat': return hijri(y, 12, 9).map((d) => [d, null]);
      case 'eidadha': return hijri(y, 12, 10).map((d) => [d, null]);
      case 'hijri': return hijri(y, 1, 1).map((d) => [d, null]);
      case 'mawlid': return hijri(y, 3, 12).map((d) => [d, null]);
      case 'cny': return (scan('chinese', y)['1-1'] || []).filter((d) => d.slice(5, 7) <= '02').slice(0, 1).map((d) => [d, null]);
      case 'easter': return [[easter(y), null]];
      case 'diwali': return DIWALI[y] ? [[DIWALI[y], null]] : [];
      case 'dsf': { const d = new Date(y, 11, 3); d.setDate(3 + ((5 - d.getDay() + 7) % 7)); const s0 = ymd0(d); return [[s0, plus(s0, 37)]]; }
      default: return [];
    }
  }
  const meta = () => (typeof db !== 'undefined' && db && db.meta) || {};
  function builtIn(y) {
    const out = [];
    FIXED.forEach(([k, name, md, end, greet]) => out.push({ id: `${k}-${y}`, key: k, name, date: `${y}-${md}`, end: end ? `${y}-${end}` : null, greet, est: false }));
    TABLE.forEach(([k, name, greet, est, extra, by]) => {
      const v = by[y];
      if (v) {
        const date = Array.isArray(v) ? v[0] : v;
        const end = Array.isArray(v) ? v[1] : extra ? plus(date, extra) : null;
        out.push({ id: `${k}-${y}`, key: k, name, date, end, greet, est });
        return;
      }
      if (Number(Object.keys(by).sort().pop()) > y) return;   // years before the table: not needed
      computed(k, y).forEach(([date, end], i) => out.push({ id: `${k}-${y}${i ? 'b' : ''}`, key: k, name, date, end: end || (extra ? plus(date, extra) : null), greet, est: k !== 'easter' }));
    });
    RULES.forEach(([k, name, fn, greet]) => out.push({ id: `${k}-${y}`, key: k, name, date: fn(y), end: null, greet, est: false }));
    return out;
  }
  // every occasion between two dates (inclusive), soonest first; corrected dates and the team's own included
  function between(from, to) {
    const fix = meta().occDates || {};
    const y0 = Number(from.slice(0, 4)) - 1, y1 = Number(to.slice(0, 4));
    let all = [];
    for (let y = y0; y <= y1; y++) all = all.concat(builtIn(y));
    // a corrected date: confirmed from the holiday calendar (auto) or set by hand; estDate keeps the old estimate
    all = all.map((o) => (fix[o.id] ? { ...o, date: fix[o.id].date || o.date, end: fix[o.id].end === undefined ? o.end : fix[o.id].end, est: false, fixed: true, confirmed: !!fix[o.id].auto, estDate: o.date } : o));
    all = all.concat((meta().occasions || []).map((o) => ({ ...o, custom: true, est: false })));
    return all.filter((o) => (o.end || o.date) >= from && o.date <= to).sort((a, b) => a.date.localeCompare(b.date) || a.name.localeCompare(b.name));
  }
  const on = (day) => between(day, day);
  const byId = (id) => {
    if (!id) return null;
    const custom = (meta().occasions || []).find((o) => o.id === id);
    if (custom) return { ...custom, custom: true };
    const m = /(\d{4})b?$/.exec(String(id));
    const y = m ? Number(m[1]) : 0;
    if (!y) return null;
    return between(`${y - 1}-01-01`, `${y + 1}-12-31`).find((o) => o.id === id) || null;
  };
  // the greeting for a day, if one of its occasions has one ("Ramadan Kareem")
  function greeting(day) {
    const o = on(day).find((x) => x.greet);
    return o ? o.greet : null;
  }
  // occasions a post on this day is likely for: on the day, or up to 3 days before it
  const suggest = (day) => (day ? between(day, plus(day, 3)) : []);
  const fmt = (o) => {
    const f = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }); };
    return o.end && o.end !== o.date ? `${f(o.date)} – ${f(o.end)}` : f(o.date);
  };
  return { between, on, byId, greeting, suggest, fmt, plus };
})();

const Cal = (() => {
  const CHANNELS = [
    ['ig', 'Instagram', 'IG', '#e1306c'], ['tt', 'TikTok', 'TT', '#25f4ee'], ['li', 'LinkedIn', 'IN', '#0a66c2'], ['x', 'X', 'X', '#8b8b96'],
    ['fb', 'Facebook', 'FB', '#1877f2'], ['yt', 'YouTube', 'YT', '#ff3d3d'], ['sc', 'Snapchat', 'SC', '#f7d417'], ['edm', 'EDM', 'EDM', '#f08a24'],
  ];
  const CH = Object.fromEntries(CHANNELS.map(([k, name, short, color]) => [k, { k, name, short, color }]));
  const STATUS = {
    progress: ['In progress', '#8b8b96'], review: ['In review', '#f2b23e'], amend: ['Amendments', '#ff7a7a'], approved: ['Approved', '#3ddc97'], posted: ['Done', '#5b9bff'],
  };
  const owns = (v) => v === 'calendar';
  const canSee = (u = me()) => !!u && u.active !== false && (isAdm(u) || u.role === 'am' || u.role === 'social');
  const phone = () => typeof Phone !== 'undefined' && Phone.on;
  // filters: several clients and several channels can be picked (empty = all)
  const st = () => { const f = (ui.cal = ui.cal || { mode: 'month', anchor: todayStr(), projects: [], channels: [] }); f.projects = f.projects || []; f.channels = f.channels || []; return f; };

  // what the calendar shows: top-level tasks with a channel or an occasion, on their go-live (else due) day
  const isPost = (t) => !t.parentId && ((t.channels || []).length || t.occasion);
  const dayOf = (t) => t.golive || t.due || null;
  function statusOf(t) {
    if (t.done) return 'posted';
    if (needsCD(t)) {
      const rs = reviewersOf(t).map((u) => reviewState(t, u));
      if (rs.some((s) => s === 'pending')) return 'review';
      if (rs.some((s) => s === 'amend')) return 'amend';
      if (rs.length && rs.every((s) => s === 'approved')) return 'approved';
    }
    return 'progress';
  }
  const chips = (t) => (t.channels || []).filter((k) => CH[k]).map((k) => `<span class="cal-ch" style="--c:${CH[k].color}" title="${esc(CH[k].name)}">${CH[k].short}</span>`).join('');
  const pill = (s) => `<span class="cal-st" style="--c:${STATUS[s][1]}">${STATUS[s][0]}</span>`;
  const projOf = (t) => (t.projectId && proj(t.projectId)) || null;
  function posts(from, to) {
    const f = st();
    return db.tasks.filter((t) => isPost(t) && dayOf(t) && dayOf(t) >= from && dayOf(t) <= to
      && (!f.projects.length || f.projects.includes(t.projectId)) && (!f.channels.length || (t.channels || []).some((c) => f.channels.includes(c))))
      .sort((a, b) => dayOf(a).localeCompare(dayOf(b)) || (a.title || '').localeCompare(b.title || ''));
  }
  // Monday-first week start
  const monday = (s) => { const d = parseYmd(s); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); return ymd(d); };
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const WD = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  function range() {
    const f = st();
    if (f.mode === 'week') { const a = monday(f.anchor); return { from: a, to: addDays(a, 6), label: weekLabel(a) }; }
    const d = parseYmd(f.anchor);
    const first = ymd(new Date(d.getFullYear(), d.getMonth(), 1)), last = ymd(new Date(d.getFullYear(), d.getMonth() + 1, 0));
    return { from: monday(first), to: addDays(monday(last), 6), month: d.getMonth(), label: `${MONTHS[d.getMonth()]} ${d.getFullYear()}` };
  }
  function weekLabel(a) {
    const b = addDays(a, 6), A = parseYmd(a), B = parseYmd(b);
    const f = (x, y) => x.toLocaleDateString('en-GB', y ? { day: 'numeric', month: 'short', year: 'numeric' } : { day: 'numeric', month: 'short' });
    return `${f(A)} – ${f(B, true)}`;
  }

  /* ---------- page ---------- */
  function title() {
    return `<div class="page-icon" style="background:#3b2f14;color:#f9be33">${icon('cal')}</div><div class="page-title">Content calendar</div>`;
  }
  function toolbar(r) {
    const f = st();
    const ps = f.projects.map(proj).filter(Boolean), cs = f.channels.filter((k) => CH[k]);
    const pLabel = !ps.length ? 'All clients' : ps.length === 1 ? `<span class="dot" style="background:${ps[0].color}"></span>${esc(ps[0].name)}` : `${ps.map((p) => `<span class="dot" style="background:${p.color}"></span>`).join('')}${ps.length} clients`;
    const cLabel = !cs.length ? 'All channels' : cs.length <= 2 ? cs.map((k) => esc(CH[k].name)).join(', ') : `${cs.length} channels`;
    return `<div class="cal-bar">
      <div class="cal-nav">
        <button class="icon-btn" data-cal="prev" title="Previous ${f.mode}">${icon('chev-left')}</button>
        <b class="cal-label">${esc(r.label)}</b>
        <button class="icon-btn" data-cal="next" title="Next ${f.mode}">${icon('chev-right')}</button>
        <button class="btn ghost sm" data-cal="today">Today</button>
      </div>
      <div class="cal-tools">
        <button class="btn ghost sm cal-filter ${ps.length ? 'on' : ''}" data-cal="f-project">${pLabel}${icon('chev')}</button>
        <button class="btn ghost sm cal-filter ${cs.length ? 'on' : ''}" data-cal="f-channel">${cLabel}${icon('chev')}</button>
        <div class="cal-seg"><button class="${f.mode === 'month' ? 'on' : ''}" data-cal="mode" data-v="month">Month</button><button class="${f.mode === 'week' ? 'on' : ''}" data-cal="mode" data-v="week">Week</button></div>
        <button class="btn primary sm" data-cal="new">${icon('plus')}New post</button>
      </div>
    </div>`;
  }
  // Long occasions (Ramadan, DSF) are named on their first day and at the start of each week, and show as a
  // thin gold line on the other days, so a month doesn't fill up with the same label
  const long = (o) => o.end && dayDiffBetween(o.date, o.end) > 3;
  const dayDiffBetween = (a, b) => Math.round((parseYmd(b) - parseYmd(a)) / 86400000);
  function occLine(day) {
    const os = Occasions.on(day).filter((o) => !long(o) || o.date === day || parseYmd(day).getDay() === 1);
    return os.length ? `<span class="cal-occ" title="${esc(os.map((o) => o.name + (o.est ? ' (expected date)' : '') + (long(o) ? ' · ' + Occasions.fmt(o) : '')).join(', '))}">${esc(os.map((o) => o.name).join(' · '))}</span>` : '';
  }
  // 'occ' = a short occasion today (tinted), 'span' = inside a long one (thin line)
  const occClass = (day) => { const os = Occasions.on(day); return [os.some((o) => !long(o)) ? 'occ' : '', os.some(long) ? 'span' : ''].join(' '); };
  function month(r) {
    const list = posts(r.from, r.to);
    const today = todayStr();
    let cells = '';
    for (let d = r.from; d <= r.to; d = addDays(d, 1)) {
      const day = list.filter((t) => dayOf(t) === d);
      const out = parseYmd(d).getMonth() !== r.month;
      cells += `<div class="cal-cell ${out ? 'out' : ''} ${d === today ? 'today' : ''} ${occClass(d)}" data-day="${d}">
        <div class="cal-dh"><span class="cal-num">${parseYmd(d).getDate()}</span>${occLine(d)}<button class="cal-add" data-cal="new" data-d="${d}" title="New post on this day">${icon('plus')}</button></div>
        ${day.slice(0, 3).map((t) => { const p = projOf(t); const s = statusOf(t); return `<button class="cal-chip" data-cal="open" data-id="${t.id}" title="${esc((p ? p.name + ' · ' : '') + (t.title || 'Untitled task') + ' · ' + STATUS[s][0])}">
          <span class="dot" style="background:${p ? p.color : '#8b8b96'}"></span><span class="cal-chip-t">${esc(t.title || 'Untitled task')}</span><span class="cal-sdot" style="background:${STATUS[s][1]}"></span></button>`; }).join('')}
        ${day.length > 3 ? `<button class="cal-more" data-cal="week-of" data-d="${d}">+${day.length - 3} more</button>` : ''}
      </div>`;
    }
    return `<div class="cal-month"><div class="cal-wd">${WD.map((w) => `<span>${w}</span>`).join('')}</div><div class="cal-grid">${cells}</div></div>`;
  }
  function week(r) {
    const list = posts(r.from, r.to);
    const days = Array.from({ length: 7 }, (_, i) => addDays(r.from, i));
    const today = todayStr();
    const pids = [...new Set(list.map((t) => t.projectId || ''))];
    const rows = pids.map((id) => ({ p: id ? proj(id) : null, id })).sort((a, b) => (a.p ? a.p.name : '~').localeCompare(b.p ? b.p.name : '~'));
    const head = `<div class="cal-wk-h"></div>${days.map((d, i) => `<div class="cal-wk-h ${d === today ? 'today' : ''} ${occClass(d)}"><span class="cal-wk-d"><small>${WD[i]}</small>${parseYmd(d).getDate()}</span>${occLine(d)}</div>`).join('')}`;
    const body = rows.map(({ p, id }) => {
      const mine = list.filter((t) => (t.projectId || '') === id);
      return `<div class="cal-wk-l"><span class="dot" style="background:${p ? p.color : '#8b8b96'}"></span><b>${esc(p ? p.name : 'No project')}</b><small>${mine.length} this week</small></div>${days.map((d) => `<div class="cal-wk-c ${occClass(d)}" data-day="${d}">${mine.filter((t) => dayOf(t) === d).map((t) => { const s = statusOf(t); return `<button class="cal-card" data-cal="open" data-id="${t.id}" style="--pc:${p ? p.color : '#8b8b96'}">
          <span class="cal-card-top">${chips(t) || '<span class="cal-ch none">No channel</span>'}</span>
          <span class="cal-card-t">${esc(t.title || 'Untitled task')}</span>${pill(s)}</button>`; }).join('')}<button class="cal-add" data-cal="new" data-d="${d}" data-p="${esc(id)}" title="New post">${icon('plus')}</button></div>`).join('')}`;
    }).join('');
    return `<div class="cal-week">${head}${body || `<div class="cal-empty">No posts this week${st().projects.length || st().channels.length ? ' for these filters' : ''}. Use <b>New post</b>, or set a <b>Channel</b> on a task, to add one.</div>`}</div>`;
  }
  function side(r) {
    const today = todayStr();
    const soon = Occasions.between(today, addDays(today, 75)).slice(0, 7);
    const all = db.tasks.filter(isPost);
    const inRange = posts(r.from, r.to);
    const counts = Object.keys(STATUS).map((k) => [k, inRange.filter((t) => statusOf(t) === k).length]);
    const mgr = isManager();
    return `<aside class="cal-side">
      <section class="cal-box"><div class="cal-box-h"><h3>Occasions coming up</h3>${mgr ? `<button class="btn ghost xs" data-cal="occ-add">${icon('plus')}Add</button>` : ''}</div>
        ${soon.length ? soon.map((o) => {
          const linked = all.filter((t) => t.occasion === o.id);
          const ok = linked.filter((t) => ['approved', 'posted'].includes(statusOf(t))).length;
          // the date moved (confirmed): posts still going live on the old estimate
          const stale = o.estDate && o.estDate !== o.date ? linked.filter((t) => t.golive === o.estDate).length : 0;
          const d = parseYmd(o.date);
          return `<div class="cal-occ-row">
            <div class="cal-occ-date"><small>${MONTHS[d.getMonth()].slice(0, 3).toUpperCase()}</small><b>${d.getDate()}</b></div>
            <div class="cal-occ-txt"><b>${esc(o.name)}</b><span>${o.est ? 'Expected · ' : o.confirmed ? '<i class="cal-conf">Confirmed</i> · ' : ''}${esc(Occasions.fmt(o))}</span>
              ${stale ? `<span class="warn">${stale} post${stale === 1 ? '' : 's'} still on the old date</span>` : ''}
              <span class="${linked.length ? (ok === linked.length ? 'ok' : 'warn') : 'none'}">${linked.length ? `${linked.length} planned · ${ok} approved` : 'Nothing planned yet'}</span></div>
            <div class="cal-occ-acts"><button class="btn ghost xs" data-cal="plan" data-id="${esc(o.id)}">Plan</button>${mgr ? `<button class="icon-btn xs" data-cal="occ-edit" data-id="${esc(o.id)}" title="Change the date">${icon('edit')}</button>` : ''}</div>
          </div>`;
        }).join('') : '<div class="cal-muted">No occasions in the next weeks</div>'}
        ${mgr && Host.isServer ? `<div class="cal-check" id="cal-check">Expected dates are checked against the UAE holiday calendar twice a day.<button class="btn ghost xs" data-cal="check">Check now</button></div>` : ''}
      </section>
      <section class="cal-box"><h3>${st().mode === 'week' ? 'This week' : 'This month'}</h3>
        ${counts.map(([k, n]) => `<div class="cal-stat"><span class="cal-sdot" style="background:${STATUS[k][1]}"></span><span>${STATUS[k][0]}</span><b>${n}</b></div>`).join('')}
      </section>
    </aside>`;
  }
  function render(c) {
    const r = range();
    if (phone()) { c.innerHTML = agenda(); return; }
    c.innerHTML = `<div class="cal-page">${toolbar(r)}<div class="cal-body"><div class="cal-main">${st().mode === 'week' ? week(r) : month(r)}</div>${side(r)}</div></div>`;
    if (isManager() && Host.isServer) api('GET', '/api/holidays').then(paintCheck).catch(() => {});
  }
  function paintCheck(s) {
    const el = document.getElementById('cal-check');
    if (!el || !s) return;
    const txt = !s.at ? 'Expected dates are checked against the UAE holiday calendar twice a day.'
      : s.ok ? `Holiday calendar checked ${timeAgo(s.at)}: ${(s.foundList || []).length ? 'confirmed ' + s.foundList.map((f) => `${f.name} ${fmtDay(f.date)}`).join(', ') : 'nothing confirmed yet'}${(s.tentativeList || []).length ? ` · listed as tentative: ${s.tentativeList.map((f) => `${f.name} ${fmtDay(f.date)}`).join(', ')} (these confirm closer to the day)` : (s.foundList || []).length ? '' : ` · no Islamic occasions in it (${s.events || 0} holidays read${(s.sample || []).length ? `; it lists: ${s.sample.join(', ')}` : ''})`}${s.lastChange ? ` · last change ${timeAgo(s.lastChange)}` : ''}.`
        : `Couldn’t read the holiday calendar ${timeAgo(s.at)} (${s.error}). The expected dates stay as they are.`;
    el.innerHTML = `${esc(txt)}<button class="btn ghost xs" data-cal="check">Check now</button>`;
  }
  async function checkNow(btn) {
    if (btn) { btn.disabled = true; btn.textContent = 'Checking…'; }
    try {
      const s = await api('POST', '/api/holidays', {});
      paintCheck(s);
      toast(s.ok ? (s.changed && s.changed.length && s.lastChange === s.at ? `Updated: ${s.changed.map((c) => c.name).join(', ')}` : `Checked — ${(s.foundList || []).length} confirmed date${(s.foundList || []).length === 1 ? '' : 's'} found, no changes`) : 'Couldn’t read the holiday calendar');
    } catch (e) { toast(e.message); if (btn) { btn.disabled = false; btn.textContent = 'Check now'; } }
  }
  // Phone: the next 6 weeks as a list by day, and the occasions in them
  function agenda() {
    const today = todayStr(), to = addDays(today, 41);
    const list = posts(today, to);
    const occ = Occasions.between(today, to);
    const days = [...new Set([...list.map(dayOf), ...occ.map((o) => (o.date < today ? today : o.date))])].sort();
    return `<div class="cal-agenda">
      ${days.length ? days.map((d) => {
        const ps = list.filter((t) => dayOf(t) === d);
        const os = Occasions.on(d).filter((o) => o.date === d || d === today);
        const D = parseYmd(d);
        return `<section class="cal-ag-day"><h3>${d === today ? 'Today' : D.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'short' })}</h3>
          ${os.map((o) => `<div class="cal-ag-occ">${esc(o.name)}${o.est ? ' <small>expected</small>' : ''}</div>`).join('')}
          ${ps.map((t) => { const p = projOf(t), s = statusOf(t); return `<button class="cal-card" data-cal="open" data-id="${t.id}" style="--pc:${p ? p.color : '#8b8b96'}"><span class="cal-card-top"><small>${esc(p ? p.name : 'No project')}</small>${chips(t)}</span><span class="cal-card-t">${esc(t.title || 'Untitled task')}</span>${pill(s)}</button>`; }).join('')}
        </section>`;
      }).join('') : '<div class="cal-empty">Nothing planned in the next 6 weeks.</div>'}
    </div>`;
  }

  /* ---------- new posts and planning ---------- */
  function newPost(day, projectId) {
    if (!can('createTask')) return denied();
    const f = st();
    const pid = projectId || (f.projects.length === 1 ? f.projects[0] : null);
    const p = pid && proj(pid);
    const t = createTask({ projectId: p ? p.id : null, sectionId: p ? p.sections[0].id : null, golive: day || null, channels: f.channels.slice() });
    const sug = day && Occasions.suggest(day)[0];
    if (sug) t.occasion = sug.id;
    Draft.start(t);
    commit();
    openTask(t.id, true);
  }
  function planDialog(o) {
    if (!can('createTask')) return denied();
    const projects = db.projects.slice().sort(byOrder);
    const root = $('#overlay-root');
    const due = (() => { const d = addDays(o.date, -5); return d < todayStr() ? todayStr() : d; })();
    const sel = new Set(), chs = new Set(['ig']);
    root.innerHTML = `<div class="scrim"><div class="dialog cal-plan" role="dialog" aria-label="Plan ${esc(o.name)}">
      <h2>Plan ${esc(o.name)}</h2>
      <p class="cal-muted">${o.est ? 'Expected ' : ''}${esc(Occasions.fmt(o))}. One task per client, going live on ${esc(fmtDay(o.date))}, due ${esc(fmtDay(due))} so there's time for CD review.</p>
      <h4>Clients</h4>
      <div class="cal-pick">${projects.map((p) => `<button type="button" class="cal-opt" data-pp="${p.id}"><span class="dot" style="background:${p.color}"></span>${esc(p.name)}</button>`).join('')}</div>
      <h4>Channels</h4>
      <div class="cal-pick">${CHANNELS.map(([k, name]) => `<button type="button" class="cal-opt ${chs.has(k) ? 'on' : ''}" data-pc="${k}">${esc(name)}</button>`).join('')}</div>
      <div class="actions"><button class="btn" data-r="0">Cancel</button><button class="btn primary" data-r="1" disabled>Create tasks</button></div>
    </div></div>`;
    const ok = $('[data-r="1"]', root);
    const sync = () => { ok.disabled = !sel.size || !chs.size; ok.textContent = sel.size ? `Create ${sel.size} task${sel.size === 1 ? '' : 's'}` : 'Create tasks'; };
    const close = () => { root.innerHTML = ''; };
    $('.scrim', root).addEventListener('click', (e) => {
      if (e.target.classList.contains('scrim')) return close();
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.pp) { sel.has(b.dataset.pp) ? sel.delete(b.dataset.pp) : sel.add(b.dataset.pp); b.classList.toggle('on'); return sync(); }
      if (b.dataset.pc) { chs.has(b.dataset.pc) ? chs.delete(b.dataset.pc) : chs.add(b.dataset.pc); b.classList.toggle('on'); return sync(); }
      if (b.dataset.r === '0') return close();
      if (b.dataset.r === '1') {
        let n = 0;
        projects.filter((p) => sel.has(p.id)).forEach((p) => {
          createTask({ title: `${p.name} | ${o.name}`, projectId: p.id, sectionId: p.sections[0].id, golive: o.date, due, occasion: o.id, channels: [...chs] });
          n++;
        });
        commit(); close(); render($('#content'));
        toast(`Created ${n} task${n === 1 ? '' : 's'} for ${o.name}`);
      }
    });
  }
  // Admins and Account Managers: add an occasion, or correct a date (moon-based ones are estimates)
  function occDialog(o) {
    if (!isManager()) return denied();
    const root = $('#overlay-root');
    const isNew = !o;
    root.innerHTML = `<div class="scrim"><div class="dialog cal-plan" role="dialog" aria-label="${isNew ? 'Add an occasion' : 'Change the date'}">
      <h2>${isNew ? 'Add an occasion' : esc(o.name)}</h2>
      ${isNew ? '<label class="cal-field"><span>Name</span><input id="occ-name" maxlength="60" placeholder="e.g. Ford anniversary"></label>' : `<p class="cal-muted">${o.est ? 'This date is an estimate. ' : ''}Change it here once it’s confirmed — everyone sees the new date.</p>`}
      <div class="cal-dates"><label class="cal-field"><span>Date</span><input type="date" id="occ-date" value="${o ? o.date : ''}"></label>
      <label class="cal-field"><span>Until (optional)</span><input type="date" id="occ-end" value="${o && o.end ? o.end : ''}"></label></div>
      ${isNew || o.custom ? `<label class="cal-field"><span>Greeting on the startup screen (optional)</span><input id="occ-greet" maxlength="40" placeholder="e.g. Happy anniversary" value="${o && o.greet ? esc(o.greet) : ''}"></label>` : ''}
      <div class="actions">${o && o.custom ? '<button class="btn ghost danger" data-r="del">Delete</button><span class="spacer"></span>' : ''}<button class="btn" data-r="0">Cancel</button><button class="btn primary" data-r="1">Save</button></div>
    </div></div>`;
    const close = () => { root.innerHTML = ''; };
    $('.scrim', root).addEventListener('click', (e) => {
      if (e.target.classList.contains('scrim')) return close();
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.r === '0') return close();
      const m = db.meta;
      if (b.dataset.r === 'del') { m.occasions = (m.occasions || []).filter((x) => x.id !== o.id); persist(0); close(); render($('#content')); return; }
      if (b.dataset.r !== '1') return;
      const date = $('#occ-date', root).value, end = $('#occ-end', root).value || null;
      if (!date) { toast('Pick a date'); return; }
      if (end && end < date) { toast('The end date is before the start'); return; }
      const greet = $('#occ-greet', root) ? $('#occ-greet', root).value.trim() || null : undefined;
      if (isNew) {
        const name = $('#occ-name', root).value.trim();
        if (!name) { toast('Give it a name'); return; }
        m.occasions = (m.occasions || []).concat({ id: 'occ-' + uid() + '-' + date.slice(0, 4), name, date, end, greet });
      } else if (o.custom) {
        m.occasions = (m.occasions || []).map((x) => (x.id === o.id ? { ...x, date, end, greet } : x));
      } else {
        m.occDates = { ...(m.occDates || {}), [o.id]: { date, end } };
      }
      persist(0); close(); render($('#content'));
    });
  }
  function filterMenu(anchor, kind) {
    const f = st();
    const ck = (on) => (on ? `<span class="wf-ck">${icon('check')}</span>` : '');
    const list = kind === 'project' ? 'projects' : 'channels';
    // tick and untick several; the menu stays open until you click elsewhere
    const reopen = () => { render($('#content')); setTimeout(() => { const a = document.querySelector(`[data-cal="f-${kind}"]`); if (a) filterMenu(a, kind); }, 0); };
    const toggle = (v) => { f[list] = f[list].includes(v) ? f[list].filter((x) => x !== v) : f[list].concat(v); reopen(); };
    const all = () => { f[list] = []; render($('#content')); };
    const items = kind === 'project'
      ? [{ html: `<div class="mi">All clients${ck(!f.projects.length)}</div>`, run: all }, ...db.projects.slice().sort(byOrder).map((p) => ({ html: `<div class="mi"><span class="dot" style="background:${p.color}"></span>${esc(p.name)}${ck(f.projects.includes(p.id))}</div>`, run: () => toggle(p.id) }))]
      : [{ html: `<div class="mi">All channels${ck(!f.channels.length)}</div>`, run: all }, ...CHANNELS.map(([k, name]) => ({ html: `<div class="mi"><span class="cal-ch" style="--c:${CH[k].color}">${CH[k].short}</span>${esc(name)}${ck(f.channels.includes(k))}</div>`, run: () => toggle(k) }))];
    showMenu(anchor, items.map((it, i) => ({ ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) }))).classList.add('wf-menu');
  }

  /* ---------- the three task fields ---------- */
  const fieldRows = (t) => {
    if (t.parentId || !(canSee() || (t.channels || []).length || t.golive || t.occasion)) return [];
    const ed = canSee();
    const o = t.occasion && Occasions.byId(t.occasion);
    const sug = !t.occasion && ed ? Occasions.suggest(dayOf(t))[0] : null;
    return [
      { k: 'channels', ic: 'send', l: 'Channel', v: (t.channels || []).length ? 1 : null, html: (t.channels || []).length ? `<span class="cal-chs">${chips(t)}</span>` : '', edit: ed },
      { k: 'golive', ic: 'cal', l: 'Go-live', v: t.golive, raw: `<span class="date-chip fl-date ${t.golive ? 'set' : 'is-empty'}">${t.golive ? `<span class="date-lbl">${esc(fmtDay(t.golive))}</span>` : '<span class="date-lbl fl-empty">–</span>'}${ed ? `<input type="date" class="date-in" id="d-golive" value="${t.golive || ''}" title="Go-live date">` : ''}</span>${t.golive && ed ? `<button class="icon-btn xs" data-action="clear-golive" title="Remove go-live date">${icon('x')}</button>` : ''}` },
      { k: 'occasion', ic: 'sun', l: 'Occasion', v: t.occasion, html: o ? `<span class="cal-occ-pill">${esc(o.name)}</span>` : '', edit: ed, extra: sug ? `<button class="cal-suggest" data-action="occ-accept" data-id="${esc(sug.id)}" title="Link this task to ${esc(sug.name)}">Suggested: ${esc(sug.name)}</button>` : '' },
    ];
  };
  function fieldMenu(anchor, k, t) {
    if (!canSee()) return denied();
    const ck = (on) => (on ? `<span class="wf-ck">${icon('check')}</span>` : '');
    let items = [];
    if (k === 'channels') {
      const cur = new Set(t.channels || []);
      items = CHANNELS.map(([key, name]) => ({ html: `<div class="mi"><span class="cal-ch" style="--c:${CH[key].color}">${CH[key].short}</span>${esc(name)}${ck(cur.has(key))}</div>`, run: () => { setChannels(t, cur.has(key) ? [...cur].filter((x) => x !== key) : [...cur, key]); setTimeout(() => { const a = document.querySelector('[data-action="field-pick"][data-k="channels"]'); if (a) fieldMenu(a, 'channels', t); }, 0); } }));
      if (cur.size) items.push({ html: '<div class="sep"></div>' }, { html: `<div class="mi fl-clear">${icon('x')}Clear</div>`, run: () => setChannels(t, []) });
    } else {
      const day = dayOf(t) || todayStr();
      const sug = new Set(Occasions.suggest(dayOf(t)).map((o) => o.id));
      const list = Occasions.between(addDays(day, -30), addDays(day, 90));
      items = list.map((o) => ({ html: `<div class="mi cal-mi"><span>${esc(o.name)}<small>${o.est ? 'Expected · ' : ''}${esc(Occasions.fmt(o))}${sug.has(o.id) ? ' · Suggested' : ''}</small></span>${ck(t.occasion === o.id)}</div>`, run: () => setOccasion(t, o.id) }));
      if (!items.length) items.push({ html: '<div class="mi-note">No occasions near this date</div>' });
      if (t.occasion) items.push({ html: '<div class="sep"></div>' }, { html: `<div class="mi fl-clear">${icon('x')}Clear</div>`, run: () => setOccasion(t, null) });
    }
    const m = showMenu(anchor, items.map((it, i) => (it.run ? { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) } : it)));
    m.classList.add('wf-menu', 'fl-menu');
  }
  const names = (ks) => (ks || []).map((k) => (CH[k] ? CH[k].name : k)).join(', ');
  function setChannels(t, v) {
    const old = names(t.channels);
    t.channels = v;
    logChange(t, 'the <b>channels</b>', old, names(v));
    t.updatedAt = nowISO();
    commit();
  }
  function setGolive(t, v) {
    const old = t.golive || null;
    if (old === v) return;
    t.golive = v || null;
    logChange(t, 'the <b>go-live date</b>', fmtDay(old), fmtDay(t.golive));
    t.updatedAt = nowISO();
    commit();
  }
  function setOccasion(t, id) {
    const o = id && Occasions.byId(id), was = t.occasion && Occasions.byId(t.occasion);
    t.occasion = id || null;
    logChange(t, 'the <b>occasion</b>', was ? was.name : '', o ? o.name : '');
    t.updatedAt = nowISO();
    commit();
  }

  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-cal]');
    if (!el || !db || !owns(ui.view)) return;
    const f = st(), a = el.dataset.cal;
    e.preventDefault();
    const step = (n) => { f.anchor = f.mode === 'week' ? addDays(f.anchor, 7 * n) : (() => { const d = parseYmd(f.anchor); return ymd(new Date(d.getFullYear(), d.getMonth() + n, 1)); })(); render($('#content')); };
    switch (a) {
      case 'prev': return step(-1);
      case 'next': return step(1);
      case 'today': f.anchor = todayStr(); return render($('#content'));
      case 'mode': f.mode = el.dataset.v; return render($('#content'));
      case 'week-of': f.mode = 'week'; f.anchor = el.dataset.d; return render($('#content'));
      case 'open': return openTask(el.dataset.id);
      case 'new': return newPost(el.dataset.d || null, el.dataset.p || null);
      case 'f-project': e.stopImmediatePropagation(); return filterMenu(el, 'project');   // (the app closes menus on any other click)
      case 'f-channel': e.stopImmediatePropagation(); return filterMenu(el, 'channel');
      case 'plan': { const o = Occasions.byId(el.dataset.id); if (o) planDialog(o); return; }
      case 'occ-add': return occDialog(null);
      case 'check': return checkNow(el);
      case 'occ-edit': { const o = Occasions.byId(el.dataset.id); if (o) occDialog(o); return; }
    }
  });

  // the server confirmed new dates: tell Admins / AMs who have the app open
  function confirmed(changed) {
    const f = (d) => fmtDay(d);
    alertUser({ title: 'Occasion date confirmed', body: changed.map((c) => `${c.name}: ${f(c.date)} (was ${f(c.was)})`).join(' · '), stay: 12000 }, true);
    if (owns(ui.view)) render($('#content'));
  }
  return { confirmed, owns, canSee, render, title, fieldRows, fieldMenu, setGolive, setOccasion, CHANNELS, statusOf, dayOf, isPost };
})();
