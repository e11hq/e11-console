/* ================= Scheduled comments =================
   Desktop: the composer's Send / Reply button has a ⌄ that opens a scheduler — type a time ("tomorrow 2pm"),
   pick a quick time, or a day on the calendar and then a time. Times are Dubai time; the office is 9:00 AM–6:00 PM,
   Monday–Friday (outside it there's a note, and it still schedules). The comment is saved as `db.scheduled`
   (only its author ever receives it) and the server posts it at the time (server/src/scheduled.js). Until then it
   shows in the task for its author with Edit / Send now / Cancel. If the task is completed or deleted first the
   server cancels it and tells the author; openCancelled() brings it back as a draft, or shows its text and files. */
const Sched = (() => {
  const H = 3600000, START = 9, END = 18;
  // Dubai wall clock (UTC+4, no daylight saving)
  const dub = (ms) => { const d = new Date(ms + 4 * H); return { y: d.getUTCFullYear(), m: d.getUTCMonth(), d: d.getUTCDate(), h: d.getUTCHours(), mi: d.getUTCMinutes(), dow: d.getUTCDay() }; };
  const at = (y, m, d, h = START, mi = 0) => Date.UTC(y, m, d, h, mi) - 4 * H;
  const dayOf = (p, n = 0) => { const x = new Date(Date.UTC(p.y, p.m, p.d + n)); return { y: x.getUTCFullYear(), m: x.getUTCMonth(), d: x.getUTCDate(), dow: x.getUTCDay() }; };
  const TZ = { timeZone: 'Asia/Dubai' };
  const fmtTime = (ms) => new Date(ms).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', ...TZ });
  const wd = (ms) => new Date(ms).toLocaleDateString('en-US', { weekday: 'short', ...TZ });
  const fmtDay = (ms) => new Date(ms).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', ...TZ });
  const fmtLongDay = (ms) => new Date(ms).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric', ...TZ });
  const when = (ms) => `${fmtDay(ms)} · ${fmtTime(ms)}`;
  const outside = (ms) => { const p = dub(ms), mins = p.h * 60 + p.mi; return p.dow === 0 || p.dow === 6 || mins < START * 60 || mins > END * 60; };
  const NOTE = 'Outside office hours (Mon–Fri, 9–6)';
  const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
  const SVG = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const QI = {
    soon: SVG('<path d="M12 7v5l3 2"/><path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v4h-4"/>'),
    hours: SVG('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
    tomorrow: SVG('<path d="M4 18h16"/><path d="M7 14a5 5 0 0 1 10 0"/><path d="M12 4v3M4.9 7.9l2 2M19.1 7.9l-2 2"/>'),
    days: SVG('<circle cx="14" cy="12" r="7"/><path d="M14 8.5V12l2 1.5"/><path d="M2.5 9h3M2 12h3M2.5 15h3"/>'),
    week: SVG('<rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M8 3v4M16 3v4M9.5 13h5M12.5 10.5 15 13l-2.5 2.5"/>'),
  };

  /* ---- Reading a typed time: "in 3 hours", "tomorrow 2pm", "thu 10:30", "next week", "5 Nov 4pm", "29/10 14:00" ---- */
  function parse(raw, now = Date.now()) {
    let s = ' ' + String(raw || '').toLowerCase().replace(/[,.]/g, ' ').replace(/\s+/g, ' ').trim() + ' ';
    if (!s.trim()) return null;
    const today = dub(now);
    // relative: in 20 minutes / 2 hours / 3 days / 1 week, half an hour
    const word = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, ten: 10 };
    let m = s.match(/^\s*(?:in\s+)?(half an?|\d+(?:\.\d+)?|an?|one|two|three|four|five|six|ten)\s*(m|mins?|minutes?|h|hrs?|hours?|d|days?|w|wks?|weeks?)\s*$/);
    if (m && (/^\s*in\s/.test(s) || /\d|half/.test(m[1]))) {
      const n = /^half/.test(m[1]) ? 0.5 : word[m[1]] || Number(m[1]);
      const u = m[2][0] === 'm' ? 60000 : m[2][0] === 'h' ? H : m[2][0] === 'd' ? 24 * H : 7 * 24 * H;
      if (!n) return null;
      if (u >= 24 * H) { const p = dayOf(today, Math.round(n * u / (24 * H))); return at(p.y, p.m, p.d); }   // (days and weeks: at the office start)
      return Math.round((now + n * u) / 60000) * 60000;
    }
    // the time of day
    let hh = null, mm = 0, ampm = null;
    const take = (re, fn) => { const x = s.match(re); if (!x) return false; fn(x); s = s.replace(x[0], ' '); return true; };
    take(/\b(noon|midday)\b/, () => { hh = 12; ampm = 'pm'; })
      || take(/\bmidnight\b/, () => { hh = 0; ampm = 'am'; })
      || take(/\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)\b/, (x) => { hh = +x[1]; mm = +(x[2] || 0); ampm = x[3][0] === 'a' ? 'am' : 'pm'; })
      || take(/\b(\d{1,2}):(\d{2})\b/, (x) => { hh = +x[1]; mm = +x[2]; })
      || take(/\bat\s+(\d{1,2})\b/, (x) => { hh = +x[1]; });
    if (hh != null) {
      if (hh > 23 || mm > 59 || (ampm && (hh < 1 || hh > 12) && !(hh === 0 && ampm === 'am'))) return null;
      if (ampm === 'pm' && hh < 12) hh += 12;
      if (ampm === 'am' && hh === 12) hh = 0;
      if (!ampm && hh >= 1 && hh <= 7) hh += 12;     // "at 2" is 2 PM
    }
    // the day
    let day = null;
    take(/\bday after tomorrow\b/, () => { day = dayOf(today, 2); })
      || take(/\b(tomorrow|tmrw?|tmr|tom)\b/, () => { day = dayOf(today, 1); })
      || take(/\btonight\b/, () => { day = dayOf(today); if (hh == null) hh = 20; })
      || take(/\btoday\b/, () => { day = dayOf(today); })
      || take(/\bnext week\b/, () => { day = dayOf(today, ((8 - today.dow) % 7) || 7); })
      || take(/\b(?:next |this |on )?(sun|mon|tue|wed|thu|fri|sat)[a-z]*\b/, (x) => { const want = DAYS.indexOf(x[1]); day = dayOf(today, ((want - today.dow + 7) % 7) || 7); })
      || take(/\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*(?:\s+(\d{4}))?\b/, (x) => { day = { y: x[3] ? +x[3] : today.y, m: MONTHS.indexOf(x[2]), d: +x[1], fixedYear: !!x[3] }; })
      || take(/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(\d{4}))?\b/, (x) => { day = { y: x[3] ? +x[3] : today.y, m: MONTHS.indexOf(x[1]), d: +x[2], fixedYear: !!x[3] }; })
      || take(/\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/, (x) => { day = { y: x[3] ? (x[3].length === 2 ? 2000 + +x[3] : +x[3]) : today.y, m: +x[2] - 1, d: +x[1], fixedYear: !!x[3] }; });
    // anything left over must be filler
    if (s.replace(/\b(at|on|the|this|by|for|send|it|in)\b/g, ' ').trim()) return null;
    if (day == null && hh == null) return null;
    if (day && (day.m < 0 || day.m > 11 || day.d < 1 || day.d > 31)) return null;
    let ms;
    if (day) {
      ms = at(day.y, day.m, day.d, hh == null ? START : hh, hh == null ? 0 : mm);
      const chk = dub(ms);
      if (chk.d !== day.d && hh != null) return null;                       // (31 Feb…)
      if (ms <= now && day.fixedYear === false) ms = at(day.y + 1, day.m, day.d, hh == null ? START : hh, hh == null ? 0 : mm);   // a date already past this year: next year
    } else {
      ms = at(today.y, today.m, today.d, hh, mm);
      if (ms <= now) { const p = dayOf(today, 1); ms = at(p.y, p.m, p.d, hh, mm); }
    }
    return ms > now ? ms : null;
  }

  const quick = (now = Date.now()) => {
    const t = dub(now);
    const d1 = dayOf(t, 1), d2 = dayOf(t, 2), wk = dayOf(t, ((8 - t.dow) % 7) || 7);
    const r = (ms) => Math.round(ms / 60000) * 60000;
    return [
      { k: 'soon', l: 'In 20 minutes', ms: r(now + 20 * 60000), short: true },
      { k: 'hours', l: 'In 2 hours', ms: r(now + 2 * H), short: true },
      { k: 'tomorrow', l: 'Tomorrow', ms: at(d1.y, d1.m, d1.d) },
      { k: 'days', l: 'In 2 days', ms: at(d2.y, d2.m, d2.d) },
      { k: 'week', l: 'Next week', ms: at(wk.y, wk.m, wk.d) },
    ];
  };

  /* ---- The pop-up ---- */
  let st = null;   // { anchor, replyTo, taskId, q, view: {y, m}, day: {y,m,d} | null, pick: ms | null, custom }
  const pop = () => document.getElementById('sc-pop');
  function close() { const p = pop(); if (p) p.remove(); st = null; document.removeEventListener('mousedown', onDown, true); document.removeEventListener('keydown', onKey, true); }
  function onDown(e) { const p = pop(); if (p && !p.contains(e.target) && !(st && st.anchor && st.anchor.contains(e.target))) close(); }
  function onKey(e) {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); if (st && st.day) { st.day = null; paint(); } else close(); return; }
    if (e.key === 'Enter' && st) {
      const p = pop(); if (!p || !p.contains(document.activeElement)) return;
      e.preventDefault(); e.stopPropagation();
      if (document.activeElement.id === 'sc-q') { const ms = parse(st.q); if (ms) schedule(ms); return; }
      if (document.activeElement.id === 'sc-other') { const ms = dayTime(st.custom); if (ms) schedule(ms); }
    }
  }
  const noteHTML = (ms) => (ms && outside(ms) ? `<div class="sc-note">${icon('info')}${NOTE}</div>` : '');
  // a time typed for the picked day ("4:30 pm", "16:30", "4pm")
  function dayTime(txt) {
    if (!st || !st.day) return null;
    const ms = parse(`${st.day.d}/${st.day.m + 1}/${st.day.y} ${txt}`);
    return ms && dub(ms).d === st.day.d ? ms : null;
  }
  function calHTML() {
    const now = Date.now(), today = dub(now), v = st.view;
    const first = new Date(Date.UTC(v.y, v.m, 1)).getUTCDay();          // 0 = Sunday
    const lead = (first + 6) % 7;                                        // Monday first
    const dim = new Date(Date.UTC(v.y, v.m + 1, 0)).getUTCDate();
    const cells = [];
    for (let i = 0; i < 42; i++) {
      const x = new Date(Date.UTC(v.y, v.m, 1 - lead + i)), y = x.getUTCFullYear(), m = x.getUTCMonth(), d = x.getUTCDate();
      const past = Date.UTC(y, m, d) < Date.UTC(today.y, today.m, today.d);
      const isToday = y === today.y && m === today.m && d === today.d;
      const out = m !== v.m, wkend = x.getUTCDay() === 0 || x.getUTCDay() === 6;
      cells.push(`<button type="button" class="sc-d ${out ? 'out' : ''} ${isToday ? 'today' : ''} ${wkend ? 'wkend' : ''}" ${past ? 'disabled' : `data-sc-day="${y}-${m}-${d}"`}>${d}</button>`);
    }
    void dim;
    const title = new Date(Date.UTC(v.y, v.m, 1)).toLocaleDateString('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' });
    const atThis = v.y === today.y && v.m === today.m;
    return `<div class="sc-cal"><div class="sc-cal-h"><b>${title}</b><button type="button" class="sc-mini" data-sc-nav="today">Today</button>
      <button type="button" class="sc-ic" data-sc-nav="-1" aria-label="Previous month" ${atThis ? 'disabled' : ''}>${icon('chev-left')}</button><button type="button" class="sc-ic" data-sc-nav="1" aria-label="Next month">${icon('chev-right')}</button></div>
      <div class="sc-grid">${['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map((x) => `<span class="sc-wd">${x}</span>`).join('')}${cells.join('')}</div></div>`;
  }
  function body() {
    const now = Date.now();
    if (st.day) {
      const dms = at(st.day.y, st.day.m, st.day.d);
      const chips = [9, 11, 13, 15, 17].map((h) => at(st.day.y, st.day.m, st.day.d, h)).filter((ms) => ms > now + 60000);
      if (st.pick == null || st.pick <= now) st.pick = chips[0] || null;
      const custom = st.custom ? dayTime(st.custom) : null;
      const chosen = custom || st.pick;
      return `<div class="sc-dayh"><button type="button" class="sc-ic" data-sc-back aria-label="Back to the calendar">${icon('chev-left')}</button><b>${esc(fmtLongDay(dms))}</b></div>
        <div class="sc-times">${chips.map((ms) => `<button type="button" class="sc-t ${!custom && ms === st.pick ? 'on' : ''}" data-sc-pick="${ms}">${fmtTime(ms)}</button>`).join('')}
          <label class="sc-other"><span class="sr">Other time</span><input id="sc-other" placeholder="${chips.length ? 'Other time' : 'e.g. 4:30 PM'}" value="${esc(st.custom || '')}" autocomplete="off"></label></div>
        ${st.custom && !custom ? '<div class="sc-bad">Type a later time, like 4:30 PM</div>' : ''}
        ${noteHTML(chosen)}
        <button type="button" class="btn primary sc-go" ${chosen ? `data-sc-at="${chosen}"` : 'disabled'}>${chosen ? `Schedule for ${esc(when(chosen))}` : 'Pick a time'}</button>`;
    }
    const q = (st.q || '').trim();
    if (q) {
      const ms = parse(q);
      return ms ? `<div class="sc-res"><button type="button" class="sc-hit" data-sc-at="${ms}">${icon('cal')}<span><b>${esc(when(ms))}</b><small>${esc(rel(ms))}</small></span><kbd>↵ Schedule</kbd></button>${noteHTML(ms)}</div>`
        : '<div class="sc-res"><p class="sc-hint">Try “tomorrow 10am”, “in 3 hours”, “next Monday” or “5 Nov 4pm”.</p></div>';
    }
    return `<div class="sc-list">${quick(now).map((x) => `<button type="button" class="sc-q" data-sc-at="${x.ms}"><span class="sc-qi">${QI[x.k]}</span><span class="sc-ql">${x.l}</span><span class="sc-qt">${x.short ? fmtTime(x.ms) : `${wd(x.ms)}, ${fmtTime(x.ms)}`}${outside(x.ms) ? '<i>Outside office hours</i>' : ''}</span></button>`).join('')}</div>${calHTML()}`;
  }
  function rel(ms) {
    const mins = Math.round((ms - Date.now()) / 60000);
    if (mins < 60) return `in ${mins} minute${mins === 1 ? '' : 's'}`;
    const t = dub(Date.now()), d = dub(ms);
    const days = Math.round((Date.UTC(d.y, d.m, d.d) - Date.UTC(t.y, t.m, t.d)) / 86400000);
    if (days === 0) return `today, in ${Math.round(mins / 60)} hour${Math.round(mins / 60) === 1 ? '' : 's'}`;
    return days === 1 ? 'tomorrow' : `in ${days} days`;
  }
  function paint(keepFocus) {
    const p = pop(); if (!p || !st) return;
    const focusId = keepFocus && document.activeElement ? document.activeElement.id : null;
    const caret = focusId && document.activeElement.selectionStart;
    p.querySelector('.sc-body').innerHTML = body();
    p.querySelector('.sc-top').style.display = st.day ? 'none' : '';
    if (focusId) { const el = document.getElementById(focusId); if (el) { el.focus(); try { el.setSelectionRange(caret, caret); } catch (e) { /* ignore */ } } }
    place();
  }
  function place() {
    const p = pop(); if (!p || !st || !st.anchor.isConnected) return;
    const r = st.anchor.getBoundingClientRect(), w = p.offsetWidth, h = p.offsetHeight;
    const left = Math.max(8, Math.min(r.right - w, innerWidth - w - 8));
    const top = r.top - h - 8 >= 8 ? r.top - h - 8 : Math.min(r.bottom + 8, innerHeight - h - 8);
    p.style.left = left + 'px'; p.style.top = Math.max(8, top) + 'px';
  }
  function open(anchor, replyTo) {
    if (pop()) { close(); return; }
    const t = task(ui.taskId);
    if (!t) return;
    const btn = anchor.closest('.send-split') || anchor;
    const today = dub(Date.now());
    st = { anchor: btn, replyTo: replyTo || null, taskId: t.id, q: '', view: { y: today.y, m: today.m }, day: null, pick: null, custom: '' };
    const p = document.createElement('div');
    p.id = 'sc-pop'; p.className = 'sc-pop'; p.setAttribute('role', 'dialog'); p.setAttribute('aria-label', `Schedule this ${replyTo ? 'reply' : 'comment'}`);
    p.innerHTML = `<div class="sc-top"><label><span class="sr">When to send</span><input id="sc-q" placeholder="Try “Tomorrow at 2 PM”…" autocomplete="off" spellcheck="false"></label></div><div class="sc-body"></div>`;
    document.body.appendChild(p);
    p.addEventListener('input', (e) => {
      if (e.target.id === 'sc-q') { st.q = e.target.value; paint(true); }
      else if (e.target.id === 'sc-other') { st.custom = e.target.value; paint(true); }
    });
    p.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b || b.disabled) return;
      if (b.dataset.scAt) return schedule(+b.dataset.scAt);
      if (b.dataset.scNav) {
        const v = st.view, today2 = dub(Date.now());
        if (b.dataset.scNav === 'today') st.view = { y: today2.y, m: today2.m };
        else { const x = new Date(Date.UTC(v.y, v.m + +b.dataset.scNav, 1)); st.view = { y: x.getUTCFullYear(), m: x.getUTCMonth() }; }
        return paint();
      }
      if (b.dataset.scDay) { const [y, m, d] = b.dataset.scDay.split('-').map(Number); st.day = { y, m, d }; st.pick = null; st.custom = ''; return paint(); }
      if (b.dataset.scPick) { st.pick = +b.dataset.scPick; st.custom = ''; return paint(); }
      if (b.hasAttribute('data-sc-back')) { st.day = null; paint(); setTimeout(() => { const q = document.getElementById('sc-q'); if (q) q.focus(); }, 0); }
    });
    paint();
    document.addEventListener('mousedown', onDown, true);
    document.addEventListener('keydown', onKey, true);
    setTimeout(() => { const q = document.getElementById('sc-q'); if (q) q.focus(); }, 20);
  }

  function schedule(ms) {
    const t = st && task(st.taskId);
    if (!t) return close();
    if (!(ms > Date.now() + 30000)) { toast('Pick a time in the future'); return; }
    const replyTo = st.replyTo, key = draftKey(t, replyTo);
    if (ui.commentUp && ui.commentUp[key]) { toast('Wait for your files to finish uploading'); return; }
    const box = ui.taskId === t.id ? $(`#detail [data-draft-key="${key}"]`) : null;
    const empty = !box || editorEmpty(box);
    const text = empty ? '' : box.innerText.trim(), html = empty ? '' : sanitizeHTML(box.innerHTML);
    const files = ui.commentFiles[key] || [];
    if (!text && !files.length) { close(); toast(`Write your ${replyTo ? 'reply' : 'comment'} first`); setTimeout(() => { const b = $(`#detail [data-draft-key="${key}"]`); if (b) b.focus(); }, 0); return; }
    db.scheduled.push({ id: 's-' + uid(), taskId: t.id, taskTitle: t.title || '', authorId: currentUserId, replyTo: replyTo || null, text, html, attachments: files, sendAt: new Date(ms).toISOString(), createdAt: nowISO(), state: 'waiting' });
    delete ui.commentFiles[key]; delete ui.commentDraft[key];
    if (typeof Unsent !== 'undefined') Unsent.save();
    close();
    commit();
    toast(`${replyTo ? 'Reply' : 'Comment'} scheduled for ${when(ms)}`);
    setTimeout(() => { const f = $('#detail .tm-feed'); if (f) f.scrollTop = f.scrollHeight; }, 0);
  }

  /* ---- In the task: your waiting scheduled comments ---- */
  const mine = (t, thread) => (db.scheduled || []).filter((s) => s.taskId === t.id && s.authorId === currentUserId && s.state === 'waiting' && (!thread || s.replyTo === thread))
    .sort((a, b) => String(a.sendAt).localeCompare(String(b.sendAt)));
  function feedHTML(t, thread) {
    const list = mine(t, thread);
    if (!list.length) return '';
    return `<div class="sc-cards">${list.map((s) => {
      const target = s.replyTo && (t.comments || []).find((c) => c.id === s.replyTo);
      const re = s.replyTo && !thread ? `<div class="sc-re">${icon('reply')}Reply to ${esc(target ? (target.authorId === currentUserId ? 'your comment' : fullName(userById(target.authorId))) : 'a comment')}</div>` : '';
      const files = (s.attachments || []).map((a) => `<span class="sc-file">${icon('clip')}<span>${esc(a.name)}</span><i>· shows once sent</i></span>`).join('');
      return `<div class="sc-card" data-sched="${esc(s.id)}">
        <div class="sc-card-h">${avatarHTML(currentUserId, 26)}<b>You</b><span class="sc-badge">${icon('clock')}Scheduled · ${esc(when(Date.parse(s.sendAt)))}</span></div>
        ${re}
        ${s.html ? `<div class="cm-text rich">${sanitizeHTML(s.html, true)}</div>` : s.text ? `<div class="cm-text">${linkify(esc(s.text))}</div>` : ''}
        ${files ? `<div class="sc-files">${files}</div>` : ''}
        <div class="sc-card-a"><button type="button" class="btn ghost xs" data-sc-act="edit" data-id="${esc(s.id)}">Edit</button><button type="button" class="btn ghost xs sc-now" data-sc-act="now" data-id="${esc(s.id)}">Send now</button><button type="button" class="btn ghost xs sc-del" data-sc-act="cancel" data-id="${esc(s.id)}">Cancel</button></div>
      </div>`;
    }).join('')}</div>`;
  }
  const byId = (id) => (db.scheduled || []).find((s) => s.id === id);
  const drop = (s) => { db.scheduled = (db.scheduled || []).filter((x) => x !== s); };
  const plain = (html) => { const d = document.createElement('div'); d.innerHTML = html || ''; return d.textContent.trim(); };
  // put a scheduled comment back in its task's comment box (added to anything already there)
  function toDraft(s) {
    const t = task(s.taskId);
    if (!t) return false;
    const replyTo = s.replyTo && (t.comments || []).some((c) => c.id === s.replyTo) ? s.replyTo : null;
    const key = draftKey(t, replyTo);
    const html = s.html || esc(s.text || '').replace(/\n/g, '<br>');
    ui.commentDraft[key] = plain(ui.commentDraft[key]) ? ui.commentDraft[key] + '<br>' + html : html;
    ui.commentFiles[key] = (ui.commentFiles[key] || []).concat((s.attachments || []).filter((a) => !(ui.commentFiles[key] || []).some((x) => x.path === a.path)));
    if (typeof Unsent !== 'undefined') Unsent.save();
    return key;
  }
  function focusDraft(t, key, replyTo) {
    if (replyTo && ui.thread !== replyTo) { ui.replyTo = replyTo; renderDetail(); }
    setTimeout(() => { const b = $(`#detail [data-draft-key="${key}"]`); if (b) { b.focus(); placeCaretAtEnd(b); } }, 60);
  }
  document.addEventListener('click', async (e) => {
    const b = e.target.closest && e.target.closest('[data-sc-act]');
    if (!b) return;
    e.preventDefault(); e.stopPropagation();
    const s = byId(b.dataset.id);
    if (!s || s.state !== 'waiting') return;
    const t = task(s.taskId);
    if (!t) return;
    if (b.dataset.scAct === 'edit') {
      const key = draftKey(t, s.replyTo);
      if ((plain(ui.commentDraft[key]) || (ui.commentFiles[key] || []).length) && !(await dialog({ title: 'Add it to what you’re writing?', body: 'The scheduled comment goes back into the comment box, after what’s already there. It won’t be sent until you send or schedule it again.', okText: 'Move it back' }))) return;
      const k = toDraft(s);
      drop(s); commit();
      focusDraft(t, k, s.replyTo && k !== t.id ? s.replyTo : null);
      toast('Back in the comment box — send or schedule it again');
    } else if (b.dataset.scAct === 'now') {
      drop(s);
      const replyTo = s.replyTo && (t.comments || []).some((c) => c.id === s.replyTo) ? s.replyTo : null;
      postComment(t, replyTo, s.text || '', s.html || '', s.attachments || []);
      t.updatedAt = nowISO();
      commit();
      toast(`${replyTo ? 'Reply' : 'Comment'} sent`);
    } else if (b.dataset.scAct === 'cancel') {
      drop(s); commit();
      let undone = false;
      toast(`Scheduled ${s.replyTo ? 'reply' : 'comment'} cancelled`, { label: 'Undo', run: () => { undone = true; if (!byId(s.id)) { db.scheduled.push(s); commit(); } } });
      setTimeout(() => { if (!undone && !byId(s.id)) safeTrash((s.attachments || []).map((a) => a.path)); }, 8000);
    }
  }, true);

  /* ---- Not sent (the task was completed or deleted first) ---- */
  // a deleted task that was restored: its cancelled comments come back as drafts by themselves
  function reclaim() {
    if (!db || !db.scheduled || !currentUserId) return;
    let changed = false;
    for (const s of db.scheduled) {
      if (s.authorId !== currentUserId || s.state !== 'cancelled' || s.reason !== 'deleted' || s.drafted || !task(s.taskId)) continue;
      toDraft(s); s.drafted = true; changed = true;
    }
    if (changed) persist();
  }
  function openCancelled(n) {
    const s = byId(n.schedId);
    if (!s) { toast('That comment is no longer kept (after 30 days)'); return; }
    const t = task(s.taskId);
    if (t) {
      let key = draftKey(t, s.replyTo && (t.comments || []).some((c) => c.id === s.replyTo) ? s.replyTo : null);
      if (!s.drafted) { key = toDraft(s); s.drafted = true; persist(); }
      ui.forceTab = 'comments';
      openTask(t.id);
      focusDraft(t, key, key !== t.id ? s.replyTo : null);
      return;
    }
    // deleted: Admins and Account Managers find it in the Trash; everyone else gets its text and files
    const inTrash = trashList().find((it) => ((it.data || {}).tasks || []).some((x) => x && x.id === s.taskId));
    if (inTrash && isManager()) { if (ui.taskId) closeDetail(); ui.trashQ = trashTitle(inTrash); ui.trashFilter = 'all'; go('trash'); toast('The task is in the Trash — restore it and your comment comes back as a draft'); return; }
    lost(s);
  }
  function lost(s) {
    const w = document.createElement('div');
    w.className = 'us-wrap'; w.id = 'sc-lost';
    const files = (s.attachments || []).map((a, i) => `<div class="sc-lf">${icon('clip')}<span>${esc(a.name)}</span><button type="button" class="btn sm" data-lf="${i}">${icon('download')}Download</button></div>`).join('');
    w.innerHTML = `<div class="us-card" role="dialog" aria-modal="true" aria-labelledby="sl-t">
      <div class="us-head"><span class="us-ic">${icon('clock')}</span><div><h2 id="sl-t">Your scheduled ${s.replyTo ? 'reply' : 'comment'} wasn’t sent</h2><p><b>${esc(s.taskTitle || 'The task')}</b> was deleted.</p></div></div>
      <div class="us-box"><div class="sc-lt">${s.html ? sanitizeHTML(s.html, true) : esc(s.text || '')}</div>${files ? `<div class="sc-lfs">${files}</div>` : ''}</div>
      <div class="us-acts"><button type="button" class="btn" data-sl="copy">${icon('copy')}Copy text</button><span class="us-sp"></span><button type="button" class="btn primary" data-sl="close">Close</button></div>
      <p class="us-note">If the task is restored, your ${s.replyTo ? 'reply' : 'comment'} comes back as a draft.</p></div>`;
    const done = () => { w.remove(); document.removeEventListener('keydown', esc1, true); };
    const esc1 = (e) => { if (e.key === 'Escape') { e.stopPropagation(); done(); } };
    w.addEventListener('click', async (e) => {
      if (e.target === w) return done();
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.sl === 'close') return done();
      if (b.dataset.sl === 'copy') { try { await navigator.clipboard.writeText(s.text || plain(s.html)); toast('Copied'); } catch (err) { toast('Couldn’t copy — select the text instead'); } return; }
      if (b.dataset.lf != null) { const a = (s.attachments || [])[+b.dataset.lf]; if (a) Host.call('revealPath', { path: a.path }).catch((err) => toast('Couldn’t download: ' + err.message)); }
    });
    document.body.appendChild(w);
    document.addEventListener('keydown', esc1, true);
  }

  window.addEventListener('resize', () => place());
  return { open, close, parse, quick, outside, when, feedHTML, reclaim, openCancelled, _dub: dub };
})();

/* ================= Pin to brief =================
   A task's description is locked once it goes for CD review (idLocked in app.js), so changes to the brief go in
   comments. Any comment can be pinned from its ••• menu ("Pin to brief"): pinned comments show as "Brief updates"
   under the description, with who and when, and a click jumps to the comment. A pinned comment can't be edited
   (the server refuses it too). Whoever pinned it, an Account Manager or an Admin can unpin it. */
const Brief = (() => {
  const pins = (t) => (t && t.briefPins) || [];
  const isPinned = (t, cid) => pins(t).some((p) => p.cid === cid);
  function pinMenu(t, c) {
    if (!t || !c) return [];
    const p = pins(t).find((x) => x.cid === c.id);
    if (p) return p.by === currentUserId || isManager() ? [{ label: 'Unpin from brief', icon: 'pushpin', run: () => { t.briefPins = pins(t).filter((x) => x.cid !== c.id); t.updatedAt = nowISO(); commit(); } }, '-'] : [];
    return [{ label: 'Pin to brief', icon: 'pushpin', run: () => {
      t.briefPins = pins(t).concat({ cid: c.id, by: currentUserId, at: nowISO() });
      logActivity(t, 'pinned a comment to the brief');
      t.updatedAt = nowISO(); commit();
      toast('Pinned under the description as a brief update');
    } }, '-'];
  }
  function pinsHTML(t) {
    const list = pins(t).map((p) => ({ p, c: (t.comments || []).find((c) => c.id === p.cid) })).filter((x) => x.c)
      .sort((a, b) => String(a.c.at).localeCompare(String(b.c.at)));
    if (!list.length) return '';
    return `<div class="brief-pins"><div class="bp-h">${icon('pushpin')}<b>Brief updates</b><span>${list.length}</span></div>
      ${list.map(({ p, c }) => `<button type="button" class="bp-row" data-bp="${esc(c.id)}">${avatarHTML(c.authorId, 22)}<span class="bp-b">
        <span class="bp-m"><b>${esc(c.authorId === currentUserId ? 'You' : fullName(userById(c.authorId)))}</b> · ${esc(fmtShort(c.at))}${p.by !== c.authorId ? ` <i>· pinned by ${esc(p.by === currentUserId ? 'you' : firstName(p.by))}</i>` : ''}</span>
        <span class="bp-t">${esc(trunc(c.text || `${(c.attachments || []).length} file${(c.attachments || []).length === 1 ? '' : 's'}`, 240))}</span></span></button>`).join('')}</div>`;
  }
  // a click on a brief update: its comment in the comments (in its thread if it's a reply)
  document.addEventListener('click', (e) => {
    const b = e.target.closest && e.target.closest('[data-bp]');
    if (!b) return;
    e.preventDefault(); e.stopPropagation();
    const t = task(ui.taskId); if (!t) return;
    const c = (t.comments || []).find((x) => x.id === b.dataset.bp); if (!c) return;
    ui.sideTab = 'comments'; ui.activityFilter = 'comments'; ui.replyTo = null;
    ui.thread = c.parentId || null;
    renderDetail();
    setTimeout(() => focusCommentInFeed(c.id), 30);
  }, true);
  return { isPinned, pinMenu, pinsHTML };
})();
