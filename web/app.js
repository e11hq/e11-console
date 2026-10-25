/* E11 Console — task manager (single user, local data) */
'use strict';

/* ================= Utilities ================= */
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const nowISO = () => new Date().toISOString();
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const byOrder = (a, b) => (a.order || 0) - (b.order || 0);

const ICONS = {
  plus: '<path d="M8 3v10M3 8h10"/>',
  home: '<path d="M2.5 7.2 8 2.8l5.5 4.4V13a.5.5 0 0 1-.5.5H9.6V9.8H6.4v3.7H3a.5.5 0 0 1-.5-.5z"/>',
  'check-circle': '<circle cx="8" cy="8" r="5.8"/><path d="m5.6 8.1 1.7 1.7 3.2-3.4"/>',
  check: '<path d="m3.5 8.4 3 3 6-6.6"/>',
  search: '<circle cx="7" cy="7" r="4.3"/><path d="m10.3 10.3 3.2 3.2"/>',
  list: '<path d="M5.5 4h8M5.5 8h8M5.5 12h8"/><circle cx="2.6" cy="4" r=".7"/><circle cx="2.6" cy="8" r=".7"/><circle cx="2.6" cy="12" r=".7"/>',
  board: '<rect x="2" y="2.5" width="3.4" height="11" rx="1"/><rect x="6.3" y="2.5" width="3.4" height="7" rx="1"/><rect x="10.6" y="2.5" width="3.4" height="9" rx="1"/>',
  trash: '<path d="M2.8 4.3h10.4M6.3 4.3V2.8h3.4v1.5M4.2 4.3l.6 8.6c0 .4.4.8.8.8h4.8c.4 0 .8-.4.8-.8l.6-8.6"/>',
  x: '<path d="m4 4 8 8M12 4l-8 8"/>',
  clip: '<path d="M10.5 5.5 6.1 9.9a1.3 1.3 0 0 0 1.8 1.8l4.6-4.6a2.6 2.6 0 0 0-3.7-3.7L4.2 8a3.9 3.9 0 0 0 5.5 5.5L13 10.2"/>',
  chat: '<path d="M2.7 3.2h10.6v7.3H7.1L4.3 13v-2.5H2.7z"/>',
  sub: '<path d="M4 2.5v6.2c0 .9.7 1.6 1.6 1.6H12M9.6 7.9l2.4 2.4-2.4 2.4"/>',
  chev: '<path d="m4.5 6.2 3.5 3.6 3.5-3.6"/>',
  'chev-up': '<path d="m4.5 9.8 3.5-3.6 3.5 3.6"/>',
  'chev-right': '<path d="m6.2 4.5 3.6 3.5-3.6 3.5"/>',
  more: '<circle cx="3.5" cy="8" r="1.1" fill="currentColor" stroke="none"/><circle cx="8" cy="8" r="1.1" fill="currentColor" stroke="none"/><circle cx="12.5" cy="8" r="1.1" fill="currentColor" stroke="none"/>',
  grip: '<circle cx="6" cy="4" r=".9" fill="currentColor" stroke="none"/><circle cx="10" cy="4" r=".9" fill="currentColor" stroke="none"/><circle cx="6" cy="8" r=".9" fill="currentColor" stroke="none"/><circle cx="10" cy="8" r=".9" fill="currentColor" stroke="none"/><circle cx="6" cy="12" r=".9" fill="currentColor" stroke="none"/><circle cx="10" cy="12" r=".9" fill="currentColor" stroke="none"/>',
  cal: '<rect x="2.5" y="3.3" width="11" height="10.2" rx="1.5"/><path d="M2.5 6.6h11M5.5 2v2.4M10.5 2v2.4"/>',
  folder: '<path d="M2.2 4.2c0-.6.4-1 1-1h3l1.4 1.5h5.2c.6 0 1 .4 1 1v6.6c0 .6-.4 1-1 1H3.2c-.6 0-1-.4-1-1z"/>',
  edit: '<path d="M10.4 3.2 12.8 5.6 6 12.4l-3 .6.6-3z"/>',
  select: '<rect x="2" y="3.5" width="12" height="9" rx="2"/><path d="M8.5 3.5v9"/><path d="m10.3 7.3 1.2 1.2 1.2-1.2"/>',
  coin: '<circle cx="8" cy="8" r="5.6"/><path d="M9.9 6.1c-.3-.6-1-1-1.9-1-1.1 0-1.9.6-1.9 1.4 0 1.9 3.9 1 3.9 2.9 0 .8-.8 1.5-2 1.5-.9 0-1.7-.4-2-1.1M8 4v1.1M8 10.9V12"/>',
  link: '<path d="M6.9 9.1a2.6 2.6 0 0 0 3.7 0l2.2-2.2a2.6 2.6 0 0 0-3.7-3.7l-.9.9"/><path d="M9.1 6.9a2.6 2.6 0 0 0-3.7 0L3.2 9.1a2.6 2.6 0 0 0 3.7 3.7l.9-.9"/>',
  open: '<path d="M9.5 2.7h3.8v3.8M13.3 2.7 7.6 8.4M11.6 9.3v3.2c0 .5-.4.8-.8.8H3.5a.8.8 0 0 1-.8-.8V5.2c0-.4.3-.8.8-.8h3.2"/>',
  arrow: '<path d="M3 8h9.5M8.8 4.3 12.5 8l-3.7 3.7"/>',
  flag: '<path d="M3.5 13.5V2.8M3.5 3h8l-1.7 2.8 1.7 2.8h-8"/>',
  tag: '<path d="M2.7 2.7h5l5.6 5.6-5 5-5.6-5.6z"/><circle cx="5.3" cy="5.3" r=".9"/>',
  sun: '<circle cx="8" cy="8" r="2.8"/><path d="M8 1.6v1.6M8 12.8v1.6M1.6 8h1.6M12.8 8h1.6M3.5 3.5l1.1 1.1M11.4 11.4l1.1 1.1M3.5 12.5l1.1-1.1M11.4 4.6l1.1-1.1"/>',
  'chev-left': '<path d="m9.8 4.5-3.6 3.5 3.6 3.5"/>',
  reply: '<path d="M6.5 4 3 7.5 6.5 11M3.3 7.5h6.2a3.5 3.5 0 0 1 3.5 3.5v1"/>',
  send: '<path d="M3.4 8 2.6 3.2 13.6 8 2.6 12.8 3.4 8zm0 0h4.8"/>',
  smile: '<circle cx="8" cy="8" r="5.8"/><path d="M5.6 9.4c.6.9 1.4 1.3 2.4 1.3s1.8-.4 2.4-1.3"/><circle cx="6" cy="6.6" r=".5" fill="currentColor"/><circle cx="10" cy="6.6" r=".5" fill="currentColor"/>',
  checklist: '<path d="m2.5 4.2 1.1 1.1 2-2.2M2.5 9.7l1.1 1.1 2-2.2M7.8 4.4h5.7M7.8 9.9h5.7"/>',
  activity: '<path d="M1.8 8h2.6l1.8-4.6 3.2 9.2 1.8-4.6h3"/>',
  play: '<path d="M5 3.5v9l7-4.5z"/>',
  sidebar: '<rect x="2" y="2.8" width="12" height="10.4" rx="2"/><path d="M6.2 2.8v10.4"/>',
  moon: '<path d="M13.2 9.6A5.6 5.6 0 0 1 6.4 2.8a5.6 5.6 0 1 0 6.8 6.8z"/>',
  'theme-auto': '<circle cx="8" cy="8" r="5.6"/><path d="M8 2.4a5.6 5.6 0 0 1 0 11.2z" fill="currentColor"/>',
  layout: '<rect x="2" y="2.8" width="12" height="10.4" rx="2"/><path d="M9.8 2.8v10.4"/>',
  modal: '<rect x="1.8" y="2.6" width="12.4" height="10.8" rx="2"/><rect x="4.6" y="5" width="6.8" height="6" rx="1"/>',
  panel: '<rect x="1.8" y="2.6" width="12.4" height="10.8" rx="2"/><path d="M9 2.6v10.8"/><path d="M10.6 5.2h2M10.6 7.2h2"/>',
  info: '<circle cx="8" cy="8" r="5.8"/><path d="M8 7.2v3.6M8 5.1v.1"/>',
  inbox: '<path d="M2.3 9.2 4 3.4c.1-.4.5-.7.9-.7h6.2c.4 0 .8.3.9.7l1.7 5.8v3.3c0 .4-.4.8-.8.8H3.1a.8.8 0 0 1-.8-.8z"/><path d="M2.3 9.2h3.2l.9 1.6h3.2l.9-1.6h3.2"/>',
  users: '<circle cx="6" cy="5.6" r="2.3"/><path d="M1.9 13c.4-2.2 2-3.4 4.1-3.4s3.7 1.2 4.1 3.4"/><path d="M10.4 3.5a2.2 2.2 0 0 1 0 4.3M12 9.8c1.2.4 1.9 1.5 2.1 3.2"/>',
  user: '<circle cx="8" cy="5.6" r="2.6"/><path d="M3 13.4c.5-2.6 2.5-4 5-4s4.5 1.4 5 4"/>',
  logout: '<path d="M6.4 13.3H3.5a.8.8 0 0 1-.8-.8v-9c0-.4.4-.8.8-.8h2.9M10.4 11l3-3-3-3M13.3 8H6.2"/>',
  bell: '<path d="M4 11.2V7.4a4 4 0 0 1 8 0v3.8l1.2 1.2H2.8zM6.6 13.4a1.5 1.5 0 0 0 2.8 0"/>',
  lock: '<rect x="3.2" y="7.2" width="9.6" height="6.4" rx="1.4"/><path d="M5.4 7.2V5.3a2.6 2.6 0 0 1 5.2 0v1.9"/>',
  image: '<rect x="2.3" y="2.8" width="11.4" height="10.4" rx="1.6"/><circle cx="5.9" cy="6.3" r="1.2"/><path d="m13.7 10.6-3.4-3.3-6.7 5.9"/>',
  camera: '<path d="M2.3 5.4c0-.5.4-.9.9-.9h1.9l1-1.5h3.8l1 1.5h1.9c.5 0 .9.4.9.9v6.7c0 .5-.4.9-.9.9H3.2a.9.9 0 0 1-.9-.9z"/><circle cx="8" cy="8.6" r="2.3"/>',
  details: '<path d="M2.4 4.2h7.2M2.4 8h5.2M2.4 11.8h7.2"/><path d="M12.6 7.2v5"/><circle cx="12.6" cy="4.4" r=".75" fill="currentColor" stroke="none"/>',
  comment: '<path d="M3.2 2.9h9.6c.6 0 1 .4 1 1v6.6c0 .6-.4 1-1 1H7.4l-3 2.4v-2.4H3.2c-.6 0-1-.4-1-1V3.9c0-.6.4-1 1-1z"/><path d="M5.2 6h5.6M5.2 8.4h3.8"/>',
  upload: '<path d="M8 10.5V2.8M4.9 5.8 8 2.7l3.1 3.1M2.8 10.2v2.2c0 .5.4.9.9.9h8.6c.5 0 .9-.4.9-.9v-2.2"/>',
  download: '<path d="M8 2.7v7.7M4.9 7.4 8 10.5l3.1-3.1M2.8 10.2v2.2c0 .5.4.9.9.9h8.6c.5 0 .9-.4.9-.9v-2.2"/>',
  clock: '<circle cx="8" cy="8" r="5.8"/><path d="M8 4.8V8l2.2 1.5"/>',
  copy: '<rect x="5.4" y="5.4" width="8" height="8.2" rx="1.5"/><path d="M10.6 5.4V3.8c0-.6-.4-1-1-1H3.8c-.6 0-1 .4-1 1v5.8c0 .6.4 1 1 1h1.6"/>',
  pin: '<path d="M8 14.2s4.6-4.2 4.6-7.8a4.6 4.6 0 0 0-9.2 0c0 3.6 4.6 7.8 4.6 7.8z"/><circle cx="8" cy="6.4" r="1.7"/>',
  mail: '<rect x="2.2" y="3.4" width="11.6" height="9.2" rx="1.5"/><path d="m2.6 4.3 5.4 4.3 5.4-4.3"/>',
  assets: '<rect x="2.4" y="2.4" width="4.8" height="4.8" rx="1.2"/><rect x="8.8" y="2.4" width="4.8" height="4.8" rx="1.2"/><rect x="2.4" y="8.8" width="4.8" height="4.8" rx="1.2"/><path d="M11.2 8.6v5M8.7 11.1h5"/>',
  shield: '<path d="M8 1.9 13 3.8v3.8c0 3-2.1 5.4-5 6.5-2.9-1.1-5-3.5-5-6.5V3.8z"/><path d="m5.8 8 1.5 1.5 2.9-3"/>',
};
function icon(name, cls = '') {
  return `<span class="ic ${cls}"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg></span>`;
}
function hydrateIcons(root = document) {
  $$('[data-icon]', root).forEach((el) => { el.outerHTML = icon(el.dataset.icon); });
}

/* Dates (stored as local YYYY-MM-DD) */
const pad2 = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
const parseYmd = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
const todayStr = () => ymd(new Date());
const addDays = (s, n) => { const d = parseYmd(s); d.setDate(d.getDate() + n); return ymd(d); };
const dayDiff = (s) => Math.round((parseYmd(s) - parseYmd(todayStr())) / 86400000);
function fmtDue(s) {
  if (!s) return '';
  const d = dayDiff(s);
  if (d === 0) return 'Today';
  if (d === 1) return 'Tomorrow';
  if (d === -1) return 'Yesterday';
  const dt = parseYmd(s);
  if (d > 1 && d < 7) return dt.toLocaleDateString('en-US', { weekday: 'long' });
  const o = { month: 'short', day: 'numeric' };
  if (dt.getFullYear() !== new Date().getFullYear()) o.year = 'numeric';
  return dt.toLocaleDateString('en-US', o);
}
function dueClass(t) {
  if (!t.due || t.done) return '';
  const d = dayDiff(t.due);
  return d < 0 ? 'overdue' : d === 0 ? 'today' : d <= 2 ? 'soon' : '';
}
function timeAgo(iso) {
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  if (s < 86400) return Math.floor(s / 3600) + 'h ago';
  if (s < 86400 * 7) return Math.floor(s / 86400) + 'd ago';
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}
const fmtDateTime = (iso) => new Date(iso).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' });
function fmtSize(b) {
  if (b == null) return '';
  if (b < 1024) return b + ' B';
  if (b < 1048576) return (b / 1024).toFixed(0) + ' KB';
  return (b / 1048576).toFixed(1) + ' MB';
}

/* ================= Host bridge ================= */
const Host = (() => {
  const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.e11;
  let seq = 0;
  const pending = new Map();
  window.__e11Reply = (id, res) => {
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    if (res && res.ok === false) p.reject(new Error(res.error || 'Something went wrong'));
    else p.resolve(res || {});
  };
  function fallback(cmd, args) {
    // Browser preview only (no file access)
    switch (cmd) {
      case 'load': return Promise.resolve({ ok: true, data: localStorage.getItem('e11-data'), dataDir: 'Browser preview storage' });
      case 'save': localStorage.setItem('e11-data', args.data); return Promise.resolve({ ok: true });
      case 'pickAttachments': toast('Attachments work in the Mac app'); return Promise.resolve({ ok: true, files: [] });
      default: return Promise.resolve({ ok: true });
    }
  }
  // Opened from the office server (console.e11hq.com) instead of the Mac app
  // (the E11 Console Mac app also opens the server, and adds native extras through the same bridge)
  const server = /^https?:$/.test(location.protocol) && !window.__E11_LOCAL_PREVIEW;
  function call(cmd, args = {}) {
    if (server) return ServerHost.call(cmd, args);
    if (!native) return fallback(cmd, args);
    return new Promise((resolve, reject) => {
      const id = ++seq;
      // File pickers wait for the user; everything else should answer quickly
      const timer = cmd === 'pickAttachments' || cmd === 'pickImage' ? null : setTimeout(() => {
        if (pending.has(id)) { pending.delete(id); reject(new Error('The app did not respond (' + cmd + ')')); }
      }, 20000);
      const settle = (fn, v) => { clearTimeout(timer); if (pending.has(id)) { pending.delete(id); fn(v); } };
      pending.set(id, true);
      native.postMessage(JSON.stringify({ id, cmd, args }));
      fetch(new URL('/__reply/' + id, location.href).href, { cache: 'no-store' })
        .then((r) => r.json())
        .then((res) => (res && res.ok === false ? settle(reject, new Error(res.error || 'Something went wrong')) : settle(resolve, res || {})))
        .catch((e) => settle(reject, new Error('The app did not respond (' + cmd + '): ' + e.message)));
    });
  }
  // isNative = files can be shown (true in the Mac app and on the server); isServer = connected to the server
  return { call, isNative: !!native || server, isServer: server, isMacApp: server && !!native };
})();

// Talking to the E11 Console Mac app around the page (file picker, Downloads, Dock badge…)
const NativeMac = (() => {
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.e11;
  let seq = 0;
  const waiting = new Map();
  window.__e11NativeReply = (id, res) => {
    const w = waiting.get(id);
    if (!w) return;
    waiting.delete(id);
    if (res && res.ok === false) w.reject(new Error(res.error || 'Something went wrong')); else w.resolve(res || {});
  };
  function call(cmd, args = {}) {
    if (!handler) return Promise.reject(new Error('Not in the Mac app'));
    return new Promise((resolve, reject) => {
      const id = 'n' + (++seq);
      waiting.set(id, { resolve, reject });
      handler.postMessage(JSON.stringify({ id, cmd, args }));
    });
  }
  return { call };
})();


/* ================= Mac app Dock icon (chosen by the owner on the server) ================= */
const AppIcon = (() => {
  let info = null, applied = null, busy = null, owner = false;
  const KEY = 'e11-appicon-custom';
  const lsGet = () => { try { return localStorage.getItem(KEY); } catch (e) { return null; } };
  const lsSet = (v) => { try { if (v) localStorage.setItem(KEY, v); else localStorage.removeItem(KEY); } catch (e) { /* storage off */ } };
  const toB64 = (blob) => new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result).split(',')[1] || ''); r.onerror = rej; r.readAsDataURL(blob); });
  // Make this Mac's Dock icon match the server (old Mac apps without setIcon simply ignore it)
  async function sync(next) {
    if (next) info = next;
    if (!Host.isMacApp || !info || applied === info.v || busy === info.v) return;
    const v = info.v;
    busy = v;
    try {
      if (info.custom) {
        const r = await fetch('/api/app-icon?v=' + encodeURIComponent(v), { cache: 'no-store', credentials: 'same-origin' });
        if (!r.ok) return;
        await NativeMac.call('setIcon', { b64: await toB64(await r.blob()) });
        lsSet(v);
      } else if (info.def) {
        // the default icon (it can change with an update): apply it unless this Mac already has it
        if (lsGet() !== 'def-' + info.def) {
          const r = await fetch('/api/app-icon?v=' + encodeURIComponent(v), { cache: 'no-store', credentials: 'same-origin' });
          if (!r.ok) return;
          await NativeMac.call('setIcon', { b64: await toB64(await r.blob()) });
          lsSet('def-' + info.def);
        }
      } else if (lsGet()) {
        await NativeMac.call('setIcon', { reset: true });
        lsSet(null);
      }
      applied = v;
    } catch (e) { /* older Mac app or offline: try again next time */ }
    if (busy === v) busy = null;
    if (info && info.v !== v) sync(); // a newer icon arrived while this one was being applied
  }
  return {
    sync, toB64,
    setOwner: (v) => { owner = !!v; },
    isOwner: () => owner,
    info: () => info || { v: 'default', custom: false },
    url: () => '/api/app-icon?v=' + encodeURIComponent((info && info.v) || 'default'),
  };
})();


/* ================= Mac app title bar (Mac app 4 and newer) ================= */
// The window's page runs to the very top: the close / minimise / full-screen buttons sit in our own
// 48px top row, next to the sidebar, theme and back / forward buttons. Empty parts of that row drag the
// window (double-click zooms, like any Mac title bar). Older Mac apps keep the normal title bar.
const MacChrome = (() => {
  let on = false;
  async function init() {
    if (!Host.isMacApp || on) return;
    let shell = 1;
    try { shell = Number((await NativeMac.call('appInfo')).shell) || 1; } catch (e) { return; }
    if (shell >= 6) {
      const mark = (n) => { const u = typeof me === 'function' && typeof db !== 'undefined' && db && currentUserId ? me() : null; if (!u) { if (n < 60) setTimeout(() => mark(n + 1), 1000); return; } if (!u.macApp) { u.macApp = true; persist(0); } };
      mark(0);
    }
    if (shell < 4) return;
    on = true;
    document.documentElement.classList.add('mac-chrome');
    const bar = document.createElement('div');
    bar.id = 'mac-bar';
    bar.innerHTML = `<button class="icon-btn sb-toggle" data-action="toggle-sidebar" title="Collapse sidebar">${icon('sidebar')}</button>`
      + `<button class="icon-btn theme-toggle" data-action="toggle-theme" title="Switch to light mode">${icon('sun')}</button>`
      + `<button class="icon-btn" id="nav-back" data-action="nav-back" title="Back (⌘[)" disabled>${icon('chev-left')}</button>`
      + `<button class="icon-btn" id="nav-fwd" data-action="nav-forward" title="Forward (⌘])" disabled>${icon('chev-right')}</button>`;
    document.body.appendChild(bar);
    paintThemeButtons();
    if ($('#app') && $('#app').classList.contains('sb-collapsed')) bar.querySelector('.sb-toggle').title = 'Expand sidebar';
    PageHistory.paint();
    const ACTIVE = 'button, a, input, textarea, select, label, [contenteditable="true"], [data-action], [data-nav], [data-id], .tabs, .search, .tm-crumbs > *, #overlay-root *, .tm-backdrop';
    const inBar = (e) => e.clientY <= 48 && !(e.target.closest && e.target.closest(ACTIVE));
    document.addEventListener('mousedown', (e) => {
      if (e.button !== 0 || e.detail > 1 || !inBar(e)) return;
      e.preventDefault();
      NativeMac.call('dragWindow').catch(() => {});
    }, true);
    document.addEventListener('dblclick', (e) => { if (inBar(e)) NativeMac.call('zoomWindow').catch(() => {}); }, true);
  }
  return { init, on: () => on };
})();

/* ================= Date picker (computers) ================= */
// The task's Start / Due chips keep a hidden <input type="date"> (the phone uses the iPhone's own wheel);
// on a computer, clicking one opens this calendar instead, and picking a day sets the input and fires
// its usual "change", so everything else stays the same.
const DatePicker = (() => {
  let pop = null, input = null, view = null, onDoc = null, onKey = null;
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  function close() {
    if (!pop) return;
    pop.remove(); pop = null; input = null;
    document.removeEventListener('mousedown', onDoc, true); document.removeEventListener('keydown', onKey, true);
  }
  function days() {
    // six rows, ending with the week that holds the month's last day
    const last = new Date(view.y, view.m + 1, 0);
    const end = new Date(last); end.setDate(last.getDate() + (6 - last.getDay()));
    const start = new Date(end); start.setDate(end.getDate() - 41);
    const out = [];
    for (let i = 0; i < 42; i++) { const d = new Date(start); d.setDate(start.getDate() + i); out.push(d); }
    return out;
  }
  function draw() {
    const today = todayStr(), sel = input.value || '';
    pop.innerHTML = `<div class="dp-head"><b>${MONTHS[view.m]} ${view.y}</b><span class="spacer"></span>
        <button class="dp-today" data-dp="today">Today</button>
        <button class="dp-nav" data-dp="prev" title="Previous month">${icon('chev-up')}</button>
        <button class="dp-nav" data-dp="next" title="Next month">${icon('chev')}</button></div>
      <div class="dp-grid">${['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'].map((d) => `<span class="dp-wd">${d}</span>`).join('')}
      ${days().map((d) => { const k = ymd(d); const cls = [k < today ? 'past' : '', d.getMonth() !== view.m ? 'out' : '', k === today ? 'today' : '', k === sel ? 'sel' : ''].join(' '); return `<button class="dp-day ${cls}" data-day="${k}">${d.getDate()}</button>`; }).join('')}</div>`;
  }
  function pick(v) {
    const el = input; close();
    if (!el) return;
    el.value = v;
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function open(el) {
    close();
    input = el;
    const base = el.value ? parseYmd(el.value) : new Date();
    view = { y: base.getFullYear(), m: base.getMonth() };
    pop = document.createElement('div');
    pop.className = 'dp-pop';
    draw();
    document.body.appendChild(pop);
    const r = (el.closest('.date-chip') || el).getBoundingClientRect();
    const w = pop.offsetWidth, h = pop.offsetHeight;
    let x = r.left, y = r.bottom + 6;
    if (x + w > innerWidth - 10) x = innerWidth - w - 10;
    if (y + h > innerHeight - 10) y = Math.max(10, r.top - h - 6);
    pop.style.left = Math.max(10, x) + 'px'; pop.style.top = y + 'px';
    pop.addEventListener('mousedown', (e) => e.preventDefault());
    pop.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      e.stopPropagation();
      if (b.dataset.day) return pick(b.dataset.day);
      if (b.dataset.dp === 'today') return pick(todayStr());
      view.m += b.dataset.dp === 'next' ? 1 : -1;
      if (view.m < 0) { view.m = 11; view.y--; } if (view.m > 11) { view.m = 0; view.y++; }
      draw();
    });
    pop.addEventListener('wheel', (e) => { e.preventDefault(); if (Math.abs(e.deltaY) < 4) return; view.m += e.deltaY > 0 ? 1 : -1; if (view.m < 0) { view.m = 11; view.y--; } if (view.m > 11) { view.m = 0; view.y++; } draw(); }, { passive: false });
    onDoc = (e) => { if (pop && !pop.contains(e.target)) close(); };
    onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); close(); } };
    setTimeout(() => { document.addEventListener('mousedown', onDoc, true); document.addEventListener('keydown', onKey, true); }, 0);
  }
  const desktop = () => !(typeof Phone !== 'undefined' && Phone.on);
  const grab = (e) => {
    // every date field on a computer, including plain ones, so the Mac's own date box never shows
    const el = e.target.closest && e.target.closest('input.date-in, input[type="date"]');
    if (!el || !desktop()) return;
    e.preventDefault(); e.stopPropagation();
    if (e.type === 'click') { if (pop && input === el) close(); else open(el); }
  };
  document.addEventListener('mousedown', grab, true);
  document.addEventListener('click', grab, true);
  document.addEventListener('keydown', (e) => { const el = e.target.closest && e.target.closest('input.date-in, input[type="date"]'); if (el && desktop() && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); open(el); } }, true);
  return { open, close };
})();

/* ================= Task links (Share button) ================= */
// The link is <server>/?task=<id>. Opened in a browser by someone who uses the Mac app, it is handed
// to the app (e11console://task/<id>); if the app doesn't answer, the task simply opens in the browser.
const TaskLink = (() => {
  const url = (id) => location.origin + '/?task=' + encodeURIComponent(id);
  const scheme = () => window.__forceScheme || (/^test\./.test(location.hostname) ? 'e11console-test' : /(^|\.)e11hq\.com$/.test(location.hostname) ? 'e11console' : null);
  async function copy(id) {
    const link = url(id);
    let ok = false;
    try { await navigator.clipboard.writeText(link); ok = true; } catch (e) {
      const ta = document.createElement('textarea'); ta.value = link; ta.style.cssText = 'position:fixed;opacity:0'; document.body.appendChild(ta); ta.select();
      try { ok = document.execCommand('copy'); } catch (e2) { ok = false; }
      ta.remove();
    }
    toast(ok ? 'Link copied — it opens in the E11 Console app, or the browser' : 'Could not copy the link');
  }
  function show(id) {
    ui.sideTab = 'details';
    if (task(id)) openTask(id); else toast('That task is not available');
  }
  // Called once data has loaded, for a link opened in this page
  function open(id) {
    const sch = scheme(), u = me && me();
    const tryApp = sch && !Host.isMacApp && !(typeof Phone !== 'undefined' && Phone.on) && u && u.macApp && /Macintosh/.test(navigator.userAgent);
    if (!tryApp) return show(id);
    let left = false;
    const away = () => { left = true; };
    window.addEventListener('blur', away);
    document.addEventListener('visibilitychange', away);
    const card = document.createElement('div');
    card.id = 'open-app';
    card.innerHTML = `<div class="oa-card"><div class="oa-t">Opening in the E11 Console app…<small>If your browser asks, choose Open or Allow.</small></div><button class="btn" data-oa="here">Show it here instead</button></div>`;
    document.body.appendChild(card);
    const done = (here) => {
      window.removeEventListener('blur', away); document.removeEventListener('visibilitychange', away);
      if (here) { card.remove(); show(id); }
    };
    card.addEventListener('click', (e) => { if (e.target.closest('[data-oa="here"]')) done(true); });
    window.__triedScheme = sch + '://task/' + encodeURIComponent(id);
    if (window.__fakeLeave) away(); else location.href = window.__triedScheme;
    // Safari asks before handing a link to an app, so give people time to answer; leaving the page
    // (the app came forward) means it worked. No answer after 8 s: show the task here.
    const t0 = Date.now();
    const tick = setInterval(() => {
      if (!document.body.contains(card)) return clearInterval(tick);
      if (left && Date.now() - t0 > 600) {
        clearInterval(tick); done(false);
        card.querySelector('.oa-t').innerHTML = 'Opened in the E11 Console app.<small>You can close this tab.</small>';
      } else if (Date.now() - t0 > 8000) { clearInterval(tick); done(true); }
    }, 300);
  }
  // Same-server task links inside the app open the task directly
  document.addEventListener('click', (e) => {
    const a = e.target.closest && e.target.closest('a[href]');
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey) return;
    let u; try { u = new URL(a.getAttribute('href'), location.href); } catch (err) { return; }
    if (u.origin !== location.origin || !u.searchParams.get('task')) return;
    e.preventDefault(); e.stopPropagation();
    show(u.searchParams.get('task'));
  }, true);
  return { copy, open, show };
})();
// The Mac app hands shared links to the page
window.__e11OpenTask = (id) => { if (typeof db !== 'undefined' && db && currentUserId) TaskLink.show(id); else location.href = '/?task=' + encodeURIComponent(id); };

/* ================= Page history (back / forward) ================= */
const PageHistory = (() => {
  const stack = []; let idx = -1, moving = false;
  const snap = () => ({ view: ui.view, projectId: ui.projectId || null, clientId: ui.view === 'client' ? ui.clientId : null, folderId: ui.view === 'client' ? (ui.folderId || null) : null });
  const same = (a, b) => a && b && a.view === b.view && a.projectId === b.projectId && a.clientId === b.clientId && a.folderId === b.folderId;
  function mark() {
    if (moving || !ui.view) return;
    const s = snap();
    if (same(stack[idx], s)) return;
    stack.splice(idx + 1);
    stack.push(s);
    if (stack.length > 100) stack.shift();
    idx = stack.length - 1;
    paint();
  }
  function move(d) {
    mark();
    const j = idx + d;
    if (j < 0 || j >= stack.length) return;
    idx = j;
    const s = stack[idx];
    moving = true;
    if (ui.taskId && typeof closeDetail === 'function') closeDetail();
    if (s.view === 'client') { ui.clientId = s.clientId; ui.folderId = s.folderId; }
    go(s.view, s.projectId);
    moving = false;
    paint();
  }
  function paint() {
    const b = document.getElementById('nav-back'), f = document.getElementById('nav-fwd');
    if (b) b.disabled = idx <= 0;
    if (f) f.disabled = idx >= stack.length - 1;
  }
  return { mark, back: () => move(-1), forward: () => move(1), paint };
})();


/* ================= Required Mac app update ================= */
// When the installer has a newer Mac app (its native part), older Mac apps show a banner that can't be
// dismissed. "Update now" opens Terminal with the usual install line; the app closes, is replaced and
// reopens, and Terminal's window closes when it finished cleanly. Works in every installed Mac app:
// it only uses "save a file and open it" (a .terminal file holding the command), which they all have.
const MacUpdate = (() => {
  let need = false;
  async function check(required) {
    if (!Host.isMacApp || !required) return;
    let shell = 1;
    try { const r = await NativeMac.call('appInfo'); shell = Number(r.shell) || 1; } catch (e) { return; }
    need = shell < required;
    paint();
  }
  const xml = (t) => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  function terminalFile() {
    // After a clean install the shell exits and Terminal closes this window by itself (shellExitAction 1).
    // A helper started completely apart from the window (its own session, via perl's setsid, so the shell
    // has no job to wait for and Terminal sees nothing running in the window) closes the window by its
    // title if it's still there, then quits Terminal when no windows are left. A failed install keeps
    // the window open with the error.
    const TITLE = 'E11 Console update';
    const closer = `sleep 2; osascript -e 'tell application "Terminal"' -e 'close (every window whose name contains "${TITLE}")' -e 'if (count of windows) is 0 then quit' -e 'end tell'`;
    const detached = `(perl -MPOSIX -e 'setsid(); exec @ARGV' /bin/sh -c ${JSON.stringify(closer)} </dev/null >/dev/null 2>&1 &)`;
    const cmd = `printf '\\033]0;${TITLE}\\007'; clear; echo "Updating E11 Console… this takes about 10 seconds."; curl -fsSL ${location.origin}/install | bash && { ${detached}; exit 0; }`;
    return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CommandString</key><string>${xml(cmd)}</string>
  <key>RunCommandAsShell</key><false/>
  <key>shellExitAction</key><integer>1</integer>
  <key>name</key><string>E11 Console update</string>
  <key>type</key><string>Window Settings</string>
  <key>ProfileCurrentVersion</key><real>2.07</real>
</dict>
</plist>`;
  }
  async function run() {
    const el = document.getElementById('mac-update');
    if (el) el.classList.add('busy');
    const btn = el && el.querySelector('button');
    if (btn) { btn.disabled = true; btn.textContent = 'Updating…'; }
    try {
      const b64 = btoa(unescape(encodeURIComponent(terminalFile())));
      await NativeMac.call('saveFile', { token: 'upd-' + Date.now(), name: 'Update E11 Console.terminal', b64, open: true, done: true });
      if (el) el.querySelector('.mu-txt span').textContent = 'Terminal is updating the app — it will close and reopen by itself in a few seconds.';
      else toast('Terminal is updating the app — it will close and reopen by itself in a few seconds', null, 8000);
      setTimeout(() => { if (btn) { btn.disabled = false; btn.textContent = 'Try again'; } }, 30000);
    } catch (e) {
      if (btn) { btn.disabled = false; btn.textContent = 'Try again'; }
      toast('Couldn’t start the update: ' + e.message);
    }
  }
  function paint() {
    let el = document.getElementById('mac-update');
    if (!need) { if (el) el.remove(); document.body.classList.remove('mac-upd'); return; }
    if (el) return;
    el = document.createElement('div');
    el.id = 'mac-update';
    el.setAttribute('role', 'alert');
    el.innerHTML = `<span class="mu-ic">${icon('shield')}</span>
      <div class="mu-txt"><b>Important update for the Mac app</b><span>A required update keeps E11 Console secure and working properly. It takes about 10 seconds — the app closes and reopens by itself.</span></div>
      <button class="btn primary" data-action="mac-update">${icon('download')}Update now</button>`;
    document.body.appendChild(el);
    document.body.classList.add('mac-upd');
  }
  return { check, run };
})();

const FINDER_LABEL = Host.isServer ? 'Download' : 'Show in Finder';


/* ================= Mac app installer ================= */
function macAppDialog() {
  const cmd = `curl -fsSL ${location.origin}/install | bash`;
  const root = $('#overlay-root');
  root.innerHTML = `<div class="scrim"><div class="dialog mac-dlg">
    <div class="wn-kick">${icon('download')}E11 Console for Mac</div>
    <h2>Install the Mac app</h2>
    <p>Your own E11 Console app with a Dock icon, notifications and the Mac file picker. It always shows the latest version, so you only install it once.</p>
    <ol class="mac-steps">
      <li>Open <b>Terminal</b> (press <kbd>⌘</kbd> <kbd>Space</kbd>, type <b>Terminal</b>, press <kbd>Return</kbd>).</li>
      <li>Copy this line, paste it into Terminal and press <kbd>Return</kbd>:
        <div class="mac-cmd"><code>${esc(cmd)}</code><button class="btn sm" data-copy-cmd>${icon('copy')}Copy</button></div></li>
      <li>After about 20 seconds E11 Console opens — sign in with your work email. It’s now in your Applications folder; drag it to the Dock to keep it there.</li>
    </ol>
    <div class="actions"><button class="btn primary" data-r="1">Done</button></div>
  </div></div>`;
  const close = () => { root.innerHTML = ''; };
  $('[data-r="1"]', root).addEventListener('click', close);
  $('[data-copy-cmd]', root).addEventListener('click', (e) => {
    try { navigator.clipboard.writeText(cmd).then(() => toast('Copied — paste it into Terminal')); }
    catch (err) { const ta = document.createElement('textarea'); ta.value = cmd; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove(); toast('Copied — paste it into Terminal'); }
    e.currentTarget.innerHTML = `${icon('check')}Copied`;
  });
  $('.scrim', root).addEventListener('click', (e) => { if (e.target.classList.contains('scrim')) close(); });
}

/* ================= Updates (server) ================= */
// Simple formatting for release notes: "## Heading", "- bullet", **bold**
function notesHTML(md) {
  const lines = String(md || '').split(/\r?\n/);
  let out = '', inList = false;
  const inline = (t) => esc(t).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`(.+?)`/g, '<code>$1</code>');
  lines.forEach((l) => {
    const li = /^\s*[-*]\s+(.*)/.exec(l), h = /^#{1,3}\s+(.*)/.exec(l);
    if (li) { if (!inList) { out += '<ul>'; inList = true; } out += `<li>${inline(li[1])}</li>`; return; }
    if (inList) { out += '</ul>'; inList = false; }
    if (h) out += `<h4>${inline(h[1])}</h4>`;
    else if (l.trim()) out += `<p>${inline(l)}</p>`;
  });
  if (inList) out += '</ul>';
  return out || '<p>Improvements and fixes.</p>';
}
// A newer version is running on the server: offer a reload (nothing is lost, changes are saved first)
function showUpdateBanner(v) {
  let el = document.getElementById('update-banner');
  if (!el) { el = document.createElement('div'); el.id = 'update-banner'; document.body.appendChild(el); }
  el.innerHTML = `<div class="ub-text">${icon('download')}<div><b>Update ready</b><span>Reload to get the latest version</span></div></div>
    <div class="ub-acts"><button class="btn" data-action="whats-new">What’s new</button><button class="btn primary" data-action="reload-app">Reload</button></div>`;
  el.title = `Version ${v}`;
  el.classList.add('on');
}
async function reloadApp(btn) {
  // "Reloading" with three bouncing dots, shown for a moment so it's seen, then the normal reload
  const banner = document.getElementById('update-banner');
  if (btn) { btn.innerHTML = 'Reloading<span class="ub-dots"><i></i><i></i><i></i></span>'; btn.classList.add('ub-busy'); }
  if (banner) banner.querySelectorAll('button').forEach((b) => { b.disabled = true; });
  const shown = new Promise((r) => setTimeout(r, 900));
  try { await Sync.push(); } catch (e) { /* offline: changes stay in this window until reload */ }
  await shown;
  location.reload();
}
async function whatsNewDialog(auto) {
  let r;
  try { r = await api('GET', '/api/whatsnew'); } catch (e) { if (!auto) toast(e.message); return; }
  if (auto && !r.notes) return;
  const root = $('#overlay-root');
  root.innerHTML = `<div class="scrim"><div class="dialog wn-dlg"><div class="wn-kick">${icon('download')}What’s new</div><h2>${esc(r.name || r.version)}</h2>${r.publishedAt ? `<div class="wn-date">${esc(fmtDateTime(r.publishedAt))}</div>` : ''}<div class="wn-notes">${notesHTML(r.notes)}</div><div class="actions"><button class="btn primary" data-r="1">Got it</button></div></div></div>`;
  const close = () => { root.innerHTML = ''; };
  $('[data-r="1"]', root).addEventListener('click', close);
  $('.scrim', root).addEventListener('click', (e) => { if (e.target.classList.contains('scrim')) close(); });
}
// After a reload into a new version, show its notes once
function maybeShowWhatsNew() {
  if (!Host.isServer || !Sync.version) return;
  let seen = null;
  try { seen = localStorage.getItem('e11-seen-version'); localStorage.setItem('e11-seen-version', Sync.version); } catch (e) { return; }
  if (seen && seen !== Sync.version) setTimeout(() => whatsNewDialog(true), 1200);
}
// Admin page: version, available update, update now, roll back
function viewUpdates() {
  // Ask for a fresh check every time the page opens (the server itself only checks once an hour)
  setTimeout(() => loadUpdates('check'), 0);
  return `<div class="upd"><div class="upd-card" id="upd-body"><div class="ph">Checking for updates…</div></div>
    <div class="upd-card imp-card">
      <h3>${icon('upload')}Move data from the Mac app</h3>
      <p class="upd-note">Choose <b>e11-data.json</b> from the “E11 Console Data” folder on the Mac. Tasks, clients, comments, people, notifications and client assets are added to the server. Copy the folders <b>attachments</b>, <b>Clients</b> and <b>.thumbs</b> into the NAS folder <b>E11Console/live/files</b> as well, so the files open. A copy of the database is made first.</p>
      <button class="btn" data-action="import-mac">${icon('upload')}Choose e11-data.json…</button>
    </div></div>`;
}
async function importFromMac() {
  const files = await ServerHost.pickFiles({ multiple: false, accept: '.json,application/json' });
  if (!files.length) return;
  let data;
  try { data = JSON.parse(await files[0].text()); } catch (e) { toast('That file isn’t an E11 Console data file'); return; }
  if (!data || !Array.isArray(data.tasks) || !Array.isArray(data.users)) { toast('That file isn’t an E11 Console data file'); return; }
  const ok = await dialog({ title: 'Import from the Mac app?', body: `${data.tasks.length} tasks, ${(data.projects || []).length} clients, ${data.users.length} people and ${(data.clients || []).length} Client Assets folders will be added to the server. Items that already exist are replaced by the Mac’s version.`, okText: 'Import' });
  if (!ok) return;
  if (data.meta) { delete data.meta.prefs; }
  try {
    const r = await api('POST', '/api/import', { data });
    toast(`Imported ${r.count} items`);
    setTimeout(() => location.reload(), 1200);
  } catch (e) { toast('Import failed: ' + e.message); }
}
async function loadUpdates(action) {
  const el = document.getElementById('upd-body');
  if (!el) return;
  if (action) el.classList.add('busy');
  let s;
  try { s = await api(action ? 'POST' : 'GET', '/api/updates', action ? { action } : undefined); }
  catch (e) { el.innerHTML = `<div class="ph">${esc(e.message)}</div>`; return; }
  const st = s.status || s;
  el.classList.remove('busy');
  if (action === 'update' || action === 'rollback') {
    if (!s.ok) toast(s.error || 'Something went wrong');
    else if (s.started) {
      // The server restarts on the new version; keep asking until it's back, then show the result
      el.classList.add('busy');
      el.innerHTML = `<h3>${icon('download')}${action === 'rollback' ? 'Going back to the previous version…' : 'Updating E11 Console…'}</h3><p class="upd-note">This takes about 10 seconds. The app reconnects by itself.</p>`;
      const t0 = Date.now();
      const poll = async () => {
        if (!document.getElementById('upd-body')) return;
        let st2 = null;
        try { st2 = await api('GET', '/api/updates'); } catch (e) { /* restarting */ }
        if (st2 && !st2.busy && st2.lastResult && st2.lastResult.action === action && Date.parse(st2.lastResult.at) >= t0 - 1000) {
          toast(st2.lastResult.ok ? (action === 'rollback' ? `Went back to ${st2.lastResult.version}` : st2.lastResult.upToDate ? 'Already up to date' : `Updated to ${st2.lastResult.version}`) : st2.lastResult.error || 'Something went wrong');
          return loadUpdates();
        }
        if (Date.now() - t0 < 120000) setTimeout(poll, 2000); else loadUpdates();
      };
      setTimeout(poll, 2500);
      return;
    }
  }
  if (!st.managed && s.managed === false) { el.innerHTML = `<h3>${icon('download')}App updates</h3><p class="upd-note">This copy (${esc(s.running)}) isn’t managed by the updater.</p>`; return; }
  const hour = st.updateHour == null ? null : `${String(st.updateHour).padStart(2, '0')}:00`;
  el.innerHTML = `
    <h3>${icon('download')}App updates</h3>
    <div class="upd-row"><span>Running</span><b>${esc(st.running || st.current || '—')}</b>${st.channel === 'staging' ? '<span class="upd-chip">Test copy</span>' : ''}</div>
    <div class="upd-row"><span>Last checked</span><b>${st.lastCheck ? esc(timeAgo(st.lastCheck)) : 'Never'}</b><button class="btn ghost xs" data-action="upd" data-a="check">Check now</button></div>
    ${st.lastError ? `<div class="upd-err">${icon('info')}${esc(st.lastError)}</div>` : ''}
    ${st.available ? `<div class="upd-new">
        <div class="upd-new-head"><div><div class="upd-kick">Update available</div><b>${esc(st.available.name || st.available.version)}</b></div>
        <button class="btn primary" data-action="upd" data-a="update" ${st.busy ? 'disabled' : ''}>${icon('download')}Update now</button></div>
        <div class="wn-notes">${notesHTML(st.available.notes)}</div>
        <div class="upd-note">${hour ? `Installs automatically tonight at ${hour} if you don’t update now. ` : ''}A copy of the database is made first, and it takes about 10 seconds. Open apps show a “Reload” button.</div>
      </div>` : `<div class="upd-ok">${icon('check')}You’re up to date</div>`}
    ${st.previous ? `<div class="upd-row"><span>Previous version</span><b>${esc(st.previous)}</b><button class="btn ghost xs danger" data-action="upd" data-a="rollback" ${st.busy ? 'disabled' : ''}>Roll back</button></div>` : ''}
    ${(st.history || []).length ? `<h4 class="pf-sub">History</h4>${st.history.map((h) => `<div class="upd-hist"><b>${esc(h.version)}</b><span>${esc(h.reason)}</span><small>${esc(fmtDateTime(h.at))}</small></div>`).join('')}` : ''}`;
}

/* ================= Server connection (console.e11hq.com) ================= */
// Team page: is Cloudflare letting the freelancers on the Team page in?
function paintCfStatus(s) {
  const el = document.getElementById('cf-status');
  if (!el || !s) return;
  if (!s.configured) { el.innerHTML = `${icon('info')}<span>Freelancers with personal emails must be added in Cloudflare by hand (automatic access isn’t switched on yet).</span>`; return; }
  el.className = 'cf-status ' + (s.ok === false ? 'bad' : 'good');
  el.innerHTML = s.ok === false
    ? `${icon('info')}<span>Couldn’t update Cloudflare access: ${esc(s.error || 'unknown error')}</span><button class="btn ghost xs" data-action="cf-sync-now">Try again</button>`
    : `${icon('shield')}<span>Freelancer sign-in access is kept up to date automatically${s.at ? ` · last updated ${esc(timeAgo(s.at))}` : ''} (${(s.emails || []).length} personal email${(s.emails || []).length === 1 ? '' : 's'})</span>`;
}
// Requests to the server. Cloudflare signs people in before the page even loads.
async function api(method, url, body) {
  const res = await fetch(url, { method, headers: body ? { 'Content-Type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined, credentials: 'same-origin', cache: 'no-store', redirect: 'manual' });
  if (res.type === 'opaqueredirect' || (res.status >= 300 && res.status < 400)) {
    const err = new Error('Your sign-in has expired — sign in again to continue'); err.auth = true; err.expired = true; throw err;
  }
  let data = null;
  try { data = await res.json(); } catch (e) { /* not JSON */ }
  if (res.status === 401 || res.status === 403) {
    const err = new Error((data && data.error) || 'Please sign in again'); err.auth = true; err.status = res.status; throw err;
  }
  if (!res.ok || (data && data.ok === false)) throw new Error((data && data.error) || `Server error (${res.status})`);
  return data || {};
}
const ServerHost = (() => {
  const CHUNK_SIZE = 2 * 1024 * 1024;
  const b64 = (blob) => new Promise((resolve, reject) => {
    const fr = new FileReader();
    fr.onload = () => resolve(String(fr.result).split(',')[1] || '');
    fr.onerror = () => reject(fr.error || new Error('Could not read the file'));
    fr.readAsDataURL(blob);
  });
  // Ask the browser for files (resolves with [] when the picker is cancelled)
  function pickFiles({ multiple = true, accept = '' } = {}) {
    return new Promise((resolve) => {
      const inp = document.createElement('input');
      inp.type = 'file'; inp.multiple = multiple; if (accept) inp.accept = accept;
      inp.style.cssText = 'position:fixed;left:-9999px;top:0';
      let done = false;
      const finish = (list) => { if (done) return; done = true; inp.remove(); resolve(list); };
      inp.addEventListener('change', () => finish([...(inp.files || [])]));
      inp.addEventListener('cancel', () => finish([]));
      window.addEventListener('focus', () => setTimeout(() => finish([...(inp.files || [])]), 800), { once: true });
      document.body.appendChild(inp);
      inp.click();
    });
  }
  // A file to upload: a browser File, or a file picked in the Mac app (read through the app)
  const readPiece = (file, off, len) => (file.macToken
    ? NativeMac.call('readLocalChunk', { token: file.macToken, offset: off, length: len, last: off + len >= file.size }).then((r) => r.b64)
    : b64(file.slice(off, off + len)));
  // A picked logo (browser File, or a file picked in the Mac app) → its square version; the original if that fails
  async function logoFile(f) {
    try {
      let blob = f;
      if (f.macToken) {
        const b64 = await readPiece(f, 0, f.size);
        const bin = atob(b64); const arr = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
        const ext = String(f.name).split('.').pop().toLowerCase();
        blob = new Blob([arr], { type: ext === 'svg' ? 'image/svg+xml' : 'image/' + (ext === 'jpg' ? 'jpeg' : ext) });
      }
      return await squareLogo(blob);
    } catch (e) { return f; }
  }
  async function pickMacFiles(opts) {
    const r = await NativeMac.call('pickLocalFiles', opts);
    return (r.files || []).map((f) => ({ name: f.name, size: f.size, macToken: f.token }));
  }
  // Save something from the server on this Mac: into Downloads (shown in Finder) or opened directly
  async function saveOnMac(url, name, open) {
    const res = await fetch(url, { credentials: 'same-origin' });
    if (!res.ok) throw new Error(`Download failed (${res.status})`);
    const blob = await res.blob();
    const tok = uid();
    for (let off = 0; off < Math.max(blob.size, 1); off += CHUNK_SIZE) {
      const piece = await b64(blob.slice(off, off + CHUNK_SIZE));
      await NativeMac.call('saveFile', { token: tok, name, b64: piece, open, done: off + CHUNK_SIZE >= blob.size });
    }
  }
  // Upload one file in 2 MB pieces; onProgress(0..1)
  // Width and height of a picture or video before it uploads, so previews can hold their exact space while loading
  async function mediaDims(file) {
    if (!(file instanceof Blob)) return null;
    const type = file.type || '', name = (file.name || '').toLowerCase();
    const isImg = /^image\//.test(type) || /\.(png|jpe?g|gif|webp|heic|bmp|avif)$/.test(name);
    const isVid = /^video\//.test(type) || /\.(mp4|mov|m4v|webm)$/.test(name);
    if (!isImg && !isVid) return null;
    const url = URL.createObjectURL(file);
    try {
      return await new Promise((resolve) => {
        const done = (w, h) => resolve(w > 0 && h > 0 ? { w: Math.round(w), h: Math.round(h) } : null);
        setTimeout(() => resolve(null), 4000);
        if (isImg) { const im = new Image(); im.onload = () => done(im.naturalWidth, im.naturalHeight); im.onerror = () => resolve(null); im.src = url; }
        else { const v = document.createElement('video'); v.preload = 'metadata'; v.muted = true; v.onloadedmetadata = () => done(v.videoWidth, v.videoHeight); v.onerror = () => resolve(null); v.src = url; }
      });
    } finally { setTimeout(() => URL.revokeObjectURL(url), 5000); }
  }
  // One upload piece as raw bytes (a third smaller than base64, nothing to encode)
  async function sendRaw(blob, params) {
    const q = new URLSearchParams(Object.entries(params).filter(([, v]) => v != null && v !== '').map(([k, v]) => [k, String(v)]));
    const res = await fetch('/api/host/writeChunkBin?' + q, { method: 'POST', body: blob, headers: { 'Content-Type': 'application/octet-stream' }, credentials: 'same-origin', cache: 'no-store', redirect: 'manual' });
    if (res.type === 'opaqueredirect' || (res.status >= 300 && res.status < 400)) { const err = new Error('Your sign-in has expired — sign in again to continue'); err.auth = true; throw err; }
    let data = null;
    try { data = await res.json(); } catch (e) { /* not JSON */ }
    if (!res.ok || (data && data.ok === false)) { const err = new Error((data && data.error) || `Server error (${res.status})`); err.status = res.status; err.auth = res.status === 401 || res.status === 403; throw err; }
    return data || {};
  }
  // Keep trying a piece through dropped connections — including the phone pausing the app while you're in
  // another one: it waits until you're back, then carries on. Refusals (no access, too large) stop at once.
  const whenVisible = () => (document.hidden ? new Promise((r) => { const on = () => { if (!document.hidden) { document.removeEventListener('visibilitychange', on); r(); } }; document.addEventListener('visibilitychange', on); }) : Promise.resolve());
  async function persistently(run) {
    for (let n = 0; ; n++) {
      try { return await run(); } catch (e) {
        if (e.auth || (e.status >= 400 && e.status < 500) || n >= 12) throw e;
        if (document.hidden) await whenVisible();
        else await new Promise((r) => setTimeout(r, Math.min(8000, 700 * 2 ** n)));
      }
    }
  }
  const PIECE = 4 * 1024 * 1024;
  async function uploadFile(file, target, onProgress) {
    const dims = await mediaDims(file).catch(() => null);
    const raw = file instanceof Blob;
    const size = Math.max(file.size, 0);
    const piece = raw ? PIECE : CHUNK_SIZE;
    const put = (off, len, path) => persistently(async () => (raw
      ? sendRaw(file.slice(off, off + len), { ...target, name: file.name, path, offset: path ? off : null })
      : api('POST', '/api/host/writeChunk', { ...target, name: file.name, path, offset: path ? off : null, b64: await readPiece(file, off, len) })));
    let sent = 0;
    const tick = (n) => { sent += n; if (onProgress) onProgress(Math.min(1, sent / Math.max(size, 1))); };
    // the first piece creates the file; the rest go up a few at a time, each to its own place in the file
    const first = await put(0, Math.min(piece, size), null);
    const path = first.path;
    tick(Math.min(piece, size));
    const offs = [];
    for (let off = piece; off < size; off += piece) offs.push(off);
    let biggest = first.size || 0;
    const lanes = raw ? 3 : 1;
    await Promise.all(Array.from({ length: Math.min(lanes, offs.length) }, async () => {
      while (offs.length) {
        const off = offs.shift();
        const len = Math.min(piece, size - off);
        const r = await put(off, len, path);
        biggest = Math.max(biggest, r.size || 0);
        tick(len);
      }
    }));
    if (biggest < size) throw new Error('The upload didn’t finish — please try again');
    return { id: uid(), name: first.name || file.name, path, size: size || biggest, addedAt: nowISO(), ...(dims || {}) };
  }
  // Small progress card while files upload
  function uploadToast(files) {
    let root = document.getElementById('upload-root');
    if (!root) { root = document.createElement('div'); root.id = 'upload-root'; document.body.appendChild(root); }
    const el = document.createElement('div');
    el.className = 'up-card';
    el.innerHTML = files.map((f, i) => `<div class="up-row" data-i="${i}"><span class="up-name">${esc(f.name)}</span><span class="up-bar"><i></i></span><small>0%</small></div>`).join('');
    root.appendChild(el);
    return {
      set(i, p, msg) { const r = el.querySelector(`[data-i="${i}"]`); if (!r) return; r.querySelector('i').style.width = Math.round(p * 100) + '%'; r.querySelector('small').textContent = msg || Math.round(p * 100) + '%'; },
      done() { setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 300); }, 700); },
    };
  }
  async function uploadMany(files, target) {
    if (!files.length) return [];
    const ui1 = uploadToast(files);
    // two files at a time (each sends a few pieces at once)
    const out = new Array(files.length).fill(null);
    let next = 0;
    await Promise.all(Array.from({ length: Math.min(2, files.length) }, async () => {
      while (next < files.length) {
        const i = next++;
        try { out[i] = await uploadFile(files[i], target, (p) => ui1.set(i, p)); ui1.set(i, 1, 'Done'); }
        catch (e) { ui1.set(i, 0, 'Failed'); toast(`Could not upload ${files[i].name}: ${e.message}`); }
      }
    }));
    ui1.done();
    return out.filter(Boolean);
  }
  const fileHref = (p) => '/__file/' + String(p).split('/').map(encodeURIComponent).join('/');
  function download(url, name) {
    const a = document.createElement('a');
    a.href = url; if (name) a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
  }
  async function call(cmd, args = {}) {
    if (Host.isMacApp) {
      const mac = await macCall(cmd, args);
      if (mac !== undefined) return mac;
    }
    switch (cmd) {
      case 'load': case 'save': case 'sweepOrphans': case 'setAppearance': case 'revealData': return { ok: true };
      case 'badge': try { if (navigator.setAppBadge) { if (args.n) navigator.setAppBadge(args.n); else navigator.clearAppBadge(); } } catch (e) { /* not installed */ } return { ok: true };
      case 'pickAttachments': {
        const files = await pickFiles({ multiple: !args.single, accept: args.accept || '' });
        return { ok: true, files: await uploadMany(files, args.dest ? { dest: args.dest } : { taskId: args.taskId }) };
      }
      case 'uploadBlob': {
        const f = new File([args.blob], args.name || 'file', { type: args.blob.type || 'application/octet-stream' });
        return { ok: true, file: await uploadFile(f, { dest: args.dest }) };
      }
      case 'pickImage': {
        const files = await pickFiles({ multiple: false, accept: args.kind === 'logo' ? 'image/*,.svg' : 'image/*' });
        if (!files.length) return { ok: true, path: null };
        const up = await uploadFile(args.kind === 'logo' ? await logoFile(files[0]) : files[0], { taskId: '_uploads' });
        return { ...(await api('POST', '/api/host/processImage', { path: up.path, kind: args.kind || 'avatar', userId: args.userId })), original: files[0] };
      }
      case 'openPath': case 'quickLook': window.open(fileHref(args.path), '_blank', 'noopener'); return { ok: true };
      case 'revealPath': download(fileHref(args.path), String(args.path).split('/').pop()); return { ok: true };
      case 'openURL': window.open(args.url, '_blank', 'noopener'); return { ok: true };
      case 'exportFiles': { const r = await api('POST', '/api/host/exportFiles', args); if (r.count) download(r.url); return { ...r, dir: (r.dir || 'E11 files') + '.zip' }; }
      case 'expenseReport': { const r = await api('POST', '/api/host/expenseReport', args); download(r.url || fileHref(r.path), r.name); return r; }
      case 'notify': {
        try {
          if ('Notification' in window && Notification.permission === 'granted' && args.banner !== false) {
            const n = new Notification(args.title || 'E11 Console', { body: args.body || '', icon: '/icon-192.png', tag: 'e11-' + Date.now() });
            n.onclick = () => { window.focus(); n.close(); };
          }
        } catch (e) { /* not available */ }
        if (args.sound) chime();
        return { ok: true };
      }
      default: return api('POST', '/api/host/' + cmd, args);
    }
  }
  // Inside the Mac app: use the Mac's own file picker, Downloads folder, notifications and Dock badge
  async function macCall(cmd, args) {
    const fileHrefName = (p) => String(p).split('/').pop();
    switch (cmd) {
      case 'pickAttachments': {
        const files = await pickMacFiles({ multiple: !args.single, prompt: args.dest ? 'Upload' : 'Attach' });
        return { ok: true, files: await uploadMany(files, args.dest ? { dest: args.dest } : { taskId: args.taskId }) };
      }
      case 'pickImage': {
        const files = await pickMacFiles({ multiple: false, images: true, prompt: args.kind === 'logo' ? 'Use logo' : 'Use photo' });
        if (!files.length) return { ok: true, path: null };
        const up = await uploadFile(args.kind === 'logo' ? await logoFile(files[0]) : files[0], { taskId: '_uploads' });
        return { ...(await api('POST', '/api/host/processImage', { path: up.path, kind: args.kind || 'avatar', userId: args.userId })), original: files[0] };
      }
      case 'openPath': case 'quickLook': await saveOnMac(fileHref(args.path), fileHrefName(args.path), true); return { ok: true };
      case 'revealPath': await saveOnMac(fileHref(args.path), fileHrefName(args.path), false); toast(`Saved to Downloads`); return { ok: true };
      case 'exportFiles': {
        const r = await api('POST', '/api/host/exportFiles', args);
        if (r.count) await saveOnMac(r.url, (r.dir || 'E11 files') + '.zip', false);
        return { ...r, dir: 'Downloads › ' + (r.dir || 'E11 files') + '.zip' };
      }
      case 'expenseReport': { const r = await api('POST', '/api/host/expenseReport', args); await saveOnMac(r.url || fileHref(r.path), r.name, false); return r; }
      case 'openURL': case 'notify': case 'badge': case 'setAppearance': return NativeMac.call(cmd, args);
      default: return undefined;
    }
  }
  return { call, uploadMany, pickFiles, download };
})();

/* ================= Data ================= */
const COLORS = ['#5b8cff', '#3ddc97', '#ffb547', '#ff6b6b', '#c27cff', '#4fd1c5', '#ff8fc7', '#f2f26d', '#9aa0ab'];
const TAG_COLORS = [
  ['rgba(91,140,255,.16)', '#8fb0ff'], ['rgba(61,220,151,.16)', '#6fe6b3'], ['rgba(255,181,71,.16)', '#ffc675'],
  ['rgba(255,107,107,.16)', '#ff9494'], ['rgba(194,124,255,.16)', '#d4a6ff'], ['rgba(79,209,197,.16)', '#7fe0d7'],
  ['rgba(255,143,199,.16)', '#ffb0d6'], ['rgba(154,160,171,.18)', '#c3c7cf'],
];
// Priority: 'urgent' (unlimited), numbers 1–10 (one task per number per day), or 'none'
function normPrio(p) {
  if (p === 'urgent' || p === 'high') return 'urgent';
  const n = Number(p);
  return Number.isInteger(n) && n >= 1 && n <= 10 ? n : 'none';
}
const prioRank = (p) => { p = normPrio(p); return p === 'urgent' ? 0 : p === 'none' ? 99 : p; };
const PRIO_RANK = new Proxy({}, { get: (_, k) => prioRank(k) });
const prioLabel = (p) => { p = normPrio(p); return p === 'urgent' ? 'Urgent' : p === 'none' ? 'No priority' : `Priority ${p}`; };
// Priorities are per person: t.prio = { userId: value } ('_' = nobody assigned yet).
// Everyone sees their own priority; people not on the task see the highest one set.
function prioOf(t, who = currentUserId) {
  const pr = t.prio || {};
  if (who && pr[who] != null) return normPrio(pr[who]);
  if (who && (t.assignees || []).includes(who)) return 'none';
  const vals = Object.values(pr).map(normPrio);
  return vals.length ? vals.sort((a, b) => prioRank(a) - prioRank(b))[0] : 'none';
}
const prioOwnerName = (key) => (key === '_' ? '' : fullName(userById(key)));
const isUrgent = (t) => prioOf(t) === 'urgent';
const dayKey = (t) => t.due || 'none';
// each number once per person per day
function prioTakenBy(n, day, key, exceptId) {
  return db.tasks.find((x) => !x.done && !partDone(x, key) && x.id !== exceptId && dayKey(x) === day && normPrio((x.prio || {})[key]) === n) || null;
}
// After a task's day changes (or it is reopened), make sure its number is still free that day
function checkPrioConflict(t) {
  if (t.done) return;
  Object.entries(t.prio || {}).forEach(([key, v]) => {
    const p = normPrio(v);
    if (typeof p !== 'number') return;
    const other = prioTakenBy(p, dayKey(t), key, t.id);
    if (!other) return;
    delete t.prio[key];
    const who = prioOwnerName(key);
    logActivity(t, `cleared ${who ? `<b>${esc(who)}</b>’s` : 'the'} <b>priority</b> ${chg(prioLabel(p), prioLabel('none'))} (already used by another task that day)`);
    toast(`${who ? who + '’s ' : ''}Priority ${p} is already used by “${other.title || 'Untitled task'}” ${t.due ? 'on ' + fmtDue(t.due) : 'with no due date'} — cleared`);
  });
}
// Sort helpers: urgent first, then 1–10, then no priority
const byPrio = (a, b) => prioRank(prioOf(a)) - prioRank(prioOf(b));
const urgentFirst = (a, b) => (isUrgent(b) ? 1 : 0) - (isUrgent(a) ? 1 : 0);

let db = null;
let dataDir = '';
const ui = {
  view: 'home', projectId: null, taskId: null,
  search: '', prevView: null,
  showDone: {}, collapsed: {}, mytasksCollapsed: {},
  commentDraft: {}, commentFiles: {}, descOpen: {},
  day: null, navIds: [], openThreads: {}, replyTo: null, editingComment: null, activityFilter: 'comments', thread: null, fileClip: null, previewAtt: null, clientId: null, folderId: null,
};

const proj = (id) => db.projects.find((p) => p.id === id);
const task = (id) => db.tasks.find((t) => t.id === id);
const subtasksOf = (id) => db.tasks.filter((t) => t.parentId === id).sort(byOrder);
const topTasks = () => db.tasks.filter((t) => !t.parentId);

/* ================= Team: users, roles, permissions ================= */
const ROLES = { admin: 'Admin', am: 'Account Manager', production: 'Production', social: 'Social', freelancer: 'Freelancer', finance_admin: 'Finance only · Admin', finance_viewer: 'Finance only · Viewer' };
// Admin rights: the Admin role, or any other role given Admin rights on top (u.admin)
const isAdm = (u) => !!u && (u.role === 'admin' || u.admin === true);
// "Finance only" people (roles finance_admin / finance_viewer) only use the Finance pages.
// Anyone else can also be given Finance access on top of their role: u.fin = 'admin' | 'viewer'.
const isFinUser = (u = me()) => !!u && (u.role === 'finance_admin' || u.role === 'finance_viewer');
const finLevel = (u = me()) => (!u ? null : u.role === 'finance_admin' ? 'admin' : u.role === 'finance_viewer' ? 'viewer' : u.fin === 'admin' || u.fin === 'viewer' ? u.fin : null);
const isFinAdmin = (u = me()) => finLevel(u) === 'admin';
const FIN_ACCESS = { '': 'No Finance access', admin: 'Finance Admin', viewer: 'Finance Viewer' };
const SEED_ADMIN_ID = 'u-haris';
let currentUserId = null;
const userById = (id) => (db && db.users.find((u) => u.id === id)) || null;
const me = () => userById(currentUserId);
const fullName = (u) => (u ? (u.name || u.email.split('@')[0]) : 'Former member');
const userName = (id) => (id && id === currentUserId ? 'You' : fullName(userById(id)));
const activeUsers = () => db.users.filter((u) => u.active !== false).sort((a, b) => fullName(a).localeCompare(fullName(b)));
// Production / Social cannot do these; Account Managers can do everything except manage users
const LIMITED = new Set(['editProject', 'editPriority', 'assign', 'removeTag', 'editDesc', 'deleteTask', 'deleteChecklist', 'editTitle', 'createTask', 'deleteProject']);
function can(perm) {
  const u = me();
  if (!u) return false;
  if (isFinUser(u)) return false;
  if (perm === 'manageUsers') return isAdm(u);
  if (isAdm(u) || u.role === 'am') return true;
  return !LIMITED.has(perm);
}
function denied() { toast('Your role doesn’t allow this — ask an Admin or Account Manager'); }
const isMine = (t) => (t.assignees || []).includes(currentUserId);
// Each assignee can finish their own part of a shared task: t.partsDone = { userId: isoTime }
const partDone = (t, u = currentUserId) => !!(t.partsDone || {})[u];
const myOpen = (t) => !t.done && !partDone(t);
const myDoneAt = (t) => (t.done ? t.completedAt : (t.partsDone || {})[currentUserId] || null);
// A task you created but haven't given to anyone yet stays on your own lists until it has an assignee
const needsOwner = (t) => !t.parentId && !t.done && !(t.assignees || []).length && t.createdBy === currentUserId;
const onMyList = (t) => isMine(t) || needsOwner(t);
const myTop = () => topTasks().filter(onMyList);
/* ---------- Task fields (under the description) ----------
   Task Update: what's happening now — everyone sees it, changes are logged and sent to everyone on the task.
   Finance: Account Managers and Admins only. Guardian: one person from Production / Social / Freelancers. */
const TASK_UPDATES = ['WIP', 'Brief to come', 'Amendments', 'Minor Amendments', 'Shoot', 'Edit Video', 'Adaptations', 'On hold', 'Oversee', 'Followup', 'Meeting', 'Reel Cover', 'Ready to Post', 'Ongoing', 'Redesign', 'Awaiting client assets', 'Storyboard', 'Open files', 'Brainstorm', 'Briefing', 'Out of scope', 'Dispatch', 'Copy Writing', 'Edit images', 'HTML', 'Mockup'];
const FIELD_COLORS = ['#f9be33', '#4c9aff', '#ff6b70', '#3ddc97', '#a875ff', '#ff8a4c', '#4fd1c5', '#ff8fc7', '#9aa4b2', '#7b68ee'];
const UPDATE_COLOR = (v) => FIELD_COLORS[Math.max(0, TASK_UPDATES.indexOf(v)) % FIELD_COLORS.length];
const FINANCE = { 'Quote to be sent': '#9aa4b2', 'LPO Pending': '#f9be33', 'Invoiced': '#3ddc97', 'Retainer': '#a875ff', 'To be invoiced': '#ff8a4c' };
// Most used first (ties keep the agreed order)
function updatesByUse() {
  const n = {};
  db.tasks.forEach((t) => { if (t.update) n[t.update] = (n[t.update] || 0) + 1; });
  return TASK_UPDATES.slice().sort((a, b) => (n[b] || 0) - (n[a] || 0) || TASK_UPDATES.indexOf(a) - TASK_UPDATES.indexOf(b));
}
const fieldPill = (v, color) => `<span class="fl-pill" style="--c:${color}">${esc(v)}${icon('chev')}</span>`;
function fieldsHTML(t) {
  const mgr = isManager();
  const canGuard = can('assign');
  const rows = [
    { k: 'update', ic: 'select', l: 'Task Update', v: t.update, html: t.update ? fieldPill(t.update, UPDATE_COLOR(t.update)) : '', edit: true },
    ...(mgr ? [{ k: 'finance', ic: 'coin', l: 'Finance', v: t.finance, html: t.finance ? fieldPill(t.finance, FINANCE[t.finance] || '#9aa4b2') : '', edit: true }] : []),
    { k: 'guardian', ic: 'user', l: 'Guardian', v: t.guardian && userById(t.guardian) ? t.guardian : null,
      html: t.guardian && userById(t.guardian) ? `<span class="fl-person">${avatarHTML(t.guardian, 20)}${esc(fullName(userById(t.guardian)))}</span>` : '', edit: canGuard },
    ...Cal.fieldRows(t),
  ];
  const empty = rows.filter((r) => !r.v).length;
  const hide = !!ui.fieldsHideEmpty;
  const open = ui.fieldsOpen !== false;
  return `<div class="d-section fl-sec ${open ? '' : 'closed'}">
    <button class="fl-head" data-action="fields-toggle">${icon('chev')}<span>Fields</span></button>
    ${open ? `<div class="fl-rows">${rows.filter((r) => !(hide && !r.v)).map((r) => `<div class="fl-row">
        <span class="fl-l">${icon(r.ic)}${esc(r.l)}</span>
        <span class="fl-v">${r.raw ? r.raw : r.edit ? `<button class="fl-btn" data-action="field-pick" data-k="${r.k}">${r.html || '<span class="fl-empty">–</span>'}</button>` : (r.html || '<span class="fl-empty">–</span>')}${r.extra || ''}</span>
      </div>`).join('')}
      ${empty ? `<button class="fl-more" data-action="fields-empty">${icon(hide ? 'chev' : 'chev-up')}${hide ? 'Show' : 'Hide'} ${empty} empty field${empty === 1 ? '' : 's'}</button>` : ''}
    </div>` : ''}
  </div>`;
}
function fieldMenu(anchor, k) {
  const t = task(ui.taskId);
  if (!t) return;
  if (k === 'channels' || k === 'occasion') return Cal.fieldMenu(anchor, k, t);
  const set = (v) => setField(t, k, v);
  const cur = t[k] || null;
  let items = [];
  const ck = (on) => (on ? `<span class="wf-ck">${icon('check')}</span>` : '');
  if (k === 'update') items = updatesByUse().map((v) => ({ html: `<div class="mi">${fieldPill(v, UPDATE_COLOR(v)).replace(icon('chev'), '')}${ck(cur === v)}</div>`, run: () => set(v) }));
  else if (k === 'finance') {
    if (!isManager()) return denied();
    items = Object.entries(FINANCE).map(([v, c]) => ({ html: `<div class="mi">${fieldPill(v, c).replace(icon('chev'), '')}${ck(cur === v)}</div>`, run: () => set(v) }));
  } else if (k === 'guardian') {
    if (!can('assign')) return denied();
    [['production', 'Production'], ['social', 'Social'], ['freelancer', 'Freelancers']].forEach(([r, label]) => {
      const us = activeUsers().filter((u) => u.role === r);
      if (!us.length) return;
      items.push({ html: `<div class="wf-mh">${esc(label)}</div>` });
      us.forEach((u) => items.push({ html: `<div class="mi wf-person">${avatarHTML(u.id, 20)}<span>${esc(fullName(u))}</span>${ck(cur === u.id)}</div>`, run: () => set(u.id) }));
    });
  }
  if (cur) items.push({ html: '<div class="sep"></div>' }, { html: `<div class="mi fl-clear">${icon('x')}Clear</div>`, run: () => set(null) });
  const m = showMenu(anchor, items.map((it, i) => (it.run ? { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) } : it)));
  m.classList.add('wf-menu', 'fl-menu');
}
function setField(t, k, v) {
  const old = t[k] || null;
  if (old === v) return;
  if (k === 'finance' && !isManager()) return denied();
  t[k] = v || null;
  if (k === 'finance') { t.financeAt = nowISO(); t.financeBy = currentUserId; }
  const name = (id) => (id && userById(id) ? fullName(userById(id)) : '');
  if (k === 'update') {
    logChange(t, 'the <b>Task Update</b>', old, v);
    const to = new Set(watchersOf(t)); if (t.guardian) to.add(t.guardian);
    to.forEach((u) => pushNotif(u, t, 'update', v ? `set the Task Update to <b>${esc(v)}</b> on` : 'cleared the Task Update on'));
  } else if (k === 'finance') logChange(t, 'the <b>Finance</b> status', old, v);
  else if (k === 'guardian') {
    logChange(t, 'the <b>Guardian</b>', name(old), name(v));
    if (v) pushNotif(v, t, 'assigned', 'made you the Guardian of');
  }
  t.updatedAt = nowISO();
  commit();
}

/* ---------- Whose tasks the personal pages show ----------
   Everyone else: tasks assigned to them (as before).
   Account Managers and Admins: tasks they created. My Tasks has filters — Created date, People
   (assignees), "Assigned to me" (back to the personal list) and, for Admins only, Account managers
   (tasks those AMs created). My Day: an AM's created tasks; an Admin's "E11 Day" shows tasks created
   by every Account Manager and Admin. */

const Work = (() => {
  const f = () => (ui.workF = ui.workF || { created: null, due: null, finished: false, cd: false, people: [], ams: [], team: false, assigned: false });
  const lead = () => isManager();
  const personal = () => !lead() || f().assigned;
  const openOf = (t) => (personal() ? myOpen(t) : !t.done);
  const doneAtOf = (t) => (personal() ? myDoneAt(t) : t.done ? t.completedAt || null : null);
  const createdBy = (ids) => { const set = new Set(ids); return topTasks().filter((t) => set.has(t.createdBy)); };
  // An Account Manager's work: every task (by anyone, old ones too) in the clients they look after — while they're not
  // on leave; whoever covers sees them for as long as they're covering — plus their own tasks without a client.
  // An AM not yet given any client keeps seeing the tasks they created.
  const amClients = (id) => db.projects.filter((p) => (p.ams || []).some((a) => a.id === id && !a.onLeave)).map((p) => p.id);
  const hasClients = (id) => db.projects.some((p) => (p.ams || []).some((a) => a.id === id));
  const ofAms = (ids) => {
    const pids = new Set(), byOwn = new Set();
    ids.forEach((id) => { if (hasClients(id)) { amClients(id).forEach((x) => pids.add(x)); } byOwn.add(id); });
    return topTasks().filter((t) => (t.projectId ? pids.has(t.projectId) || (byOwn.has(t.createdBy) && !hasClients(t.createdBy)) : byOwn.has(t.createdBy)));
  };
  const leadSet = (ids) => { const am = ids.filter((id) => { const u = userById(id); return u && u.role === 'am' && !isAdm(u); }); const rest = ids.filter((id) => !am.includes(id)); const set = new Map(); ofAms(am).forEach((t) => set.set(t.id, t)); createdBy(rest).forEach((t) => set.set(t.id, t)); return [...set.values()]; };
  // Everyone whose created tasks an Admin can look at (same people as E11 Day)
  const teamIds = () => db.users.filter((x) => x.role === 'am' || isAdm(x)).map((x) => x.id);
  const creators = () => (isAdmin() && f().team ? teamIds() : isAdmin() && f().ams.length ? f().ams : [currentUserId]);
  function inCreated(t, k) {
    if (!k) return true;
    const c = new Date(t.createdAt), now = new Date();
    if (k === 'today') return ymd(c) === todayStr();
    if (k === 'month') return c.getFullYear() === now.getFullYear() && c.getMonth() === now.getMonth();
    const wd = (now.getDay() + 6) % 7; // weeks start on Monday
    return ymd(c) >= addDays(todayStr(), -wd);
  }
  // My Tasks list (both tabs), with the filters applied
  function list() {
    const F = f();
    let l = personal() ? myTop() : leadSet(creators());
    if (F.created) l = l.filter((t) => inCreated(t, F.created));
    if (F.people.length) l = l.filter((t) => (t.assignees || []).some((u) => F.people.includes(u)));
    if (F.due) l = l.filter((t) => dueIn(t, F.due));
    if (F.finished) { const wk = Date.now() - 7 * 86400000; l = l.filter((t) => { const d = doneAtOf(t); return !!d && new Date(d).getTime() > wk; }); }
    if (F.cd) l = l.filter((t) => reviewPending(t));
    return l;
  }
  // Home: an AM / Admin's own created tasks (no filters); everyone else: their tasks
  const home = () => (lead() ? leadSet([currentUserId]) : myTop());
  const homeOpen = (t) => (lead() ? !t.done : myOpen(t));
  const homeDoneAt = (t) => (lead() ? (t.done ? t.completedAt || null : null) : myDoneAt(t));
  // My Day pool
  function day() {
    const u = me();
    if (!lead()) return { tasks: db.tasks.filter(onMyList), open: myOpen, doneAt: myDoneAt, doneTasks: db.tasks.filter(isMine) };
    const who = isAdmin() ? db.users.filter((x) => x.role === 'am' || isAdm(x)).map((x) => x.id) : [u.id];
    const ts = leadSet(who);
    const dAt = (t) => (t.done ? t.completedAt || null : null);
    return { tasks: ts, open: (t) => !t.done, doneAt: dAt, doneTasks: ts };
  }
  const dayTitle = () => (isAdmin() ? 'E11 Day' : 'My Day');
  const active = () => { const F = f(); return !!(F.created || F.due || F.finished || F.cd || F.people.length || F.ams.length || F.team || F.assigned); };
  return { f, lead, personal, openOf, doneAtOf, list, home, homeOpen, homeDoneAt, day, dayTitle, inCreated, active, leadSet, hasClients };
})();
const CREATED_L = { today: 'Today', week: 'This week', month: 'This month' };
// Due date filter (same groups as the Home page): late = past due, today, week = today to Sunday
const DUE_L = { late: 'Overdue', today: 'Today', week: 'This week' };
function dueIn(t, k) {
  const today = todayStr();
  if (k === 'late') return !!t.due && t.due < today;
  if (k === 'today') return t.due === today;
  if (k === 'week') return !!t.due && t.due >= today && t.due <= addDays(today, 6 - ((new Date().getDay() + 6) % 7));
  return true;
}
// Filter bar for My Tasks (Account Managers and Admins)
function workFilterBar() {
  if (!Work.lead()) return '';
  const F = Work.f();
  const chip = (label, act, id = '') => `<span class="wf-chip">${label}<button data-action="${act}" ${id ? `data-id="${esc(id)}"` : ''} title="Remove filter">${icon('x')}</button></span>`;
  const chips = [
    F.assigned ? chip('Assigned to me', 'wf-clear-assigned') : '',
    F.created ? chip(`Created: ${CREATED_L[F.created]}`, 'wf-clear-created') : '',
    F.due ? chip(`Due: ${DUE_L[F.due]}`, 'wf-clear-due') : '',
    F.finished ? chip('Finished in the last 7 days', 'wf-clear-finished') : '',
    F.cd ? chip('Waiting for CD review', 'wf-clear-cd') : '',
    F.team ? chip('All Account Managers & Admins', 'wf-clear-team') : '',
    ...F.ams.map((id) => chip(`${avatarHTML(id, 16)}${esc(fullName(userById(id)))}’s tasks`, 'wf-clear-am', id)),
    ...F.people.map((id) => chip(`${avatarHTML(id, 16)}${esc(fullName(userById(id)))}`, 'wf-clear-person', id)),
  ].join('');
  return `<div class="wf-bar"><div class="wf-btns">
    <button class="wf-btn ${F.created ? 'on' : ''}" data-action="wf-created">${icon('cal')}Created date${icon('chev')}</button>
    <button class="wf-btn ${F.due ? 'on' : ''}" data-action="wf-due">${icon('flag')}Due date${icon('chev')}</button>
    <button class="wf-btn ${F.people.length ? 'on' : ''}" data-action="wf-people">${icon('users')}People${icon('chev')}</button>
    ${isAdmin() ? `<button class="wf-btn ${F.ams.length || F.team ? 'on' : ''}" data-action="wf-ams">${icon('user')}Account managers${icon('chev')}</button>` : ''}
    <button class="wf-btn ${F.assigned ? 'on' : ''}" data-action="wf-assigned">${icon('check-circle')}Assigned to me</button></div>
    ${chips ? `<div class="wf-chips">${chips}${Work.active() ? '<button class="wf-reset" data-action="wf-reset">Clear all</button>' : ''}</div>` : ''}
  </div>`;
}
function workMenu(anchor, kind) {
  const F = Work.f();
  const redraw = () => { renderContent(); renderSidebar(); };
  const check = (on) => (on ? `<span class="wf-ck">${icon('check')}</span>` : '');
  let items = [];
  if (kind === 'due') {
    items = Object.entries(DUE_L).map(([k, l]) => ({ html: `<div class="mi ${F.due === k ? 'cur' : ''}">${esc(l)}${check(F.due === k)}</div>`, run: () => { F.due = F.due === k ? null : k; redraw(); } }));
  } else if (kind === 'created') {
    items = Object.entries(CREATED_L).map(([k, l]) => ({ html: `<div class="mi ${F.created === k ? 'cur' : ''}">${esc(l)}${check(F.created === k)}</div>`, run: () => { F.created = F.created === k ? null : k; redraw(); } }));
  } else {
    const roles = kind === 'ams' ? [['am', 'Account Managers']] : [['production', 'Production'], ['social', 'Social'], ['freelancer', 'Freelancers']];
    const key = kind === 'ams' ? 'ams' : 'people';
    if (kind === 'ams') items.push({ html: `<div class="mi wf-person"><span>All Account Managers &amp; Admins</span>${check(F.team)}</div>`, run: () => { F.team = !F.team; if (F.team) F.ams = []; redraw(); } });
    roles.forEach(([r, label]) => {
      const us = activeUsers().filter((u) => u.role === r && u.id !== currentUserId);
      if (!us.length) return;
      items.push({ html: `<div class="wf-mh">${esc(label)}</div>` });
      us.forEach((u) => items.push({ html: `<div class="mi wf-person">${avatarHTML(u.id, 20)}<span>${esc(fullName(u))}</span>${check(F[key].includes(u.id))}</div>`,
        run: () => { F[key] = F[key].includes(u.id) ? F[key].filter((x) => x !== u.id) : F[key].concat(u.id); if (key === 'ams') F.team = false; redraw(); } }));
    });
    if (!items.length) items.push({ html: `<div class="wf-mh">Nobody here yet</div>` });
  }
  const m = showMenu(anchor, items.map((it, i) => (it.run ? { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) } : it)));
  m.classList.add('wf-menu');
}

const AV_COLORS = ['#7b68ee', '#4c9aff', '#3ddc97', '#f9be33', '#ff8a4c', '#e5484d', '#ff8fc7', '#4fd1c5', '#a875ff'];
function avColor(id) { let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return AV_COLORS[h % AV_COLORS.length]; }
function avatarHTML(id, size = 24, cls = '') {
  const u = userById(id);
  const name = fullName(u);
  const st = `width:${size}px;height:${size}px;font-size:${Math.round(size * 0.4)}px`;
  if (u && u.avatar && Host.isNative) return `<span class="av ${cls}" style="${st}" title="${esc(name)}"><img src="${fileUrl({ path: u.avatar })}" alt=""></span>`;
  return `<span class="av ${cls}" style="${st};background:${avColor(id || 'x')}" title="${esc(name)}">${esc(initials(name))}</span>`;
}
function avatarStack(ids, size = 20, max = 3, t = null) {
  if (!ids || !ids.length) return '';
  const shown = ids.slice(0, max).map((id) => (t && partDone(t, id) ? `<span class="av-done">${avatarHTML(id, size)}<i>${icon('check')}</i></span>` : avatarHTML(id, size))).join('');
  return `<span class="av-stack">${shown}${ids.length > max ? `<span class="av more" style="width:${size}px;height:${size}px">+${ids.length - max}</span>` : ''}</span>`;
}
// People who follow a task: its assignees and whoever created it (a subtask also notifies its parent's people)
function watchersOf(t) {
  const set = new Set((t.assignees || []).concat(t.createdBy ? [t.createdBy] : []));
  if (t.parentId) { const p = task(t.parentId); if (p) watchersOf(p).forEach((x) => set.add(x)); }
  return [...set];
}

/* ---- Password hashing (SHA-256, salted, stretched) ---- */
function sha256(str) {
  const K = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];
  const bytes = new TextEncoder().encode(str);
  const l = bytes.length;
  const n = ((l + 9 + 63) >> 6) << 6;
  const m = new Uint8Array(n); m.set(bytes); m[l] = 0x80;
  const dv = new DataView(m.buffer);
  dv.setUint32(n - 4, (l * 8) >>> 0); dv.setUint32(n - 8, Math.floor(l / 0x20000000));
  const H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const W = new Uint32Array(64);
  const r = (x, k) => (x >>> k) | (x << (32 - k));
  for (let o = 0; o < n; o += 64) {
    for (let i = 0; i < 16; i++) W[i] = dv.getUint32(o + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 = r(W[i - 15], 7) ^ r(W[i - 15], 18) ^ (W[i - 15] >>> 3);
      const s1 = r(W[i - 2], 17) ^ r(W[i - 2], 19) ^ (W[i - 2] >>> 10);
      W[i] = (W[i - 16] + s0 + W[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const t1 = (h + (r(e, 6) ^ r(e, 11) ^ r(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + W[i]) >>> 0;
      const t2 = ((r(a, 2) ^ r(a, 13) ^ r(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) >>> 0;
      h = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
  }
  return H.map((x) => x.toString(16).padStart(8, '0')).join('');
}
function hashPw(pw, salt) { let h = salt + ':' + pw; for (let i = 0; i < 1500; i++) h = sha256(salt + h); return h; }
function setPassword(u, pw) { u.salt = uid() + uid(); u.hash = hashPw(pw, u.salt); }
const checkPassword = (u, pw) => !!u && !!u.salt && hashPw(pw, u.salt) === u.hash;
const validEmail = (s) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(s).trim());

/* ---- CD Status & completion rules ---- */
const CD = { review: { label: 'Internal Review', color: '#f9be33' }, approved: { label: 'Approved', color: '#3ddc97' } };
const statusList = (t) => { const p = proj(t.projectId); return p ? p.sections : db.statuses; };
const isToDoName = (n) => /^to ?-?do$/i.test(String(n).trim());
const isDoneName = (n) => /^(done|complete|completed)$/i.test(String(n).trim());
// CD Status is always shown on main tasks, but can only be set once the task has left "To Do"
const showsCD = (t) => !t.parentId;
const cdLocked = (t) => !t.done && !!sectionOf(t) && isToDoName(sectionOf(t).name);
const CD_LOCK_MSG = 'CD Status can be set once the task moves out of To Do';
// Main tasks can be completed only when the status is Done and CD Status is Approved
const canComplete = (t) => !!t.parentId || (!!sectionOf(t) && isDoneName(sectionOf(t).name) && cdOK(t));
function completeBlockedMsg(t) {
  const s = sectionOf(t);
  const needDone = !(s && isDoneName(s.name)), needCD = !cdOK(t);
  return 'To mark complete, ' + [needDone ? 'set the status to Done' : '', needCD ? 'the Creative Director needs to approve the files' : ''].filter(Boolean).join(' and ');
}

function tagColor(name) {
  let h = 0;
  for (const c of name.toLowerCase()) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return TAG_COLORS[h % TAG_COLORS.length];
}
const tagChip = (name) => { const [bg, fg] = tagColor(name); return `<span class="tag" style="background:${bg};color:${fg}">${esc(name)}</span>`; };
const prioPill = (p) => (p && p !== 'none' ? `<span class="prio ${p}">${p[0].toUpperCase() + p.slice(1)}</span>` : '');
const initials = (name) => name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?';

const STATUS_COLORS = ['#87909e', '#4c9aff', '#a875ff', '#f9be33', '#e5484d', '#3ddc97', '#ff8fc7', '#4fd1c5'];
function defaultSectionColor(name, i) {
  const n = String(name).toLowerCase();
  if (/done|complete|closed|finish|delivered/.test(n)) return '#3ddc97';
  if (/progress|doing|working|active/.test(n)) return '#a875ff';
  if (/review|qa|approv|check/.test(n)) return '#f9be33';
  if (/block|stuck|hold|wait/.test(n)) return '#e5484d';
  if (/to ?do|backlog|open|new|idea/.test(n)) return '#87909e';
  return STATUS_COLORS[i % STATUS_COLORS.length];
}
function textOn(hex) {
  const h = String(hex).replace('#', '');
  const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.62 ? '#1a1a1d' : '#ffffff';
}
const sectionOf = (t) => {
  const p = proj(t.projectId);
  if (p) return p.sections.find((s) => s.id === t.sectionId) || null;
  const list = db.statuses || [];
  return list.find((s) => s.id === t.sectionId) || list[0] || null;
};
function statusInfo(t) {
  if (t.done) return { name: 'Complete', color: '#3ddc97' };
  const s = sectionOf(t);
  return s ? { name: s.name, color: s.color } : { name: 'Open', color: '#87909e' };
}
function statusPill(t, extra = '') {
  const s = statusInfo(t);
  return `<span class="status-pill" style="background:${s.color};color:${textOn(s.color)}" ${extra}>${esc(s.name)}</span>`;
}
// Round status icon that fills up as the task moves through its statuses (ClickUp-style)
function statusIconSVG(color, kind, frac) {
  if (kind === 'done') return `<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="${color}"/><path d="m4.9 8.2 2.1 2.1 4-4.3" fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  if (kind === 'todo') return `<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.2" fill="none" stroke="${color}" stroke-width="1.7" stroke-dasharray="2.4 1.9"/></svg>`;
  const a = Math.min(.999, Math.max(.08, frac)) * Math.PI * 2, r = 3.6;
  const x = 8 + r * Math.sin(a), y = 8 - r * Math.cos(a);
  return `<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.2" fill="none" stroke="${color}" stroke-width="1.7"/><path d="M8 8 L8 ${8 - r} A${r} ${r} 0 ${a > Math.PI ? 1 : 0} 1 ${x.toFixed(2)} ${y.toFixed(2)} Z" fill="${color}"/></svg>`;
}
function statusIcon(t, size = 16) {
  const st = sectionOf(t);
  const info = statusInfo(t);
  let kind = 'mid', frac = .5;
  if (t.done || (st && isDoneName(st.name))) kind = 'done';
  else if (!st || isToDoName(st.name)) kind = 'todo';
  else { const list = statusList(t); const i = list.indexOf(st); frac = list.length > 1 ? i / (list.length - 1) : .5; }
  return `<span class="st-ic" style="width:${size}px;height:${size}px" title="${esc(info.name)}">${statusIconSVG(t.done ? '#3ddc97' : info.color, kind, frac)}</span>`;
}
function sectionPill(s) {
  return `<span class="status-pill" style="background:${s.color};color:${textOn(s.color)}">${esc(s.name)}</span>`;
}
// "changed X: old → new" with the old value struck out
const trunc = (v, n = 140) => { v = String(v == null ? '' : v).replace(/\s+/g, ' ').trim(); return v.length > n ? v.slice(0, n - 1) + '…' : v; };
const fmtDay = (s) => { if (!s) return ''; const d = parseYmd(s); const o = { month: 'short', day: 'numeric' }; if (d.getFullYear() !== new Date().getFullYear()) o.year = 'numeric'; return d.toLocaleDateString('en-US', o); };
function chg(oldV, newV, long) {
  const o = trunc(oldV, long ? 220 : 80), n = trunc(newV, long ? 220 : 80);
  const empty = '<i class="chg-empty">empty</i>';
  return `<span class="chg${long ? ' long' : ''}"><span class="chg-old">${o ? esc(o) : empty}</span><span class="chg-arrow">→</span><span class="chg-new">${n ? esc(n) : empty}</span></span>`;
}
function logChange(t, label, oldV, newV, long) {
  if (String(oldV || '') === String(newV || '')) return;
  logActivity(t, `changed ${label} ${chg(oldV, newV, long)}`);
}
const struck = (v) => `<span class="chg-old">${esc(trunc(v, 80))}</span>`;

// Typed fields (title, description, subtask names, checklist items) are logged once,
// when you finish editing — not on every keystroke.
let editSnap = null;
function editKeyOf(el) {
  if (!el || !el.closest || !el.closest('#detail')) return null;
  if (el.id === 'd-title') return { kind: 'title', id: ui.taskId };
  if (el.id === 'd-notes') return { kind: 'notes', id: ui.taskId };
  if (el.classList && el.classList.contains('sub-title')) return { kind: 'sub', id: el.dataset.subId };
  if (el.classList && el.classList.contains('cl-text')) return { kind: 'cl', id: el.dataset.clId };
  return null;
}
function snapValue(k) {
  const t = task(ui.taskId);
  if (!t) return null;
  if (k.kind === 'title') return t.title;
  if (k.kind === 'notes') return t.notes;
  if (k.kind === 'sub') { const x = task(k.id); return x ? x.title : null; }
  if (k.kind === 'cl') { const c = (t.checklist || []).find((x) => x.id === k.id); return c ? c.text : null; }
  return null;
}
function flushEdit() {
  if (!editSnap) return;
  const snap = editSnap; editSnap = null;
  const t = task(snap.taskId);
  if (!t) return;
  const now = snapValue({ ...snap.key });
  if (now == null || now === snap.before) return;
  if (snap.key.kind === 'title') logChange(t, 'the <b>title</b>', snap.before, now);
  else if (snap.key.kind === 'notes') {
    logActivity(t, 'changed the <b>description</b>');
    const before = mentionsIn(snap.beforeHtml);
    mentionsIn(t.notesHtml).forEach((u) => { if (!before.has(u)) pushNotif(u, t, 'mention', 'mentioned you in the description of', { snippet: trunc(t.notes, 160) }); });
  }
  else if (snap.key.kind === 'sub') logChange(t, 'a <b>subtask</b>', snap.before, now);
  else if (snap.key.kind === 'cl') logChange(t, 'a <b>checklist item</b>', snap.before, now);
  persist();
  if (ui.taskId === t.id) refreshActivity();
}
// Re-draw only the activity feed (keeps the cursor where it is while editing)
function refreshActivity() {
  const t = task(ui.taskId);
  const feed = $('#detail .tm-feed');
  if (!t || !feed) return;
  const atEnd = feed.scrollHeight - feed.scrollTop - feed.clientHeight < 30;
  feed.innerHTML = activityHTML(t);
  if (atEnd) feed.scrollTop = feed.scrollHeight;
}
document.addEventListener('focusin', (e) => {
  const k = editKeyOf(e.target);
  if (!k) return;
  if (editSnap && editSnap.el !== e.target) flushEdit();
  if (!editSnap) { const tt = task(ui.taskId); editSnap = { key: k, el: e.target, taskId: ui.taskId, before: snapValue(k), beforeHtml: tt ? tt.notesHtml || '' : '' }; }
});
document.addEventListener('focusout', (e) => { if (editSnap && editSnap.el === e.target) flushEdit(); });

function logActivity(t, text) {
  t.activity = t.activity || [];
  t.activity.push({ id: uid(), at: nowISO(), text, actor: currentUserId });
  if (t.activity.length > 300) t.activity.splice(0, t.activity.length - 300);
}

/* ================= Notifications ================= */
// Notification types each person can switch off in their profile (all on by default)
const NOTIF_TYPES = [
  { k: 'assign', kinds: ['assigned', 'unassigned'], l: 'Assigned or removed', d: 'Someone adds you to a task or takes you off it' },
  { k: 'mention', kinds: ['mention'], l: '@Mentions', d: 'Someone tags you in a comment or a description' },
  { k: 'comment', kinds: ['comment'], l: 'Comments & replies', d: 'New comments on your tasks and replies in your threads' },
  { k: 'status', kinds: ['status', 'done'], l: 'Status & completion', d: 'A task moves to another status or is marked complete' },
  { k: 'update', kinds: ['update'], l: 'Task Update changes', d: 'The Task Update of a task you’re on changes' },
  { k: 'cd', kinds: ['cd'], l: 'CD Status changes', d: 'The CD Status of a task is set or cleared' },
  { k: 'due', kinds: ['due'], l: 'Due dates', d: 'A due date is added, moved or removed' },
  { k: 'priority', kinds: ['priority'], l: 'Priority', d: 'Your priority on a task is changed' },
  { k: 'attach', kinds: ['attach'], l: 'Files added', d: 'Someone attaches files to a task' },
  { k: 'part', kinds: ['part', 'allparts'], l: 'Parts done', d: 'Someone finishes or reopens their part of a shared task' },
  { k: 'result', kinds: ['review-ok', 'review-amend'], l: 'CD review results', d: 'The CD approves your files or asks for amendments' },
  { k: 'review', kinds: ['review'], l: 'New review requests', d: 'Someone submits files for your review', cd: true },
  { k: 'review-wd', kinds: ['review-wd'], l: 'Withdrawn submissions', d: 'Someone withdraws files they sent for review', cd: true },
];
const notifTypeOf = (kind) => NOTIF_TYPES.find((x) => x.kinds.includes(kind));
const notifOn = (u, kind) => { const g = notifTypeOf(kind); return !g || !((u.prefs || {}).notifOff || {})[g.k]; };
// One notification per person; never to the person who made the change
function pushNotif(to, t, kind, text, extra = {}) {
  if (!to || !currentUserId || to === currentUserId || !t) return;
  const u = userById(to);
  if (!u || u.active === false) return;
  if (!notifOn(u, kind)) return;
  db.notifications.push({ id: uid(), to, from: currentUserId, taskId: t.id, kind, text, snippet: extra.snippet || '', commentId: extra.commentId || null, at: nowISO(), read: false });
  if (db.notifications.length > 5000) db.notifications.splice(0, db.notifications.length - 5000);
}
function notifyWatchers(t, kind, text, extra = {}) {
  const skip = new Set(extra.skip || []);
  watchersOf(t).forEach((u) => { if (!skip.has(u)) pushNotif(u, t, kind, text, extra); });
}
const mentionsIn = (html) => { const out = new Set(); String(html || '').replace(/data-user="([^"]+)"/g, (_, id) => { out.add(id); return ''; }); return out; };

function normalize(d) {
  d = d && typeof d === 'object' ? d : {};
  d.version = 1;
  d.meta = d.meta || { createdAt: nowISO() };
  d.projects = Array.isArray(d.projects) ? d.projects : [];
  d.clients = Array.isArray(d.clients) ? d.clients : [];
  d.clients.forEach((c) => { c.folders = Array.isArray(c.folders) ? c.folders : []; c.folders.forEach((f) => { f.files = Array.isArray(f.files) ? f.files : []; }); });
  d.tasks = Array.isArray(d.tasks) ? d.tasks : [];
  d.meta.migrations = d.meta.migrations || {};
  // Team members — the first admin is created on a fresh install / upgrade
  d.users = Array.isArray(d.users) ? d.users : [];
  if (!d.users.length) {
    const u = { id: SEED_ADMIN_ID, email: 'haris@e11-digital.com', name: 'Haris', role: 'admin', avatar: null, setup: false, active: true, createdAt: nowISO(), prefs: {} };
    setPassword(u, '123456');
    d.users.push(u);
  }
  d.users.forEach((u) => { u.prefs = u.prefs || {}; if (u.active == null) u.active = true; });
  const firstAdmin = (d.users.find((u) => u.role === 'admin') || d.users[0]).id;
  d.notifications = Array.isArray(d.notifications) ? d.notifications : [];
  d.trash = Array.isArray(d.trash) ? d.trash : [];
  d.finance = Array.isArray(d.finance) ? d.finance : [];
  d.claims = Array.isArray(d.claims) ? d.claims : [];
  // Statuses for tasks that are not in a project
  d.statuses = Array.isArray(d.statuses) && d.statuses.length ? d.statuses : [
    { id: 'st-todo', name: 'To do', color: '#87909e' }, { id: 'st-progress', name: 'In progress', color: '#a875ff' },
    { id: 'st-review', name: 'Review', color: '#f9be33' }, { id: 'st-ctr', name: 'CTR', color: '#ff8a4c' }, { id: 'st-done', name: 'Done', color: '#3ddc97' },
  ];
  d.projects.forEach((p, i) => {
    p.sections = Array.isArray(p.sections) && p.sections.length ? p.sections : [{ id: uid(), name: 'To do' }];
    p.sections.forEach((s, j) => { if (!s.color) s.color = defaultSectionColor(s.name, j); });
    p.color = p.color || COLORS[i % COLORS.length];
    p.view = p.view || 'list';
    if (p.order == null) p.order = i + 1;
    // add the CTR status (once) just before Done
    if (!d.meta.migrations.ctr && !p.sections.some((s) => /^ctr$/i.test(s.name.trim()))) {
      const di = p.sections.findIndex((s) => isDoneName(s.name));
      p.sections.splice(di >= 0 ? di : p.sections.length, 0, { id: uid(), name: 'CTR', color: '#ff8a4c' });
    }
  });
  d.meta.migrations.ctr = true;
  d.tasks.forEach((t) => {
    t.tags = t.tags || []; t.comments = t.comments || []; t.attachments = t.attachments || [];
    t.comments.forEach((c) => { c.attachments = c.attachments || []; c.text = c.text || ''; c.parentId = c.parentId || null; c.reactions = c.reactions || {}; });
    t.activity = t.activity || []; t.checklist = t.checklist || []; t.start = t.start || null;
    t.priority = t.priority === 'medium' || t.priority === 'low' ? 'none' : normPrio(t.priority); t.notes = t.notes || ''; t.title = t.title || '';
    t.cdStatus = t.cdStatus === 'review' || t.cdStatus === 'approved' ? t.cdStatus : '';
    t.reviews = Array.isArray(t.reviews) ? t.reviews : [];
    if (t.needsCD == null) { t.needsCD = !t.parentId && !t.done && !!t.projectId && t.cdStatus !== 'approved'; if (t.needsCD && t.cdStatus === 'review' && !t.reviews.length) t.cdStatus = ''; }
    // tasks from before team accounts belong to the first admin
    if (!t.createdBy) t.createdBy = firstAdmin;
    if (!Array.isArray(t.assignees)) t.assignees = [firstAdmin];
    if (!t.prio || typeof t.prio !== 'object') {
      t.prio = {};
      const old = normPrio(t.priority);
      if (old !== 'none') (t.assignees.length ? t.assignees : ['_']).forEach((a) => { t.prio[a] = old; });
    }
    delete t.priority;
    t.comments.forEach((c) => { if (!c.authorId) c.authorId = firstAdmin; });
    t.activity.forEach((a) => { if (!a.actor) a.actor = firstAdmin; });
    if (!t.projectId && !t.parentId && !d.statuses.some((s) => s.id === t.sectionId)) t.sectionId = d.statuses[0].id;
  });
  return d;
}

function createProject(name, color) {
  const p = {
    id: uid(), name, color, view: 'list', createdAt: nowISO(),
    order: db.projects.length ? Math.max(...db.projects.map((x) => x.order || 0)) + 1 : 1,
    sections: [{ id: uid(), name: 'To do', color: '#87909e' }, { id: uid(), name: 'In progress', color: '#a875ff' }, { id: uid(), name: 'Review', color: '#f9be33' }, { id: uid(), name: 'CTR', color: '#ff8a4c' }, { id: uid(), name: 'Done', color: '#3ddc97' }],
  };
  db.projects.push(p);
  return p;
}

function createTask(fields = {}) {
  const t = {
    id: uid(), projectId: null, sectionId: null, parentId: null,
    title: '', notes: '', done: false, completedAt: null, due: null, prio: {},
    tags: [], attachments: [], comments: [], checklist: [], activity: [], start: null, createdAt: nowISO(), updatedAt: nowISO(),
    cdStatus: '', assignees: [], createdBy: currentUserId || SEED_ADMIN_ID, reviews: [], needsCD: !fields.parentId && !!fields.projectId,
    ...fields,
  };
  if (!fields.silent) t.activity.push({ id: uid(), at: t.createdAt, text: 'created this task', actor: t.createdBy });
  delete t.silent;
  if (fields.priority != null) { const v = normPrio(fields.priority); if (v !== 'none') (t.assignees.length ? t.assignees : ['_']).forEach((a) => { t.prio[a] = v; }); }
  delete t.priority;
  if (t.parentId) {
    const parent = task(t.parentId);
    if (parent) { t.projectId = parent.projectId; t.sectionId = parent.sectionId; }
  } else if (t.projectId && !t.sectionId) {
    const p = proj(t.projectId);
    t.sectionId = p && p.sections[0] ? p.sections[0].id : null;
  } else if (!t.projectId && !t.sectionId) {
    t.sectionId = db.statuses[0].id;
  }
  const sibs = db.tasks.filter((x) => (t.parentId ? x.parentId === t.parentId : (!x.parentId && x.projectId === t.projectId && x.sectionId === t.sectionId)));
  t.order = fields.order != null ? fields.order : (sibs.length ? Math.max(...sibs.map((x) => x.order || 0)) + 1 : 1);
  db.tasks.push(t);
  return t;
}

function descendants(id) {
  const out = [];
  const walk = (pid) => db.tasks.filter((t) => t.parentId === pid).forEach((t) => { out.push(t); walk(t.id); });
  walk(id);
  return out;
}

function removeTasks(ids) {
  const set = new Set(ids);
  const removed = db.tasks.filter((t) => set.has(t.id));
  db.tasks = db.tasks.filter((t) => !set.has(t.id));
  return removed;
}

function setDone(t, done) {
  if (!!t.done !== !!done) {
    logActivity(t, done ? 'completed this task' : 'reopened this task');
    notifyWatchers(t, 'done', done ? 'completed' : 'reopened');
  }
  t.done = done;
  t.completedAt = done ? nowISO() : null;
  t.updatedAt = nowISO();
  if (!done && db.tasks.includes(t)) checkPrioConflict(t);
}

function moveTask(id, sectionId, targetId, after) {
  const t = task(id);
  if (!t) return;
  if (t.sectionId !== sectionId) {
    const list = statusList(t);
    const from = list.find((x) => x.id === t.sectionId);
    const to = list.find((x) => x.id === sectionId);
    if (to) { logChange(t, 'the <b>status</b>', from ? from.name : '', to.name); notifyWatchers(t, 'status', `changed the status to <b>${esc(to.name)}</b>`); }
  }
  t.sectionId = sectionId;
  descendants(t.id).forEach((d) => { d.sectionId = sectionId; });
  const sibs = db.tasks.filter((x) => !x.parentId && x.projectId === t.projectId && x.sectionId === sectionId && x.id !== id).sort(byOrder);
  let idx = sibs.length;
  if (targetId) {
    const i = sibs.findIndex((x) => x.id === targetId);
    if (i >= 0) idx = i + (after ? 1 : 0);
  }
  sibs.splice(idx, 0, t);
  sibs.forEach((x, i) => { x.order = i + 1; });
  t.updatedAt = nowISO();
}

function setTaskProject(t, projectId) {
  const p = projectId ? proj(projectId) : null;
  const oldP = proj(t.projectId);
  logChange(t, 'the <b>client</b>', oldP ? oldP.name : 'My Tasks', p ? p.name : 'My Tasks');
  t.projectId = p ? p.id : null;
  t.sectionId = p && p.sections[0] ? p.sections[0].id : db.statuses[0].id;
  const sibs = db.tasks.filter((x) => !x.parentId && x.projectId === t.projectId && x.sectionId === t.sectionId && x.id !== t.id);
  t.order = sibs.length ? Math.max(...sibs.map((x) => x.order || 0)) + 1 : 1;
  descendants(t.id).forEach((d) => { d.projectId = t.projectId; d.sectionId = t.sectionId; });
  t.updatedAt = nowISO();
}

function seed() {
  const A = [SEED_ADMIN_ID];
  const p = createProject('Getting Started', '#5b8cff');
  const [todo, doing, , done] = p.sections;
  const today = todayStr();
  const t1 = createTask({ projectId: p.id, sectionId: todo.id, title: 'Welcome to E11 Console', priority: 1, due: today, tags: ['tour'], assignees: A,
    notes: 'Click any task to open its details here. You can add a description, due date, priority, tags, subtasks, files and comments.\n\nEverything is saved automatically to the "E11 Console Data" folder on your Desktop.' });
  t1.checklist = [{ id: uid(), text: 'Try the new task page', done: false }, { id: uid(), text: 'Reply to a comment', done: false }];
  t1.comments.push({ id: 'c-welcome', text: 'Comments are threaded — click Reply to start a thread. Type @ to mention a teammate.', at: nowISO(), attachments: [], parentId: null, reactions: {}, authorId: SEED_ADMIN_ID });
  createTask({ parentId: t1.id, title: 'Open a task to see its details' });
  createTask({ parentId: t1.id, title: 'Tick a circle to complete a task' });
  createTask({ projectId: p.id, sectionId: todo.id, title: 'Switch to Board view and drag a card between columns', due: addDays(today, 1), tags: ['tour'], assignees: A });
  createTask({ projectId: p.id, sectionId: todo.id, title: 'Add your first client from the sidebar', priority: 'urgent', due: addDays(today, 2), assignees: A });
  createTask({ projectId: p.id, sectionId: doing.id, title: 'Press ⌘K to search all tasks', tags: ['tip'], assignees: A });
  const d = createTask({ projectId: p.id, sectionId: done.id, title: 'Install E11 Console', assignees: A });
  setDone(d, true);
  createTask({ title: 'Plan this week', due: today, priority: 'urgent', assignees: A });
}


/* ================= Live sync with the server ================= */
// The app keeps the whole data set in memory as before. When something changes we send only the
// items that changed (with the version we last saw, so the server can merge), and the server
// pushes everyone else's changes to us live.

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const hasId = (v) => isObj(v) && (typeof v.id === 'string' || typeof v.id === 'number');
const isIdArray = (a) => Array.isArray(a) && a.every(hasId);
const isPrimArray = (a) => Array.isArray(a) && a.every((x) => x === null || typeof x !== 'object');

function deepEqual(a, b) {
  if (a === b) return true;
  if (typeof a !== typeof b || a === null || b === null || typeof a !== 'object') return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a)) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (!deepEqual(a[i], b[i])) return false;
    return true;
  }
  const ka = Object.keys(a), kb = Object.keys(b);
  if (ka.length !== kb.length) return false;
  for (const k of ka) if (!Object.prototype.hasOwnProperty.call(b, k) || !deepEqual(a[k], b[k])) return false;
  return true;
}

function merge3(base, mine, theirs) {
  if (deepEqual(mine, base)) return theirs;     // I didn't touch it: keep the server's
  if (deepEqual(theirs, base)) return mine;     // nobody else touched it: take mine
  if (deepEqual(mine, theirs)) return mine;     // we both made the same change
  if (isObj(mine) && isObj(theirs)) return mergeObjects(isObj(base) ? base : {}, mine, theirs);
  const arrays = [base, mine, theirs].filter((x) => x !== undefined);
  if (Array.isArray(mine) && Array.isArray(theirs)) {
    if (arrays.every(isIdArray)) return mergeIdArrays(Array.isArray(base) ? base : [], mine, theirs);
    if (arrays.every(isPrimArray)) return mergeSets(Array.isArray(base) ? base : [], mine, theirs);
  }
  return mine;                                   // true conflict on a single value: latest save wins
}

function mergeObjects(base, mine, theirs) {
  const out = {};
  const keys = new Set([...Object.keys(theirs), ...Object.keys(mine), ...Object.keys(base)]);
  for (const k of keys) {
    const inMine = Object.prototype.hasOwnProperty.call(mine, k);
    const inTheirs = Object.prototype.hasOwnProperty.call(theirs, k);
    const inBase = Object.prototype.hasOwnProperty.call(base, k);
    if (!inMine && inBase && deepEqual(base[k], theirs[k])) continue;        // I deleted it, they didn't change it
    if (!inTheirs && inBase && deepEqual(base[k], mine[k])) continue;        // they deleted it, I didn't change it
    const v = merge3(base[k], mine[k], theirs[k]);
    if (v !== undefined) out[k] = v;
  }
  return out;
}

// Lists of things with ids (comments, activity, attachments, checklist, sections, folders…)
function mergeIdArrays(base, mine, theirs) {
  const byId = (a) => new Map(a.map((x) => [String(x.id), x]));
  const b = byId(base), m = byId(mine), t = byId(theirs);
  const out = [];
  // Use my order if I reordered things, otherwise the server's order
  const common = (a) => a.map((x) => String(x.id)).filter((id) => b.has(id));
  const reordered = !deepEqual(common(mine), common(base).filter((id) => m.has(id)));
  const order = reordered ? [...mine, ...theirs.filter((x) => !m.has(String(x.id)))] : [...theirs, ...mine.filter((x) => !t.has(String(x.id)))];
  const seen = new Set();
  for (const item of order) {
    const id = String(item.id);
    if (seen.has(id)) continue;
    seen.add(id);
    const inB = b.has(id), inM = m.has(id), inT = t.has(id);
    if (inB && !inM) continue;                  // I removed it
    if (inB && !inT) continue;                  // someone else removed it
    if (inM && inT) out.push(merge3(b.get(id), m.get(id), t.get(id)));
    else if (inM) out.push(m.get(id));          // I added it
    else out.push(t.get(id));                   // someone else added it
  }
  return out;
}

// Lists of plain values (tags, assignees): apply my additions and removals to the server's list
function mergeSets(base, mine, theirs) {
  const key = (x) => JSON.stringify(x);
  const bk = new Set(base.map(key)), mk = new Set(mine.map(key));
  const removed = new Set(base.filter((x) => !mk.has(key(x))).map(key));
  const added = mine.filter((x) => !bk.has(key(x)));
  const out = theirs.filter((x) => !removed.has(key(x)));
  const have = new Set(out.map(key));
  added.forEach((x) => { if (!have.has(key(x))) { out.push(x); have.add(key(x)); } });
  return out;
}

const Sync = (() => {
  const KINDS = ['users', 'projects', 'tasks', 'clients', 'notifications', 'statuses', 'trash', 'meta', 'finance', 'claims'];
  const clientId = 'c-' + uid() + uid();
  const synced = {};               // kind -> Map(id -> JSON the server has)
  KINDS.forEach((k) => { synced[k] = new Map(); });
  let rev = 0, es = null, pushing = false, again = false, online = true, retryTimer = null, version = null;
  const prefKey = (id) => 'e11-prefs-' + id;
  const loadPrefs = (id) => { try { return JSON.parse(localStorage.getItem(prefKey(id)) || '{}') || {}; } catch (e) { return {}; } };
  const savePrefs = () => { try { if (currentUserId) localStorage.setItem(prefKey(currentUserId), JSON.stringify(db.meta.prefs || {})); } catch (e) { /* private mode */ } };
  // Settings that belong to this device/person, not shared with the team
  const sharedMeta = (m) => { const o = { ...(m || {}) }; delete o.prefs; delete o.updatedAt; return o; };
  const items = (kind) => (kind === 'meta' ? [['main', sharedMeta(db.meta)]] : (db[kind] || []).map((x) => [String(x.id), x]));
  const remember = (kind, id, data) => { if (data == null) synced[kind].delete(id); else synced[kind].set(id, JSON.stringify(data)); };
  function localOf(kind, id) {
    if (kind === 'meta') return sharedMeta(db.meta);
    return (db[kind] || []).find((x) => String(x.id) === id) || null;
  }
  // Put the server's version of an item into the app's data (keeping object identity)
  function setLocal(kind, id, data) {
    if (kind === 'meta') { const prefs = db.meta.prefs; db.meta = { ...(data || {}), prefs }; return; }
    const list = db[kind] || (db[kind] = []);
    const i = list.findIndex((x) => String(x.id) === id);
    if (data == null) { if (i >= 0) list.splice(i, 1); return; }
    if (i < 0) { list.push(data); return; }
    const obj = list[i];
    Object.keys(obj).forEach((k) => { delete obj[k]; });
    Object.assign(obj, data);
  }

  async function start() {
    const me = await api('GET', '/api/me');
    if (typeof ViewAs !== 'undefined') ViewAs.init(me.viewAs);   // test site only: the owner using the app as someone else
    AppIcon.setOwner(me.owner); if (me.appIcon) AppIcon.sync(me.appIcon);
    MacUpdate.check(me.macShell);
    MacChrome.init();
    const snap = await api('GET', '/api/snapshot');
    rev = snap.rev; version = snap.version || me.version;
    const data = snap.data;
    KINDS.forEach((k) => { if (k === 'meta') remember('meta', 'main', sharedMeta(data.meta)); else (data[k] || []).forEach((x) => remember(k, String(x.id), x)); });
    data.meta = { ...(data.meta || {}), prefs: loadPrefs(me.user.id) };
    db = normalize(JSON.parse(JSON.stringify(data)));
    if (me.user && (me.user.role === 'finance_admin' || me.user.role === 'finance_viewer')) db.tasks.forEach((t) => remember('tasks', String(t.id), t));
    connect();
    window.addEventListener('online', () => { push(); reconnect(0); });
    return me.user;
  }

  function changes() {
    const out = [];
    KINDS.forEach((kind) => {
      const seen = new Set();
      items(kind).forEach(([id, x]) => {
        seen.add(id);
        const now = JSON.stringify(x), was = synced[kind].get(id);
        if (now !== was) out.push({ kind, id, base: was ? JSON.parse(was) : undefined, data: JSON.parse(now) });
      });
      synced[kind].forEach((_, id) => { if (!seen.has(id)) out.push({ kind, id, del: true }); });
    });
    return out;
  }

  async function push() {
    savePrefs();
    if (pushing) { again = true; return; }
    const list = changes();
    if (!list.length) { if (online) setSaveState('saved'); else paintOffline(); return; }
    pushing = true;
    if (online) setSaveState('saving'); else paintOffline();
    try {
      const r = await api('POST', '/api/push', { client: clientId, changes: list });
      rev = Math.max(rev, r.rev || 0);
      const sent = new Map(list.map((c) => [c.kind + ':' + c.id, c]));
      let touched = false, refused = 0;
      (r.results || []).forEach((res) => {
        const key = res.kind + ':' + res.id, mine = sent.get(key);
        if (res.refused && res.kind !== 'meta') refused++;
        if (res.deleted) { remember(res.kind, res.id, null); if (localOf(res.kind, res.id) && (res.refused || res.hidden || !(mine && mine.del))) { setLocal(res.kind, res.id, null); touched = true; } return; }
        remember(res.kind, res.id, res.data);
        // Keep anything typed while this save was on its way, on top of the server's merged version
        const local = localOf(res.kind, res.id);
        const next = res.refused || !mine || mine.del ? res.data : merge3(mine.data, local ? JSON.parse(JSON.stringify(local)) : null, res.data);
        if (!deepEqual(local && JSON.parse(JSON.stringify(local)), next)) { setLocal(res.kind, res.id, next); touched = true; }
      });
      setOnline(true);
      if (refused) toast('Some changes weren’t saved — your role doesn’t allow them');
      if (touched) refresh();
      setSaveState('saved');
    } catch (e) {
      if (e.auth) return signedOut(e);
      setOnline(false); paintOffline();
      clearTimeout(retryTimer);
      retryTimer = setTimeout(push, 5000);
    } finally {
      pushing = false;
      if (again) { again = false; push(); }
    }
  }

  // Someone else changed something
  function applyRemote(list) {
    let touched = false, notif = false;
    list.forEach((ch) => {
      const kind = ch.kind, id = String(ch.id);
      if (!synced[kind]) return;
      const was = synced[kind].get(id);
      const local = localOf(kind, id);
      const localJSON = local ? JSON.stringify(local) : null;
      const remote = ch.deleted ? null : ch.data;
      remember(kind, id, remote);
      if (remote == null) { if (local) { setLocal(kind, id, null); touched = true; } return; }
      // If I have unsaved edits to the same item, merge them on top
      const next = local && was && localJSON !== was ? merge3(JSON.parse(was), JSON.parse(localJSON), remote) : remote;
      if (localJSON !== JSON.stringify(next)) { setLocal(kind, id, next); touched = true; if (kind === 'notifications') notif = true; }
    });
    if (touched) { refresh(); setTimeout(() => Announce.check(), 300); }
    if (notif) deliverPending();
    if (changes().length) persist(400);
  }

  // Redraw without disturbing whoever is typing: the open task waits until they click away
  let detailDirty = false;
  function refresh() {
    if (!currentUserId || !db) return;
    const a = document.activeElement;
    const typing = a && $('#detail') && $('#detail').contains(a) && (a.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName));
    const editingList = a && !$('#detail').contains(a) && (a.isContentEditable || /^(INPUT|TEXTAREA)$/.test(a.tagName));
    if (editingList) { renderSidebar(); detailDirty = true; return; }
    render({ keepDetail: typing });
    detailDirty = typing;
  }
  document.addEventListener('focusout', () => setTimeout(() => {
    if (!detailDirty || !db || !currentUserId) return;
    const a = document.activeElement;
    if (a && (a.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName))) return;
    detailDirty = false;
    render({ keepDetail: false });
  }, 50));

  let lastHeard = Date.now(), downSince = 0;
  function connect() {
    if (es) es.close();
    lastHeard = Date.now();
    es = new EventSource(`/api/events?since=${rev}&client=${encodeURIComponent(clientId)}`);
    ['hello', 'changes', 'version', 'resync', 'ping', 'appicon'].forEach((ev) => es.addEventListener(ev, () => { lastHeard = Date.now(); }));
    es.addEventListener('hello', (e) => { setOnline(true); const m = JSON.parse(e.data); checkVersion(m.version); if (m.appIcon) AppIcon.sync(m.appIcon); if (changes().length) push(); });
    es.addEventListener('appicon', (e) => { AppIcon.sync(JSON.parse(e.data)); if (ui.view === 'profile') renderContent(); });
    es.addEventListener('changes', (e) => {
      const m = JSON.parse(e.data);
      if (m.rev > rev) rev = m.rev;
      if (m.client === clientId) return;          // my own save, already applied
      applyRemote(m.changes || []);
    });
    es.addEventListener('version', (e) => checkVersion(JSON.parse(e.data).version));
    es.addEventListener('occasion', (e) => { try { Cal.confirmed(JSON.parse(e.data).changed || []); } catch (err) { /* ignore */ } });
    es.addEventListener('resync', () => resync());
    es.onerror = () => { setOnline(false); reconnect(3000); };
  }
  // What this person may see has changed (e.g. a freelancer was given another project): reload everything
  async function resync() {
    try {
      await push();
      const snap = await api('GET', '/api/snapshot');
      rev = snap.rev;
      KINDS.forEach((k) => { synced[k].clear(); });
      const data = snap.data;
      KINDS.forEach((k) => { if (k === 'meta') remember('meta', 'main', sharedMeta(data.meta)); else (data[k] || []).forEach((x) => remember(k, String(x.id), x)); });
      const prefs = db.meta.prefs;
      const next = normalize(JSON.parse(JSON.stringify({ ...data, meta: { ...(data.meta || {}), prefs } })));
      Object.keys(next).forEach((k) => { db[k] = next[k]; });
      if (ui.projectId && !proj(ui.projectId)) { ui.view = 'home'; ui.projectId = null; }
      if (ui.taskId && !task(ui.taskId)) ui.taskId = null;
      refresh();
    } catch (e) { reconnect(3000); }
  }
  function reconnect(ms) { if (es) { es.close(); es = null; } clearTimeout(retryTimer); retryTimer = setTimeout(() => { connect(); }, ms); }
  // Coming back to the app (window restored, Mac woke up, internet back): reconnect straight away
  function wake() {
    if (!currentUserId || document.hidden) return;
    if (!online || !es || es.readyState === 2 || Date.now() - lastHeard > 70000) reconnect(0);
    else if (changes().length) push();
  }
  document.addEventListener('visibilitychange', wake);
  window.addEventListener('focus', wake);
  window.addEventListener('online', wake);
  window.addEventListener('pageshow', wake);
  // Heartbeat: the server says hello every 25 s; if it goes quiet (e.g. after sleep), reconnect
  setInterval(() => { if (es && !document.hidden && Date.now() - lastHeard > 70000) reconnect(0); if (!online && !document.hidden) paintOffline(); }, 5000);
  function paintOffline() {
    // only call it "Offline" after a real wait while someone is looking; before that it's "Reconnecting…"
    setSaveState(downSince && Date.now() - downSince > 15000 ? 'offline' : 'reconnecting');
  }
  function setOnline(v) {
    if (online === v) return;
    online = v;
    downSince = v ? 0 : Date.now();
    if (v) setSaveState(changes().length ? 'saving' : 'saved');
    else if (!document.hidden) paintOffline();
  }
  function checkVersion(v) {
    if (!v) return;
    if (!version) { version = v; return; }
    if (v !== version && typeof showUpdateBanner === 'function') showUpdateBanner(v);
  }
  function signedOut(e) {
    if (es) es.close();
    if (e.expired) { location.reload(); return; }
    document.body.innerHTML = `<div class="fatal" style="margin:20vh auto;max-width:420px;text-align:center"><h2>${esc(e.status === 403 ? 'No access' : 'Signed out')}</h2><p>${esc(e.message)}</p><button class="btn primary" onclick="location.reload()">Sign in again</button></div>`;
  }
  return { start, push, savePrefs, get online() { return online; }, get version() { return version; }, clientId };
})();

/* ================= Persistence ================= */
let saveTimer = null, saving = false, saveAgain = false, readOnly = false;

function setSaveState(state, detail) {
  const dot = $('#save-dot'), label = $('#save-label');
  if (!dot) return;
  dot.className = 'save-dot ' + (state === 'saved' ? 'ok' : state === 'saving' ? 'busy' : state === 'error' || state === 'offline' ? 'err' : '');
  if (Host.isServer) {
    label.textContent = state === 'saving' ? 'Syncing…' : state === 'reconnecting' ? 'Reconnecting…' : state === 'offline' ? 'Offline — changes will sync' : state === 'error' ? 'Not synced — ' + (detail || 'error') : `Synced · ${location.host}`;
    label.parentElement.title = state === 'offline' ? 'Can’t reach the office server. Your changes are kept and sent when the connection is back.' : 'Everything is saved on the office server';
    return;
  }
  label.textContent = state === 'saving' ? 'Saving…' : state === 'error' ? 'Not saved — ' + (detail || 'error') : (Host.isNative ? 'Saved · E11 Console Data' : 'Preview mode (browser)');
  label.parentElement.title = dataDir ? 'Data folder: ' + dataDir + '\nClick to show in Finder' : '';
}

function persist(delay = 250) {
  if (readOnly) return;
  clearTimeout(saveTimer);
  setSaveState('saving');
  saveTimer = setTimeout(doSave, delay);
}
async function doSave() {
  if (Host.isServer) { saveTimer = null; return Sync.push(); }
  if (saving) { saveAgain = true; return; }
  saving = true;
  try {
    db.meta.updatedAt = nowISO();
    await Host.call('save', { data: JSON.stringify(db, null, 1) });
    setSaveState('saved');
  } catch (e) {
    setSaveState('error', e.message);
    toast('Could not save: ' + e.message);
  }
  saving = false;
  if (saveAgain) { saveAgain = false; doSave(); }
}
window.addEventListener('beforeunload', () => { if (saveTimer) { clearTimeout(saveTimer); doSave(); } });
// In the browser, a file dropped outside a drop area must not open in place of the app
['dragover', 'drop'].forEach((ev) => window.addEventListener(ev, (e) => { if (e.dataTransfer && [...(e.dataTransfer.types || [])].includes('Files') && !e.defaultPrevented) e.preventDefault(); }));

/* commit: save + re-render. opts.keepDetail avoids re-rendering the detail pane while typing in it */
function commit(opts = {}) {
  persist(opts.delay);
  render(opts);
}

/* ================= Rendering ================= */
function render(opts = {}) {
  renderSidebar();
  renderTitle();
  renderContent();
  if (!opts.keepDetail) renderDetail();
  else refreshDetailMeta();
}

function openTasksCount() {
  return topTasks().filter((t) => !t.done).length;
}

let lastBadge = -1;
function updateAppBadge() {
  if (!Host.isServer || !currentUserId) return;
  const n = myNotifs().filter((x) => !x.read).length;
  if (n === lastBadge) return;
  lastBadge = n;
  Host.call('badge', { n }).catch(() => {});
}
function renderSidebar() {
  updateAppBadge();
  { const add = document.querySelector('.nav-heading [data-action="new-project"]'); if (add) add.style.display = isAdmin() ? '' : 'none'; }   // only Admins add clients
  if (typeof Season !== 'undefined') { const u = currentUserId && db && me(); Season.sync(u ? !!(u.prefs || {}).seasonOff : undefined); }
  $$('.nav-item[data-nav]').forEach((a) => a.classList.toggle('active', !ui.search && (ui.view === a.dataset.nav || (a.dataset.nav === 'clients' && ui.view === 'client'))));
  Fin.paintNav();
  { const cc = $('#clients-count'); if (cc) cc.textContent = (db.clients || []).length ? String(db.clients.length) : ''; }
  { const cn = $('#nav-calendar'); if (cn) cn.style.display = Cal.canSee() ? '' : 'none'; }
  { const tn = $('#nav-trash'); if (tn) { tn.style.display = isManager() ? '' : 'none'; $('#trash-count').textContent = trashList().length ? String(trashList().length) : ''; } }
  const mt = Work.home().filter((t) => Work.homeOpen(t) && t.due && dayDiff(t.due) <= 0).length;
  $('#mytasks-count').textContent = mt ? String(mt) : '';
  const D = Work.day();
  const td = D.tasks.filter((t) => D.open(t) && t.due && dayDiff(t.due) === 0).length;
  $('#today-count').textContent = td ? String(td) : '';
  { const dn = $('.nav-item[data-nav="today"]'); if (dn && dn.lastChild && dn.childNodes[1]) dn.childNodes[1].nodeValue = Work.dayTitle(); }
  const unread = myNotifs().filter((n) => !n.read).length;
  const ib = $('#inbox-count');
  if (ib) { ib.textContent = unread ? String(unread > 99 ? '99+' : unread) : ''; ib.classList.toggle('hot', !!unread); }
  const rn = $('#nav-reviews');
  if (rn) { rn.style.display = isCD() ? '' : 'none'; const k = isCD() ? activeReviews().length : 0; const rc = $('#reviews-count'); rc.textContent = k ? String(k) : ''; rc.classList.toggle('hot', !!k); }
  renderMeChip();
  if (typeof Phone !== 'undefined') Phone.chrome();
  $('.create-btn').style.display = can('createTask') ? '' : 'none';
  const list = db.projects.filter((x) => !x.inactive).sort(byOrder);   // inactive clients leave the sidebar
  $('#project-list').innerHTML = list.length ? list.map((p) => {
    const open = db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length;
    const active = !ui.search && ui.view === 'project' && ui.projectId === p.id;
    return `<a class="nav-item ${active ? 'active' : ''}" data-project="${p.id}" title="${esc(p.name)}">
      ${clientOfProject(p) && clientOfProject(p).logo ? `<span class="nav-clogo">${clientLogoHTML(clientOfProject(p), 16)}</span>` : `<span class="dot" style="background:${p.color}"></span>`}<span class="name">${esc(p.name)}</span>
      <span class="count p">${open || ''}</span>
      ${isAdmin() ? `<button class="icon-btn sm more" data-action="project-menu" data-id="${p.id}" title="Client options">${icon('more')}</button>` : ''}
    </a>`;
  }).join('') : isAdmin() ? `<div class="nav-item ph" data-action="new-project" style="font-size:12.5px">${icon('plus')} Add your first client</div>` : '';
}

function renderTitle() {
  const el = $('#title-area');
  if (typeof Phone !== 'undefined' && Phone.on) { el.innerHTML = ''; return; }
  if (Fin.owns(ui.view)) { el.innerHTML = Fin.title(); return; }
  if (Claims.owns(ui.view)) { el.innerHTML = Claims.title(); return; }
  if (Cal.owns(ui.view)) { el.innerHTML = Cal.title(); return; }
  if (ClientList.owns(ui.view)) { el.innerHTML = ClientList.title(); return; }
  if (ui.search) { el.innerHTML = `<div class="page-title">Search</div>`; return; }
  if (ui.view === 'home') { el.innerHTML = `<div class="page-title">Home</div>`; return; }
  if (ui.view === 'inbox') { el.innerHTML = `<div class="page-icon" style="background:#2b2650;color:#c9c0ff">${icon('inbox')}</div><div class="page-title">Inbox</div>`; return; }
  if (ui.view === 'reviews') { el.innerHTML = `<div class="page-icon" style="background:#3b1f2c;color:#ff8fc0">${icon('shield')}</div><div class="page-title">Review Requests</div>${cdActing() ? '<span class="cd-badge">Acting CD</span>' : ''}`; return; }
  if (ui.view === 'team') { el.innerHTML = `<div class="page-icon" style="background:#173b33;color:#7fe0d7">${icon('users')}</div><div class="page-title">Team members</div>`; return; }
  if (ui.view === 'profile') { el.innerHTML = `<div class="page-icon" style="background:#3a2a1a;color:#ffc675">${icon('user')}</div><div class="page-title">My profile</div>`; return; }
  if (ui.view === 'trash') { el.innerHTML = `<div class="page-icon" style="background:#3b1f22;color:#ff8a8a">${icon('trash')}</div><div class="page-title">Trash</div>`; return; }
  if (ui.view === 'updates') { el.innerHTML = `<div class="page-icon ca-icon">${icon('download')}</div><div class="page-title">App updates</div>`; return; }
  if (ui.view === 'clients' || ui.view === 'client') {
    const c = ui.view === 'client' ? clientById(ui.clientId) : null;
    if (ui.view === 'client' && !c) { ui.view = 'clients'; return renderTitle(); }
    const f = c && c.folders.find((x) => x.id === ui.folderId);
    el.innerHTML = `<div class="page-icon ca-icon">${icon('assets')}</div>${c
      ? `<a class="page-title crumb-link" data-nav="clients">Client Assets</a><span class="crumb-sep">/</span>${f ? `<a class="page-title crumb-link" data-action="open-client" data-id="${c.id}">${esc(c.name)}</a><span class="crumb-sep">/</span><div class="page-title">${esc(f.name)}</div>` : `<div class="page-title">${esc(c.name)}</div>`}`
      : '<div class="page-title">Client Assets</div>'}`;
    return;
  }
  if (ui.view === 'today') {
    el.innerHTML = `<div class="page-icon" style="background:#3b2f14;color:#f9be33">${icon('sun')}</div><div class="page-title">${Work.dayTitle()}</div>`;
    return;
  }
  if (ui.view === 'mytasks') {
    el.innerHTML = `<div class="page-icon" style="background:#2a3b66;color:#c9d7ff">${icon('check-circle')}</div><div class="page-title">My Tasks</div>`;
    return;
  }
  const p = proj(ui.projectId);
  if (!p) { ui.view = 'home'; return renderTitle(); }
  el.innerHTML = `<div class="page-icon" style="background:${p.color}">${esc(initials(p.name))}</div>
    <div class="page-title" data-action="rename-project" data-id="${p.id}" ${isAdmin() ? 'title="Double-click to rename"' : ''}>${esc(p.name)}</div>
    ${isAdmin() ? `<button class="icon-btn" data-action="project-menu" data-id="${p.id}" title="Client options">${icon('chev')}</button>` : ''}
    ${clientOfProject(p) ? `<button class="proj-client" data-action="open-client" data-id="${p.clientId}" title="Open ${esc(clientOfProject(p).name)} brand assets">${clientLogoHTML(clientOfProject(p), 20)}<span>${esc(clientOfProject(p).name)} assets</span>${icon('chev-right')}</button>` : ''}
    <div class="tabs">
      <button class="tab ${p.view === 'list' ? 'active' : ''}" data-action="set-view" data-v="list">${icon('list')}List</button>
      <button class="tab ${p.view === 'board' ? 'active' : ''}" data-action="set-view" data-v="board">${icon('board')}Board</button>
    </div>`;
}

function renderContent() {
  const c = $('#content');
  const scroll = { top: c.scrollTop, left: (c.querySelector('.board') || {}).scrollLeft || 0 };
  if (typeof Phone !== 'undefined' && Phone.renderContent(c)) { c.scrollTop = scroll.top; return; }
  if (Fin.owns(ui.view)) { Fin.render(c); c.scrollTop = scroll.top; return; }
  if (Claims.owns(ui.view)) { Claims.render(c); return; }
  if (Cal.owns(ui.view)) { if (!Cal.canSee()) { ui.view = 'home'; return renderContent(); } Cal.render(c); if (typeof Phone !== 'undefined') Phone.decorate(c); c.scrollTop = scroll.top; return; }
  if (ClientList.owns(ui.view)) { ClientList.render(c); c.scrollTop = scroll.top; return; }
  if (ui.search) c.innerHTML = viewSearch();
  else if (ui.view === 'home') c.innerHTML = viewHome();
  else if (ui.view === 'mytasks') c.innerHTML = viewMyTasks();
  else if (ui.view === 'today') c.innerHTML = viewMyDay();
  else if (ui.view === 'inbox') c.innerHTML = viewInbox();
  else if (ui.view === 'team') { c.innerHTML = viewTeam(); if (Host.isServer && can('manageUsers')) api('GET', '/api/cloudflare').then(paintCfStatus).catch(() => {}); }
  else if (ui.view === 'reviews') { c.innerHTML = viewReviews(); hydrateThumbs(c); }
  else if (ui.view === 'profile') c.innerHTML = viewProfile();
  else if (ui.view === 'updates') c.innerHTML = viewUpdates();
  else if (ui.view === 'trash') c.innerHTML = viewTrash();
  else if (ui.view === 'clients') { c.innerHTML = viewClients(); migrateClientLogos(); }
  else if (ui.view === 'client') {
    const cl = clientById(ui.clientId);
    const f = cl && cl.folders.find((x) => x.id === ui.folderId);
    if (!cl) { ui.view = 'clients'; c.innerHTML = viewClients(); }
    else c.innerHTML = f ? viewClientFolder(cl, f) : viewClient(cl);
    hydrateThumbs(c);
  }
  else {
    const p = proj(ui.projectId);
    c.innerHTML = p.view === 'board' ? viewBoard(p) : viewList(p);
  }
  if (typeof Phone !== 'undefined') Phone.decorate(c);
  c.scrollTop = scroll.top;
  const b = c.querySelector('.board');
  if (b) b.scrollLeft = scroll.left;
}

/* ---------- Pieces ---------- */
const checkbox = (t) => (t.done || canComplete(t)
  ? `<button class="check ${t.done ? 'done' : ''}" data-action="toggle" data-id="${t.id}" title="${t.done ? 'Mark incomplete' : 'Mark complete'}">${icon('check')}</button>`
  : '');

function taskMetaIcons(t) {
  const subs = subtasksOf(t.id);
  let h = '';
  if (subs.length) h += `<span class="meta" title="Subtasks">${subs.filter((s) => s.done).length}/${subs.length}${icon('sub')}</span>`;
  if (t.comments.length) h += `<span class="meta" title="Comments">${t.comments.length}${icon('chat')}</span>`;
  const nFiles = shownAtts(t).length + t.comments.reduce((n, c) => n + (c.attachments || []).length, 0);
  if (nFiles) h += `<span class="meta" title="Files">${nFiles}${icon('clip')}</span>`;
  return h;
}

function projChip(t) {
  const p = proj(t.projectId);
  return p ? `<span class="proj-chip"><i style="background:${p.color}"></i>${esc(p.name)}</span>` : `<span class="proj-chip ph">My Tasks</span>`;
}

function highlight(text) {
  const s = esc(text);
  if (!ui.search) return s;
  const q = ui.search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return q ? s.replace(new RegExp('(' + esc(q) + ')', 'ig'), '<mark>$1</mark>') : s;
}

function taskRow(t, o = {}) {
  const parent = o.showParent && t.parentId ? task(t.parentId) : null;
  const st = statusInfo(t);
  const nameCell = `<div class="cell name"><span class="grip">${o.drag ? icon('grip') : ''}</span>${statusIcon(t)}${parent ? `<span class="parent-ref">${esc(parent.title || 'Untitled')} ›</span>` : ''}<span class="title">${t.title ? (o.mark ? sMark(t.title, o.mark) : highlight(t.title)) : '<span class="ph">Untitled task</span>'}</span>${taskMetaIcons(t)}${t.cdStatus && !t.done ? cdChip(t) : ''}<span class="row-actions">${checkbox(t)}${can('deleteTask') ? `<button class="icon-btn sm row-del" data-action="delete-task" data-id="${t.id}" title="Delete task">${icon('trash')}</button>` : ''}</span>${avatarStack(t.assignees, 20, 3, t)}</div>`;
  const due = `<div class="cell"><span class="due ${dueClass(t)}">${fmtDue(t.due)}</span></div>`;
  const prio = `<div class="cell">${prioFlag(prioOf(t), true)}</div>`;
  const cells = o.showProject
    ? nameCell + `<div class="cell">${statusPill(t)}</div><div class="cell">${projChip(t)}</div>` + due + prio
    : nameCell + due + prio + `<div class="cell tags-cell">${t.tags.map(tagChip).join('')}</div>`;
  return `<div class="row task-row ${t.done ? 'is-done' : ''} ${isUrgent(t) && !t.done ? 'is-urgent' : ''} ${ui.taskId === t.id ? 'is-selected' : ''}" data-task="${t.id}" ${o.drag ? 'draggable="true"' : ''}>${cells}</div>`;
}

function listHead(showProject) {
  return showProject
    ? `<div class="list-head"><div>Name</div><div>Status</div><div>Client</div><div>Due date</div><div>Priority</div></div>`
    : `<div class="list-head"><div>Name</div><div>Due date</div><div>Priority</div><div>Tags</div></div>`;
}

function prioFlag(p, compact) {
  p = normPrio(p);
  if (p === 'urgent') return `<span class="prio-flag urgent">${icon('flag')}<span>Urgent</span></span>`;
  if (typeof p === 'number') return `<span class="prio-flag num"><span class="prio-num">${p}</span>${compact ? '' : `<span>Priority ${p}</span>`}</span>`;
  return compact ? '' : `<span class="prio-flag none">${icon('flag')}<span>No priority</span></span>`;
}

/* ---------- List view ---------- */
function viewList(p) {
  const showDone = !!ui.showDone[p.id];
  const sections = p.sections.map((s) => {
    const all = db.tasks.filter((t) => t.projectId === p.id && t.sectionId === s.id && !t.parentId).sort((a, b) => urgentFirst(a, b) || byOrder(a, b));
    const tasks = showDone ? all : all.filter((t) => !t.done);
    const collapsed = ui.collapsed[s.id];
    return `<div class="section ${collapsed ? 'collapsed' : ''}" data-section="${s.id}">
      <div class="section-head" data-drop-section="${s.id}">
        <button class="icon-btn sm chev" data-action="collapse" data-id="${s.id}">${icon('chev')}</button>
        <span class="sname" data-action="rename-section" data-id="${s.id}" ${isAdmin() ? 'title="Double-click to rename"' : ''}>${sectionPill(s)}</span>
        <span class="scount">${all.filter((t) => !t.done).length || ''}</span>
        ${isAdmin() ? `<button class="icon-btn sm more" data-action="section-menu" data-id="${s.id}">${icon('more')}</button>` : ''}
      </div>
      <div class="section-body">
        ${tasks.map((t) => taskRow(t, { drag: true })).join('')}
        ${can('createTask') ? `<div class="add-row" data-action="add-task-inline" data-section="${s.id}">${icon('plus')}<span>Add task…</span></div>` : ''}
      </div>
    </div>`;
  }).join('');
  const total = db.tasks.filter((t) => t.projectId === p.id && !t.parentId);
  const doneN = total.filter((t) => t.done).length;
  return `<div class="list-wrap">
    <div class="list-toolbar">
      ${can('createTask') ? `<button class="btn primary" data-action="add-task-top">${icon('plus')}Add task</button>` : ''}
      <div class="spacer"></div>
      <button class="btn ghost" data-action="toggle-show-done">${icon('check-circle')}${showDone ? 'Hide' : 'Show'} completed${doneN ? ` (${doneN})` : ''}</button>
    </div>
    ${listHead(false)}
    ${sections}
    ${isAdmin() ? `<div class="add-section" data-action="add-section">${icon('plus')}<span>Add status</span></div>` : ''}
  </div>`;
}

/* ---------- Board view ---------- */
function card(t) {
  const subs = subtasksOf(t.id);
 return `<div class="card ${t.done ? 'is-done' : ''} ${isUrgent(t) && !t.done ? 'is-urgent' : ''} ${ui.taskId === t.id ? 'is-selected' : ''}" data-task="${t.id}" draggable="true">
    <div class="card-top">${checkbox(t)}<div class="title">${t.title ? esc(t.title) : '<span class="ph">Untitled task</span>'}</div></div>
    ${t.tags.length ? `<div class="card-tags">${t.tags.map(tagChip).join('')}</div>` : ''}
    ${t.due || subs.length || t.comments.length || shownAtts(t).length || prioOf(t) !== 'none' || (t.assignees || []).length || t.cdStatus ? `<div class="card-foot">${t.due ? `<span class="due ${dueClass(t)}">${icon('cal')}${fmtDue(t.due)}</span>` : ''}${prioFlag(prioOf(t), true)}${t.cdStatus && !t.done ? cdChip(t) : ''}<span class="spacer"></span>${taskMetaIcons(t)}${avatarStack(t.assignees, 20, 3, t)}</div>` : ''}
  </div>`;
}

function viewBoard(p) {
  const showDone = !!ui.showDone[p.id];
  const cols = p.sections.map((s) => {
 const all = db.tasks.filter((t) => t.projectId === p.id && t.sectionId === s.id && !t.parentId).sort((a, b) => urgentFirst(a, b) || byOrder(a, b));
    const tasks = showDone ? all : all.filter((t) => !t.done);
    return `<div class="col" data-col="${s.id}" style="--col:${s.color}">
      <div class="col-head">
        <span class="sname" data-action="rename-section" data-id="${s.id}" ${isAdmin() ? 'title="Double-click to rename"' : ''}>${sectionPill(s)}</span>
        <span class="scount">${all.filter((t) => !t.done).length || ''}</span>
        <span class="spacer"></span>
        ${can('createTask') ? `<button class="icon-btn sm" data-action="add-card" data-section="${s.id}" title="Add task">${icon('plus')}</button>` : ''}
        ${isAdmin() ? `<button class="icon-btn sm" data-action="section-menu" data-id="${s.id}">${icon('more')}</button>` : ''}
      </div>
      <div class="col-body">${tasks.map(card).join('')}</div>
      ${can('createTask') ? `<div class="col-add" data-action="add-card" data-section="${s.id}">${icon('plus')}Add task</div>` : ''}
    </div>`;
  }).join('');
  return `<div class="board">${cols}${isAdmin() ? `<div class="add-col" data-action="add-section">${icon('plus')}<span>Add status</span></div>` : ''}
    <div style="flex:none;display:flex;align-items:flex-start;padding-top:6px"><button class="btn ghost" data-action="toggle-show-done">${showDone ? 'Hide' : 'Show'} completed</button></div></div>`;
}

/* ---------- My Tasks ---------- */
const byDayThenPrio = (a, b) => (a.due || '9999').localeCompare(b.due || '9999') || byPrio(a, b) || a.createdAt.localeCompare(b.createdAt);
function myTaskGroups() {
  if (ui.myTasksTab === 'done') {
    const cutoff = Date.now() - AUTO_DELETE_DAYS * 86400000;
    return [{ id: 'done', name: 'Recently completed', color: '#3ddc97', empty: 'No completed tasks in the last 30 days',
      tasks: myTop().filter((t) => myDoneAt(t) && new Date(myDoneAt(t)).getTime() > cutoff).sort((a, b) => myDoneAt(b).localeCompare(myDoneAt(a))) }];
  }
  const open = myTop().filter(myOpen);
  return [
    { id: 'overdue', name: 'Overdue', color: '#e5484d', tasks: open.filter((t) => t.due && dayDiff(t.due) < 0).sort(byDayThenPrio) },
    { id: 'today', name: 'Today', color: '#4c9aff', empty: 'Nothing due today 🎉', tasks: open.filter((t) => t.due && dayDiff(t.due) === 0).sort(byDayThenPrio) },
    { id: 'upcoming', name: 'Upcoming', color: '#a875ff', tasks: open.filter((t) => t.due && dayDiff(t.due) > 0).sort(byDayThenPrio) },
    { id: 'nodate', name: 'No due date', color: '#87909e', tasks: open.filter((t) => !t.due).sort((a, b) => byPrio(a, b) || a.createdAt.localeCompare(b.createdAt)) },
  ];
}

function mwDue(t) {
  if (!t.due) return '';
  const d = dayDiff(t.due);
  if (!t.done && d < 0) return d === -1 ? 'Yesterday' : `${-d} days ago`;
  return fmtDue(t.due);
}
function mwRow(t) {
  const p = proj(t.projectId);
  const loc = [p ? p.name : 'My Tasks', statusInfo(t).name].join(' / ');
  return `<div class="mw-row task-row ${t.done ? 'is-done' : ''} ${isUrgent(t) && !t.done ? 'is-urgent' : ''} ${ui.taskId === t.id ? 'is-selected' : ''}" data-task="${t.id}">
    ${statusIcon(t)}
    <span class="title">${t.title ? highlight(t.title) : '<span class="ph">Untitled task</span>'}</span>${needsOwner(t) ? '<span class="na-chip" title="Assign someone to this task">No assignee</span>' : ''}
    <span class="mw-loc">• ${p ? `<i style="background:${p.color}"></i>` : ''}${esc(loc)}</span>
    ${t.cdStatus && !t.done ? cdChip(t) : ''}
    <span class="spacer"></span>
    <span class="row-actions">${checkbox(t)}${can('deleteTask') ? `<button class="icon-btn sm row-del" data-action="delete-task" data-id="${t.id}" title="Delete task">${icon('trash')}</button>` : ''}</span>
    ${prioFlag(prioOf(t), true)}
    ${avatarStack(t.assignees, 20, 3, t)}
    <span class="mw-due due ${myOpen(t) ? dueClass(t) : ''}">${myDoneAt(t) ? (t.done ? '' : 'My part · ') + esc(fmtDay(ymd(new Date(myDoneAt(t))))) : esc(mwDue(t))}</span>
  </div>`;
}
function viewMyTasks() {
  const tab = ui.myTasksTab === 'done' ? 'done' : 'todo';
  const L = Work.list(), isOpen = Work.openOf, doneAt = Work.doneAtOf;
  const open = L.filter(isOpen);
  const cutoff = Date.now() - AUTO_DELETE_DAYS * 86400000;
  const doneList = L.filter((t) => doneAt(t) && new Date(doneAt(t)).getTime() > cutoff).sort((a, b) => doneAt(b).localeCompare(doneAt(a)));
  const groups = tab === 'done'
    ? [{ id: 'mw-done', name: 'Recently completed', tasks: doneList, empty: 'Tasks you complete in the last 30 days show here.' }]
    : [
      { id: 'mw-today', name: 'Today', tasks: open.filter((t) => t.due && dayDiff(t.due) === 0).sort(byDayThenPrio), empty: Work.active() ? 'No tasks match these filters.' : Work.personal() ? 'Tasks and reminders assigned to you will show here.' : 'Tasks you create will show here.' },
      { id: 'mw-overdue', name: 'Overdue', tasks: open.filter((t) => t.due && dayDiff(t.due) < 0).sort(byDayThenPrio) },
      { id: 'mw-next', name: 'Next', tasks: open.filter((t) => t.due && dayDiff(t.due) > 0).sort(byDayThenPrio) },
      { id: 'mw-none', name: 'Unscheduled', tasks: open.filter((t) => !t.due).sort((a, b) => byPrio(a, b) || a.createdAt.localeCompare(b.createdAt)) },
    ];
  const body = groups.map((g) => {
    const collapsed = ui.mytasksCollapsed[g.id] != null ? ui.mytasksCollapsed[g.id] : (g.id === 'mw-next' || g.id === 'mw-none') && g.tasks.length > 12;
    return `<div class="mw-group ${collapsed ? 'collapsed' : ''}">
      <button class="mw-ghead" data-action="mw-group" data-id="${g.id}"><span class="mw-caret">${icon('chev')}</span>${g.name}<span class="mw-n">${g.tasks.length}</span></button>
      <div class="mw-gbody">${g.tasks.map(mwRow).join('') || (g.empty ? `<div class="mw-empty">${g.empty}</div>` : '')}</div>
    </div>`;
  }).join('');
  return `<div class="mywork">
    <div class="mw-card">
      <div class="mw-title">My Work</div>
      <div class="mw-tabs">
        <button class="mw-tab ${tab === 'todo' ? 'on' : ''}" data-action="mt-tab" data-tab="todo">To Do</button>
        <button class="mw-tab ${tab === 'done' ? 'on' : ''}" data-action="mt-tab" data-tab="done">Done</button>
      </div>
      ${workFilterBar()}
      ${tab === 'todo' && can('createTask') ? `<div class="quick-add mw-add">${icon('plus')}<input id="quick-add" placeholder="Add a task… (due today)" autocomplete="off"><span class="hint">Enter</span></div>` : ''}
      ${body}
    </div>
  </div>`;
}

/* ---------- My Day ---------- */
function viewMyDay() {
  const today = todayStr();
  const day = ui.day || today;
  const isToday = day === today;
  const dt = parseYmd(day);
  // week strip (Mon–Sun) around the selected day
  const wd = (dt.getDay() + 6) % 7;
  const start = addDays(day, -wd);
  const D = Work.day();
  const strip = Array.from({ length: 7 }, (_, i) => {
    const d = addDays(start, i);
    const n = D.tasks.filter((t) => D.open(t) && t.due === d).length;
    const dd = parseYmd(d);
    return `<button class="ds-day ${d === day ? 'on' : ''} ${d === today ? 'today' : ''}" data-action="pick-day" data-day="${d}">
      <span class="ds-wd">${dd.toLocaleDateString('en-US', { weekday: 'short' })}</span>
      <span class="ds-n">${dd.getDate()}</span>
      <span class="ds-dots">${n ? `<i></i>${n > 1 ? '<i></i>' : ''}${n > 2 ? '<i></i>' : ''}` : ''}</span>
    </button>`;
  }).join('');

  const open = D.tasks.filter(D.open);
  const overdue = isToday ? open.filter((t) => t.due && t.due < today) : [];
  const dueDay = open.filter((t) => t.due === day);
  const inProgress = open.filter((t) => t.start && t.start <= day && t.due && t.due > day);
  const doneDay = D.doneTasks.filter((t) => D.doneAt(t) && ymd(new Date(D.doneAt(t))) === day);
  const sortP = (a, b) => byPrio(a, b) || (a.due || '').localeCompare(b.due || '') || a.createdAt.localeCompare(b.createdAt);
  [overdue, dueDay, inProgress].forEach((g) => g.sort(sortP));
  const planned = dueDay.length + overdue.length + doneDay.length;
  const pct = planned ? Math.round((doneDay.length / planned) * 100) : 0;

  const group = (id, name, color, tasks, emptyText) => {
    if (!tasks.length && !emptyText) return '';
    const collapsed = ui.mytasksCollapsed['md-' + id];
    return `<div class="section ${collapsed ? 'collapsed' : ''}">
      <div class="section-head">
        <button class="icon-btn sm chev" data-action="collapse-mt" data-id="md-${id}">${icon('chev')}</button>
        <span class="status-pill" style="background:${color};color:${textOn(color)}">${name}</span><span class="scount">${tasks.length || ''}</span>
      </div>
      <div class="section-body">${tasks.map((t) => taskRow(t, { showProject: true, showParent: true })).join('') || `<div class="add-row" style="cursor:default">${emptyText}</div>`}</div>
    </div>`;
  };

  const title = isToday ? 'Today' : dayDiff(day) === 1 ? 'Tomorrow' : dayDiff(day) === -1 ? 'Yesterday' : dt.toLocaleDateString('en-US', { weekday: 'long' });
  return `<div class="list-wrap with-proj myday">
    <div class="md-head">
      <div>
        <div class="md-title">${title}</div>
        <div class="md-sub">${dt.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}</div>
      </div>
      <div class="md-nav">
        <button class="icon-btn" data-action="shift-day" data-n="-1" title="Previous day">${icon('chev-left')}</button>
        <button class="btn ghost" data-action="pick-day" data-day="${today}" ${isToday ? 'disabled' : ''}>Today</button>
        <button class="icon-btn" data-action="shift-day" data-n="1" title="Next day">${icon('chev-right')}</button>
      </div>
    </div>
    <div class="day-strip">
      <button class="icon-btn" data-action="shift-day" data-n="-7" title="Previous week">${icon('chev-left')}</button>
      ${strip}
      <button class="icon-btn" data-action="shift-day" data-n="7" title="Next week">${icon('chev-right')}</button>
    </div>
    <div class="md-progress">
      <div class="md-ring" style="--p:${pct}"><span>${pct}%</span></div>
      <div class="md-stats">
        <div><b>${doneDay.length}</b> of <b>${planned}</b> planned tasks done${isToday ? ' today' : ''}</div>
        <div class="md-bar"><i style="width:${pct}%"></i></div>
      </div>
      <div class="md-chips">
        ${isToday ? `<span class="md-chip red">${overdue.length} overdue</span>` : ''}
        <span class="md-chip">${dueDay.length} due</span>
        <span class="md-chip green">${doneDay.length} completed</span>
      </div>
    </div>
    ${can('createTask') ? `<div class="quick-add">${icon('plus')}<input id="quick-add" data-day="${day}" placeholder="Add a task for ${isToday ? 'today' : esc(dt.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' }))}…" autocomplete="off"><span class="hint">Enter to add</span></div>` : ''}
    ${listHead(true)}
    ${group('overdue', 'Overdue', '#e5484d', overdue)}
    ${group('due', isToday ? 'Due today' : 'Due this day', '#4c9aff', dueDay, isToday ? 'Nothing else due today 🎉' : 'Nothing due this day')}
    ${group('ongoing', 'In progress (started, due later)', '#a875ff', inProgress)}
    ${group('done', 'Completed', '#3ddc97', doneDay)}
  </div>`;
}

/* ---------- Home ---------- */
// Home page: see home.js
function viewHome() { return typeof Home !== 'undefined' ? Home.view() : ''; }

/* ---------- Search ---------- */
/* ================= Smart search (tasks and Client Assets) =================
   Every word must match somewhere. Each word may match a whole word, the start of a word, part of a
   word, or — if nothing closer exists — a word that is one or two letters off (typos like "frod",
   "offorad"). Task fields count differently: a hit in the title beats one in a comment. */
const sNorm = (s) => String(s || '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/[’'`]/g, '');
const sWords = (s) => sNorm(s).split(/[^\p{L}\p{N}]+/u).filter(Boolean);
// Edit distance with swapped letters counted as one (frod → ford). Gives up beyond `max`.
function editDist(a, b, max) {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  const prev2 = new Array(b.length + 1), prev = new Array(b.length + 1), cur = new Array(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    cur[0] = i; let best = cur[0];
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
      cur[j] = v; if (v < best) best = v;
    }
    if (best > max) return max + 1;
    for (let j = 0; j <= b.length; j++) { prev2[j] = prev[j]; prev[j] = cur[j]; }
  }
  return prev[b.length];
}
const typoLimit = (w) => (w.length >= 8 ? 2 : w.length >= 4 ? 1 : 0);
// For one search word: which words in the vocabulary it matches, and how well (1 = exact)
function termMatches(term, vocab) {
  const out = new Map();
  let close = false;
  vocab.forEach((w) => {
    if (w === term) { out.set(w, 1); close = true; } else if (w.startsWith(term)) { out.set(w, 0.85); close = true; } else if (term.length >= 3 && w.includes(term)) { out.set(w, 0.55); close = true; }
  });
  let fuzzy = null;
  if (!close && typoLimit(term)) {
    let bestD = 99;
    vocab.forEach((w) => {
      const lim = typoLimit(term);
      // compare with the whole word and with its start (so "offro" still reaches "offroad")
      const d = Math.min(editDist(term, w, lim), w.length > term.length ? editDist(term, w.slice(0, term.length), lim) : 99);
      if (d <= lim) { out.set(w, d === 1 ? 0.45 : 0.3); if (d < bestD || (d === bestD && fuzzy && w.length < fuzzy.length)) { bestD = d; fuzzy = w; } }
    });
  }
  return { words: out, fuzzy };
}

// Handy words that describe a task rather than appear in it
const TS_FLAGS = {
  overdue: (t) => myOpenAny(t) && t.due && dayDiff(t.due) < 0,
  today: (t) => !t.done && t.due && dayDiff(t.due) === 0,
  tomorrow: (t) => !t.done && t.due && dayDiff(t.due) === 1,
  urgent: (t) => isUrgent(t),
  done: (t) => t.done, completed: (t) => t.done,
  open: (t) => !t.done,
  mine: (t) => isMine(t), me: (t) => isMine(t),
  unassigned: (t) => !(t.assignees || []).length,
  review: (t) => t.cdStatus === 'review', approved: (t) => t.cdStatus === 'approved',
};
const myOpenAny = (t) => !t.done;

// What can be searched in a task, and how much each part counts
function taskFields(t) {
  const p = proj(t.projectId);
  const cl = p ? clientOfProject(p) : null;
  const sec = sectionOf(t);
  const people = (ids) => (ids || []).map((id) => fullName(userById(id))).join(' ');
  const f = [
    { k: 'title', w: 10, text: t.title },
    { k: 'project', w: 6, text: p ? p.name : 'My Tasks' },
    { k: 'client', w: 5, text: cl ? cl.name : '' },
    { k: 'tag', w: 5, text: (t.tags || []).join(' ') },
    { k: 'people', w: 4, text: people(t.assignees) },
    { k: 'status', w: 3, text: sec ? sec.name : '' },
    { k: 'creator', w: 2, text: people([t.createdBy]) },
    { k: 'desc', w: 2.5, text: t.notesHtml ? notifPlainHTML(t.notesHtml) : t.notes },
    { k: 'check', w: 1.5, text: (t.checklist || []).map((c) => c.text).join(' · ') },
    { k: 'sub', w: 2, text: subtasksOf(t.id).map((s) => s.title).join(' · ') },
  ];
  (t.comments || []).forEach((c) => f.push({ k: 'comment', w: 1.2, text: c.text || notifPlainHTML(c.html), who: c.authorId, cid: c.id, reply: !!c.parentId }));
  if (t.parentId) { const par = task(t.parentId); if (par) f.push({ k: 'parent', w: 3, text: par.title }); }
  return f;
}

function taskSearch(query, { limit = 200 } = {}) {
  const terms = sWords(query);
  if (!terms.length) return { tasks: [], projects: [], fixed: [] };
  const docs = db.tasks.map((t) => {
    const fields = taskFields(t);
    const words = new Map(); // word -> best weight
    fields.forEach((fl, i) => sWords(fl.text).forEach((w) => { if (!words.has(w) || words.get(w).w < fl.w) words.set(w, { w: fl.w, i }); }));
    Object.keys(TS_FLAGS).forEach((k) => { if (TS_FLAGS[k](t)) words.set('#' + k, { w: 4, i: -1 }); });
    return { t, fields, words };
  });
  const vocab = new Set();
  docs.forEach((d) => d.words.forEach((_, w) => { if (w[0] !== '#') vocab.add(w); }));
  const fixed = [];
  const per = terms.map((term) => {
    const m = termMatches(term, vocab);
    if (m.fuzzy && !m.words.has(term)) fixed.push({ from: term, to: m.fuzzy });
    return { term, words: m.words, flag: TS_FLAGS[term] ? '#' + term : null };
  });
  const tasks = [];
  docs.forEach((d) => {
    let score = 0; const hits = [];
    for (const pt of per) {
      let best = 0, bestWord = null, bestField = -1;
      if (pt.flag && d.words.has(pt.flag)) { best = 4; bestWord = pt.term; }
      pt.words.forEach((q, w) => { const e = d.words.get(w); if (e && e.w * q > best) { best = e.w * q; bestWord = w; bestField = e.i; } });
      if (!best) return; // every word has to match somewhere
      score += best; hits.push({ word: bestWord, field: bestField });
    }
    if (!d.t.done) score += 1.5;
    if (d.t.parentId) score -= 1;
    tasks.push({ t: d.t, score, hits, fields: d.fields });
  });
  tasks.sort((a, b) => b.score - a.score || (a.t.done - b.t.done) || b.t.updatedAt.localeCompare(a.t.updatedAt));
  // projects whose name (or client) matches every word
  const projects = db.projects.filter((p) => {
    const ws = new Set(sWords(`${p.name} ${(clientOfProject(p) || {}).name || ''}`));
    return per.every((pt) => [...pt.words.keys()].some((w) => ws.has(w)));
  });
  return { tasks: tasks.slice(0, limit), total: tasks.length, projects, fixed, terms: per };
}
// Highlight the words that matched (including typo-corrected ones)
function sMark(text, r) {
  const src = String(text || '');
  const want = new Set();
  (r.terms || []).forEach((pt) => pt.words.forEach((_, w) => want.add(w)));
  return src.split(/([\p{L}\p{N}]+)/u).map((part) => {
    const n = sNorm(part);
    return n && [...want].some((w) => n === w || (w.length >= 3 && n.startsWith(w)) || w.startsWith(n) && n.length >= 3) ? `<mark>${esc(part)}</mark>` : esc(part);
  }).join('');
}
// One line saying where a result matched, when it wasn't the title
const FIELD_LABEL = { project: 'Client', client: 'Client Assets', tag: 'Tag', people: 'Assigned to', status: 'Status', creator: 'Created by', desc: 'Description', check: 'Checklist', sub: 'Subtask', parent: 'Part of' };
function searchWhy(hit, r) {
  const fi = hit.hits.map((h) => h.field).filter((i) => i > 0)
    .sort((a, b) => hit.fields[b].w - hit.fields[a].w)[0];
  if (fi == null) return '';
  const fl = hit.fields[fi];
  const words = hit.hits.filter((h) => h.field === fi).map((h) => h.word);
  let text = String(fl.text || '').replace(/\s+/g, ' ');
  // a window of text around the first matching word
  const low = sNorm(text); const at = Math.max(0, low.indexOf(words[0] || ''));
  if (text.length > 90) { const s = Math.max(0, at - 30); text = (s ? '…' : '') + text.slice(s, s + 90) + (s + 90 < text.length ? '…' : ''); }
  const label = fl.k === 'comment' ? `${fl.reply ? 'Reply' : 'Comment'} by ${esc(fl.who === currentUserId ? 'you' : firstName(fl.who))}` : FIELD_LABEL[fl.k] || '';
  return `<span class="sr-why"><b>${label}:</b> ${sMark(text, r)}</span>`;
}
function searchFixedNote(r) {
  return r.fixed.length ? `<div class="sr-fixed">${icon('search')}Showing results for ${r.fixed.map((f) => `<b>${esc(f.to)}</b>`).join(', ')} <span>(you typed ${r.fixed.map((f) => `“${esc(f.from)}”`).join(', ')})</span></div>` : '';
}

function viewSearch() {
  const r = taskSearch(ui.search);
  const projects = r.projects.length ? `<div class="sr-projects">${r.projects.map((p) => `<button class="sr-proj" data-action="go-project" data-id="${p.id}"><span class="page-icon sm" style="background:${p.color}">${esc(initials(p.name))}</span><span><b>${sMark(p.name, r)}</b><small>${db.tasks.filter((t) => t.projectId === p.id && !t.parentId && !t.done).length} open tasks${clientOfProject(p) ? ' · ' + esc(clientOfProject(p).name) : ''}</small></span>${icon('chev-right')}</button>`).join('')}</div>` : '';
  const rows = r.tasks.map((h) => {
    const why = searchWhy(h, r);
    return `<div class="sr-hit">${taskRow(h.t, { showProject: true, showParent: true, mark: r })}${why ? `<div class="sr-why-row">${why}</div>` : ''}</div>`;
  }).join('');
  return `<div class="list-wrap with-proj">
    <div class="search-results-head">${r.total || 0} task${r.total === 1 ? '' : 's'}${r.projects.length ? ` and ${r.projects.length} client${r.projects.length === 1 ? '' : 's'}` : ''} for “${esc(ui.search.trim())}”</div>
    ${searchFixedNote(r)}
    ${projects}
    ${r.tasks.length ? listHead(true) + rows : (r.projects.length ? '' : '<div class="empty"><div class="big">No matching tasks</div>Try a client name, a person, a tag — or words like “overdue”, “urgent” or “mine”.</div>')}
  </div>`;
}

/* ================= Task page (detail) ================= */
const REACTIONS = ['👍', '✅', '🎉', '❤️', '👀', '🙏'];
const draftKey = (t, cid) => (cid ? t.id + ':' + cid : t.id);

function fmtShort(iso) {
  const d = new Date(iso);
  const sameYear = d.getFullYear() === new Date().getFullYear();
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', ...(sameYear ? {} : { year: 'numeric' }) }) + ' at ' +
    d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }).toLowerCase();
}

// The one composer at the bottom of the comments panel. It posts a comment, or a reply when
// a thread is open or "Reply" was clicked on a comment.
function composer(t, cid) {
  const onPhone = typeof Phone !== 'undefined' && Phone.on;
  const key = draftKey(t, cid);
  const files = ui.commentFiles[key] || [];
  const target = cid && t.comments.find((c) => c.id === cid);
  const inThread = !!cid && ui.thread === cid;
  const banner = target && !inThread
    ? `<div class="cb-replying">${icon('reply')}<span>Replying to <b>${esc(target.authorId === currentUserId ? 'your comment' : firstName(target.authorId))}</b>${target.text ? ` <i>“${esc(trunc(target.text, 70))}”</i>` : ''}</span><button class="icon-btn xs" data-action="cancel-reply" title="Cancel reply (Esc)">${icon('x')}</button></div>` : '';
  const ph = inThread ? 'Reply to this thread… Type @ to mention someone' : cid ? 'Write a reply… Type @ to mention someone' : 'Write a comment… Type @ to mention someone';
  return `<div class="composer ${cid ? 'reply' : ''}">
    ${banner}
    <div class="rt-editor" contenteditable="true" id="d-comment" data-draft-key="${key}" ${cid ? `data-reply-to="${cid}"` : ''} data-placeholder="${ph}">${ui.commentDraft[key] || ''}</div>
    ${files.length ? `<div class="cb-files">${files.map((a) => `<span class="cb-chip ${a.linked ? 'linked' : ''}">${isImage(a) && Host.isNative ? `<img src="${imgUrl(a, 160)}" alt="">` : icon('clip')}<span>${esc(a.name)}</span><button data-action="unstage-file" data-key="${key}" data-id="${a.id}" title="Remove">${icon('x')}</button></span>`).join('')}</div>` : ''}
    <div class="cb-foot">
      <button class="icon-btn sm" data-action="attach-comment" ${cid ? `data-reply="${cid}"` : ''} title="Attach files" aria-label="Attach files">${icon(onPhone ? 'plus' : 'clip')}</button>
      ${fmtToolbar()}
      <span class="spacer"></span>${clipPasteBtn('comment')}<span class="hint">⌘ Enter</span>
      <button class="btn primary sm" data-action="add-comment" ${cid ? `data-reply="${cid}"` : ''} title="⌘ Enter" aria-label="${cid ? 'Reply' : 'Comment'}">${onPhone ? icon('send') : cid ? 'Reply' : 'Comment'}</button>
    </div>
  </div>`;
}

// Compact time for phones: 5m, 2h, then Oct 19 (with the year if it's not this year)
function shortWhen(iso) {
  const d = new Date(iso), mins = Math.round((Date.now() - d) / 60000);
  if (mins < 1) return 'now';
  if (mins < 60) return mins + 'm';
  if (mins < 24 * 60) return Math.round(mins / 60) + 'h';
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', ...(d.getFullYear() === new Date().getFullYear() ? {} : { year: 'numeric' }) });
}
function commentHTML(t, c, isReply) {
  const editing = ui.editingComment === c.id;
  const reacts = Object.entries(c.reactions || {}).filter(([, n]) => n);
  return `<div class="cm ${isReply ? 'cm-reply' : ''}" data-comment="${c.id}">
    <span class="cm-av-wrap" data-user-card="${esc(c.authorId)}">${avatarHTML(c.authorId, 28, 'cm-av')}</span>
    <div class="cm-body">
      <div class="cm-meta"><b data-user-card="${esc(c.authorId)}">${esc(c.authorId === currentUserId ? 'You' : userName(c.authorId))}</b><span class="cm-when" title="${fmtDateTime(c.at)}">${typeof Phone !== 'undefined' && Phone.on ? shortWhen(c.at) : fmtShort(c.at)}</span>${c.editedAt ? '<span class="cm-edited">(edited)</span>' : ''}
        <span class="cm-tools">
          <button class="icon-btn sm" data-action="react-menu" data-id="${c.id}" title="React">${icon('smile')}</button>
          ${isReply || ui.thread === c.id ? '' : `<button class="icon-btn sm" data-action="reply" data-id="${c.id}" title="Reply">${icon('reply')}</button>`}
          ${c.authorId === currentUserId || isAdm(me()) ? `<button class="icon-btn sm" data-action="comment-menu" data-id="${c.id}" title="More">${icon('more')}</button>` : ''}
        </span>
      </div>
      ${editing
        ? `<div class="composer edit"><div class="rt-editor" contenteditable="true" id="edit-comment" data-placeholder="Edit comment…">${c.html ? sanitizeHTML(c.html) : esc(c.text).replace(/\n/g, '<br>')}</div><div class="cb-foot">${fmtToolbar()}<span class="spacer"></span><button class="btn ghost sm" data-action="cancel-edit">Cancel</button><button class="btn primary sm" data-action="save-edit" data-id="${c.id}">Save</button></div></div>`
        : (c.html ? `<div class="cm-text rich">${sanitizeHTML(c.html, true)}</div>` : c.text ? `<div class="cm-text">${linkify(esc(c.text))}</div>` : '')}
      ${(c.attachments || []).length ? `<div class="c-files">${c.attachments.map((a) => attPreview(a, 'comment')).join('')}</div>` : ''}
      ${reacts.length ? `<div class="cm-reacts">${reacts.map(([e, n]) => `<button class="react on" data-action="react" data-id="${c.id}" data-emoji="${e}">${e}<span>${n}</span></button>`).join('')}</div>` : ''}
    </div>
  </div>`;
}

const FMT_BUTTONS = [
  ['bold', '<b>B</b>', 'Bold (⌘B)'], ['italic', '<i>I</i>', 'Italic (⌘I)'], ['underline', '<u>U</u>', 'Underline (⌘U)'],
  ['strikeThrough', '<s>S</s>', 'Strikethrough'], ['code', '&lt;/&gt;', 'Code'], ['insertUnorderedList', '•', 'Bulleted list'],
  ['insertOrderedList', '1.', 'Numbered list'], ['quote', '❝', 'Quote'], ['link', '🔗', 'Link'],
];
function fmtToolbar() {
  return `<span class="rt-tools">${FMT_BUTTONS.map(([f, label, tip]) => `<button class="rt-btn" data-action="fmt" data-fmt="${f}" title="${tip}" tabindex="-1">${label}</button>`).join('')}</span>`;
}
// Keep the editor selection when clicking toolbar buttons
document.addEventListener('mousedown', (e) => { if (e.target.closest('.rt-btn')) e.preventDefault(); });
async function applyFormat(fmt, btn) {
  const comp = btn.closest('.composer');
  const ed = comp && comp.querySelector('.rt-editor');
  if (!ed) return;
  if (document.activeElement !== ed) { ed.focus(); placeCaretAtEnd(ed); }
  const sel = window.getSelection();
  if (fmt === 'link') {
    const range = sel.rangeCount ? sel.getRangeAt(0).cloneRange() : null;
    const res = await dialog({ title: 'Add link', input: { label: 'Web address', placeholder: 'https://…' }, okText: 'Add link' });
    if (!res || !res.value) return;
    let url = res.value.trim();
    if (!/^https?:\/\//i.test(url)) url = 'https://' + url;
    ed.focus();
    if (range) { sel.removeAllRanges(); sel.addRange(range); }
    if (sel.isCollapsed) document.execCommand('insertHTML', false, `<a href="${esc(url)}">${esc(url)}</a>`);
    else document.execCommand('createLink', false, url);
  } else if (fmt === 'code') {
    const txt = sel.toString();
    document.execCommand('insertHTML', false, `<code>${esc(txt || 'code')}</code>&nbsp;`);
  } else if (fmt === 'quote') {
    document.execCommand('formatBlock', false, 'blockquote');
  } else {
    document.execCommand(fmt, false, null);
  }
  ed.dispatchEvent(new Event('input', { bubbles: true }));
}
function placeCaretAtEnd(el) {
  const r = document.createRange(); r.selectNodeContents(el); r.collapse(false);
  const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
}
// Allow only simple formatting tags; display mode turns links into safe in-app links
const RT_TAGS = { B: 'b', STRONG: 'b', I: 'i', EM: 'i', U: 'u', S: 's', STRIKE: 's', DEL: 's', CODE: 'code', PRE: 'pre', UL: 'ul', OL: 'ol', LI: 'li', BLOCKQUOTE: 'blockquote', BR: 'br', DIV: 'div', P: 'div', A: 'a' };
function sanitizeHTML(html, display) {
  const tpl = document.createElement('template');
  tpl.innerHTML = String(html || '');
  const walk = (node, inLink) => {
    let out = '';
    node.childNodes.forEach((n) => {
      if (n.nodeType === 3) { out += display && !inLink ? linkify(esc(n.nodeValue)) : esc(n.nodeValue); return; }
      if (n.nodeType !== 1) return;
      if (n.tagName === 'SPAN' && n.classList.contains('mention') && n.dataset.user) {
        const id = n.dataset.user;
        const label = '@' + (userById(id) ? fullName(userById(id)) : n.textContent.replace(/^@/, ''));
        out += display ? `<span class="mention ${id === currentUserId ? 'me' : ''}" data-user="${esc(id)}">${esc(label)}</span>`
          : `<span class="mention" data-user="${esc(id)}" contenteditable="false">${esc(label)}</span>`;
        return;
      }
      if (n.tagName === 'SPAN' && n.classList.contains('fileref') && n.dataset.fpath) {
        out += fileRefHTML({ path: n.dataset.fpath, name: n.dataset.fname || n.dataset.fpath.split('/').pop(), size: +n.dataset.fsize || 0, thumb: n.dataset.fthumb || null }, display);
        return;
      }
      const tag = RT_TAGS[n.tagName];
      if (!tag) { out += walk(n, inLink); return; }
      if (tag === 'br') { out += '<br>'; return; }
      if (tag === 'a') {
        const href = n.getAttribute('href') || '';
        if (!/^https?:\/\//i.test(href)) { out += walk(n, inLink); return; }
        out += display ? `<a href="#" data-action="open-url" data-url="${esc(href)}">${walk(n, true)}</a>` : `<a href="${esc(href)}">${walk(n, true)}</a>`;
        return;
      }
      out += `<${tag}>${walk(n, inLink)}</${tag}>`;
    });
    return out;
  };
  return walk(tpl.content, false);
}
const editorEmpty = (ed) => !ed.textContent.trim() && !ed.querySelector('img, li');

function linkify(html) {
  return html.replace(/(https?:\/\/[^\s<]+)/g, '<a href="#" data-action="open-url" data-url="$1">$1</a>');
}

const repliesOf = (t, cid) => t.comments.filter((r) => r.parentId === cid).sort((a, b) => a.at.localeCompare(b.at));
// Main feed: each first comment with a "N replies" link that opens the thread page
function threadHTML(t, c) {
  const replies = repliesOf(t, c.id);
  const people = [...new Set(replies.map((r) => r.authorId).reverse())].slice(0, 3);
  return `<div class="thread ${ui.replyTo === c.id ? 'is-target' : ''}" data-thread="${c.id}">
    ${commentHTML(t, c, false)}
    ${replies.length ? `<button class="thread-open" data-action="open-thread" data-id="${c.id}" title="Open this thread">
      <span class="to-avs">${people.map((u) => avatarHTML(u, 20)).join('')}</span>
      <b>${replies.length} ${replies.length === 1 ? 'reply' : 'replies'}</b><span class="to-last">Last reply ${timeAgo(replies[replies.length - 1].at)}</span>${icon('chev-right')}</button>` : ''}
  </div>`;
}
// Thread page: the first comment, then every reply in order
function threadPageHTML(t, c) {
  const replies = repliesOf(t, c.id);
  return `<div class="thread-root">${commentHTML(t, c, false)}</div>
    <div class="thread-sep"><span>${replies.length ? `${replies.length} ${replies.length === 1 ? 'reply' : 'replies'}` : 'No replies yet'}</span></div>
    ${replies.map((r) => commentHTML(t, r, true)).join('')}`;
}

function activityHTML(t) {
  const items = [];
  if (ui.activityFilter !== 'comments') (t.activity || []).forEach((a) => items.push({ at: a.at, html: `<div class="act-line"><span class="act-dot"></span><span><b>${esc(userName(a.actor))}</b> ${/^changed the <b>description<\/b>/.test(a.text) ? 'changed the description' : a.actor === currentUserId ? a.text.replace(/\btheir part\b/, 'your part') : a.text}</span><span class="act-time">${fmtShort(a.at)}</span></div>` }));
  t.comments.filter((c) => !c.parentId).forEach((c) => items.push({ at: c.at, html: threadHTML(t, c) }));
  items.sort((a, b) => a.at.localeCompare(b.at));
  return items.map((i) => i.html).join('') || '<div class="empty" style="padding:30px 10px">No comments yet</div>';
}

function renderDetail() {
  const pane = $('#detail');
  const t = ui.taskId ? task(ui.taskId) : null;
  if (!t) {
    ui.taskId = null;
    if (typeof Phone !== 'undefined') Phone.chrome();
    pane.classList.remove('open', 'anim', 'side');
    pane.setAttribute('aria-hidden', 'true');
    pane.innerHTML = '';
    delete pane.dataset.shown;
    return;
  }
  // keep scroll positions when re-rendering the same task
  const prev = pane.dataset.shown === t.id ? { main: ($('.tm-main', pane) || {}).scrollTop || 0, feed: ($('.tm-feed', pane) || {}).scrollTop, focus: document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.draftKey : null } : null;

  const parent = t.parentId ? task(t.parentId) : null;
  const p = proj(t.projectId);
  const sec = sectionOf(t);
  const subs = subtasksOf(t.id);
  const subsDone = subs.filter((x) => x.done).length;
  const cl = t.checklist || [];
  const clDone = cl.filter((x) => x.done).length;
  const navIdx = ui.navIds.indexOf(t.id);
  const projectOptions = ['<option value="">No client (My Tasks)</option>']
    .concat(db.projects.filter((x) => !x.inactive || x.id === t.projectId).sort(byOrder).map((x) => `<option value="${x.id}" ${x.id === t.projectId ? 'selected' : ''}>${esc(x.name)}</option>`)).join('');
  const nComments = t.comments.length;
  const nTop = t.comments.filter((c) => !c.parentId).length;
  if (ui.thread && !t.comments.some((c) => c.id === ui.thread && !c.parentId)) ui.thread = null;
  const thread = ui.thread ? t.comments.find((c) => c.id === ui.thread) : null;
  const phone = (typeof Phone !== 'undefined' && Phone.on);
  if (phone) Phone.chrome();
  const mode = phone ? 'side' : ui.detailMode === 'side' || ui.detailMode === 'full' ? ui.detailMode : 'modal';
  const side = mode === 'side';
  const railTabs = side && !phone;
  const sideTab = ui.sideTab === 'comments' ? 'comments' : 'details';
  // Sidebar view on a computer: Comments and Activity are separate icons in the side rail (no Comments | All switch)

  const keepMedia = {};
  if (pane.dataset.shown === t.id) $$('[data-media-key]', pane).forEach((m) => { keepMedia[m.dataset.mediaKey] = m; });
  const fresh = !pane.classList.contains('open');
  pane.dataset.shown = t.id;
  pane.innerHTML = `
  <div class="tm-backdrop" data-action="close-detail"></div>
  <div class="tm" role="dialog">
    ${phone ? Phone.taskHead(t, sideTab, nComments) : ''}
    <div class="tm-top">
      <div class="tm-crumbs">
        ${p ? `<a class="crumb" data-action="go-project" data-id="${p.id}"><i style="background:${p.color}"></i>${esc(p.name)}</a>${sec ? `<span class="crumb-sep">/</span><span class="crumb plain">${esc(sec.name)}</span>` : ''}` : `<span class="crumb plain">${icon('check-circle')}My Tasks</span>`}
        ${clientOfProject(p) ? `<button class="tm-client" data-action="open-client" data-id="${p.clientId}" title="Logos, guidelines and fonts for ${esc(clientOfProject(p).name)}">${clientLogoHTML(clientOfProject(p), 16)}<span>${esc(clientOfProject(p).name)} assets</span></button>` : ''}
        ${parent ? `<span class="crumb-sep">/</span><a class="crumb" data-action="open-task" data-id="${parent.id}">${icon('sub')}${esc(parent.title || 'Untitled task')}</a>` : ''}
        <span class="crumb-sep tm-tt">/</span><span class="crumb plain tm-tt">${esc(t.title || 'Untitled task')}</span>
      </div>
      <div class="tm-actions">
        <button class="icon-btn" data-action="nav-task" data-n="-1" ${navIdx > 0 ? '' : 'disabled'} title="Previous task">${icon('chev-left')}</button>
        <button class="icon-btn" data-action="nav-task" data-n="1" ${navIdx >= 0 && navIdx < ui.navIds.length - 1 ? '' : 'disabled'} title="Next task">${icon('chev-right')}</button>
        <span class="tm-divider"></span>
        ${phone ? '' : `<button class="icon-btn" data-action="share-task" data-id="${t.id}" title="Copy link to this task">${icon('link')}</button>`}
        <button class="icon-btn" data-action="attach" title="Attach files">${icon('clip')}</button>
        ${can('deleteTask') ? `<button class="icon-btn" data-action="delete-task" data-id="${t.id}" title="Delete task">${icon('trash')}</button>` : ''}
        <div class="disp-wrap">
          <button class="icon-btn" data-action="disp-toggle" title="Switch layout">${icon(side ? 'panel' : mode === 'full' ? 'layout' : 'modal')}</button>
          <div class="disp-menu lay-menu">
            ${[['modal', 'Modal'], ['full', 'Full screen'], ['side', 'Sidebar']].map(([m, l]) => `<button class="lay-opt ${mode === m ? 'on' : ''}" data-action="detail-mode" data-mode="${m}"><span class="lay-pic lp-${m}"><i class="dots"><b></b><b></b><b></b></i><i class="win"></i></span><span>${l}</span></button>`).join('')}
          </div>
        </div>
        <button class="icon-btn" data-action="close-detail" title="Close window (Esc)">${icon('x')}</button>
      </div>
    </div>
    <div class="tm-body">
      <div class="tm-main">
        <div class="tm-type"><span class="type-pill">${icon(parent ? 'sub' : 'check-circle')}${parent ? 'Subtask' : 'Task'}</span>${t.done ? `<span class="tm-id">Completed ${timeAgo(t.completedAt)} · auto-deletes in ${daysUntilAutoDelete(t)} day${daysUntilAutoDelete(t) === 1 ? '' : 's'}</span>` : ''}${creatorChip(t)}</div>
        <textarea class="d-title" id="d-title" rows="1" placeholder="Task name" spellcheck="true" ${can('editTitle') ? '' : 'readonly'}>${esc(t.title)}</textarea>

        <div class="props">
          <div class="prop prop-status"><label>${icon('check-circle')}Status</label><div class="pv">
            <span class="st-split" style="--sc:${statusInfo(t).color};--sf:${textOn(statusInfo(t).color)}"><button class="st-main" data-action="status-menu">${esc(statusInfo(t).name)}</button><button class="st-next" data-action="status-next" title="Move to next status">${icon('chev-right')}</button></span>
            ${cdArea(t)}
            ${t.done || canComplete(t) ? `<button class="done-btn ${t.done ? 'on' : ''}" data-action="toggle" data-id="${t.id}" title="${t.done ? 'Reopen' : 'Mark complete'}">${icon('check')}</button>` : ''}
          </div></div>
          <div class="prop prop-asg"><label>${icon('user')}Assignees</label><div class="pv">${(t.assignees || []).length
            ? `<div class="asg-stack ${can('assign') ? '' : 'ro'}">${t.assignees.map((id) => `<span class="asg-av ${partDone(t, id) ? 'pdone' : ''}" ${can('assign') ? 'data-action="assign-menu"' : ''} title="${esc(fullName(userById(id)))}${partDone(t, id) ? ' — part done' : ''}">${avatarHTML(id, 28)}${partDone(t, id) ? `<i class="pd-tick">${icon('check')}</i>` : ''}${can('assign') ? `<button class="asg-x" data-action="unassign" data-id="${id}" title="Remove ${esc(fullName(userById(id)))}">${icon('x')}</button>` : ''}</span>`).join('')}</div>`
            : (can('assign') ? `<button class="pv-empty" data-action="assign-menu">Empty</button>` : '<span class="pv-empty">Empty</span>')}${can('assign') && (t.assignees || []).length ? `<button class="asg-add" data-action="assign-menu" title="Assign people">${icon('plus')}</button>` : ''}</div></div>
          ${partsRow(t)}
          ${cdReviewRow(t)}
          <div class="prop prop-dates"><label>${icon('cal')}Dates</label><div class="pv">
            <span class="date-chip ${t.start ? 'set' : 'is-empty'}">${icon('cal')}<span class="date-lbl">${t.start ? esc(fmtDay(t.start)) : 'Start'}</span><input type="date" class="date-in" id="d-start" value="${t.start || ''}" title="Start date"></span>${t.start ? `<button class="icon-btn xs" data-action="clear-start" title="Remove start date">${icon('x')}</button>` : ''}
            <span class="date-arrow">${icon('arrow')}</span>
            <span class="date-chip ${t.due ? 'set' : 'is-empty'} ${dueClass(t)}">${icon('cal')}<span class="date-lbl">${t.due ? esc(mwDue(t)) : 'Due'}</span><input type="date" class="date-in" id="d-due" value="${t.due || ''}" title="Due date${t.due ? ': ' + esc(fmtDay(t.due)) : ''}"></span>${t.due ? `<button class="icon-btn xs" data-action="clear-due" title="Remove due date">${icon('x')}</button>` : `<button class="btn ghost xs" data-action="due-today">Today</button>`}
          </div></div>
          <div class="prop prop-prio"><label>${icon('flag')}Priority</label><div class="pv">${(t.assignees || []).length > 1 || ((t.assignees || []).length === 1 && t.assignees[0] !== currentUserId)
            ? `<div class="prio-people">${t.assignees.map((id) => `<div class="pp-row ${id === currentUserId ? 'mine' : ''}">${avatarHTML(id, 20)}<span class="pp-name">${esc(id === currentUserId ? 'You' : fullName(userById(id)).split(' ')[0])}</span><button class="pv-btn" data-action="prio-menu" data-key="${id}" ${can('editPriority') ? '' : 'disabled'}>${prioOf(t, id) === 'none' ? '<span class="pv-empty">Empty</span>' : prioFlag(prioOf(t, id), true)}</button></div>`).join('')}</div>`
            : (() => { const key = (t.assignees || [])[0] || '_'; const v = key === '_' ? normPrio((t.prio || {})._) : prioOf(t, key); return `<button class="pv-btn" data-action="prio-menu" data-key="${key}" ${can('editPriority') ? '' : 'disabled'}>${v === 'none' ? '<span class="pv-empty">Empty</span>' : prioFlag(v, true)}</button>`; })()}</div></div>
          ${parent ? '' : `<div class="prop"><label>${icon('folder')}Client</label><div class="pv"><select class="field" id="d-project" ${can('editProject') ? '' : 'disabled'}>${projectOptions}</select></div></div>`}
          <div class="prop"><label>${icon('tag')}Tags</label><div class="pv"><div class="tag-editor" id="d-tags">${t.tags.map((g, i) => { const [bg, fg] = tagColor(g); return `<span class="tag" style="background:${bg};color:${fg}">${esc(g)}${can('removeTag') ? `<button data-action="remove-tag" data-i="${i}">${icon('x')}</button>` : ''}</span>`; }).join('')}<input id="d-tag-input" placeholder="${t.tags.length ? 'Add' : 'Empty'}" list="tag-suggest" autocomplete="off"></div>
            <datalist id="tag-suggest">${allTags().filter((g) => !t.tags.includes(g)).map((g) => `<option value="${esc(g)}">`).join('')}</datalist></div></div>
        </div>

        ${(() => {
          const open = !!ui.descOpen[t.id];
          const view = t.notesHtml ? sanitizeHTML(t.notesHtml, true) : t.notes ? linkify(esc(t.notes)).replace(/\n/g, '<br>') : '';
          const ro = !can('editDesc');
          if (ro && !view) return '';
          const body = open && !ro
            ? `<div class="composer desc"><div class="rt-editor d-notes" contenteditable="true" id="d-notes" data-placeholder="Add a description, links or notes… Type @ to mention someone">${t.notesHtml ? sanitizeHTML(t.notesHtml) : esc(t.notes).replace(/\n/g, '<br>')}</div><div class="cb-foot">${fmtToolbar()}<span class="spacer"></span>${clipPasteBtn('desc')}</div></div>`
            : `<div class="desc-view ${open ? 'full' : ''} ${view ? '' : 'blank'} ${ro ? 'ro' : ''}" ${ro ? '' : 'data-action="desc-open"'}>${view || `<span class="ph">${can('editDesc') ? 'Add description… Type @ to mention someone' : 'No description'}</span>`}</div>`;
          return `<div class="d-section desc-sec ${open ? 'open' : ''} ${view ? '' : 'is-empty'}">${body}
            <div class="desc-toggle-wrap"><button class="desc-toggle" data-action="desc-toggle">${icon(open ? 'chev-up' : 'chev')}${open ? 'Collapse' : 'Expand'}</button></div></div>`;
        })()}

        ${fieldsHTML(t)}

        <div class="d-section">
          <h4>${icon('sub')}Subtasks <span class="n">${subs.length ? `${subsDone}/${subs.length}` : ''}</span>${subs.length ? `<span class="mini-bar"><i style="width:${Math.round(subsDone / subs.length * 100)}%"></i></span>` : ''}</h4>
          <div id="d-subs">
            ${subs.map((x) => `<div class="sub-row ${x.done ? 'is-done' : ''}" data-sub="${x.id}">${checkbox(x)}
              <input class="sub-title" value="${esc(x.title)}" placeholder="Subtask name" data-sub-id="${x.id}" ${can('editTitle') ? '' : 'readonly'}>
              ${avatarStack(x.assignees, 18)}
              ${statusPill(x)}
              ${x.due ? `<span class="due ${dueClass(x)}">${fmtDue(x.due)}</span>` : ''}
              <span class="sub-actions"><button class="icon-btn sm" data-action="open-task" data-id="${x.id}" title="Open subtask">${icon('open')}</button>${can('deleteTask') ? `<button class="icon-btn sm" data-action="delete-sub" data-id="${x.id}" title="Delete subtask">${icon('trash')}</button>` : ''}</span>
            </div>`).join('')}
          </div>
          ${can('createTask') ? `<div class="sub-add">${icon('plus')}<input id="d-sub-add" placeholder="Add subtask"></div>` : ''}
        </div>

        <div class="d-section">
          <h4>${icon('checklist')}Checklist <span class="n">${cl.length ? `${clDone}/${cl.length}` : ''}</span>${cl.length ? `<span class="mini-bar"><i style="width:${Math.round(clDone / cl.length * 100)}%"></i></span>` : ''}</h4>
          ${cl.map((c) => `<div class="cl-row ${c.done ? 'is-done' : ''}">
            <button class="cl-box ${c.done ? 'on' : ''}" data-action="cl-toggle" data-id="${c.id}">${icon('check')}</button>
            <input class="cl-text" value="${esc(c.text)}" data-cl-id="${c.id}" placeholder="Checklist item">
            ${can('deleteChecklist') ? `<button class="icon-btn sm cl-del" data-action="cl-delete" data-id="${c.id}" title="Delete item">${icon('x')}</button>` : ''}
          </div>`).join('')}
          <div class="sub-add">${icon('plus')}<input id="d-cl-add" placeholder="Add checklist item"></div>
        </div>

        <div class="d-section">
          <h4>${icon('clip')}Attachments <span class="n">${shownAtts(t).length || ''}</span><span class="spacer"></span><button class="btn ghost sm" data-action="attach">${icon('plus')}Add files</button></h4>
          ${shownAtts(t).length ? `<div class="tile-grid">${shownAtts(t).map((a) => attTile(a)).join('')}</div>` : '<div class="ph" style="font-size:12.5px">No files yet. Files you attach are copied into your data folder.</div>'}
        </div>

        <div class="d-foot" id="d-foot">${detailFoot(t)}</div>
      </div>

      <aside class="tm-activity">
        ${thread ? `<div class="tm-act-head thread-head">
          <button class="icon-btn th-back" data-action="close-thread" title="Back to all comments (Esc)">${icon('chev-left')}</button>
          <span class="tm-act-title">Thread<small>${repliesOf(t, thread.id).length} ${repliesOf(t, thread.id).length === 1 ? 'reply' : 'replies'} · started by ${esc(thread.authorId === currentUserId ? 'you' : userName(thread.authorId))}</small></span>
        </div>` : `<div class="tm-act-head">
          <span class="tm-act-title">${railTabs && ui.activityFilter === 'all' ? 'Activity' : 'Comments'}<small>Created ${esc(fmtDay(ymd(new Date(t.createdAt))))}</small></span>
          ${railTabs ? '' : `<div class="seg">
            <button class="${ui.activityFilter !== 'all' ? 'on' : ''}" data-action="act-filter" data-f="comments">Comments${nTop ? ` ${nTop}` : ''}</button>
            <button class="${ui.activityFilter === 'all' ? 'on' : ''}" data-action="act-filter" data-f="all">All</button>
          </div>`}
        </div>`}
        <div class="tm-feed ${thread ? 'in-thread' : ''}">${thread ? threadPageHTML(t, thread) : activityHTML(t)}</div>
        <div class="tm-composer">${composer(t, thread ? thread.id : (ui.replyTo && t.comments.some((c) => c.id === ui.replyTo) ? ui.replyTo : null))}</div>
      </aside>
      ${side ? `<nav class="tm-rail">
        <button class="rail-btn ${sideTab === 'details' ? 'on' : ''}" data-action="side-tab" data-tab="details" title="Task">${icon('details')}</button>
        <button class="rail-btn ${sideTab === 'comments' && !(railTabs && ui.activityFilter === 'all') ? 'on' : ''}" data-action="side-tab" data-tab="comments" title="Comments">${icon('comment')}${nComments ? `<i>${nComments}</i>` : ''}</button>
        ${railTabs ? `<button class="rail-btn ${sideTab === 'comments' && ui.activityFilter === 'all' ? 'on' : ''}" data-action="side-tab" data-tab="activity" title="Activity">${icon('activity')}</button>` : ''}
      </nav>` : ''}
    </div>
  </div>`;
  pane.classList.add('open');
  pane.classList.toggle('anim', fresh);
  pane.classList.toggle('side', side);
  pane.classList.toggle('full', mode === 'full');
  pane.dataset.tab = sideTab;
  pane.setAttribute('aria-hidden', 'false');
  $$('[data-media-key]', pane).forEach((m) => { const old = keepMedia[m.dataset.mediaKey]; if (old) m.replaceWith(old); });
  hydratePreviews(pane);
  autosize($('#d-title'));
  // short descriptions don't need the Expand button
  const dv = $('.desc-view:not(.full)', pane);
  if (dv && dv.scrollHeight <= dv.clientHeight + 4) dv.closest('.desc-sec').classList.add('fits');

  $$('.composer textarea', pane).forEach(autosize);
  const feed = $('.tm-feed', pane);
  if (prev) {
    $('.tm-main', pane).scrollTop = prev.main;
    if (feed && prev.feed != null) feed.scrollTop = prev.feed;
    if (prev.focus) { const el = $(`[data-draft-key="${prev.focus}"]`, pane); if (el) { el.focus(); placeCaretAtEnd(el); } }
  } else if (feed && ui.focusComment) { const fc = ui.focusComment; ui.focusComment = null; focusCommentInFeed(fc); }
  else if (feed) stickFeedToBottom(feed);
  if (ui.focusDesc) { ui.focusDesc = false; setTimeout(() => { const d = $('#detail .desc-sec'); if (d) d.scrollIntoView({ behavior: 'smooth', block: 'center' }); }, 120); }
  hydrateThumbs(pane);
}

// Keep the activity feed scrolled to the newest item while images/videos finish loading,
// until the user scrolls up themselves.
function stickFeedToBottom(feed) {
  let stick = true;
  const toEnd = () => { if (stick) feed.scrollTop = feed.scrollHeight; };
  toEnd();
  const stop = () => { stick = false; };
  feed.addEventListener('wheel', stop, { once: true, passive: true });
  feed.addEventListener('mousedown', stop, { once: true });
  feed.addEventListener('touchstart', stop, { once: true, passive: true }); // a finger on the phone counts too
  feed.addEventListener('keydown', stop, { once: true });
  $$('img, video, iframe', feed).forEach((m) => {
    m.addEventListener('load', toEnd, { once: true });
    m.addEventListener('loadedmetadata', toEnd, { once: true });
  });
  [60, 250, 600, 1200, 2500].forEach((ms) => setTimeout(toEnd, ms));
}

// "Created by" at the top of the task: hover for their card, click to @mention them in a comment
function creatorChip(t) {
  const u = t.createdBy && userById(t.createdBy);
  if (!u) return '';
  const mine = u.id === currentUserId;
  // Phone: "by Carine · Oct 13" so it fits beside the Task chip
  return `<span class="tm-creator"><span class="cr-word">Created </span>by
    <button class="cr-chip" ${mine ? '' : 'data-action="mention-user" title="Mention them in a comment"'} data-id="${esc(u.id)}" data-user-card="${esc(u.id)}" ${mine ? 'disabled' : ''}>${avatarHTML(u.id, 20)}<b>${mine ? 'You' : `<span class="cr-full">${esc(fullName(u))}</span><span class="cr-first">${esc(firstName(u.id))}</span>`}</b>${mine ? '' : `<i class="cr-at">@</i>`}</button>
    <span class="cr-when"><span class="cr-full">${esc(timeAgo(t.createdAt))}</span><span class="cr-first">${esc(shortWhen(t.createdAt))}</span></span></span>`;
}
function mentionInComposer(uidToTag) {
  const u = userById(uidToTag);
  if (!u) return;
  if ((ui.detailMode === 'side' || (typeof Phone !== 'undefined' && Phone.on)) && ui.sideTab !== 'comments') { ui.sideTab = 'comments'; renderDetail(); }
  const ed = $('#d-comment');
  if (!ed) return;
  ed.focus();
  const sel = window.getSelection();
  if (!sel.rangeCount || !ed.contains(sel.anchorNode)) placeCaretAtEnd(ed);
  const before = ed.textContent && !/\s$/.test(ed.textContent) ? '&nbsp;' : '';
  document.execCommand('insertHTML', false, `${before}<span class="mention" data-user="${esc(u.id)}" contenteditable="false">@${esc(fullName(u))}</span>&nbsp;`);
  ed.dispatchEvent(new Event('input', { bubbles: true }));
}

/* ---- People card on hover: @mentions, comment authors, task creator ---- */
const TEAM_LABEL = { admin: 'Admin', am: 'Account Manager', production: 'Production Team', social: 'Social Team', freelancer: 'Freelancer' };
function designationOf(u) {
  if (!u) return '';
  if (u.id === cdUserId()) return cdActing() ? `Acting Creative Director · ${TEAM_LABEL[u.role] || ''}` : 'Creative Director';
  return TEAM_LABEL[u.role] || '';
}
let cardTimer = null, cardHideTimer = null, cardFor = null;
function userCardHTML(u) {
  return `<div class="ucard-top">${avatarHTML(u.id, 56)}<div class="ucard-id"><b>${esc(fullName(u))}${u.id === currentUserId ? ' <small>(you)</small>' : ''}</b><span class="ucard-role ${u.id === cdUserId() ? 'cd' : 'r-' + u.role}">${esc(designationOf(u))}</span></div></div>
    <div class="ucard-rows">
      <div>${icon('pin')}<span>${u.office ? esc(u.office) : '<i>Office not set</i>'}</span></div>
      <div>${icon('mail')}<span>${esc(u.email)}</span></div>
      ${u.active === false ? `<div class="ucard-off">${icon('lock')}<span>No longer on the team</span></div>` : ''}
    </div>`;
}
function showUserCard(anchor, id) {
  const u = userById(id);
  if (!u) return;
  let card = $('#ucard');
  if (!card) { card = document.createElement('div'); card.id = 'ucard'; card.className = 'ucard'; document.body.appendChild(card); card.addEventListener('mouseenter', () => clearTimeout(cardHideTimer)); card.addEventListener('mouseleave', hideUserCard); }
  card.innerHTML = userCardHTML(u);
  cardFor = anchor;
  const r = anchor.getBoundingClientRect();
  card.style.visibility = 'hidden'; card.classList.add('on');
  const w = card.offsetWidth, h = card.offsetHeight;
  let left = Math.min(Math.max(8, r.left + r.width / 2 - w / 2), window.innerWidth - w - 8);
  let top = r.bottom + 8;
  if (top + h > window.innerHeight - 8) top = r.top - h - 8;
  card.style.left = left + 'px'; card.style.top = Math.max(8, top) + 'px';
  card.style.visibility = '';
}
function hideUserCard() {
  clearTimeout(cardTimer);
  cardHideTimer = setTimeout(() => { const c = $('#ucard'); if (c) c.classList.remove('on'); cardFor = null; }, 120);
}
document.addEventListener('mouseover', (e) => {
  const el = e.target.closest && e.target.closest('.mention[data-user], [data-user-card]');
  if (!el) return;
  if (el === cardFor) { clearTimeout(cardHideTimer); return; }
  clearTimeout(cardTimer); clearTimeout(cardHideTimer);
  cardTimer = setTimeout(() => showUserCard(el, el.dataset.userCard || el.dataset.user), 280);
});
document.addEventListener('mouseout', (e) => {
  const el = e.target.closest && e.target.closest('.mention[data-user], [data-user-card]');
  if (!el || (e.relatedTarget && el.contains(e.relatedTarget))) return;
  hideUserCard();
});
document.addEventListener('mousedown', (e) => { if (!(e.target.closest && e.target.closest('#ucard'))) { clearTimeout(cardTimer); const c = $('#ucard'); if (c) c.classList.remove('on'); cardFor = null; } }, true);

function detailFoot(t) {
  return `Created ${fmtDateTime(t.createdAt)}${t.createdBy ? ` by ${esc(userName(t.createdBy))}` : ''}<br>Last updated ${timeAgo(t.updatedAt)}${t.completedAt ? `<br>Completed ${fmtDateTime(t.completedAt)}` : ''}`;
}
function refreshDetailMeta() {
  const t = ui.taskId && task(ui.taskId);
  const f = $('#d-foot');
  if (t && f) f.innerHTML = detailFoot(t);
}

const IMG_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp', 'tif', 'tiff', 'svg'];
const fileExt = (name) => (String(name).split('.').pop() || '').toLowerCase();
const isImage = (a) => IMG_EXT.includes(fileExt(a.name));
const fileUrl = (a) => '/__file/' + String(a.path).split('/').map(encodeURIComponent).join('/');
// A smaller copy of an image for lists, tiles and previews (made once by the server); full size stays for the viewer and downloads
const imgUrl = (a, w) => fileUrl(a) + (Host.isServer && !/\.svg$/i.test(String(a.path)) ? '?w=' + w : '');
function fileIcon(a) {
  return isImage(a) && Host.isNative
    ? `<div class="ficon thumb"><img src="${imgUrl(a, 160)}" alt="" loading="lazy"></div>`
    : `<div class="ficon">${esc((fileExt(a.name) || 'file').slice(0, 4))}</div>`;
}
const VID_EXT = ['mp4', 'mov', 'm4v', 'webm'];
const AUD_EXT = ['mp3', 'm4a', 'aac', 'wav', 'aif', 'aiff'];
const TXT_EXT = ['txt', 'md', 'csv', 'log', 'json', 'xml'];
function fileKind(a) {
  const e = fileExt(a.name);
  if (IMG_EXT.includes(e)) return 'image';
  if (VID_EXT.includes(e)) return 'video';
  if (AUD_EXT.includes(e)) return 'audio';
  if (e === 'pdf') return 'pdf';
  if (TXT_EXT.includes(e)) return 'text';
  return 'other';
}
const OFFICE_EXT = ['doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'odt', 'odp', 'ods', 'rtf'];
const OFFICE_LABEL = { ppt: 'PowerPoint', pptx: 'PowerPoint', key: 'Keynote', doc: 'Word', docx: 'Word', pages: 'Pages', xls: 'Excel', xlsx: 'Excel', numbers: 'Numbers', zip: 'Archive' };
// Thumbnail made by macOS Quick Look (cached in the data folder); placeholder until it exists
function thumbImg(a, mode) {
  if (a.thumb) return `<img class="qthumb" src="${'/__file/' + a.thumb.split('/').map(encodeURIComponent).join('/')}" alt="">`;
  const e = fileExt(a.name);
  return `<div class="thumb-ph" data-thumb-for="${a.id}" data-mode="${mode}"><span class="ext">${esc((e || 'file').slice(0, 5))}</span><small>${esc(OFFICE_LABEL[e] || 'File')}</small></div>`;
}
function attTile(a) {
  const kind = fileKind(a);
  const inner = kind === 'image' && Host.isNative ? `<img src="${imgUrl(a, 640)}" alt="" loading="lazy">` : (Host.isNative ? thumbImg(a, 'tile') : `<div class="thumb-ph"><span class="ext">${esc(fileExt(a.name) || 'file')}</span></div>`);
  return `<div class="tile" data-action="tile-open" data-id="${a.id}" title="${esc(a.name)}">
    <div class="tile-img">${inner}${kind === 'video' ? `<span class="tile-play">${icon('play')}</span>` : ''}</div>
    <div class="tile-meta"><span>${esc(a.name)}</span><small>${fmtSize(a.size)}</small></div>
    <div class="tile-actions">
      <button class="icon-btn sm" data-action="copy-att" data-id="${a.id}" title="Copy — paste into a comment or description">${icon('copy')}</button>
      <button class="icon-btn sm" data-action="quicklook" data-id="${a.id}" title="Preview">${icon('search')}</button>
      <button class="icon-btn sm" data-action="reveal-att" data-id="${a.id}" title="${FINDER_LABEL}">${icon(Host.isServer ? 'download' : 'folder')}</button>
      <button class="icon-btn sm" data-action="remove-att" data-id="${a.id}" title="Remove">${icon('trash')}</button>
    </div>
  </div>`;
}
let thumbQueue = Promise.resolve();
function hydrateThumbs(root) {
  if (!Host.isNative) return;
  $$('[data-thumb-for]', root).forEach((ph) => {
    const id = ph.dataset.thumbFor;
    const tid = ph.dataset.thumbTask || ui.taskId;
    ph.removeAttribute('data-thumb-for');
    ph.dataset.waiting = id;
    thumbQueue = thumbQueue.then(async () => {
      const t = task(tid);
      const a = ph.dataset.thumbClient ? clientFileById(id) : t && findAttachment(t, id);
      if (!a) return;
      if (!a.thumb) {
        try { const r = await Host.call('thumb', { id: a.id, path: a.path }); if (r.thumb) { a.thumb = r.thumb; persist(800); } } catch (e) { return; }
      }
      if (a.thumb) $$(`[data-waiting="${id}"]`).forEach((el) => { el.outerHTML = thumbImg(a); });
      else $$(`[data-waiting="${id}"]`).forEach((el) => el.classList.add('no-thumb'));
    });
  });
}

// Pictures and videos hold their exact space while they load (a soft shimmer fills it), so nothing below jumps.
// The size is saved when a file is uploaded; older files learn theirs the first time they load (kept on this device).
const MediaDims = (() => {
  const KEY = 'e11-media-dims';
  let cache = null;
  const seen = new Set(); // already loaded once this session: redraws show it straight away (no shimmer flicker)
  const load = () => { if (!cache) { try { cache = JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { cache = {}; } } return cache; };
  function of(a) { if (a && a.w > 0 && a.h > 0) return [a.w, a.h]; const d = a && load()[a.id]; return Array.isArray(d) ? d : null; }
  function remember(id, w, h) {
    const c = load(); c[id] = [w, h];
    const ids = Object.keys(c); if (ids.length > 3000) ids.slice(0, ids.length - 3000).forEach((k) => delete c[k]);
    try { localStorage.setItem(KEY, JSON.stringify(c)); } catch (e) { /* storage off */ }
  }
  const style = (d) => (d ? `--ar:${(d[0] / d[1]).toFixed(4)};--nw:${d[0]}px` : '');
  function frame(a, inner) { const d = of(a); return `<div class="ap-frame${d ? '' : ' nodim'}${seen.has(a.id) ? ' loaded' : ''}" style="${style(d)}" data-dim-id="${esc(a.id)}">${inner}</div>`; }
  // the moment a picture or video knows its size: show it, and remember the size if it wasn't known
  function settle(el, w, h, failed) {
    const f = el.parentElement;
    if (!f || !f.classList.contains('ap-frame')) return;
    f.classList.add('loaded'); if (failed) f.classList.add('failed'); else seen.add(f.dataset.dimId);
    if (!failed && w > 0 && h > 0 && f.classList.contains('nodim')) { remember(f.dataset.dimId, w, h); f.classList.remove('nodim'); f.setAttribute('style', style([w, h])); }
  }
  document.addEventListener('load', (e) => { if (e.target.tagName === 'IMG') settle(e.target, e.target.naturalWidth, e.target.naturalHeight); }, true);
  document.addEventListener('loadedmetadata', (e) => { if (e.target.tagName === 'VIDEO') settle(e.target, e.target.videoWidth, e.target.videoHeight); }, true);
  document.addEventListener('error', (e) => { if (e.target.tagName === 'IMG' || e.target.tagName === 'VIDEO') settle(e.target, 0, 0, true); }, true);
  return { of, frame, remember };
})();
// Rich, full-width preview with a file bar underneath
function attPreview(a, scope) {
  if (!Host.isNative) return attRow(a, scope);
  const url = fileUrl(a);
  const key = `${scope}-${a.id}`;
  const kind = fileKind(a);
  let media = '';
  if (kind === 'image') media = `<div class="ap-img" data-action="lightbox" data-src="${url}" data-name="${esc(a.name)}">${MediaDims.frame(a, `<img src="${imgUrl(a, 1280)}" alt="" loading="lazy">`)}</div>`;
  else if (kind === 'video') media = `<div class="ap-vid">${MediaDims.frame(a, `<video class="ap-video" data-media-key="${key}" src="${url}" controls preload="metadata" playsinline></video>`)}</div>`;
  else if (kind === 'audio') media = `<div class="ap-audio"><audio data-media-key="${key}" src="${url}" controls preload="metadata"></audio></div>`;
  else if (kind === 'pdf') media = `<iframe class="ap-pdf" src="${url}" title="${esc(a.name)}"></iframe>`;
  else if (kind === 'text') media = `<pre class="ap-text" data-text-src="${url}">Loading preview…</pre>`;
  else media = `<div class="ap-doc" data-action="quicklook" data-id="${a.id}" title="Click to preview">${thumbImg(a, 'wide')}<span class="ap-doc-hint">${icon('search')}Preview</span></div>`;
  return `<div class="ap ${media ? '' : 'ap-plain'}">
    ${media}
    <div class="ap-bar">
      ${fileIcon(a)}
      <div class="fname"><div>${esc(a.name)}</div><small>${fmtSize(a.size)}${a.addedAt ? ' · ' + timeAgo(a.addedAt) : ''}</small></div>
      <button class="icon-btn sm" data-action="copy-att" data-id="${a.id}" title="Copy — paste into a comment or description">${icon('copy')}</button>
      <button class="icon-btn sm" data-action="quicklook" data-id="${a.id}" title="Preview">${icon('search')}</button>
      <button class="icon-btn sm" data-action="open-att" data-id="${a.id}" title="Open in default app">${icon('open')}</button>
      <button class="icon-btn sm" data-action="reveal-att" data-id="${a.id}" title="${FINDER_LABEL}">${icon(Host.isServer ? 'download' : 'folder')}</button>
      ${scope === 'task' ? `<button class="icon-btn sm" data-action="remove-att" data-id="${a.id}" title="Remove">${icon('trash')}</button>` : ''}
    </div>
  </div>`;
}
function hydratePreviews(root) {
  $$('[data-text-src]', root).forEach((el) => {
    fetch(el.dataset.textSrc).then((r) => r.text()).then((t) => {
      el.textContent = t.length > 6000 ? t.slice(0, 6000) + '\n…' : (t || '(empty file)');
    }).catch(() => { el.textContent = 'Preview not available'; });
    el.removeAttribute('data-text-src');
  });
}
// Full-screen preview of an attachment inside the app
async function previewFile(a) {
  if (!a) return;
  ui.previewAtt = a;
  const url = fileUrl(a);
  const kind = fileKind(a);
  let body = '';
  // Phones show a PDF at its printed size (cut off on the right), so there the pages come as images that fit the screen
  const phonePages = Host.isServer && typeof Phone !== 'undefined' && Phone.on && (kind === 'pdf' || OFFICE_EXT.includes(fileExt(a.name)));
  if (phonePages) body = `<div class="fv-pages" id="fv-pages"><p class="fv-wait"><span class="spin"></span>Loading the pages…</p></div>`;
  else if (kind === 'image') body = `<img class="fv-img" src="${url}" alt="">`;
  else if (kind === 'video') body = `<video class="fv-video" src="${url}" controls autoplay playsinline></video>`;
  else if (kind === 'audio') body = `<div class="fv-audio">${icon('play')}<audio src="${url}" controls autoplay></audio></div>`;
  else if (kind === 'pdf') body = `<iframe class="fv-pdf" src="${url}"></iframe>`;
  else if (kind === 'text') body = `<pre class="fv-text" data-text-src="${url}">Loading…</pre>`;
  else if (OFFICE_EXT.includes(fileExt(a.name)) && Host.isServer) body = `<div class="fv-doc" id="fv-office">${thumbImg(a, 'wide')}<p class="fv-wait"><span class="spin"></span>Preparing the full preview…</p></div>`;
  else body = `<div class="fv-doc">${thumbImg(a, 'wide')}<p>This preview shows the first page. Click <b>Open in app</b> to see the whole file.</p></div>`;
  $('#overlay-root').innerHTML = `<div class="fv" data-action="close-preview">
    <div class="fv-box">
      <div class="fv-head">
        ${fileIcon(a)}
        <div class="fname"><div>${esc(a.name)}</div><small>${fmtSize(a.size)}</small></div>
        <button class="btn ghost sm" data-action="copy-att" data-id="${a.id}" title="Paste it into any comment or description">${icon('copy')}Copy</button>
        <button class="btn ghost sm" data-action="open-att" data-id="${a.id}">${icon('open')}Open in app</button>
        <button class="icon-btn" data-action="reveal-att" data-id="${a.id}" title="${FINDER_LABEL}">${icon(Host.isServer ? 'download' : 'folder')}</button>
        <button class="icon-btn" data-action="close-preview" title="Close (Esc)">${icon('x')}</button>
      </div>
      <div class="fv-body">${body}</div>
    </div>
  </div>`;
  const root = $('#overlay-root');
  hydratePreviews(root);
  hydrateThumbs(root);
  if (phonePages) {
    const fb = root.querySelector('.fv-body'); if (fb) fb.classList.add('pages');
    Host.call('pdfPages', { id: a.id, path: a.path }).then((r) => {
      const el = document.getElementById('fv-pages');
      if (!el || ui.previewAtt !== a) return;
      const pages = (r && r.pages) || [];
      if (!pages.length) { el.innerHTML = `<p class="fv-wait">${r && r.unavailable ? 'Full previews of Office files arrive with the next server update.' : 'This file couldn’t be previewed — use <b>Open in app</b> or download it.'}</p>`; return; }
      el.innerHTML = pages.map((pth, i) => `<img class="fv-page" src="${'/__file/' + pth.split('/').map(encodeURIComponent).join('/')}" alt="Page ${i + 1}" loading="${i < 2 ? 'eager' : 'lazy'}">`).join('')
        + (r.total > pages.length ? `<p class="fv-wait">Showing the first ${pages.length} of ${r.total} pages — use <b>Open in app</b> for the rest.</p>` : '');
    }).catch(() => { const el = document.getElementById('fv-pages'); if (el) el.innerHTML = '<p class="fv-wait">This file couldn’t be previewed right now.</p>'; });
  }
  // Word / PowerPoint / Excel: the server turns it into a PDF (once) and the whole document shows here
  if (document.getElementById('fv-office')) {
    Host.call('docPreview', { id: a.id, path: a.path }).then((r) => {
      const el = document.getElementById('fv-office');
      if (!el || ui.previewAtt !== a) return;
      if (r && r.pdf) el.outerHTML = `<iframe class="fv-pdf" src="${'/__file/' + r.pdf.split('/').map(encodeURIComponent).join('/')}" title="${esc(a.name)}"></iframe>`;
      else { const w = el.querySelector('.fv-wait'); if (w) w.innerHTML = r && r.unavailable ? 'Full previews of Office files arrive with the next server update. This shows the first page.' : 'This file couldn’t be previewed — use <b>Open in app</b> or download it.'; }
    }).catch(() => { const w = document.querySelector('#fv-office .fv-wait'); if (w) w.textContent = 'This file couldn’t be previewed right now.'; });
  }
}

function lightbox(src, name) {
  const root = $('#overlay-root');
  root.innerHTML = `<div class="lightbox" data-action="close-lightbox"><img src="${src}" alt=""><div class="lb-name">${esc(name)}</div></div>`;
}

function attRow(a, scope) {
  return `<div class="att" data-action="open-att" data-id="${a.id}" data-scope="${scope}" title="Open">
    ${fileIcon(a)}
    <div class="fname"><div>${esc(a.name)}</div><small>${fmtSize(a.size)}${a.addedAt ? ' · added ' + timeAgo(a.addedAt) : ''}</small></div>
    <button class="icon-btn sm" data-action="copy-att" data-id="${a.id}" title="Copy — paste into a comment or description">${icon('copy')}</button>
    <button class="icon-btn sm" data-action="reveal-att" data-id="${a.id}" data-scope="${scope}" title="${FINDER_LABEL}">${icon(Host.isServer ? 'download' : 'folder')}</button>
    ${scope === 'task' ? `<button class="icon-btn sm" data-action="remove-att" data-id="${a.id}" title="Remove">${icon('trash')}</button>` : ''}
  </div>`;
}
function findAttachment(t, id) {
  let a = null;
  if (t) {
    a = t.attachments.find((x) => x.id === id);
    if (a) return a;
    for (const c of t.comments) { a = (c.attachments || []).find((x) => x.id === id); if (a) return a; }
    for (const k of Object.keys(ui.commentFiles)) { if (k === t.id || k.startsWith(t.id + ':')) { a = (ui.commentFiles[k] || []).find((x) => x.id === id); if (a) return a; } }
  }
  return (ui.previewAtt && ui.previewAtt.id === id ? ui.previewAtt : null) || clientFileById(id);
}

/* ---- Copy a file once, paste it into any comment or description (no re-upload) ---- */
const unesc = (s) => String(s).replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const fileRefsIn = (html) => { const out = []; String(html || '').replace(/data-fpath="([^"]*)"/g, (_, p) => { out.push(unesc(p)); return ''; }); return out; };
const attCore = (a) => ({ name: a.name, path: a.path, size: a.size || 0, ...(a.thumb ? { thumb: a.thumb } : {}) });
function copyAttachment(a) {
  if (!a) return;
  const token = `📎 ${a.name}`;
  ui.fileClip = { att: attCore(a), token };
  try {
    const ta = document.createElement('textarea');
    ta.value = token; ta.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0';
    document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove();
  } catch (e) { /* the in-app Paste button still works */ }
  toast(`Copied “${a.name}” — paste it into any comment or description (⌘V)`);
  if (ui.taskId) renderDetail();
}
// Inline file chip used inside descriptions and edited comments
function fileRefHTML(a, display) {
  const attrs = `data-fpath="${esc(a.path)}" data-fname="${esc(a.name)}" data-fsize="${+a.size || 0}"${a.thumb ? ` data-fthumb="${esc(a.thumb)}"` : ''}`;
  if (!display) return `<span class="fileref" contenteditable="false" ${attrs}>📎 ${esc(a.name)}</span>`;
  const img = isImage(a) && Host.isNative ? `<img src="${imgUrl(a, 160)}" alt="">` : `<i class="fr-ext">${esc((fileExt(a.name) || 'file').slice(0, 4))}</i>`;
  return `<span class="fileref show" data-action="fileref-open" ${attrs} title="Preview ${esc(a.name)}">${img}<span class="fr-name">${esc(a.name)}</span>${a.size ? `<small>${fmtSize(a.size)}</small>` : ''}</span>`;
}
function fileRefAtt(el) {
  const path = el.dataset.fpath;
  let h = 0; for (const ch of path) h = (h * 31 + ch.charCodeAt(0)) | 0;
  return { id: 'ref' + Math.abs(h).toString(36), path, name: el.dataset.fname || path.split('/').pop(), size: +el.dataset.fsize || 0, ...(el.dataset.fthumb ? { thumb: el.dataset.fthumb } : {}) };
}
function pasteFileInto(ed) {
  const a = ui.fileClip && ui.fileClip.att;
  if (!a || !ed) return;
  const t = task(ui.taskId);
  if (ed.dataset.draftKey && t) {
    const key = ed.dataset.draftKey;
    ui.commentDraft[key] = editorEmpty(ed) ? '' : ed.innerHTML;
    const list = ui.commentFiles[key] || [];
    if (list.some((x) => x.path === a.path)) { toast('That file is already added'); return; }
    ui.commentFiles[key] = list.concat({ ...a, id: uid(), linked: true, addedAt: nowISO() });
    renderDetail();
    setTimeout(() => { const b = $(`[data-draft-key="${key}"]`); if (b) { b.focus(); placeCaretAtEnd(b); } }, 0);
    return;
  }
  ed.focus();
  const sel = window.getSelection();
  if (!sel.rangeCount || !ed.contains(sel.anchorNode)) placeCaretAtEnd(ed);
  document.execCommand('insertHTML', false, fileRefHTML(a) + '&nbsp;');
  ed.dispatchEvent(new Event('input', { bubbles: true }));
}
function clipPasteBtn(target) {
  const c = ui.fileClip;
  return c ? `<button class="clip-paste" data-action="paste-clip" data-target="${target}" title="Add the file you copied — no upload needed">${icon('clip')}<span>Paste “${esc(c.att.name)}”</span></button>` : '';
}
// Every file path still referenced anywhere (attachments, comments, descriptions, unsent comments)
function usedPaths() {
  const s = new Set();
  const add = (a) => { if (a && a.path) { s.add(a.path); if (a.thumb) s.add(a.thumb); } };
  db.tasks.forEach((t) => {
    t.attachments.forEach(add);
    t.comments.forEach((c) => { (c.attachments || []).forEach(add); fileRefsIn(c.html).forEach((p) => s.add(p)); });
    fileRefsIn(t.notesHtml).forEach((p) => s.add(p));
  });
  Object.values(ui.commentFiles).forEach((l) => (l || []).forEach(add));
  trashList().forEach((it) => trashFiles(it).forEach(add));
  (db.clients || []).forEach((c) => { if (c.logo) s.add(c.logo); c.folders.forEach((f) => f.files.forEach(add)); });
  return [...s];
}
// Move files to the Trash only when nothing else still uses them (copied files are shared)
function safeTrash(paths) {
  const used = usedPaths();
  const ok = (paths || []).filter((p) => p && !used.some((u) => u === p || u.startsWith(p.replace(/\/$/, '') + '/') || (p.startsWith('.thumbs/') && u.startsWith(p))));
  if (ok.length) Host.call('trashMany', { paths: ok }).catch(() => {});
  return ok;
}

function allTags() {
  const s = new Set();
  db.tasks.forEach((t) => t.tags.forEach((g) => s.add(g)));
  return Array.from(s).sort((a, b) => a.localeCompare(b));
}

function autosize(el) {
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = el.scrollHeight + 2 + 'px';
}

function openTask(id, focusTitle) {
  flushEdit();
  const pendingThread = ui.pendingThread; ui.pendingThread = null;
  // A task always opens on its Details tab, unless something asked for a tab on purpose (e.g. an Inbox mention → Comments)
  if (ui.taskId !== id) { if (ui.taskId && Draft.settle(ui.taskId)) renderContent(); ui.replyTo = null; ui.thread = null; ui.editingComment = null; ui.descOpen = {}; ui.activityFilter = 'comments'; ui.sideTab = ui.forceTab || 'details'; }
  ui.forceTab = null;
  if (pendingThread) ui.thread = pendingThread;
  const ids = $$('#content [data-task]').map((el) => el.dataset.task).filter((x, i, a) => a.indexOf(x) === i);
  if (ids.includes(id)) ui.navIds = ids;
  ui.taskId = id;
  renderDetail();
  $$('.task-row, .card').forEach((el) => el.classList.toggle('is-selected', el.dataset.task === id));
  if (focusTitle) setTimeout(() => { const el = $('#d-title'); if (el) { el.focus(); el.select(); } }, 30);
}
function closeDetail() {
  flushEdit();
  const dropped = Draft.settle(ui.taskId);
  ui.taskId = null; ui.replyTo = null; ui.thread = null; ui.editingComment = null;
  renderDetail();
  if (dropped) renderContent();
  $$('.is-selected').forEach((el) => el.classList.remove('is-selected'));
}

/* ================= Overlays ================= */
function closeMenus() { $$('.menu').forEach((m) => m.remove()); }

function showMenu(anchor, items) {
  closeMenus();
  const m = document.createElement('div');
  m.className = 'menu';
  m.innerHTML = items.map((it, i) => {
    if (it === '-') return '<div class="sep"></div>';
    if (it.html) return it.html;
    return `<div class="mi ${it.danger ? 'danger' : ''}" data-mi="${i}">${it.icon ? icon(it.icon) : ''}${esc(it.label)}</div>`;
  }).join('');
  document.body.appendChild(m);
  const r = anchor.getBoundingClientRect();
  const mw = m.offsetWidth, mh = m.offsetHeight;
  let x = r.left, y = r.bottom + 4;
  if (x + mw > innerWidth - 8) x = innerWidth - mw - 8;
  if (y + mh > innerHeight - 8) y = r.top - mh - 4;
  m.style.left = Math.max(8, x) + 'px';
  m.style.top = Math.max(8, y) + 'px';
  m.addEventListener('click', (e) => {
    e.stopPropagation();
    const mi = e.target.closest('[data-mi]');
    if (mi) { const list = m._items || items; closeMenus(); list[+mi.dataset.mi].run(); return; }
    const sw = e.target.closest('[data-swatch]');
    if (sw && m._onSwatch) { closeMenus(); m._onSwatch(sw.dataset.swatch); }
  });
  return m;
}

function dialog({ title, body = '', input = null, okText = 'OK', cancelText = 'Cancel', danger = false, colors = null }) {
  return new Promise((resolve) => {
    const root = $('#overlay-root');
    let color = colors ? colors.value : null;
    root.innerHTML = `<div class="scrim"><div class="dialog" role="dialog">
      <h2>${esc(title)}</h2>
      ${body ? `<p>${esc(body)}</p>` : ''}
      ${input ? `<label class="dlg-label">${esc(input.label || '')}</label><input class="field" id="dlg-input" value="${esc(input.value || '')}" placeholder="${esc(input.placeholder || '')}" autocomplete="off">` : ''}
      ${colors ? `<label class="dlg-label">Color</label><div class="swatches" style="display:flex;gap:8px">${COLORS.map((c) => `<button class="swatch ${c === color ? 'on' : ''}" data-c="${c}" style="background:${c}"></button>`).join('')}</div>` : ''}
      <div class="actions">${cancelText ? `<button class="btn" data-r="0">${esc(cancelText)}</button>` : ''}<button class="btn ${danger ? 'danger' : 'primary'}" data-r="1">${esc(okText)}</button></div>
    </div></div>`;
    const scrim = $('.scrim', root);
    const inp = $('#dlg-input', root);
    const done = (ok) => {
      root.innerHTML = '';
      document.removeEventListener('keydown', onKey, true);
      if (!ok) return resolve(null);
      resolve(input || colors ? { value: inp ? inp.value.trim() : null, color } : true);
    };
    const onKey = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); done(false); }
      if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); e.stopPropagation(); if (!inp || inp.value.trim()) done(true); }
    };
    document.addEventListener('keydown', onKey, true);
    scrim.addEventListener('mousedown', (e) => { if (e.target === scrim) done(false); });
    scrim.addEventListener('click', (e) => {
      const b = e.target.closest('[data-r]');
      if (b) { if (b.dataset.r === '1' && inp && !inp.value.trim()) { inp.focus(); return; } done(b.dataset.r === '1'); }
      const sw = e.target.closest('[data-c]');
      if (sw) { color = sw.dataset.c; $$('.swatch', scrim).forEach((s) => s.classList.toggle('on', s === sw)); }
    });
    setTimeout(() => (inp ? (inp.focus(), inp.select()) : $('[data-r="1"]', root).focus()), 20);
  });
}

function toast(msg, action, ms) {
  const root = $('#toast-root');
  const el = document.createElement('div');
  el.className = 'toast';
  el.innerHTML = `<span>${esc(msg)}</span>${action ? `<button>${esc(action.label)}</button>` : ''}`;
  root.appendChild(el);
  let timer = setTimeout(() => el.remove(), ms || (action ? 6000 : 3000));
  if (action) el.querySelector('button').addEventListener('click', () => { clearTimeout(timer); el.remove(); action.run(); });
}

/* ================= Inline inputs ================= */
function inlineInput(el, { placeholder = '', value = '', multiline = false, keepOpen = false, onSubmit, onDone, cls = '' }) {
  const original = el.innerHTML;
  el.classList.add('editing');
  el.innerHTML = multiline ? `<textarea class="${cls}" placeholder="${esc(placeholder)}">${esc(value)}</textarea>` : `${el.classList.contains('add-row') ? icon('plus') : ''}<input class="${cls}" placeholder="${esc(placeholder)}" value="${esc(value)}" autocomplete="off">`;
  const inp = el.querySelector('input, textarea');
  let finished = false;
  const finish = () => {
    if (finished) return;
    finished = true;
    el.classList.remove('editing');
    el.innerHTML = original;
    if (onDone) onDone();
  };
  inp.addEventListener('keydown', (e) => {
    e.stopPropagation();
    if (e.key === 'Escape') { e.preventDefault(); inp.value = ''; finish(); }
    else if (e.key === 'Enter' && !e.isComposing && !e.shiftKey) {
      e.preventDefault();
      const v = inp.value.trim();
      if (!v) { finish(); return; }
      onSubmit(v);
      if (keepOpen) { inp.value = ''; } else finish();
    }
  });
  inp.addEventListener('blur', () => {
    setTimeout(() => {
      if (finished) return;
      const v = inp.value.trim();
      if (v && !keepOpen) onSubmit(v);
      else if (v && keepOpen) onSubmit(v);
      finish();
    }, 120);
  });
  inp.addEventListener('click', (e) => e.stopPropagation());
  inp.focus();
  if (value) inp.select();
  return inp;
}

/* ================= Actions ================= */
function go(view, projectId = null) {
  if (isFinUser() && !Fin.owns(view) && view !== 'profile' && view !== 'claim') view = 'fin-dash';
  PageHistory.mark();
  if (view === 'clients') { ui.caQ = ''; ui.caScope = null; }
  // The Inbox always opens on its unread tab (Primary on computers, Unread on phones)
  if (view === 'inbox') { ui.inboxTab = 'primary'; if (typeof Phone !== 'undefined' && Phone.resetInbox) Phone.resetInbox(); }
  ui.view = view;
  ui.projectId = projectId;
  if (ui.search) { ui.search = ''; $('#search').value = ''; }
  $('#content').scrollTop = 0;
  // An open task stays as it is while you move between pages (no flicker, previews don't reload)
  const keep = !!ui.taskId && !!task(ui.taskId) && $('#detail').dataset.shown === ui.taskId && !(typeof Phone !== 'undefined' && Phone.on);
  render({ keepDetail: keep });
  PageHistory.mark();
}

async function newProjectFlow() {
  if (!isAdmin()) { toast('Only Admins can add clients'); return; }
  return ClientList.dialog(null);       // name, colour, Account Managers, active (clientlist.js)
  const used = new Set(db.projects.map((p) => p.color));
  const res = await dialog({
    title: 'New client', input: { label: 'Client name', placeholder: 'e.g. Ford & Lincoln' },
    colors: { value: COLORS.find((c) => !used.has(c)) || COLORS[0] }, okText: 'Add client',
  });
  if (!res) return;
  const p = createProject(res.value, res.color);
  // its Client Assets folder (with Logos, Brand Guidelines, Fonts, Files), linked; an existing one of that name is reused
  const c = dupClient(p.name) || createClient(p.name);
  p.clientId = c.id;
  persist(0);
  go('project', p.id);
  toast(`Added ${p.name} — its Client Assets folder is ready`);
}

function newTaskInContext() {
  let t;
  if (ui.view === 'project' && !ui.search) {
    const p = proj(ui.projectId);
    t = createTask({ projectId: p.id, sectionId: p.sections[0].id });
  } else {
    t = createTask({ due: ui.view === 'mytasks' ? todayStr() : null });
  }
  Draft.start(t);
  commit();
  openTask(t.id, true);
}

/* ---- New tasks left empty ----
   "New task" opens a blank task straight away. If it is closed without anything filled in, it is removed
   instead of being kept as an untitled, unassigned task. As soon as anything is added it is kept. */
const Draft = (() => {
  const snaps = {};
  const sig = (t) => JSON.stringify([t.title || '', t.notes || '', t.notesHtml || '', t.due, t.start, t.prio, t.tags, (t.attachments || []).length,
    (t.comments || []).length, t.checklist, t.assignees, t.projectId, t.sectionId, t.update || null, t.finance || null, t.guardian || null,
    !!t.needsCD, !!t.done, t.partsDone || null, db.tasks.some((x) => x.parentId === t.id), t.channels || [], t.golive || null, t.occasion || null]);
  const looksEmpty = (t) => !t.title && !t.notes && !(t.assignees || []).length && !(t.comments || []).length && !(t.attachments || []).length
    && !(t.checklist || []).length && !t.done && !db.tasks.some((x) => x.parentId === t.id);
  function start(t) { t.blankDraft = true; snaps[t.id] = sig(t); }
  // Called when the task is closed or another one is opened
  function settle(id) {
    if (!id || !snaps[id]) return;
    const t = task(id);
    const same = t && sig(t) === snaps[id];
    delete snaps[id];
    if (!t) return;
    if (same) { removeTasks([id]); persist(0); return true; }
    delete t.blankDraft; persist();
    return false;
  }
  // Left over from a closed window or reload: my own blank tasks that never got anything
  function sweep() {
    const gone = db.tasks.filter((t) => t.blankDraft && t.createdBy === currentUserId && !snaps[t.id] && looksEmpty(t)).map((t) => t.id);
    db.tasks.forEach((t) => { if (t.blankDraft && t.createdBy === currentUserId && !snaps[t.id] && !gone.includes(t.id)) delete t.blankDraft; });
    if (gone.length) { removeTasks(gone); persist(0); }
  }
  return { start, settle, sweep, open: (id) => !!snaps[id] };
})();

/* ---- General announcement ----
   An Admin writes a title and description on My profile. Everyone else (Finance-only people too, computer
   and phone) sees it once as a pop-up the next time they use the app, until they close it. A new one
   replaces the last. Kept in db.meta.announcement = { id, title, body, by, at }; who has closed it is
   remembered on each person (u.prefs.annSeen = its id). */
const Announce = (() => {
  const MEGAPHONE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 11v2a1 1 0 0 0 1 1h2l5 4V6L6 10H4a1 1 0 0 0-1 1zM15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/></svg>';
  const current = () => (db && db.meta && db.meta.announcement && db.meta.announcement.id ? db.meta.announcement : null);
  const FOOT = 'If you have any questions, please contact Muhammad Arsal.';
  function check() {
    const a = current(), u = me();
    if (!a || !u || a.by === u.id || (u.prefs || {}).annSeen === a.id) return;
    if ($('.an-pop') || $('#overlay-root').children.length || $('.ec-remind')) return;
    const el = document.createElement('div');
    el.className = 'an-pop';
    const from = userById(a.by);
    el.innerHTML = `<section class="an-box" role="dialog" aria-labelledby="an-t">
      <button class="an-x" data-an="close" aria-label="Close">${icon('x')}</button>
      <div class="an-top"><span class="an-ic">${MEGAPHONE}</span><div>
        <small>ANNOUNCEMENT</small><h2 id="an-t">${esc(a.title)}</h2>
        ${a.body ? `<p class="an-body">${esc(a.body)}</p>` : ''}
        <p class="an-foot">${FOOT}</p>
        <div class="an-from">${from ? avatarHTML(from.id, 22) : ''}From ${esc(from ? fullName(from).split(' ')[0] : 'E11')} · ${esc(fmtDateTime(a.at))}</div>
      </div></div>
      <button class="btn an-close" data-an="close">Close</button>
    </section>`;
    document.body.appendChild(el);
    el.addEventListener('click', (e) => {
      if (!e.target.closest('[data-an="close"]')) return;
      el.remove();
      const me1 = me(); me1.prefs = me1.prefs || {}; me1.prefs.annSeen = a.id; persist(0);
    });
  }
  // The Admin's card on My profile
  function card() {
    if (!isAdm(me()) || !Host.isServer) return '';
    const a = current();
    return `<div class="pf-card pf-ann">
      <div class="pf-ann-h"><span class="an-ic sm">${MEGAPHONE}</span><div><h3>Announcement</h3><p>Admins only · everyone sees it once as a pop-up, the next time they use the app · a new one replaces the last</p></div></div>
      <div class="pf-ann-grid">
        <div>
          <label class="dlg-label" for="an-title">Title</label><input class="field" id="an-title" maxlength="120" placeholder="e.g. Office closed on Monday">
          <label class="dlg-label" for="an-body">Description</label><textarea class="field" id="an-body" rows="5" maxlength="1500" placeholder="What everyone needs to know"></textarea>
          <div class="pf-ann-act"><button class="btn primary" data-action="ann-send">Send to everyone</button><span>${a ? `Last sent: “${esc(a.title)}” · ${esc(fmtDateTime(a.at))}` : 'Everyone sees it once, on computers and phones'}</span></div>
        </div>
        <div><span class="dlg-label">Preview</span><div class="an-prev"><div class="an-box mini"><div class="an-top"><span class="an-ic">${MEGAPHONE}</span><div><small>ANNOUNCEMENT</small><h2 id="an-pt">Your title</h2><p class="an-body" id="an-pb">Your description</p><p class="an-foot">${FOOT}</p></div></div><span class="an-close fake">Close</span></div></div></div>
      </div>
    </div>`;
  }
  async function send() {
    if (!isAdm(me())) return;
    const t = ($('#an-title') || {}).value || '', b = ($('#an-body') || {}).value || '';
    if (!t.trim()) { toast('Give the announcement a title'); $('#an-title').focus(); return; }
    const ok = await dialog({ title: 'Send this announcement?', body: `Everyone on the team sees “${t.trim()}” as a pop-up once. It can’t be changed after it’s sent.`, okText: 'Send' });
    if (!ok) return;
    db.meta.announcement = { id: uid(), title: t.trim(), body: b.trim(), by: currentUserId, at: nowISO() };
    persist(0); renderContent();
    toast('Sent — everyone sees it the next time they use the app');
  }
  document.addEventListener('input', (e) => {
    if (e.target.id === 'an-title') { const x = $('#an-pt'); if (x) x.textContent = e.target.value || 'Your title'; }
    if (e.target.id === 'an-body') { const x = $('#an-pb'); if (x) x.textContent = e.target.value || 'Your description'; }
  });
  return { check, card, send };
})();

// Files that belong to these tasks (task attachments, comment attachments, folders, thumbnails)
function filesOfTasks(list) {
  const paths = [];
  list.forEach((t) => {
    const atts = t.attachments.concat(...t.comments.map((c) => c.attachments || []));
    atts.forEach((a) => { paths.push(a.path); paths.push('.thumbs/' + a.id); });
    paths.push('attachments/' + t.id);
  });
  return paths;
}

function deleteTaskFlow(id) {
  const t = task(id);
  if (!t) return;
  const ids = [t.id, ...descendants(t.id).map((d) => d.id)];
  if (t.parentId && task(t.parentId)) logActivity(task(t.parentId), `deleted subtask ${struck(t.title || 'Untitled task')}`);
  const removed = removeTasks(ids);
  if (ui.taskId && ids.includes(ui.taskId)) ui.taskId = t.parentId || null;
  // the people on it hear about it, so a mistake is spotted early
  if (!t.parentId) notifyWatchers(t, 'trash', `moved <b>${esc(t.title || 'Untitled task')}</b> to the Trash —`);
  const it = toTrash('task', { tasks: removed }, { key: 'tasks:' + t.id, projectId: t.projectId, projectName: (proj(t.projectId) || {}).name || '' });
  commit();
  toast(`Moved “${t.title || 'Untitled task'}”${ids.length > 1 ? ` and ${ids.length - 1} subtask${ids.length > 2 ? 's' : ''}` : ''} to the Trash`, {
    label: 'Undo', run: () => { db.trash = trashList().filter((x) => x.id !== it.id); removed.forEach((x) => { if (!task(x.id)) db.tasks.push(x); }); commit(); },
  }, 10000);
}

const AUTO_DELETE_DAYS = 30;
function daysUntilAutoDelete(t) {
  if (!t.done || !t.completedAt) return null;
  return Math.max(0, AUTO_DELETE_DAYS - Math.floor((Date.now() - new Date(t.completedAt).getTime()) / 86400000));
}
// Tasks finished more than 30 days ago move to the Trash (with their subtasks and files) for 30 more days
function purgeOldCompleted() {
  if (isFinUser()) return;
  if (Host.isServer && !isManager()) { purgeTrash(); return; } // Admins and Account Managers look after this
  const cutoff = Date.now() - AUTO_DELETE_DAYS * 86400000;
  const old = db.tasks.filter((t) => t.done && t.completedAt && new Date(t.completedAt).getTime() < cutoff && !(t.parentId && task(t.parentId) && task(t.parentId).done));
  if (old.length) {
    old.forEach((t) => {
      const ids = [t.id, ...descendants(t.id).map((d) => d.id)];
      if (!task(t.id)) return;
      const removed = removeTasks(ids);
      if (ui.taskId && ids.includes(ui.taskId)) ui.taskId = null;
      const it = toTrash('task', { tasks: removed }, { key: 'tasks:' + t.id, projectId: t.projectId, projectName: (proj(t.projectId) || {}).name || '', auto: true });
      it.deletedBy = null;
    });
    persist(0);
    render();
  }
  purgeTrash();
}
/* ================= Trash =================
   Deleted tasks, projects, comments, attachments and Client Assets files wait here for 30 days
   (finished tasks first wait 30 days after completion, so 60 in all). Admins and Account Managers
   see the Trash and can restore; only Admins delete forever. Files stay in place until then. */
const TRASH_DAYS = 30;
const isManager = (u = me()) => !!u && (isAdm(u) || u.role === 'am');
const trashList = () => (db && db.trash) || [];
const trashDaysLeft = (it) => Math.max(0, TRASH_DAYS - Math.floor((Date.now() - new Date(it.deletedAt).getTime()) / 86400000));
function toTrash(type, data, extra = {}) {
  db.trash = db.trash || [];
  const item = { id: 'tr-' + uid(), type, deletedAt: nowISO(), deletedBy: currentUserId, ...extra, data };
  db.trash.push(item);
  return item;
}
const dropTrash = (id) => { db.trash = trashList().filter((x) => x.id !== id); };
// Every file a Trash item still holds (kept on disk until it's deleted for good)
function trashFiles(it) {
  const d = it.data || {};
  const fromTasks = (list) => (list || []).flatMap((t) => (t.attachments || []).concat(...(t.comments || []).map((c) => c.attachments || [])));
  if (it.type === 'task') return fromTasks(d.tasks);
  if (it.type === 'project') return fromTasks(d.tasks);
  if (it.type === 'comment') return (d.comments || []).flatMap((c) => c.attachments || []);
  if (it.type === 'attachment') return d.att ? [d.att] : [];
  if (it.type === 'cafile') return d.file ? [d.file] : [];
  return [];
}
function trashPaths(it) {
  const paths = [];
  trashFiles(it).forEach((a) => { if (!a.linked) paths.push(a.path, '.thumbs/' + a.id); });
  if (it.type === 'task' || it.type === 'project') (it.data.tasks || []).forEach((t) => paths.push('attachments/' + t.id));
  return paths;
}
// Delete for good: the item and its files
function eraseTrash(ids) {
  const set = new Set(ids);
  const gone = trashList().filter((x) => set.has(x.id));
  db.trash = trashList().filter((x) => !set.has(x.id));
  const paths = gone.flatMap(trashPaths);
  persist(0);
  if (paths.length) setTimeout(() => safeTrash(paths), 300);
  return gone.length;
}
// After 30 days in the Trash things go for good (run by Admins and Account Managers)
function purgeTrash() {
  if (!isManager()) return;
  const old = trashList().filter((x) => trashDaysLeft(x) <= 0).map((x) => x.id);
  if (old.length) eraseTrash(old);
}
// Where something lived, in words
function trashWhere(it) {
  const d = it.data || {};
  if (it.type === 'task') { const p = proj(it.projectId) || (d.tasks && d.tasks[0] && proj(d.tasks[0].projectId)); return p ? p.name : it.projectName || 'My Tasks'; }
  if (it.type === 'project') return `${(d.tasks || []).filter((t) => !t.parentId).length} tasks`;
  if (it.type === 'comment' || it.type === 'attachment') { const t = task(d.taskId); return t ? t.title || 'Untitled task' : it.taskTitle || 'a deleted task'; }
  if (it.type === 'cafile') { const c = clientById(d.clientId); const f = c && c.folders.find((x) => x.id === d.folderId); return c ? `${c.name}${f ? ' › ' + f.name : ''}` : it.where || 'Client Assets'; }
  return '';
}
const TRASH_TYPE = { task: 'Task', project: 'Client', comment: 'Comment', attachment: 'File', cafile: 'Client file' };
const TRASH_ICON = { task: 'check-circle', project: 'folder', comment: 'chat', attachment: 'clip', cafile: 'assets' };

/* ---- Putting things back ---- */
function restoreTrash(id) {
  { const it0 = (db.trash || []).find((x) => x.id === id); if (it0 && it0.type === 'project' && !isAdmin()) { toast('Only Admins can restore clients'); return; } }
  const it = trashList().find((x) => x.id === id);
  if (!it || !isManager()) return;
  const d = it.data || {};
  let msg = '', open = null;
  if (it.type === 'task' || it.type === 'project') {
    if (it.type === 'project') {
      if (!proj(d.project.id)) db.projects.push(d.project);
    }
    const tasks = (d.tasks || []).filter((t) => !task(t.id));
    const ids = new Set(tasks.map((t) => t.id));
    tasks.forEach((t) => {
      const p = proj(t.projectId);
      if (t.projectId && !p) { t.projectId = null; t.sectionId = db.statuses[0].id; }
      else if (p && !p.sections.some((s) => s.id === t.sectionId)) t.sectionId = p.sections[0].id;
      else if (!t.projectId && !db.statuses.some((s) => s.id === t.sectionId)) t.sectionId = db.statuses[0].id;
      if (t.parentId && !ids.has(t.parentId) && !task(t.parentId)) t.parentId = null;
      db.tasks.push(t);
    });
    const root = tasks.find((t) => !t.parentId || !ids.has(t.parentId)) || tasks[0];
    if (it.type === 'task' && root) {
      logActivity(root, 'restored this task from the Trash');
      notifyWatchers(root, 'restore', 'restored from the Trash');
      open = root.id;
      msg = `Restored “${root.title || 'Untitled task'}”${it.projectId && !proj(it.projectId) ? ' to My Tasks — its client is in the Trash' : ''}`;
    } else msg = `Restored the client “${d.project.name}” with ${tasks.filter((t) => !t.parentId).length} tasks`;
  } else if (it.type === 'comment' || it.type === 'attachment') {
    const t = task(d.taskId);
    if (!t) { toast('Restore its task first — it’s in the Trash too'); return; }
    if (it.type === 'comment') {
      (d.comments || []).forEach((c) => { if (!t.comments.some((x) => x.id === c.id)) t.comments.push(c); });
      t.comments.sort((a, b) => a.at.localeCompare(b.at));
      logActivity(t, 'restored a comment from the Trash');
    } else {
      if (!t.attachments.some((x) => x.id === d.att.id)) t.attachments.push(d.att);
      logActivity(t, `restored attachment <b>${esc(d.att.name)}</b>`);
    }
    t.updatedAt = nowISO();
    msg = `Restored to “${t.title || 'Untitled task'}”`; open = t.id;
  } else if (it.type === 'cafile') {
    const c = clientById(d.clientId); const f = c && c.folders.find((x) => x.id === d.folderId);
    if (!f) { toast('Its client folder no longer exists'); return; }
    if (!f.files.some((x) => x.id === d.file.id)) f.files.push(d.file);
    msg = `Restored “${d.file.name}” to ${c.name} › ${f.name}`;
  }
  dropTrash(id);
  commit({ delay: 0 });
  toast(msg, open ? { label: 'Open', run: () => openTask(open) } : null);
}
async function eraseTrashFlow(id) {
  if (!isAdm(me())) return denied();
  const it = trashList().find((x) => x.id === id);
  if (!it) return;
  const ok = await dialog({ title: `Delete “${trashTitle(it)}” forever?`, body: 'It can’t be restored after this, and its files are removed too.', okText: 'Delete forever', danger: true });
  if (ok) { eraseTrash([id]); render(); toast('Deleted forever'); }
}
async function emptyTrashFlow() {
  if (!isAdm(me())) return denied();
  const n = trashList().length;
  if (!n) return;
  const ok = await dialog({ title: 'Empty the Trash?', body: `All ${n} item${n === 1 ? '' : 's'} and their files are deleted for good. This can’t be undone.`, okText: 'Empty Trash', danger: true });
  if (ok) { eraseTrash(trashList().map((x) => x.id)); render(); toast('The Trash is empty'); }
}
function trashTitle(it) {
  const d = it.data || {};
  if (it.type === 'task') return (d.tasks && (d.tasks.find((t) => !t.parentId || !d.tasks.some((x) => x.id === t.parentId)) || d.tasks[0]) || {}).title || 'Untitled task';
  if (it.type === 'project') return d.project ? d.project.name : 'Client';
  if (it.type === 'comment') { const c = (d.comments || [])[0]; return c ? trunc(c.text || notifPlainHTML(c.html), 80) || 'Comment' : 'Comment'; }
  if (it.type === 'attachment') return d.att ? d.att.name : 'File';
  if (it.type === 'cafile') return d.file ? d.file.name : 'File';
  return 'Item';
}

/* ---- The Trash page ---- */
function trashSearch(q, list) {
  const terms = sWords(q);
  if (!terms.length) return { items: list.slice().sort((a, b) => b.deletedAt.localeCompare(a.deletedAt)), fixed: [], terms: [] };
  const docs = list.map((it) => {
    const d = it.data || {};
    const files = trashFiles(it);
    const fields = [
      { w: 10, text: trashTitle(it) }, { w: 5, text: trashWhere(it) }, { w: 4, text: TRASH_TYPE[it.type] + ' ' + (it.type === 'attachment' || it.type === 'cafile' ? 'file' : '') },
      { w: 4, text: files.map((a) => `${a.name} ${fileExt(a.name)} ${fileKind(a)}`).join(' ') },
      { w: 3, text: it.deletedBy ? fullName(userById(it.deletedBy)) : 'automatic cleanup' },
      { w: 2, text: (d.tasks || []).map((t) => `${t.title} ${(t.tags || []).join(' ')} ${t.notes || ''} ${(t.comments || []).map((c) => c.text).join(' ')}`).join(' ') },
      { w: 2, text: (d.comments || []).map((c) => c.text || notifPlainHTML(c.html)).join(' ') },
      { w: 3, text: d.project ? d.project.name : '' },
    ];
    const words = new Map();
    fields.forEach((f) => sWords(f.text).forEach((w) => { if (!words.has(w) || words.get(w) < f.w) words.set(w, f.w); }));
    return { it, words };
  });
  const vocab = new Set(); docs.forEach((x) => x.words.forEach((_, w) => vocab.add(w)));
  const fixed = [];
  const per = terms.map((term) => { const m = termMatches(term, vocab); if (m.fuzzy && !m.words.has(term)) fixed.push({ from: term, to: m.fuzzy }); return { term, words: m.words }; });
  const scored = [];
  docs.forEach(({ it, words }) => {
    let score = 0;
    for (const pt of per) { let best = 0; pt.words.forEach((q, w) => { const v = words.get(w); if (v && v * q > best) best = v * q; }); if (!best) return; score += best; }
    scored.push({ it, score });
  });
  scored.sort((a, b) => b.score - a.score || b.it.deletedAt.localeCompare(a.it.deletedAt));
  return { items: scored.map((x) => x.it), fixed, terms: per };
}
const TRASH_FILTERS = [['all', 'All'], ['task', 'Tasks'], ['project', 'Clients'], ['file', 'Files'], ['comment', 'Comments'], ['mine', 'Deleted by me']];
function trashFiltered() {
  const f = ui.trashFilter || 'all';
  return trashList().filter((it) => f === 'all' || (f === 'file' ? it.type === 'attachment' || it.type === 'cafile' : f === 'mine' ? it.deletedBy === currentUserId : it.type === f));
}
function trashRow(it, r) {
  const left = trashDaysLeft(it);
  const files = trashFiles(it);
  const who = it.auto ? 'Cleaned up automatically (finished 30+ days ago)' : `Deleted by ${it.deletedBy === currentUserId ? 'you' : esc(fullName(userById(it.deletedBy)))}`;
  const chips = files.slice(0, 4).map((a) => `<button class="tr-file" data-action="tr-preview" data-id="${it.id}" data-file="${a.id}" title="Preview ${esc(a.name)}">${isImage(a) && Host.isNative ? `<img src="${imgUrl(a, 160)}" alt="" loading="lazy">` : `<i>${esc((fileExt(a.name) || 'file').slice(0, 4))}</i>`}<span>${r && r.terms.length ? sMark(a.name, r) : esc(a.name)}</span></button>`).join('');
  return `<div class="tr-row">
    <span class="tr-ic">${icon(TRASH_ICON[it.type] || 'trash')}</span>
    <div class="tr-main">
      <div class="tr-title">${r && r.terms.length ? sMark(trashTitle(it), r) : esc(trashTitle(it))}</div>
      <div class="tr-sub"><span class="tr-type">${TRASH_TYPE[it.type] || ''}</span>${esc(trashWhere(it))} · ${who} · ${esc(timeAgo(it.deletedAt))}</div>
      ${chips ? `<div class="tr-files">${chips}${files.length > 4 ? `<span class="tr-more">+${files.length - 4} more</span>` : ''}</div>` : ''}
    </div>
    <span class="tr-left ${left <= 3 ? 'soon' : ''}" title="Deleted for good after ${TRASH_DAYS} days">${left} day${left === 1 ? '' : 's'} left</span>
    <div class="tr-acts">
      ${it.type !== 'project' || isAdm(me()) ? `<button class="btn primary sm" data-action="tr-restore" data-id="${it.id}">${icon('reply')}Restore</button>` : '<span class="tr-only" title="Only Admins add clients back">Admins restore clients</span>'}
      ${isAdm(me()) ? `<button class="icon-btn sm" data-action="tr-forever" data-id="${it.id}" title="Delete forever">${icon('trash')}</button>` : ''}
    </div>
  </div>`;
}
function trashListHTML() {
  const r = trashSearch(ui.trashQ || '', trashFiltered());
  if (!r.items.length) return ui.trashQ ? `<div class="empty"><div class="big">Nothing in the Trash matches “${esc(ui.trashQ)}”</div>Try a task or file name, a client, a file type like “pdf”, or who deleted it.</div>`
    : `<div class="empty"><div class="big">The Trash is empty</div>Deleted tasks, clients, comments and files wait here for ${TRASH_DAYS} days.</div>`;
  const groups = [];
  r.items.forEach((it) => {
    const days = -dayDiff(ymd(new Date(it.deletedAt)));
    const name = ui.trashQ ? 'Results' : days <= 0 ? 'Today' : days < 7 ? 'This week' : 'Earlier';
    let g = groups.find((x) => x.name === name); if (!g) { g = { name, rows: [] }; groups.push(g); }
    g.rows.push(it);
  });
  return searchFixedNote(r) + groups.map((g) => `<div class="tr-group">${g.name}<span>${g.rows.length}</span></div><div class="tr-card">${g.rows.map((it) => trashRow(it, r)).join('')}</div>`).join('');
}
function viewTrash() {
  if (!isManager()) return '<div class="empty"><div class="big">The Trash is for Admins and Account Managers</div>Ask one of them if something needs to come back.</div>';
  const f = ui.trashFilter || 'all';
  const n = trashList().length;
  return `<div class="trash">
    <div class="tr-head">
      <div class="tr-intro">Deleted items stay here for ${TRASH_DAYS} days, then they and their files are removed for good. Finished tasks arrive here ${AUTO_DELETE_DAYS} days after they’re completed.</div>
      ${isAdm(me()) && n ? `<button class="btn ghost danger sm" data-action="tr-empty">${icon('trash')}Empty Trash</button>` : ''}
    </div>
    <div class="ca-searchbar tr-search">${icon('search')}<input id="tr-q" value="${esc(ui.trashQ || '')}" placeholder="Search the Trash — names, files, “pdf”, people…" autocomplete="off" spellcheck="false" aria-autocomplete="none" data-form-type="other"></div>
    <div class="tr-chips">${TRASH_FILTERS.map(([k, l]) => `<button class="${f === k ? 'on' : ''}" data-action="tr-filter" data-k="${k}">${l}</button>`).join('')}</div>
    <div id="tr-list">${trashListHTML()}</div>
  </div>`;
}
document.addEventListener('input', (e) => {
  if (e.target.id !== 'tr-q') return;
  ui.trashQ = e.target.value;
  const l = $('#tr-list'); if (l) { l.innerHTML = trashListHTML(); }
});


function projectMenu(anchor, id) {
  if (!isAdmin()) return;              // only Admins change a client
  const p = proj(id);
  const m = showMenu(anchor, [
    { label: 'Edit client…', icon: 'edit', run: () => ClientList.dialog(p) },
    { html: `<div class="swatches">${COLORS.map((c) => `<button class="swatch ${c === p.color ? 'on' : ''}" data-swatch="${c}" style="background:${c}"></button>`).join('')}</div>` },
    '-',
    { label: 'Add section', icon: 'plus', run: () => { go('project', id); setTimeout(() => { const a = $('[data-action="add-section"]'); if (a) a.click(); }, 30); } },
    ...(isAdmin() ? [{ label: clientOfProject(p) ? `Client Assets: ${clientOfProject(p).name}` : 'Link to Client Assets…', icon: 'assets', run: () => setTimeout(() => projectClientMenu(anchor, p), 0) }] : []),
    '-',
    ...(isAdmin() ? [{ label: 'Delete client', icon: 'trash', danger: true, run: () => deleteProjectFlow(id) }] : []),
  ]);
  m._onSwatch = (c) => { p.color = c; commit(); };
}

async function renameProject(id) {
  const p = proj(id);
  if (p) return ClientList.dialog(p);   // renaming also renames its Client Assets folder
  const res = await dialog({ title: 'Rename client', input: { label: 'Client name', value: p.name }, okText: 'Save' });
  if (res && res.value) { p.name = res.value; commit(); }
}

async function deleteProjectFlow(id) {
  const p = proj(id);
  if (p && p.inactive) { toast('Switch the client back on before deleting it (its tasks are hidden while it’s inactive)'); return; }
  const n = db.tasks.filter((t) => t.projectId === id).length;
  const ok = await dialog({ title: `Delete “${p.name}”?`, body: `The client and its ${n} task${n === 1 ? '' : 's'} move to the Trash. An Admin can restore them within ${TRASH_DAYS} days. Its Client Assets folder stays.`, okText: 'Move to Trash', danger: true });
  if (!ok) return;
  db.projects = db.projects.filter((x) => x.id !== id);
  const removed = removeTasks(db.tasks.filter((t) => t.projectId === id).map((t) => t.id));
  toTrash('project', { project: p, tasks: removed }, { key: 'projects:' + p.id });
  if (ui.taskId && !task(ui.taskId)) ui.taskId = null;
  persist(0);
  go('home');
}

function sectionMenu(anchor, sid) {
  if (!isAdmin()) return;
  const p = proj(ui.projectId);
  const s = p.sections.find((x) => x.id === sid);
  const i = p.sections.indexOf(s);
  const m = showMenu(anchor, [
    { label: 'Rename status', icon: 'edit', run: () => renameSectionInline(sid) },
    { html: `<div class="swatches">${STATUS_COLORS.map((c) => `<button class="swatch ${c === s.color ? 'on' : ''}" data-swatch="${c}" style="background:${c}"></button>`).join('')}</div>` },
    ...(i > 0 ? [{ label: 'Move left / up', icon: 'chev', run: () => { p.sections.splice(i, 1); p.sections.splice(i - 1, 0, s); commit(); } }] : []),
    ...(i < p.sections.length - 1 ? [{ label: 'Move right / down', icon: 'chev', run: () => { p.sections.splice(i, 1); p.sections.splice(i + 1, 0, s); commit(); } }] : []),
    '-',
    { label: 'Delete status', icon: 'trash', danger: true, run: () => deleteSectionFlow(sid) },
  ]);
  m._onSwatch = (c) => { s.color = c; commit(); };
}

function renameSectionInline(sid) {
  const p = proj(ui.projectId);
  const s = p.sections.find((x) => x.id === sid);
  const el = $(`[data-action="rename-section"][data-id="${sid}"]`);
  if (!el) return;
  const inp = document.createElement('input');
  inp.className = 'field';
  inp.style.cssText = 'width:220px;padding:2px 6px;font-weight:650';
  inp.value = s.name;
  el.replaceWith(inp);
  inp.focus(); inp.select();
  let done = false;
  const finish = (save) => {
    if (done) return; done = true;
    if (save && inp.value.trim()) s.name = inp.value.trim();
    commit();
  };
  inp.addEventListener('keydown', (e) => { e.stopPropagation(); if (e.key === 'Enter') finish(true); if (e.key === 'Escape') finish(false); });
  inp.addEventListener('blur', () => finish(true));
}

async function deleteSectionFlow(sid) {
  const p = proj(ui.projectId);
  if (p.sections.length === 1) { toast('A client needs at least one section'); return; }
  const s = p.sections.find((x) => x.id === sid);
  const tasks = db.tasks.filter((t) => t.projectId === p.id && t.sectionId === sid);
  const target = p.sections.find((x) => x.id !== sid);
  if (tasks.length) {
    const ok = await dialog({ title: `Delete section “${s.name}”?`, body: `Its ${tasks.length} task${tasks.length === 1 ? '' : 's'} will move to “${target.name}”.`, okText: 'Delete section', danger: true });
    if (!ok) return;
  }
  tasks.forEach((t) => { t.sectionId = target.id; });
  p.sections = p.sections.filter((x) => x.id !== sid);
  commit();
}

async function attachFiles(target = 'task', replyTo = null) {
  const t = task(ui.taskId);
  if (!t) return;
  try {
    const res = await Host.call('pickAttachments', { taskId: t.id });
    const files = (res.files || []).map((f) => ({ ...f, addedAt: nowISO() }));
    if (!files.length) return;
    if (target === 'comment') {
      const key = draftKey(t, replyTo);
      ui.commentFiles[key] = (ui.commentFiles[key] || []).concat(files);
      renderDetail();
      setTimeout(() => { const b = $(`[data-draft-key="${key}"]`); if (b) { b.focus(); placeCaretAtEnd(b); } }, 0);
      return;
    }
    files.forEach((f) => t.attachments.push(f));
    logActivity(t, `attached ${files.length === 1 ? `<b>${esc(files[0].name)}</b>` : files.length + ' files'}`);
    notifyWatchers(t, 'attach', `attached ${files.length === 1 ? `<b>${esc(files[0].name)}</b>` : files.length + ' files'}`);
    t.updatedAt = nowISO();
    commit();
    toast(`Attached ${files.length} file${files.length === 1 ? '' : 's'}`);
  } catch (e) { toast('Could not attach: ' + e.message); }
}

function statusMenu(anchor) {
  const t = task(ui.taskId);
  const items = [];
  statusList(t).forEach((st) => items.push({ html: `<div class="mi ${!t.done && t.sectionId === st.id ? 'cur' : ''}" data-mi="${items.length}"><span class="sw" style="background:${st.color}"></span>${esc(st.name)}</div>`, run: () => { changeStatus(t, st.id); } }));
  items.push('-');
  if (t.done || canComplete(t)) items.push({ html: `<div class="mi ${t.done ? 'cur' : ''}" data-mi="${items.length}"><span class="sw" style="background:#3ddc97"></span>${t.done ? 'Complete' : 'Mark complete'}</div>`, run: () => { setDone(t, !t.done); commit(); } });
  else items.push({ html: `<div class="mi-note">${icon('lock')}${esc(completeBlockedMsg(t))}</div>` });
  // showMenu needs index-aligned items: rebuild html with real indices
  showMenu(anchor, items.map((it, i) => (it === '-' ? it : { ...it, html: it.html.replace(/data-mi="\d+"/, `data-mi="${i}"`) })));
}

/* ---- CD Status ---- */
function cdButton(t, inProps) {
  const c = CD[t.cdStatus];
  const locked = cdLocked(t);
  return `<button class="cd-btn ${c ? '' : 'empty'} ${inProps ? 'in-props' : ''} ${locked ? 'locked' : ''}" data-action="cd-menu" ${c ? `style="background:${c.color};color:${textOn(c.color)}"` : ''} title="${locked ? CD_LOCK_MSG : 'CD Status'}">${locked ? icon('lock') : ''}${inProps ? '' : '<span class="cd-k">CD</span>'}${c ? esc(c.label) : 'Set CD status'}${icon('chev')}</button>`;
}
const cdChip = (t) => { const c = CD[t.cdStatus]; return c ? `<span class="cd-chip" style="--c:${c.color}" title="CD Status: ${esc(c.label)}">${t.cdStatus === 'approved' ? icon('check') : ''}CD ${t.cdStatus === 'approved' ? 'Approved' : 'Review'}</span>` : ''; };
function setCD(t, v) {
  if ((t.cdStatus || '') === v) return;
  logChange(t, 'the <b>CD Status</b>', CD[t.cdStatus] ? CD[t.cdStatus].label : '', CD[v] ? CD[v].label : '');
  notifyWatchers(t, 'cd', v ? `set CD Status to <b>${esc(CD[v].label)}</b>` : 'cleared the CD Status');
  t.cdStatus = v; t.updatedAt = nowISO();
  if (t.done && !canComplete(t)) setDone(t, false);
  commit();
}
function cdMenu(anchor) {
  const t = task(ui.taskId);
  if (cdLocked(t)) { toast(CD_LOCK_MSG); return; }
  const items = Object.entries(CD).map(([k, c]) => ({ html: `<div class="mi ${t.cdStatus === k ? 'cur' : ''}"><span class="sw" style="background:${c.color}"></span>${esc(c.label)}</div>`, run: () => setCD(t, k) }));
  if (t.cdStatus) items.push('-', { html: `<div class="mi">${icon('x')}Clear</div>`, run: () => setCD(t, '') });
  showMenu(anchor, items.map((it, i) => (it === '-' ? it : { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) })));
}

/* ---- Assignees ---- */
function setAssignee(t, userId, on) {
  if (!can('assign')) return denied();
  const has = (t.assignees || []).includes(userId);
  if (on === has) return;
  if (on) {
    t.assignees = (t.assignees || []).concat(userId);
    t.prio = t.prio || {};
    if (t.prio._ != null) {
      const v = normPrio(t.prio._);
      delete t.prio._;
      if (!(typeof v === 'number' && prioTakenBy(v, dayKey(t), userId, t.id))) t.prio[userId] = v;
    }
    logActivity(t, `assigned <b>${esc(fullName(userById(userId)))}</b>`);
    pushNotif(userId, t, 'assigned', 'assigned you to');
  } else {
    t.assignees = t.assignees.filter((x) => x !== userId);
    if (t.prio) delete t.prio[userId];
    if (t.partsDone) delete t.partsDone[userId];
    (t.reviews || []).forEach((r) => { if (r.by === userId && r.state === 'pending') r.state = 'withdrawn'; });
    logActivity(t, `unassigned ${struck(fullName(userById(userId)))}`);
    pushNotif(userId, t, 'unassigned', 'removed you from');
  }
  syncCD(t);
  t.updatedAt = nowISO();
  commit();
}
// Floating people picker: search, current assignees (× to remove) and everyone else
function assignMenu(anchor) {
  if (!can('assign')) return denied();
  closeMenus();
  const t = task(ui.taskId);
  const pop = document.createElement('div');
  pop.className = 'menu asg-pop';
  pop.innerHTML = `<div class="ap-search">${icon('search')}<input placeholder="Search or enter email…" autocomplete="off" spellcheck="false"></div><div class="ap-list"></div>`;
  document.body.appendChild(pop);
  const r = (anchor.closest('.pv') || anchor).getBoundingClientRect();
  const place = () => {
    const h = pop.offsetHeight, w = pop.offsetWidth;
    let x = r.left - 8, y = r.bottom + 6;
    if (x + w > innerWidth - 10) x = innerWidth - w - 10;
    if (y + h > innerHeight - 10) y = Math.max(10, r.top - h - 6);
    pop.style.left = Math.max(10, x) + 'px'; pop.style.top = y + 'px';
  };
  const input = $('input', pop), list = $('.ap-list', pop);
  let hl = 0, rows = [];
  const draw = () => {
    const tt = task(ui.taskId) || t;
    const q = input.value.trim().toLowerCase();
    const match = (u) => !q || fullName(u).toLowerCase().includes(q) || u.email.toLowerCase().includes(q);
    const assigned = (tt.assignees || []).map(userById).filter(Boolean).filter(match);
    const people = activeUsers().filter((u) => !(tt.assignees || []).includes(u.id) && match(u));
    rows = assigned.map((u) => ({ u, on: true })).concat(people.map((u) => ({ u, on: false })));
    if (hl >= rows.length) hl = Math.max(0, rows.length - 1);
    const item = (x, i) => `<div class="ap-item ${x.on ? 'on' : ''} ${i === hl ? 'hl' : ''}" data-ap="${x.u.id}" data-i="${i}">
      <span class="ap-av">${avatarHTML(x.u.id, 30)}${x.on ? `<button class="ap-x" data-ap-x="${x.u.id}" title="Remove assignee">${icon('x')}</button>` : ''}</span>
      <span class="ap-name">${x.u.id === currentUserId ? 'Me' : esc(fullName(x.u))}${x.u.name ? '' : ''}</span>
      <small>${esc(ROLES[x.u.role] || '')}</small></div>`;
    let i = 0;
    list.innerHTML = (assigned.length ? `<div class="ap-label">Assignees</div>${assigned.map(() => item(rows[i], i++)).join('')}` : '')
      + (people.length ? `<div class="ap-label">People</div>${people.map(() => item(rows[i], i++)).join('')}` : '')
      + (!rows.length ? `<div class="ap-none">No one matches “${esc(input.value.trim())}”${validEmail(input.value) && can('manageUsers') ? '<br><small>Add new people from Team members first</small>' : ''}</div>` : '');
    place();
  };
  // After picking someone, keep typing where you were — but on the phone only if the keyboard was
  // already up (otherwise every pick would pop the keyboard open)
  const toggle = (uid, on) => {
    const typing = document.activeElement === input;
    setAssignee(task(ui.taskId), uid, on); draw();
    if (typing || !(typeof Phone !== 'undefined' && Phone.on)) input.focus();
  };
  pop.addEventListener('click', (e) => {
    e.stopPropagation();
    const x = e.target.closest('[data-ap-x]');
    if (x) { toggle(x.dataset.apX, false); return; }
    const it = e.target.closest('[data-ap]');
    if (it) { const on = it.classList.contains('on'); toggle(it.dataset.ap, !on); }
  });
  input.addEventListener('input', () => { hl = 0; draw(); });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); e.stopPropagation(); if (rows.length) { hl = (hl + (e.key === 'ArrowDown' ? 1 : -1) + rows.length) % rows.length; draw(); } }
    else if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); const x = rows[hl]; if (x) toggle(x.u.id, !x.on); }
    else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeMenus(); }
    else e.stopPropagation();
  });
  draw();
  // On the phone, don't focus the search box by itself: iPhone gives it focus without a keyboard,
  // and the list then ignores the first swipe. Tapping the box still brings up the keyboard.
  if (!(typeof Phone !== 'undefined' && Phone.on)) setTimeout(() => input.focus(), 0);
}

/* ---- "My part done" for shared tasks ---- */
function setMyPart(t, done) {
  if (!isMine(t)) return;
  if (iReview(t)) { toast('Your part is marked done when the Creative Director approves your files'); return; }
  t.partsDone = t.partsDone || {};
  if (done) {
    t.partsDone[currentUserId] = nowISO();
    const all = (t.assignees || []).length > 0 && t.assignees.every((u) => partDone(t, u));
    logActivity(t, all ? 'finished their part — <b>all parts are done</b>, ready for review' : 'finished their part');
    notifyWatchers(t, 'part', 'finished their part of', { skip: all ? [t.createdBy] : [] });
    if (all) {
      const to = new Set([t.createdBy].filter(Boolean));
      to.forEach((u) => pushNotif(u, t, 'allparts', 'marked the last part done — all parts are done, ready for review:'));
    }
    toast(`Your part is done — “${t.title || 'Untitled task'}” moved to your Done list`, { label: 'Undo', run: () => setMyPart(t, false) });
  } else {
    delete t.partsDone[currentUserId];
    logActivity(t, 'reopened their part');
    checkPrioConflict(t);
  }
  t.updatedAt = nowISO();
  commit();
}
function reopenPart(t, u) {
  if (!(me() && (isAdm(me()) || me().role === 'am'))) return denied();
  if (!partDone(t, u)) return;
  delete t.partsDone[u];
  if (needsCD(t)) { const r = lastReview(t, u); if (r && r.state === 'approved') r.state = 'reopened'; syncCD(t); }
  logActivity(t, `reopened <b>${esc(fullName(userById(u)))}</b>’s part`);
  pushNotif(u, t, 'part', 'reopened your part of');
  checkPrioConflict(t);
  t.updatedAt = nowISO();
  commit();
}
function partsRow(t) {
  const ids = t.assignees || [];
  if (t.parentId || t.done || !ids.length) return '';
  const n = ids.filter((u) => partDone(t, u)).length;
  const canReopen = me() && (isAdm(me()) || me().role === 'am');
  const chips = ids.map((u) => {
    const d = partDone(t, u);
    const nm = u === currentUserId ? 'You' : fullName(userById(u)).split(' ')[0];
    const pend = !d && needsCD(t) && reviewState(t, u) === 'pending';
    return `<span class="part-chip ${d ? 'done' : ''} ${pend ? 'pend' : ''}" ${d && canReopen && u !== currentUserId ? `data-action="reopen-part" data-id="${u}" title="Reopen ${esc(fullName(userById(u)))}’s part"` : `title="${esc(fullName(userById(u)))}: ${d ? (needsCD(t) && u !== cdUserId() ? 'approved by the CD ' : 'part done ') + esc(timeAgo(t.partsDone[u])) : pend ? 'files with the CD for review' : 'working on it'}"`}>${avatarHTML(u, 20)}<span>${esc(nm)}</span>${d ? icon('check') : pend ? icon('clock') : ''}</span>`;
  }).join('');
  const mine = myPartControl(t);
  return `<div class="prop prop-parts"><label>${icon('check-circle')}Parts</label><div class="pv"><span class="parts-n ${n === ids.length ? 'all' : ''}">${n}/${ids.length} done</span>${chips}${mine}</div></div>`;
}

/* ---- Field changes that notify the task's people ---- */
function setDue(t, v) {
  const o = t.due;
  t.due = v || null;
  if (o === t.due) return;
  logChange(t, 'the <b>due date</b>', fmtDay(o), fmtDay(t.due));
  notifyWatchers(t, 'due', t.due ? `changed the due date to <b>${esc(fmtDay(t.due))}</b>` : 'removed the due date');
  checkPrioConflict(t);
  t.updatedAt = nowISO();
}

function setPrio(t, key, k) {
  t.prio = t.prio || {};
  const cur = normPrio(t.prio[key]);
  if (cur === k) return;
  const who = prioOwnerName(key);
  logChange(t, who ? `<b>${esc(who)}</b>’s <b>priority</b>` : 'the <b>priority</b>', prioLabel(cur), prioLabel(k));
  if (k === 'none') delete t.prio[key]; else t.prio[key] = k;
  if (who) {
    pushNotif(key, t, 'priority', `set your priority to <b>${esc(prioLabel(k))}</b> on`);
    notifyWatchers(t, 'priority', `changed <b>${esc(who)}</b>’s priority to <b>${esc(prioLabel(k))}</b> on`, { skip: [key] });
  } else notifyWatchers(t, 'priority', `changed the priority to <b>${esc(prioLabel(k))}</b> on`);
  t.updatedAt = nowISO();
  commit();
}
function prioMenu(anchor, key) {
  if (!can('editPriority')) return denied();
  const t = task(ui.taskId);
  key = key || ((t.assignees || [])[0] || '_');
  const cur = normPrio((t.prio || {})[key]);
  const who = prioOwnerName(key);
  const set = (k) => setPrio(t, key, k);
  const items = [{ run: () => set('urgent') }];
  const nums = [];
  for (let n = 1; n <= 10; n++) {
    const by = prioTakenBy(n, dayKey(t), key, t.id);
    if (by) nums.push(`<button class="pn taken" disabled title="Used by “${esc(by.title || 'Untitled task')}”">${n}</button>`);
    else { items.push({ run: () => set(n) }); nums.push(`<button class="pn ${cur === n ? 'cur' : ''}" data-mi="${items.length - 1}">${n}</button>`); }
  }
  items.push({ run: () => set('none') });
  const noneIdx = items.length - 1;
  const html = `<div class="prio-menu">
    ${who ? `<div class="pm-who">${avatarHTML(key, 18)}<span>${esc(key === currentUserId ? 'Your' : who + '’s')} priority</span></div>` : ''}
    <div class="mi ${cur === 'urgent' ? 'cur' : ''}" data-mi="0"><span class="prio-flag urgent">${icon('flag')}<span>Urgent</span></span><small>always on top</small></div>
    <div class="pm-label">Priority for ${t.due ? esc(fmtDue(t.due)) : 'tasks with no due date'} <small>· each number once per ${who ? 'person ' : ''}per day</small></div>
    <div class="pm-grid">${nums.join('')}</div>
    <div class="sep"></div>
    <div class="mi ${cur === 'none' ? 'cur' : ''}" data-mi="${noneIdx}"><span class="prio-flag none">${icon('flag')}<span>No priority</span></span></div>
  </div>`;
  const m = showMenu(anchor, [{ html }]);
  m._items = items; // data-mi indices above refer to this list
}

function reactMenu(anchor, cid) {
  const m = showMenu(anchor, [{ html: `<div class="react-pick">${REACTIONS.map((e) => `<button data-swatch="${e}">${e}</button>`).join('')}</div>` }]);
  m._onSwatch = (emoji) => toggleReaction(cid, emoji);
}
function toggleReaction(cid, emoji) {
  const t = task(ui.taskId);
  const c = t.comments.find((x) => x.id === cid);
  if (!c) return;
  c.reactions = c.reactions || {};
  c.reactions[emoji] = c.reactions[emoji] ? 0 : 1;
  if (!c.reactions[emoji]) delete c.reactions[emoji];
  commit();
}

function commentMenu(anchor, cid) {
  const t = task(ui.taskId);
  const c = t.comments.find((x) => x.id === cid);
  if (!c) return;
  showMenu(anchor, [
    { label: 'Edit comment', icon: 'edit', run: () => { ui.editingComment = cid; renderDetail(); setTimeout(() => { const el = $('#edit-comment'); if (el) { el.focus(); placeCaretAtEnd(el); } }, 0); } },
    { label: 'Copy text', icon: 'open', run: () => { try { navigator.clipboard.writeText(c.text); toast('Copied'); } catch (e) { toast('Could not copy'); } } },
    '-',
    { label: 'Delete comment', icon: 'trash', danger: true, run: () => deleteComment(cid) },
  ]);
}

async function deleteComment(cid) {
  const t = task(ui.taskId);
  const group = t.comments.filter((x) => x.id === cid || x.parentId === cid);
  const files = group.flatMap((x) => x.attachments || []).filter((a) => !a.linked);
  const replies = group.length - 1;
  if (files.length || replies || !isManager()) {
    const parts = [];
    if (replies) parts.push(`its ${replies} repl${replies === 1 ? 'y' : 'ies'}`);
    if (files.length) parts.push(`${files.length} attached file${files.length === 1 ? '' : 's'}`);
    const back = isManager() ? `You can restore it from the Trash within ${TRASH_DAYS} days.` : `An Account Manager can bring it back within ${TRASH_DAYS} days if needed.`;
    const ok = await dialog({ title: 'Delete comment?', body: `${parts.length ? `This also removes ${parts.join(' and ')}. ` : ''}${back}`, okText: 'Delete', danger: true });
    if (!ok) return;
  }
  const ids = new Set(group.map((x) => x.id));
  t.comments = t.comments.filter((x) => !ids.has(x.id));
  const it = toTrash('comment', { taskId: t.id, comments: group }, { key: 'tasks:' + t.id, taskTitle: t.title });
  commit();
  toast(isManager() ? 'Comment moved to the Trash' : 'Comment deleted — ask an Account Manager if you need it back', {
    label: 'Undo', run: () => { db.trash = trashList().filter((x) => x.id !== it.id); group.forEach((c) => { if (!t.comments.some((x) => x.id === c.id)) t.comments.push(c); }); t.comments.sort((a, b) => a.at.localeCompare(b.at)); commit(); },
  }, 10000);
}

function navTask(n) {
  flushEdit();
  const i = ui.navIds.indexOf(ui.taskId);
  const next = ui.navIds[i + n];
  if (next && task(next)) { if (Draft.settle(ui.taskId)) renderContent(); ui.replyTo = null; ui.thread = null; ui.editingComment = null; ui.activityFilter = 'comments'; ui.taskId = next; renderDetail(); $$('.task-row, .card').forEach((el) => el.classList.toggle('is-selected', el.dataset.task === next)); }
}

/* ================= Event wiring ================= */
document.addEventListener('click', async (e) => {
  if (!db || !currentUserId) return;
  if (!e.target.closest('.menu')) closeMenus();
  if (!e.target.closest('.disp-wrap')) $$('.disp-wrap.open').forEach((w) => w.classList.remove('open'));

  const actEl = e.target.closest('[data-action]');
  const act = actEl && actEl.dataset.action;
  if (act) {
    const id = actEl.dataset.id;
    switch (act) {
      case 'new-task': e.preventDefault(); if (!can('createTask')) return denied(); newTaskInContext(); return;
      case 'new-project': e.preventDefault(); newProjectFlow(); return;
      case 'reveal-data': Host.call('revealData').catch((err) => toast(err.message)); return;
      case 'project-menu': e.preventDefault(); e.stopPropagation(); projectMenu(actEl, id); return;
      case 'section-menu': e.stopPropagation(); sectionMenu(actEl, id); return;
      case 'set-view': { const p = proj(ui.projectId); p.view = actEl.dataset.v; commit(); return; }
      case 'toggle': {
        e.stopPropagation();
        const t = task(id);
        if (!t.done && !canComplete(t)) { toast(completeBlockedMsg(t)); return; }
        setDone(t, !t.done);
        commit({ delay: 0 });
        const btn = $(`.check[data-id="${id}"]`);
        if (btn && t.done) btn.classList.add('pop');
        if (t.done && !t.parentId) toast(`Completed “${t.title || 'Untitled task'}”`, { label: 'Undo', run: () => { setDone(t, false); commit(); } });
        return;
      }
      case 'collapse': ui.collapsed[id] = !ui.collapsed[id]; renderContent(); return;
      case 'collapse-mt': ui.mytasksCollapsed[id] = !ui.mytasksCollapsed[id]; renderContent(); return;
      case 'toggle-show-done': ui.showDone[ui.projectId] = !ui.showDone[ui.projectId]; renderContent(); return;
      case 'mt-tab': ui.myTasksTab = actEl.dataset.tab; renderContent(); return;
      case 'add-task-inline': {
        if (actEl.classList.contains('editing')) return;
        const sid = actEl.dataset.section;
        inlineInput(actEl, {
          placeholder: 'Write a task name, then press Enter', keepOpen: true,
          onSubmit: (v) => { createTask({ projectId: ui.projectId, sectionId: sid, title: v }); persist(); renderSidebar(); rerenderKeepingAdd(sid); },
        });
        return;
      }
      case 'add-task-top': {
        const p = proj(ui.projectId);
        ui.collapsed[p.sections[0].id] = false;
        renderContent();
        const a = $(`.add-row[data-section="${p.sections[0].id}"]`);
        if (a) { a.scrollIntoView({ block: 'nearest' }); a.click(); }
        return;
      }
      case 'add-card': {
        const sid = actEl.dataset.section;
        const col = $(`.col[data-col="${sid}"]`);
        const slot = $('.col-add', col);
        if (!slot || slot.classList.contains('editing')) return;
        const wrap = document.createElement('div');
        wrap.className = 'col-add-input';
        slot.replaceWith(wrap);
        const ta = document.createElement('textarea');
        ta.placeholder = 'Write a task name, then press Enter';
        wrap.appendChild(ta);
        ta.focus();
        let closed = false;
        const close = () => { if (closed) return; closed = true; renderContent(); };
        ta.addEventListener('keydown', (ev) => {
          ev.stopPropagation();
          if (ev.key === 'Escape') { ta.value = ''; close(); }
          if (ev.key === 'Enter' && !ev.shiftKey && !ev.isComposing) {
            ev.preventDefault();
            const v = ta.value.trim();
            if (!v) { close(); return; }
            createTask({ projectId: ui.projectId, sectionId: sid, title: v });
            persist(); renderSidebar();
            closed = true; renderContent();
            const again = $(`.col[data-col="${sid}"] [data-action="add-card"].col-add`);
            if (again) again.click();
            const body = $(`.col[data-col="${sid}"] .col-body`);
            if (body) body.scrollTop = body.scrollHeight;
          }
        });
        ta.addEventListener('blur', () => setTimeout(() => {
          if (closed) return;
          const v = ta.value.trim();
          if (v) { createTask({ projectId: ui.projectId, sectionId: sid, title: v }); persist(); renderSidebar(); }
          close();
        }, 120));
        return;
      }
      case 'add-section': {
        if (!isAdmin()) return;
        if (actEl.classList.contains('editing')) return;
        const p = proj(ui.projectId);
        inlineInput(actEl, {
          placeholder: 'Status name (e.g. Review)', cls: '',
          onSubmit: (v) => { p.sections.push({ id: uid(), name: v, color: defaultSectionColor(v, p.sections.length) }); persist(); },
          onDone: () => renderContent(),
        });
        return;
      }
      case 'close-detail': closeDetail(); return;
      case 'open-task': openTask(id); return;
      case 'delete-task': if (!can('deleteTask')) return denied(); deleteTaskFlow(id); return;
      case 'delete-sub': if (!can('deleteTask')) return denied(); deleteTaskFlow(id); return;
      case 'clear-due': case 'due-today': case 'due-tomorrow': {
        const t = task(ui.taskId);
        setDue(t, act === 'clear-due' ? null : act === 'due-today' ? todayStr() : addDays(todayStr(), 1));
        commit(); return;
      }
      case 'remove-tag': { if (!can('removeTag')) return denied(); const t = task(ui.taskId); logActivity(t, `removed tag ${struck(t.tags[+actEl.dataset.i])}`); t.tags.splice(+actEl.dataset.i, 1); t.updatedAt = nowISO(); commit(); setTimeout(() => { const i = $('#d-tag-input'); if (i) i.focus(); }, 0); return; }
      case 'attach': attachFiles('task'); return;
      case 'attach-comment': attachFiles('comment', actEl.dataset.reply || null); return;
      case 'unstage-file': {
        e.stopPropagation();
        const key = actEl.dataset.key || ui.taskId;
        const list = ui.commentFiles[key] || [];
        const a = list.find((x) => x.id === id);
        ui.commentFiles[key] = list.filter((x) => x.id !== id);
        if (a) safeTrash([a.path]);
        renderDetail();
        return;
      }
      case 'open-att': case 'reveal-att': {
        e.stopPropagation();
        const a = findAttachment(task(ui.taskId), id);
        if (a) Host.call(act === 'open-att' ? 'openPath' : 'revealPath', { path: a.path }).catch((err) => toast('Could not open: ' + err.message));
        return;
      }
      case 'remove-att': {
        e.stopPropagation();
        const t = task(ui.taskId);
        const a = t.attachments.find((x) => x.id === id);
        const ok = await dialog({ title: `Remove “${a.name}”?`, body: isManager() ? `It moves to the Trash, where it can be restored within ${TRASH_DAYS} days.` : `An Account Manager can bring it back within ${TRASH_DAYS} days if needed.`, okText: 'Remove', danger: true });
        if (!ok) return;
        t.attachments = t.attachments.filter((x) => x.id !== id);
        logActivity(t, `removed attachment ${struck(a.name)}`);
        t.updatedAt = nowISO();
        const it = toTrash('attachment', { taskId: t.id, att: a }, { key: 'tasks:' + t.id, taskTitle: t.title });
        commit();
        toast(isManager() ? `“${a.name}” moved to the Trash` : `Removed “${a.name}” — ask an Account Manager if you need it back`, {
          label: 'Undo', run: () => { db.trash = trashList().filter((x) => x.id !== it.id); if (!t.attachments.some((x) => x.id === a.id)) t.attachments.push(a); commit(); },
        }, 10000);
        return;
      }
      case 'add-comment': addComment(actEl.dataset.reply || null); return;
      case 'copy-att': { e.stopPropagation(); const a = findAttachment(task(actEl.dataset.taskId || ui.taskId), id); if (a) copyAttachment(a); return; }
      case 'paste-clip': {
        e.preventDefault(); e.stopPropagation();
        const ed = actEl.dataset.target === 'desc' ? $('#d-notes') : actEl.closest('.composer') && actEl.closest('.composer').querySelector('.rt-editor');
        pasteFileInto(ed); return;
      }
      case 'fileref-open': { e.stopPropagation(); e.preventDefault(); previewFile(fileRefAtt(actEl)); return; }
      case 'quicklook': previewFile(findAttachment(task(ui.taskId), id)); return;
      case 'close-preview': if (e.target === actEl || actEl.tagName === 'BUTTON') $('#overlay-root').innerHTML = ''; return;
      case 'lightbox': lightbox(actEl.dataset.src, actEl.dataset.name); return;
      case 'tile-open': {
        const a = findAttachment(task(ui.taskId), id);
        if (!a) return;
        previewFile(a);
        return;
      }
      case 'fmt': e.preventDefault(); applyFormat(actEl.dataset.fmt, actEl); return;
      case 'toggle-theme': Theme.setMode(document.documentElement.dataset.theme === 'light' ? 'dark' : 'light'); if (ui.view === 'profile' || (typeof Phone !== 'undefined' && Phone.on && ui.view === 'me')) renderContent(); return;
      case 'theme-mode': Theme.setMode(actEl.dataset.mode); renderContent(); return;
      case 'disp-toggle': actEl.closest('.disp-wrap').classList.toggle('open'); return;
      case 'detail-mode': ui.detailMode = actEl.dataset.mode; savePref('detailMode', ui.detailMode); renderDetail(); return;
      case 'side-tab': { const tb = actEl.dataset.tab; ui.thread = null; ui.replyTo = null; if (tb === 'activity') { ui.sideTab = 'comments'; ui.activityFilter = 'all'; } else { ui.sideTab = tb; if (tb === 'comments') ui.activityFilter = 'comments'; } } renderDetail(); if (ui.sideTab === 'comments') { const f = $('.tm-feed'); if (f) stickFeedToBottom(f); } return;
      case 'share-task': TaskLink.copy(id); return;
      case 'wf-created': e.stopPropagation(); workMenu(actEl, 'created'); return;
      case 'wf-people': e.stopPropagation(); workMenu(actEl, 'people'); return;
      case 'wf-ams': e.stopPropagation(); workMenu(actEl, 'ams'); return;
      case 'wf-assigned': Work.f().assigned = !Work.f().assigned; renderContent(); renderSidebar(); return;
      case 'wf-clear-assigned': Work.f().assigned = false; renderContent(); renderSidebar(); return;
      case 'wf-clear-created': Work.f().created = null; renderContent(); return;
      case 'wf-due': e.stopPropagation(); workMenu(actEl, 'due'); return;
      case 'wf-clear-due': Work.f().due = null; renderContent(); return;
      case 'wf-clear-finished': Work.f().finished = false; renderContent(); return;
      case 'wf-clear-cd': Work.f().cd = false; renderContent(); return;
      case 'wf-clear-team': Work.f().team = false; renderContent(); renderSidebar(); return;
      case 'wf-clear-person': Work.f().people = Work.f().people.filter((x) => x !== id); renderContent(); return;
      case 'wf-clear-am': Work.f().ams = Work.f().ams.filter((x) => x !== id); renderContent(); renderSidebar(); return;
      case 'wf-reset': ui.workF = null; renderContent(); renderSidebar(); return;
      case 'go-claims': go('claims'); return;
      case 'ann-send': Announce.send(); return;
      case 'home-view-all': if (Work.lead()) ui.workF = null; ui.myTasksTab = 'todo'; go('mytasks'); return;
      case 'field-pick': e.stopPropagation(); fieldMenu(actEl, actEl.dataset.k); return;
      case 'fields-toggle': ui.fieldsOpen = ui.fieldsOpen === false; renderDetail(); return;
      case 'fields-empty': ui.fieldsHideEmpty = !ui.fieldsHideEmpty; renderDetail(); return;
      case 'nav-back': PageHistory.back(); return;
      case 'nav-forward': PageHistory.forward(); return;
      case 'toggle-sidebar': setSidebarCollapsed(!document.getElementById('app').classList.contains('sb-collapsed')); return;
      case 'close-lightbox': $('#overlay-root').innerHTML = ''; return;
      case 'pick-day': ui.day = actEl.dataset.day; renderContent(); return;
      case 'shift-day': ui.day = addDays(ui.day || todayStr(), +actEl.dataset.n); renderContent(); return;
      case 'go-project': closeDetail(); go('project', id); return;
      case 'nav-task': navTask(+actEl.dataset.n); return;
      case 'status-menu': e.stopPropagation(); statusMenu(actEl); return;
      case 'status-next': {
        const t = task(ui.taskId); const list = statusList(t);
        const i = list.findIndex((x) => x.id === t.sectionId);
        if (t.done) return;
        if (i >= list.length - 1) { toast('Already at the last status'); return; }
        changeStatus(t, list[Math.max(0, i) + 1].id); return;
      }
      case 'ib-filter': e.stopPropagation(); inboxFilterMenu(actEl); return;
      case 'notif-clear': e.stopPropagation(); clearTaskNotifs(id, actEl.dataset.read !== '1'); return;
      case 'mw-group': ui.mytasksCollapsed[id] = !ui.mytasksCollapsed[id]; renderContent(); return;
      case 'desc-open': {
        if (e.target.closest('a')) return;
        const t = task(ui.taskId);
        if (!ui.descOpen[t.id]) { ui.descOpen[t.id] = true; renderDetail(); }
        if (can('editDesc')) setTimeout(() => { const ed = $('#d-notes'); if (ed) { ed.focus(); placeCaretAtEnd(ed); } }, 0);
        return;
      }
      case 'desc-toggle': {
        const t = task(ui.taskId);
        flushEdit();
        ui.descOpen[t.id] = !ui.descOpen[t.id];
        renderDetail();
        if (ui.descOpen[t.id] && can('editDesc')) setTimeout(() => { const ed = $('#d-notes'); if (ed) { ed.focus(); placeCaretAtEnd(ed); } }, 0);
        else { const sec = $('.desc-sec'); if (sec) sec.scrollIntoView({ block: 'nearest' }); }
        return;
      }
      case 'my-part': { const t = task(ui.taskId); setMyPart(t, actEl.dataset.v === '1'); return; }
      case 'reopen-part': { e.stopPropagation(); const t = task(ui.taskId); const u = id; showMenu(actEl, [{ label: `Reopen ${fullName(userById(u)).split(' ')[0]}’s part`, icon: 'reply', run: () => reopenPart(t, u) }]); return; }
      case 'focus-search': { const sr = $('#search'); sr.focus(); sr.select(); return; }
      case 'cd-menu': e.stopPropagation(); toast('CD Status is set automatically when files are submitted and reviewed'); return;
      case 'submit-review': e.stopPropagation(); submitDialog(task(ui.taskId)); return;
      case 'withdraw-review': e.stopPropagation(); withdrawReview(task(ui.taskId)); return;
      case 'needs-cd': e.stopPropagation(); setNeedsCD(task(ui.taskId), actEl.checked); if (!(me() && (isAdm(me()) || me().role === 'am'))) renderDetail(); return;
      case 'cd-toggle': e.stopPropagation(); cdToggleFlow(id); return;
      case 'rr-tab': ui.rrTab = actEl.dataset.tab; renderContent(); return;
      case 'rr-open': e.preventDefault(); openTask(id); return;
      case 'rr-decide': e.stopPropagation(); decisionDialog(id); return;
      case 'rr-download': e.stopPropagation(); downloadReviewFiles(id); return;
      case 'rr-file': { const rt = task(actEl.dataset.taskId); const a = rt && findAttachment(rt, id); if (a) previewFile(a); return; }
      case 'assign-menu': e.stopPropagation(); assignMenu(actEl); return;
      case 'unassign': e.stopPropagation(); setAssignee(task(ui.taskId), id, false); return;
      case 'open-notif': openNotif(id); return;
      case 'notif-read': e.stopPropagation(); { const n = db.notifications.find((x) => x.id === id); if (n) { n.read = !n.read; persist(); renderSidebar(); renderContent(); } } return;
      case 'mark-all-read': myNotifs().forEach((n) => { n.read = true; }); persist(); renderSidebar(); renderContent(); return;
      case 'inbox-tab': ui.inboxTab = actEl.dataset.tab; renderContent(); return;
      case 'me-menu': e.stopPropagation(); meMenu(actEl); return;
      case 'add-member': addMemberFlow(); return;
      case 'member-menu': e.stopPropagation(); memberMenu(actEl, id); return;
      case 'member-projects': e.stopPropagation(); { const u = userById(id); if (u) projectAccessDialog(u); } return;
      case 'cf-sync-now': api('POST', '/api/cloudflare').then(paintCfStatus).catch((err) => toast(err.message)); return;
      case 'change-photo': changePhoto(); return;
      case 'team-tab': ui.teamTab = actEl.dataset.tab; renderContent(); return;
      case 'appicon-upload': appIconUploadFlow(); return;
      case 'mac-update': MacUpdate.run(); return;
      case 'appicon-reset': appIconResetFlow(); return;
      case 'remove-photo': { const u = me(); if (u.avatar) Host.call('trashPath', { path: u.avatar }).catch(() => {}); u.avatar = null; persist(); render(); return; }
      case 'save-profile': saveProfile(); return;
      case 'change-password': changePasswordFlow(); return;
      case 'toggle-season': { const u = me(); u.prefs = u.prefs || {}; u.prefs.seasonOff = !u.prefs.seasonOff; persist(); renderSidebar(); renderContent(); toast(u.prefs.seasonOff ? 'Seasonal decorations off' : 'Seasonal decorations on'); return; }
      case 'toggle-digest': { const u = me(); u.prefs = u.prefs || {}; u.prefs.digestOff = !u.prefs.digestOff; persist(); renderContent(); toast(u.prefs.digestOff ? 'Morning summary off' : 'Morning summary on — 10:30 am, Monday to Friday'); return; }
      case 'digest-test': Digest.test(); return;
      case 'toggle-sound': { const u = me(); u.prefs.sound = u.prefs.sound === false; persist(); renderContent(); return; }
      case 'toggle-notif-type': {
        const u = me(); u.prefs = u.prefs || {}; u.prefs.notifOff = u.prefs.notifOff || {};
        const k = actEl.dataset.k;
        if (u.prefs.notifOff[k]) delete u.prefs.notifOff[k]; else u.prefs.notifOff[k] = true;
        actEl.classList.toggle('on', !u.prefs.notifOff[k]); actEl.title = u.prefs.notifOff[k] ? 'Off' : 'On';
        persist(0); return;
      }
      case 'reload-app': reloadApp(actEl); return;
      case 'import-mac': importFromMac(); return;
      case 'whats-new': whatsNewDialog(false); return;
      case 'upd': {
        const a = actEl.dataset.a;
        if (a === 'rollback') { const ok = await dialog({ title: 'Go back to the previous version?', body: 'Everyone’s app will show a Reload button. Your data is kept — a copy of the database is made first.', okText: 'Roll back', danger: true }); if (!ok) return; }
        if (a === 'update') { const ok = await dialog({ title: 'Update E11 Console now?', body: 'It takes about 10 seconds. People see “Reconnecting…” briefly, then a Reload button. A copy of the database is made first.', okText: 'Update now' }); if (!ok) return; }
        loadUpdates(a); return;
      }
      case 'allow-notifs': try { Notification.requestPermission().then(() => renderContent()); } catch (err) { /* unsupported */ } return;
      case 'test-notif': alertUser({ title: 'E11 Console', body: 'This is how new notifications will look and sound.', taskId: null }, true); return;
      case 'prio-menu': e.stopPropagation(); prioMenu(actEl, actEl.dataset.key); return;
      case 'clear-golive': { const t = task(ui.taskId); if (t) Cal.setGolive(t, null); return; }
      case 'occ-accept': { const t = task(ui.taskId); if (t) Cal.setOccasion(t, actEl.dataset.id); return; }
      case 'clear-start': { const t = task(ui.taskId); logChange(t, 'the <b>start date</b>', fmtDay(t.start), ''); t.start = null; t.updatedAt = nowISO(); commit(); return; }
      case 'cl-toggle': { const t = task(ui.taskId); const c = t.checklist.find((x) => x.id === id); if (c) { c.done = !c.done; logActivity(t, `${c.done ? 'checked' : 'unchecked'} <b>${esc(c.text)}</b>`); t.updatedAt = nowISO(); commit(); } return; }
      case 'cl-delete': { if (!can('deleteChecklist')) return denied(); const t = task(ui.taskId); const c = t.checklist.find((x) => x.id === id); if (c) logActivity(t, `removed checklist item ${struck(c.text)}`); t.checklist = t.checklist.filter((x) => x.id !== id); t.updatedAt = nowISO(); commit(); return; }
      case 'act-filter': ui.activityFilter = actEl.dataset.f; ui.thread = null; ui.replyTo = null; renderDetail(); { const f = $('.tm-feed'); if (f) f.scrollTop = f.scrollHeight; } return;
      case 'react-menu': e.stopPropagation(); reactMenu(actEl, id); return;
      case 'react': toggleReaction(id, actEl.dataset.emoji); return;
      case 'comment-menu': e.stopPropagation(); commentMenu(actEl, id); return;
      case 'reply': {
        const t = task(ui.taskId);
        if (ui.thread !== id) {
          // carry over anything already typed in the comment box
          const mk = draftKey(t, null), rk = draftKey(t, id);
          if (ui.commentDraft[mk] && !ui.commentDraft[rk]) { ui.commentDraft[rk] = ui.commentDraft[mk]; delete ui.commentDraft[mk]; }
          if ((ui.commentFiles[mk] || []).length && !(ui.commentFiles[rk] || []).length) { ui.commentFiles[rk] = ui.commentFiles[mk]; delete ui.commentFiles[mk]; }
          ui.replyTo = id;
          if (ui.detailMode === 'side' || (typeof Phone !== 'undefined' && Phone.on)) ui.sideTab = 'comments';
          renderDetail();
        }
        setTimeout(() => { const el = $('#d-comment'); if (el) { el.focus(); placeCaretAtEnd(el); } }, 0);
        return;
      }
      case 'cancel-reply': ui.replyTo = null; renderDetail(); setTimeout(() => { const el = $('#d-comment'); if (el) el.focus(); }, 0); return;
      case 'open-thread': openThread(id); return;
      case 'open-client': e.stopPropagation(); openClient(id); return;
      case 'add-client': addClientDialog(); return;
      case 'client-menu': e.stopPropagation(); { const c = clientById(id); if (c) clientMenu(actEl, c); } return;
      case 'open-cfolder': PageHistory.mark(); ui.folderId = id; $('#content').scrollTop = 0; render(); PageHistory.mark(); return;
      case 'cfolder-menu': e.stopPropagation(); { const c = clientById(ui.clientId); const f = c && c.folders.find((x) => x.id === id); if (f) folderMenu(actEl, c, f); } return;
      case 'add-cfolder': { const c = clientById(ui.clientId); if (c) addFolderFlow(c); } return;
      case 'ca-upload': pickIntoFolder(); return;
      case 'open-cfolder-of': e.stopPropagation(); openClient(actEl.dataset.client, id); return;
      case 'ca-q-clear': { const i = $('#ca-q'); if (i) { i.value = ''; runCaSearch(i); i.focus(); } } return;
      case 'ca-remove': e.stopPropagation(); removeClientFile(id); return;
      case 'ca-download': e.stopPropagation(); { const a = clientFileById(id); if (a) downloadClientFiles([a], a.name.replace(/\.[^.]+$/, '')); } return;
      case 'ca-download-all': { const { c, f } = curFolder(); if (f) downloadClientFiles(f.files, `${c.name} - ${f.name}`); } return;
      case 'close-thread': closeThread(); return;
      case 'tr-filter': ui.trashFilter = actEl.dataset.k; renderContent(); return;
      case 'tr-restore': restoreTrash(id); return;
      case 'tr-forever': eraseTrashFlow(id); return;
      case 'tr-empty': emptyTrashFlow(); return;
      case 'tr-preview': { const it = trashList().find((x) => x.id === id); const a = it && trashFiles(it).find((x) => x.id === actEl.dataset.file); if (a) previewFile(a); return; }
      case 'mention-user': e.stopPropagation(); mentionInComposer(id); return;
      case 'cancel-edit': ui.editingComment = null; renderDetail(); return;
      case 'save-edit': saveEdit(id); return;
      case 'open-url': e.preventDefault(); Host.call('openURL', { url: actEl.dataset.url }).catch(() => { try { window.open(actEl.dataset.url); } catch (_) { /* ignore */ } }); return;
      case 'delete-comment': deleteComment(id); return;
      default: break;
    }
    if (act === 'rename-project' || act === 'rename-section') { /* handled on dblclick */ }
  }

  const nav = e.target.closest('[data-nav]');
  if (nav) {
    // My Tasks from the sidebar always starts fresh: no filters, To do tab
    if (nav.dataset.nav === 'mytasks' && nav.closest('#sidebar')) { ui.workF = null; ui.myTasksTab = 'todo'; }
    go(nav.dataset.nav); return;
  }
  const pr = e.target.closest('[data-project]');
  if (pr && !e.target.closest('[data-action]')) { go('project', pr.dataset.project); return; }

  const tr = e.target.closest('[data-task]');
  if (tr && !e.target.closest('button, input, textarea')) { openTask(tr.dataset.task); return; }

  // Click on empty content closes the detail pane
  if (ui.taskId && e.target.closest('#content') && !e.target.closest('[data-task], [data-cal], .add-row, .col-add-input, .add-section, .add-col')) closeDetail();
});

document.addEventListener('dblclick', (e) => {
  const el = e.target.closest('[data-action="rename-project"], [data-action="rename-section"]');
  if (!el || !isAdmin()) return;      // only Admins change a client and its statuses
  if (el.dataset.action === 'rename-project') renameProject(el.dataset.id);
  else renameSectionInline(el.dataset.id);
});

function rerenderKeepingAdd(sid) {
  renderContent();
  const a = $(`.add-row[data-section="${sid}"]`);
  if (a) { a.click(); a.scrollIntoView({ block: 'nearest' }); }
}

function openThread(cid) {
  const t = task(ui.taskId);
  if (!t || !t.comments.some((c) => c.id === cid)) return;
  const f = $('#detail .tm-feed');
  ui.mainFeedScroll = f && !ui.thread ? f.scrollTop : ui.mainFeedScroll;
  ui.thread = cid; ui.replyTo = null;
  if (ui.detailMode === 'side' || (typeof Phone !== 'undefined' && Phone.on)) ui.sideTab = 'comments';
  renderDetail();
  const feed = $('#detail .tm-feed');
  if (feed) stickFeedToBottom(feed);
}
function closeThread() {
  const back = ui.thread;
  ui.thread = null;
  renderDetail();
  const feed = $('#detail .tm-feed');
  // back on the main page: always land on the latest comment
  if (feed) stickFeedToBottom(feed);
}

function addComment(replyTo) {
  const t = task(ui.taskId);
  if (!t) return;
  const key = draftKey(t, replyTo);
  const box = $(`[data-draft-key="${key}"]`);
  const empty = !box || editorEmpty(box);
  const text = empty ? '' : box.innerText.trim();
  const html = empty ? '' : sanitizeHTML(box.innerHTML);
  const files = ui.commentFiles[key] || [];
  if (!text && !files.length) return;
  const cid = uid();
  t.comments.push({ id: cid, text, html, at: nowISO(), attachments: files, parentId: replyTo || null, reactions: {}, authorId: currentUserId });
  const mentioned = mentionsIn(html);
  mentioned.forEach((u) => pushNotif(u, t, 'mention', `mentioned you in a ${replyTo ? 'reply' : 'comment'} on`, { snippet: trunc(text, 160), commentId: cid }));
  // thread participants also hear about replies
  const skip = [...mentioned];
  if (replyTo) {
    const people = new Set(t.comments.filter((c) => c.id === replyTo || c.parentId === replyTo).map((c) => c.authorId));
    people.forEach((u) => { if (!mentioned.has(u) && !watchersOf(t).includes(u)) pushNotif(u, t, 'comment', 'replied in a thread on', { snippet: trunc(text, 160), commentId: cid }); });
  }
  notifyWatchers(t, 'comment', replyTo ? 'replied to a comment on' : 'commented on', { snippet: trunc(text || `${files.length} file${files.length === 1 ? '' : 's'}`, 160), skip, commentId: cid });
  delete ui.commentFiles[key];
  delete ui.commentDraft[key];
  const fromMain = replyTo && ui.thread !== replyTo;
  if (fromMain) ui.replyTo = null;
  t.updatedAt = nowISO();
  commit();
  setTimeout(() => {
    const b = $('#d-comment'); if (b) b.focus();
    const f = $('.tm-feed');
    if (!f) return;
    if (!fromMain) { f.scrollTop = f.scrollHeight; return; }
    // reply sent from the main page: show its thread with the new count
    const el = $(`#detail [data-thread="${replyTo}"]`);
    if (el) { el.scrollIntoView({ block: 'nearest' }); const o = el.querySelector('.thread-open'); if (o) { o.classList.add('flash'); setTimeout(() => o.classList.remove('flash'), 1800); } }
  }, 0);
}

function saveEdit(cid) {
  const t = task(ui.taskId);
  const c = t.comments.find((x) => x.id === cid);
  const el = $('#edit-comment');
  if (!c || !el) return;
  const v = editorEmpty(el) ? '' : el.innerText.trim();
  if (!v && !(c.attachments || []).length) return;
  const html = v ? sanitizeHTML(el.innerHTML) : '';
  if (v !== c.text || html !== (c.html || '')) {
    const before = mentionsIn(c.html);
    mentionsIn(html).forEach((u) => { if (!before.has(u)) pushNotif(u, t, 'mention', 'mentioned you in a comment on', { snippet: trunc(v, 160), commentId: c.id }); });
    c.text = v; c.html = html; c.editedAt = nowISO();
  }
  ui.editingComment = null;
  commit();
}

/* Detail pane inputs (no full re-render while typing) */
document.addEventListener('input', (e) => {
  if (!db || !currentUserId) return;
  const t = ui.taskId && task(ui.taskId);
  const el = e.target;
  if (el.id === 'search') {
    const v = el.value;
    if (v.trim() && !ui.search) ui.prevView = { view: ui.view, projectId: ui.projectId };
    ui.search = v.trim() ? v : '';
    if (!ui.search && ui.prevView) { ui.view = ui.prevView.view; ui.projectId = ui.prevView.projectId; }
    renderSidebar(); renderTitle(); renderContent();
    return;
  }
  if (!t) return;
  if (el.id === 'd-title') { t.title = el.value.replace(/\n/g, ' '); t.updatedAt = nowISO(); autosize(el); commit({ keepDetail: true, delay: 400 }); }
  else if (el.id === 'd-notes') {
    if (editorEmpty(el) && !el.querySelector('blockquote')) el.innerHTML = '';
    t.notes = el.innerText.trim(); t.notesHtml = t.notes ? sanitizeHTML(el.innerHTML) : '';
    t.updatedAt = nowISO(); commit({ keepDetail: true, delay: 500 });
  }
  else if (el.classList.contains('sub-title')) {
    const s = task(el.dataset.subId);
    if (s) { s.title = el.value; s.updatedAt = nowISO(); commit({ keepDetail: true, delay: 400 }); }
  } else if (el.dataset && el.dataset.draftKey) {
    if (editorEmpty(el) && !el.querySelector('blockquote')) el.innerHTML = '';
    ui.commentDraft[el.dataset.draftKey] = el.innerHTML;
  }
  else if (el.id === 'edit-comment') autosize(el);
  else if (el.classList.contains('cl-text')) {
    const c = (t.checklist || []).find((x) => x.id === el.dataset.clId);
    if (c) { c.text = el.value; t.updatedAt = nowISO(); commit({ keepDetail: true, delay: 400 }); }
  }
});

document.addEventListener('change', (e) => {
  if (!db || !currentUserId) return;
  const t = ui.taskId && task(ui.taskId);
  if (!t) return;
  const el = e.target;
  if (el.id === 'd-due') { setDue(t, el.value || null); commit(); }
  else if (el.id === 'd-golive') Cal.setGolive(t, el.value || null);
  else if (el.id === 'd-start') { const o = t.start; t.start = el.value || null; logChange(t, 'the <b>start date</b>', fmtDay(o), fmtDay(t.start)); t.updatedAt = nowISO(); commit(); }
  else if (el.id === 'd-project') { if (!can('editProject')) { denied(); renderDetail(); return; } setTaskProject(t, el.value || null); commit(); }
  else if (el.id === 'd-section') { moveTask(t.id, el.value, null, false); commit(); }
});

document.addEventListener('keydown', (e) => {
  if (!db || !currentUserId) return;
  const el = e.target;
  const mod = e.metaKey || e.ctrlKey;
  if (mod && !e.shiftKey && !e.altKey && (e.key === '[' || e.key === ']') && !/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) && !el.isContentEditable) {
    e.preventDefault(); if (e.key === '[') PageHistory.back(); else PageHistory.forward(); return;
  }

  if (el.id === 'd-title' && e.key === 'Enter') { e.preventDefault(); el.blur(); return; }
  if (el.id === 'd-tag-input') {
    if ((e.key === 'Enter' || e.key === ',') && el.value.trim()) {
      e.preventDefault();
      const t = task(ui.taskId);
      const v = el.value.trim().replace(/,$/, '');
      if (!t.tags.some((g) => g.toLowerCase() === v.toLowerCase())) { t.tags.push(v); logActivity(t, `added tag <b>${esc(v)}</b>`); }
      t.updatedAt = nowISO();
      commit();
      setTimeout(() => { const i = $('#d-tag-input'); if (i) i.focus(); }, 0);
      return;
    }
    if (e.key === 'Backspace' && !el.value) {
      const t = task(ui.taskId);
      if (t.tags.length && can('removeTag')) { logActivity(t, `removed tag ${struck(t.tags[t.tags.length - 1])}`); t.tags.pop(); commit(); setTimeout(() => { const i = $('#d-tag-input'); if (i) i.focus(); }, 0); }
      return;
    }
  }
  if (el.id === 'd-sub-add' && e.key === 'Enter' && el.value.trim() && !e.isComposing) {
    e.preventDefault();
    if (!can('createTask')) return denied();
    createTask({ parentId: ui.taskId, title: el.value.trim() });
    logActivity(task(ui.taskId), `added subtask <b>${esc(el.value.trim())}</b>`);
    commit();
    setTimeout(() => { const i = $('#d-sub-add'); if (i) i.focus(); }, 0);
    return;
  }
  if (el.classList && el.classList.contains('sub-title') && e.key === 'Enter') { e.preventDefault(); const n = $('#d-sub-add'); if (n) n.focus(); return; }
  if (el.classList && el.classList.contains('rt-editor') && mod && !e.shiftKey && ['b', 'i', 'u'].includes(e.key.toLowerCase())) {
    e.preventDefault();
    document.execCommand({ b: 'bold', i: 'italic', u: 'underline' }[e.key.toLowerCase()], false, null);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    return;
  }
  if (el.dataset && el.dataset.draftKey && e.key === 'Enter' && mod) { e.preventDefault(); addComment(el.dataset.replyTo || null); return; }
  if (el.id === 'edit-comment') {
    if (e.key === 'Enter' && mod) { e.preventDefault(); saveEdit(ui.editingComment); return; }
    if (e.key === 'Escape') { e.preventDefault(); ui.editingComment = null; renderDetail(); return; }
  }
  if (el.dataset && el.dataset.replyTo && e.key === 'Escape' && ui.replyTo && ui.thread !== el.dataset.replyTo) { e.preventDefault(); ui.replyTo = null; renderDetail(); setTimeout(() => { const b = $('#d-comment'); if (b) b.focus(); }, 0); return; }
  if (el.id === 'd-cl-add' && e.key === 'Enter' && el.value.trim() && !e.isComposing) {
    e.preventDefault();
    const t = task(ui.taskId);
    t.checklist.push({ id: uid(), text: el.value.trim(), done: false });
    logActivity(t, `added checklist item <b>${esc(el.value.trim())}</b>`);
    t.updatedAt = nowISO();
    commit();
    setTimeout(() => { const i = $('#d-cl-add'); if (i) i.focus(); }, 0);
    return;
  }
  if (el.classList && el.classList.contains('cl-text') && e.key === 'Enter') { e.preventDefault(); const n = $('#d-cl-add'); if (n) n.focus(); return; }
  if (el.id === 'quick-add' && e.key === 'Enter' && el.value.trim() && !e.isComposing) {
    e.preventDefault();
    if (!can('createTask')) return denied();
    createTask({ title: el.value.trim(), due: el.dataset.day || todayStr() });
    el.value = '';
    commit();
    setTimeout(() => { const i = $('#quick-add'); if (i) i.focus(); }, 0);
    return;
  }

  if (mod && e.key.toLowerCase() === 'f' && $('#ca-q')) { e.preventDefault(); $('#ca-q').focus(); $('#ca-q').select(); return; }
  if (mod && e.key.toLowerCase() === 'k') { e.preventDefault(); const s = $('#search'); s.focus(); s.select(); return; }
  if (mod && e.key.toLowerCase() === 'n') { e.preventDefault(); if (e.shiftKey) newProjectFlow(); else if (can('createTask')) newTaskInContext(); else denied(); return; }
  if (e.key === 'Escape') {
    if ($('.lightbox') || $('.fv')) { $('#overlay-root').innerHTML = ''; return; }
    if ($('.menu')) { closeMenus(); return; }
    if (el.id === 'search') { el.value = ''; el.dispatchEvent(new Event('input', { bubbles: true })); el.blur(); return; }
    if (ui.taskId && ui.thread) { if (el.blur) el.blur(); closeThread(); return; }
    if (ui.taskId) { if (el.blur) el.blur(); closeDetail(); return; }
  }
});

document.addEventListener('paste', (e) => {
  const ed = e.target.closest && e.target.closest('.rt-editor');
  if (!ed) return;
  e.preventDefault();
  const txt = (e.clipboardData || window.clipboardData).getData('text/plain');
  if (ui.fileClip && txt && txt.trim() === ui.fileClip.token) { pasteFileInto(ed); return; }
  const html = textWithMentions(txt);
  if (html) { document.execCommand('insertHTML', false, html); ed.dispatchEvent(new Event('input', { bubbles: true })); }
  else document.execCommand('insertText', false, txt);
});
// "@Full Name" (or @emailname) in pasted text → mention chip, when that person is on the team.
// Returns null when nothing matched so a normal paste is used.
function textWithMentions(txt) {
  if (!db || !txt || txt.indexOf('@') < 0) return null;
  const names = [];
  activeUsers().forEach((u) => {
    names.push({ u, k: fullName(u) });
    names.push({ u, k: u.email.split('@')[0] });
    if (u.id === currentUserId) names.push({ u, k: 'Me' });
  });
  names.sort((a, b) => b.k.length - a.k.length);
  let out = '', i = 0, found = false;
  while (i < txt.length) {
    const ch = txt[i];
    if (ch === '@' && (i === 0 || /[\s(\[,;:]/.test(txt[i - 1]))) {
      const rest = txt.slice(i + 1).toLowerCase();
      const hit = names.find((x) => rest.startsWith(x.k.toLowerCase()) && !/[\w@]/.test(rest.charAt(x.k.length)));
      if (hit) {
        out += `<span class="mention" data-user="${esc(hit.u.id)}" contenteditable="false">@${esc(fullName(hit.u))}</span>`;
        i += 1 + hit.k.length; found = true;
        continue;
      }
    }
    out += ch === '\n' ? '<br>' : esc(ch);
    i++;
  }
  return found ? out : null;
}

/* ================= Drag and drop ================= */
let dragId = null;
function clearDropMarks() { $$('.drop-before, .drop-after, .drop-target').forEach((x) => x.classList.remove('drop-before', 'drop-after', 'drop-target')); }

document.addEventListener('dragstart', (e) => {
  const el = e.target.closest && e.target.closest('[data-task][draggable="true"]');
  if (!el) return;
  dragId = el.dataset.task;
  e.dataTransfer.effectAllowed = 'move';
  try { e.dataTransfer.setData('text/plain', dragId); } catch (_) { /* ignore */ }
  setTimeout(() => el.classList.add('dragging'), 0);
});
document.addEventListener('dragend', () => { dragId = null; clearDropMarks(); $$('.dragging').forEach((x) => x.classList.remove('dragging')); });

function dropInfo(e) {
  const target = e.target.closest('[data-task][draggable="true"]');
  if (target && target.dataset.task !== dragId) {
    const r = target.getBoundingClientRect();
    const after = e.clientY > r.top + r.height / 2;
    const secEl = target.closest('.section[data-section]');
    const sid = secEl ? secEl.dataset.section : target.closest('.col[data-col]').dataset.col;
    return { el: target, sectionId: sid, targetId: target.dataset.task, after };
  }
  const sec = e.target.closest('.section[data-section], .col[data-col]');
  if (sec) return { el: sec.matches('[data-col]') ? sec : ($('.section-head', sec) || sec), sectionId: sec.dataset.section || sec.dataset.col, targetId: null, zone: true };
  return null;
}
document.addEventListener('dragover', (e) => {
  if (!dragId) return;
  const info = dropInfo(e);
  if (!info) return;
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';
  clearDropMarks();
  if (info.targetId) info.el.classList.add(info.after ? 'drop-after' : 'drop-before');
  else info.el.classList.add('drop-target');
});
document.addEventListener('drop', (e) => {
  if (!dragId) return;
  const info = dropInfo(e);
  clearDropMarks();
  if (!info) return;
  e.preventDefault();
  const dt = task(dragId);
  dragId = null;
  if (dt && dt.sectionId !== info.sectionId) changeStatus(dt, info.sectionId, info.targetId, info.after);
  else if (dt) { moveTask(dt.id, info.sectionId, info.targetId, info.after); commit(); }
});

/* ================= Client Assets ================= */
// db.clients = [{ id, name, logo, dir: 'Clients/<name>', folders: [{ id, name, dir, files: [att] }] }]
// Admins and Account Managers add clients, folders and files; only Admins delete a client.
const DEFAULT_FOLDERS = ['Logos', 'Brand Guidelines', 'Fonts', 'Files'];
const FONT_EXT = ['otf', 'ttf', 'woff', 'woff2'];
const isFont = (a) => FONT_EXT.includes(fileExt(a.name));
const canAssets = () => { const u = me(); return !!u && (isAdm(u) || u.role === 'am'); };
// Client Assets: anyone adds folders and files; people remove (or rename) only the folders and files they added,
// Account Managers anyone's; the folders made with the client stay unless an Admin removes them (the server checks the same)
const canAddAssets = () => { const u = me(); return !!u && !isFinUser(u) && u.role !== 'freelancer'; };   // freelancers only look
const isAutoFolder = (c, f) => !!f.auto || (DEFAULT_FOLDERS.includes(f.name) && (!f.createdBy || f.createdBy === c.createdBy) && Math.abs(Date.parse(f.createdAt || 0) - Date.parse(c.createdAt || 0)) < 60000);
// (Account Managers remove anyone's files and added folders)
const canDelAsset = (a) => canAddAssets() && (canAssets() || (!!a && a.addedBy === currentUserId));
const canEditFolder = (c, f) => isAdmin() || (canAddAssets() && !isAutoFolder(c, f) && (canAssets() || f.createdBy === currentUserId));
const canDelFolder = (c, f) => canEditFolder(c, f) && (canAssets() || f.files.every((a) => a.addedBy === currentUserId));
const isAdmin = () => !!isAdm(me());
const clientById = (id) => (db.clients || []).find((c) => c.id === id) || null;
const clientsSorted = () => (db.clients || []).slice().sort((a, b) => a.name.localeCompare(b.name));
const clientFileCount = (c) => c.folders.reduce((n, f) => n + f.files.length, 0);
// "Ford", "ford ", "FORD." and "Ford" with different spacing are the same client
const clientKey = (n) => String(n || '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/&/g, 'and').replace(/[^a-z0-9؀-ۿ]+/g, '');
const dupClient = (name, exceptId) => { const k = clientKey(name); return k ? (db.clients || []).find((c) => c.id !== exceptId && clientKey(c.name) === k) || null : null; };
const dupMsg = (c) => `There is already a client named “${c.name}”.`;
const diskSafe = (s) => String(s).replace(/[\/:\\]/g, '-').replace(/^\.+/, '').replace(/\s+/g, ' ').trim().slice(0, 80) || 'Untitled';
function freeDir(base, name, taken) {
  const n = diskSafe(name);
  let d = `${base}/${n}`, i = 2;
  while (taken.some((x) => x.toLowerCase() === d.toLowerCase())) d = `${base}/${n} (${i++})`;
  return d;
}
function newFolder(c, name, auto = false) {
  const f = { id: 'cf-' + uid(), name: name.trim(), dir: freeDir(c.dir, name, c.folders.map((x) => x.dir)), files: [], createdAt: nowISO(), createdBy: currentUserId, ...(auto ? { auto: true } : {}) };
  c.folders.push(f);
  Host.call('makeDir', { path: f.dir }).catch(() => {});
  return f;
}
function createClient(name, logo) {
  const c = { id: 'cl-' + uid(), name: name.trim().replace(/\s+/g, ' '), logo: logo || null, dir: '', folders: [], createdAt: nowISO(), createdBy: currentUserId };
  c.dir = freeDir('Clients', c.name, (db.clients || []).map((x) => x.dir));
  DEFAULT_FOLDERS.forEach((n) => newFolder(c, n, true));   // made with the client: only an Admin removes them
  db.clients.push(c);
  return c;
}
function clientFileById(id) {
  for (const c of db.clients || []) for (const f of c.folders) { const a = f.files.find((x) => x.id === id); if (a) return a; }
  return null;
}
const clientOfProject = (p) => (p && p.clientId ? clientById(p.clientId) : null);
function openClient(id, folderId = null) {
  if (!clientById(id)) { toast('That client has been removed'); return; }
  ui.caQ = ''; ui.caScope = null;
  if (ui.taskId) closeDetail();
  ui.clientId = id; ui.folderId = folderId;
  go('client');
}
function clientLogoHTML(c, size) {
  return c.logo
    ? `<span class="cl-logo ${isSquareLogo(c.logo) ? 'sq' : ''}" style="--s:${size}px"><img src="${'/__file/' + c.logo.split('/').map(encodeURIComponent).join('/')}" alt=""></span>`
    : `<span class="cl-logo mono" style="--s:${size}px;--c:${avColor(c.id)}">${esc(initials(c.name))}</span>`;
}

/* ---- Pages ---- */
function viewClients() {
  const list = clientsSorted();
  const cards = list.map((c) => `<div class="ca-card" data-action="open-client" data-id="${c.id}" data-q="${esc(c.name.toLowerCase())}" title="Open ${esc(c.name)}">
      <div class="ca-logo">${clientLogoHTML(c, 120)}</div>
      <div class="ca-name">${esc(c.name)}</div>
      <div class="ca-meta">${c.folders.length} folder${c.folders.length === 1 ? '' : 's'} · ${clientFileCount(c)} file${clientFileCount(c) === 1 ? '' : 's'}</div>
    </div>`).join('');
  const grid = `<div class="ca-grid">
      ${canAssets() ? `<div class="ca-card add" data-action="add-client"><div class="ca-logo"><span class="ca-plus">${icon('plus')}</span></div><div class="ca-name">Add client</div><div class="ca-meta">Name and logo</div></div>` : ''}
      ${cards}
    </div>
    ${list.length ? '' : `<div class="empty"><div class="big">No clients yet</div>${canAssets() ? 'Add your first client to start collecting their brand assets.' : 'An Admin or Account Manager will add clients here.'}</div>`}`;
  return `<div class="ca-page">
    <div class="ca-intro">
      <div><h2>Brand guidelines, logos and fonts for every client</h2><p>Open a client to find what you need, then use <b>${icon('copy')}Copy</b> on any file to paste it straight into a task — no downloading or re-uploading.</p></div>
    </div>
    ${caSearchBar(null)}
    <div id="ca-body" data-scope="">${ui.caQ && !ui.caScope ? caResultsHTML(ui.caQ, null) : grid}</div>
    <template id="ca-default">${grid}</template>
  </div>`;
}

function viewClient(c) {
  // no logo yet but the Logos folder has an image (e.g. added before this existed): use it
  if (!c.logo && canAddAssets()) { const lf = c.folders.find((f) => f.name === 'Logos'); if (lf && lf.files.length) setTimeout(() => autoLogo(c, lf), 0); }
  const projects = db.projects.filter((p) => p.clientId === c.id);
  const head = `<div class="cl-head">
      <div class="cl-head-logo">${clientLogoHTML(c, 88)}</div>
      <div class="cl-head-txt"><h2>${esc(c.name)}</h2>
        <div class="cl-head-meta">${c.folders.length} folder${c.folders.length === 1 ? '' : 's'} · ${clientFileCount(c)} file${clientFileCount(c) === 1 ? '' : 's'}${projects.length ? ` · Clients: ${projects.map((p) => `<a class="cl-proj" data-action="go-project" data-id="${p.id}"><i style="background:${p.color}"></i>${esc(p.name)}</a>`).join('')}` : ''}</div>
      </div>
      ${canAssets() ? `<button class="btn" data-action="client-menu" data-id="${c.id}">${icon('more')}Client options</button>` : ''}
    </div>`;
  const folders = c.folders.map((f) => {
    const imgs = f.files.filter((a) => isImage(a)).slice(0, 3);
    return `<div class="cf-card" data-action="open-cfolder" data-id="${f.id}" title="Open ${esc(f.name)}">
      <div class="cf-ic">${icon('folder')}</div>
      <div class="cf-name">${esc(f.name)}</div>
      <div class="cf-meta">${f.files.length ? `${f.files.length} file${f.files.length === 1 ? '' : 's'}` : 'Empty'}</div>
      ${imgs.length && Host.isNative ? `<div class="cf-peek">${imgs.map((a) => `<img src="${imgUrl(a, 160)}" alt="" loading="lazy">`).join('')}</div>` : ''}
      ${canEditFolder(c, f) ? `<button class="icon-btn sm cf-more" data-action="cfolder-menu" data-id="${f.id}" title="Folder options">${icon('more')}</button>` : ''}
    </div>`;
  }).join('');
  const grid = `<div class="cf-grid">${folders}
      ${canAddAssets() ? `<div class="cf-card add" data-action="add-cfolder"><div class="cf-ic">${icon('plus')}</div><div class="cf-name">New folder</div><div class="cf-meta">For anything else</div></div>` : ''}
    </div>`;
  const q = ui.caScope === c.id ? ui.caQ : '';
  return `<div class="ca-page">${head}
    ${caSearchBar(c)}
    <div id="ca-body" data-scope="${c.id}">${q ? caResultsHTML(q, c) : grid}</div>
    <template id="ca-default">${grid}</template></div>`;
}

function caTile(f, a, loc = null) {
  const kind = fileKind(a);
  let inner;
  if (isFont(a)) inner = `<div class="font-sample" style="font-family:'caf-${a.id}'"><b>Aa</b><span>The quick brown fox · ابجد ١٢٣</span></div>`;
  else if (kind === 'image' && Host.isNative) inner = `<img src="${imgUrl(a, 640)}" alt="" loading="lazy">`;
  else if (Host.isNative) inner = thumbImg(a, 'tile').replace('data-thumb-for="', 'data-thumb-client="1" data-thumb-for="');
  else inner = `<div class="thumb-ph"><span class="ext">${esc(fileExt(a.name) || 'file')}</span></div>`;
  return `<div class="tile ca-tile" data-action="tile-open" data-id="${a.id}" title="${esc(a.name)}">
    <div class="tile-img ${isFont(a) ? 'is-font' : ''}">${inner}${kind === 'video' ? `<span class="tile-play">${icon('play')}</span>` : ''}</div>
    <div class="tile-meta"><span>${loc ? caMark(a.name, loc.q) : esc(a.name)}</span>${loc ? `<a class="ca-loc" data-action="open-cfolder-of" data-client="${loc.c.id}" data-id="${f.id}" title="Open this folder">${clientLogoHTML(loc.c, 14)}${esc(loc.c.name)} › ${esc(f.name)}</a>` : ''}<small>${fmtSize(a.size)}${a.addedBy ? ` · ${esc(firstName(a.addedBy))}` : ''}</small></div>
    <button class="ca-copy" data-action="copy-att" data-id="${a.id}" title="Copy — paste into any task comment or description">${icon('copy')}Copy</button>
    <div class="tile-actions">
      <button class="icon-btn sm" data-action="quicklook" data-id="${a.id}" title="Preview">${icon('search')}</button>
      <button class="icon-btn sm" data-action="ca-download" data-id="${a.id}" title="Download to your Downloads folder">${icon('download')}</button>
      ${Host.isServer ? '' : `<button class="icon-btn sm" data-action="reveal-att" data-id="${a.id}" title="${FINDER_LABEL}">${icon('folder')}</button>`}
      ${canDelAsset(a) && !loc ? `<button class="icon-btn sm" data-action="ca-remove" data-id="${a.id}" title="Delete">${icon('trash')}</button>` : ''}
    </div>
  </div>`;
}


/* ---- Client Assets search: clients, folders and files (by name, type or client) ---- */
const caNorm = (s) => String(s || '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '');
const caTerms = (q) => caNorm(q).split(/[\s,]+/).map((t) => t.replace(/^\./, '')).filter(Boolean);
// Highlight the searched words inside a name
function caMark(name, q) {
  const terms = caTerms(q);
  const src = String(name), low = caNorm(src);
  const hit = new Array(src.length).fill(false);
  terms.forEach((t) => { let i = low.indexOf(t); while (i >= 0) { for (let k = i; k < i + t.length && k < src.length; k++) hit[k] = true; i = low.indexOf(t, i + 1); } });
  let out = '', on = false;
  for (let i = 0; i < src.length; i++) {
    if (hit[i] && !on) { out += '<mark>'; on = true; } else if (!hit[i] && on) { out += '</mark>'; on = false; }
    out += esc(src[i]);
  }
  return out + (on ? '</mark>' : '');
}
function caSearch(q, scope, loose) {
  const terms = caTerms(q);
  if (!terms.length) return { clients: [], folders: [], files: [] };
  // exact pieces first; if nothing matches, allow small typos ("frod" → ford, "gudelines" → guidelines)
  const near = (t, hay) => {
    if (hay.includes(t)) return true;
    if (!loose || !typoLimit(t)) return false;
    const lim = typoLimit(t);
    return sWords(hay).some((w) => editDist(t, w, lim) <= lim || (w.length > t.length && editDist(t, w.slice(0, t.length), lim) <= lim));
  };
  const all = (hay) => { const h = caNorm(hay); return terms.every((t) => near(t, h)); };
  const some = (hay) => { const h = caNorm(hay); return terms.some((t) => near(t, h)); };
  const list = scope ? [scope] : clientsSorted();
  const clients = scope ? [] : list.filter((c) => all(c.name));
  const folders = [], files = [];
  list.forEach((c) => c.folders.forEach((f) => {
    if (all(`${c.name} ${f.name}`) && some(f.name)) folders.push({ c, f });
    f.files.forEach((a) => {
      const kindWords = `${fileExt(a.name)} ${isFont(a) ? 'font' : fileKind(a)}`;
      if (all(`${c.name} ${f.name} ${a.name} ${kindWords}`) && some(`${a.name} ${kindWords}`)) files.push({ c, f, a });
    });
  }));
  files.sort((x, y) => x.a.name.localeCompare(y.a.name));
  if (!loose && !clients.length && !folders.length && !files.length) return { ...caSearch(q, scope, true), loose: true };
  return { clients, folders, files };
}
function caSearchBar(c) {
  const q = (c ? ui.caScope === c.id : !ui.caScope) ? ui.caQ || '' : '';
  return `<div class="ca-searchbar">
    ${icon('search')}
    <input id="ca-q" value="${esc(q)}" placeholder="${c ? `Search ${esc(c.name)}’s folders and files…` : 'Search all client assets — clients, folders, files (e.g. “ford logo png”)'}" autocomplete="off" spellcheck="false">
    <button class="icon-btn sm ca-q-x" data-action="ca-q-clear" title="Clear (Esc)" ${q ? '' : 'hidden'}>${icon('x')}</button>
    <span class="ca-q-scope">${c ? `In ${esc(c.name)}` : 'All clients'}</span>
  </div>`;
}
function caResultsHTML(q, scope) {
  const r = caSearch(q, scope);
  const n = r.clients.length + r.folders.length + r.files.length;
  if (!n) return `<div class="ca-noresults">${icon('search')}<b>Nothing matches “${esc(q.trim())}”</b><span>Try a client name, a folder like “fonts”, or a file type like “pdf” or “otf”.</span></div>`;
  const shown = r.files.slice(0, 120);
  const fonts = shown.filter((x) => isFont(x.a));
  return `<div class="ca-results">
    ${fonts.length ? `<style>${fonts.map((x) => `@font-face{font-family:'caf-${x.a.id}';src:url("${fileUrl(x.a)}");}`).join('')}</style>` : ''}
    <div class="ca-rcount">${n} result${n === 1 ? '' : 's'} for “${esc(q.trim())}”${scope ? ` in ${esc(scope.name)}` : ''}${r.loose ? ' <span class="ca-loose">— close matches (check the spelling)</span>' : ''}</div>
    ${r.clients.length ? `<h4 class="ca-rh">Clients <span>${r.clients.length}</span></h4><div class="ca-rlist">${r.clients.map((c) => `<button class="ca-rrow" data-action="open-client" data-id="${c.id}">${clientLogoHTML(c, 34)}<span><b>${caMark(c.name, q)}</b><small>${c.folders.length} folders · ${clientFileCount(c)} files</small></span>${icon('chev-right')}</button>`).join('')}</div>` : ''}
    ${r.folders.length ? `<h4 class="ca-rh">Folders <span>${r.folders.length}</span></h4><div class="ca-rlist">${r.folders.map(({ c, f }) => `<button class="ca-rrow" data-action="open-cfolder-of" data-client="${c.id}" data-id="${f.id}"><span class="cf-ic sm">${icon('folder')}</span><span><b>${caMark(f.name, q)}</b><small>${esc(c.name)} · ${f.files.length} file${f.files.length === 1 ? '' : 's'}</small></span>${icon('chev-right')}</button>`).join('')}</div>` : ''}
    ${r.files.length ? `<h4 class="ca-rh">Files <span>${r.files.length}</span></h4><div class="tile-grid ca-files">${shown.map(({ c, f, a }) => caTile(f, a, { c, q })).join('')}</div>${r.files.length > shown.length ? `<div class="ca-rmore">Showing the first ${shown.length} files — add another word to narrow it down.</div>` : ''}` : ''}
  </div>`;
}
let caSearchTimer = null;
function runCaSearch(input) {
  const body = $('#ca-body');
  if (!body) return;
  const scope = body.dataset.scope ? clientById(body.dataset.scope) : null;
  ui.caQ = input.value; ui.caScope = scope ? scope.id : null;
  const q = input.value.trim();
  const x = $('.ca-q-x'); if (x) x.hidden = !q;
  body.innerHTML = q ? caResultsHTML(q, scope) : (($('#ca-default') || {}).innerHTML || '');
  hydrateThumbs(body);
}
document.addEventListener('input', (e) => {
  if (e.target.id !== 'ca-q') return;
  clearTimeout(caSearchTimer);
  caSearchTimer = setTimeout(() => runCaSearch(e.target), 120);
});
document.addEventListener('keydown', (e) => {
  if (e.target.id !== 'ca-q') return;
  if (e.key === 'Escape' && e.target.value) { e.preventDefault(); e.stopPropagation(); e.target.value = ''; runCaSearch(e.target); }
  else if (e.key === 'Enter') { clearTimeout(caSearchTimer); runCaSearch(e.target); const first = $('#ca-body .ca-rrow, #ca-body .ca-tile'); if (first) { e.preventDefault(); first.click(); } }
}, true);

function viewClientFolder(c, f) {
  const fonts = f.files.filter(isFont);
  return `<div class="ca-page ca-folder" data-folder="${f.id}">
    ${fonts.length ? `<style>${fonts.map((a) => `@font-face{font-family:'caf-${a.id}';src:url("${fileUrl(a)}");}`).join('')}</style>` : ''}
    <div class="cfo-head">
      <button class="icon-btn" data-action="open-client" data-id="${c.id}" title="Back to ${esc(c.name)}">${icon('chev-left')}</button>
      ${clientLogoHTML(c, 40)}
      <div class="cfo-title"><h2>${esc(f.name)}</h2><small>${esc(c.name)} · ${f.files.length} file${f.files.length === 1 ? '' : 's'}</small></div>
      <span class="spacer"></span>
      ${f.files.length ? `<button class="btn ghost" data-action="ca-download-all">${icon('download')}Download all</button>` : ''}
      ${canAddAssets() ? `<button class="btn primary" data-action="ca-upload">${icon('upload')}Upload files</button>` : ''}
    </div>
    <div class="ca-uploads" id="ca-uploads"></div>
    ${f.files.length ? `<div class="tile-grid ca-files">${f.files.slice().sort((a, b) => a.name.localeCompare(b.name)).map((a) => caTile(f, a)).join('')}</div>`
      : `<div class="ca-empty ${canAddAssets() ? 'drop' : ''}">${icon(canAddAssets() ? 'upload' : 'folder')}<b>${canAddAssets() ? 'Drag files here or click Upload files' : 'Nothing in this folder yet'}</b><span>${canAddAssets() ? 'Logos, guideline PDFs, fonts, templates — any file type.' : 'The E11 team adds files here.'}</span></div>`}
    ${canAddAssets() ? `<div class="ca-dropscrim">${icon('upload')}<b>Drop to upload to ${esc(f.name)}</b></div>` : ''}
  </div>`;
}

/* ---- Actions ---- */
function addClientDialog() {
  if (!canAssets()) return denied();
  let logo = null, logoOriginal = null;
  const root = $('#overlay-root');
  root.innerHTML = `<div class="scrim"><form class="dialog form-dlg ac-dlg" autocomplete="off">
    <h2>Add client</h2>
    <div class="ac-row">
      <button type="button" class="ac-logo" id="ac-logo" title="Choose a logo">${icon('camera')}<span>Add logo</span></button>
      <div class="ac-fields"><label class="dlg-label">Client name</label><input class="field" name="name" placeholder="e.g. Ford" maxlength="80">
      <div class="dlg-hint">New clients start with ${DEFAULT_FOLDERS.join(', ')} folders.</div></div>
    </div>
    <div class="dlg-err"></div>
    <div class="actions"><button type="button" class="btn" data-r="0">Cancel</button><button type="submit" class="btn primary">Add client</button></div>
  </form></div>`;
  const form = $('form', root), err = $('.dlg-err', root), inp = form.elements.name, ok = $('[type="submit"]', root);
  const check = () => { const d = dupClient(inp.value); err.textContent = d ? dupMsg(d) : ''; ok.disabled = !!d || !inp.value.trim(); inp.classList.toggle('bad', !!d); };
  const close = () => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); };
  const cancel = () => { if (logo) safeTrash([logo]); close(); };
  const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); cancel(); } else e.stopPropagation(); };
  document.addEventListener('keydown', onKey, true);
  $('[data-r="0"]', root).addEventListener('click', cancel);
  inp.addEventListener('input', check);
  $('#ac-logo', root).addEventListener('click', async () => {
    if (!Host.isNative) { toast('Logos can be added in the Mac app'); return; }
    try {
      const r = await Host.call('pickImage', { kind: 'logo', userId: 'client-sq' });
      if (!r.path) return;
      if (logo) safeTrash([logo]);
      logo = r.path; logoOriginal = r.original || null;
      $('#ac-logo', root).innerHTML = `<img src="${'/__file/' + logo.split('/').map(encodeURIComponent).join('/')}" alt=""><span class="ac-change">Change</span>`;
      $('#ac-logo', root).classList.add('has');
    } catch (e) { toast('Could not use that logo: ' + e.message); }
  });
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const name = inp.value.trim();
    if (!name) { err.textContent = 'Enter the client’s name'; return; }
    const d = dupClient(name);
    if (d) { err.textContent = dupMsg(d); inp.classList.add('bad'); return; }
    const c = createClient(name, logo);
    logo = null;
    if (logoOriginal) setTimeout(() => saveLogoOriginal(c, logoOriginal), 300);
    close();
    persist(0);
    openClient(c.id);
    toast(`Added ${c.name}`);
  });
  check(); ok.disabled = true;
  setTimeout(() => inp.focus(), 20);
}

async function renameClient(c) {
  const v = await formDialog({ title: 'Rename client', fields: [{ key: 'name', label: 'Client name', value: c.name }], okText: 'Save',
    validate: (x) => (!x.name ? 'Enter the client’s name' : dupClient(x.name, c.id) ? dupMsg(dupClient(x.name, c.id)) : null) });
  if (!v) return;
  c.name = v.name.replace(/\s+/g, ' '); persist(0); render();
}
// A logo chosen with Add / Change logo also goes into the client's Logos folder, as the original file; a file of the
// same name there is replaced
async function saveLogoOriginal(c, file) {
  if (!c || !file || !Host.isServer) return;
  const f = c.folders.find((x) => x.name === 'Logos' && isAutoFolder(c, x)) || c.folders.find((x) => x.name === 'Logos');
  if (!f) return;
  const same = f.files.filter((a) => a.name.toLowerCase() === file.name.toLowerCase());
  if (same.length) {
    f.files = f.files.filter((a) => !same.includes(a));
    persist(0);
    try { await Sync.push(); } catch (e) { /* offline */ }
    const paths = safeTrash(same.flatMap((a) => [a.path, '.thumbs/' + a.id]));   // (kept on disk if pasted into a task)
    if (paths.length) await new Promise((r) => setTimeout(r, 400));                 // let the name free up
  }
  try {
    const up = await ServerHost.uploadMany([file], { dest: f.dir });
    if (!up.length) return;
    f.files.push(...up.map((x) => ({ ...x, name: file.name, addedAt: nowISO(), addedBy: currentUserId })));
    assetNotify(c, f, same.length ? 'replaced' : 'added', [file.name]);
    persist(0); render();
  } catch (e) { toast('The logo is set, but it could not be added to Logos: ' + e.message); }
}
async function changeClientLogo(c) {
  if (!Host.isNative) { toast('Logos can be added in the Mac app'); return; }
  try {
    const r = await Host.call('pickImage', { kind: 'logo', userId: 'client-sq' });
    if (!r.path) return;
    const old = c.logo; c.logo = r.path; delete c.logoAuto; persist(0); render(); renderSidebar();   // a chosen logo always wins
    if (old) safeTrash([old]);
    saveLogoOriginal(c, r.original);
  } catch (e) { toast('Could not use that logo: ' + e.message); }
}
async function deleteClient(c) {
  if (!isAdmin()) { toast('Only an Admin can delete a client'); return; }
  const n = clientFileCount(c);
  const ok = await dialog({ title: `Delete ${c.name}?`, body: `This removes the client and its ${c.folders.length} folders${n ? ` and ${n} file${n === 1 ? '' : 's'} (moved to the Trash)` : ''}. Files already pasted into tasks stay in those tasks.`, okText: 'Delete client', danger: true });
  if (!ok) return;
  const paths = [c.logo, ...c.folders.flatMap((f) => f.files.flatMap((a) => [a.path, '.thumbs/' + a.id])), ...c.folders.map((f) => f.dir), c.dir].filter(Boolean);
  db.clients = db.clients.filter((x) => x.id !== c.id);
  db.projects.forEach((p) => { if (p.clientId === c.id) delete p.clientId; });
  persist(0);
  go('clients');
  safeTrash(paths);
  toast(`Deleted ${c.name}`);
}
function clientMenu(anchor, c) {
  showMenu(anchor, [
    { label: 'Rename client', icon: 'edit', run: () => renameClient(c) },
    { label: c.logo ? 'Change logo' : 'Add logo', icon: 'camera', run: () => changeClientLogo(c) },
    ...(Host.isServer ? [] : [{ label: 'Show in Finder', icon: 'folder', run: () => Host.call('makeDir', { path: c.dir }).then(() => Host.call('revealPath', { path: c.dir })).catch((e) => toast(e.message)) }]),
    ...(isAdmin() ? ['-', { label: 'Delete client', icon: 'trash', danger: true, run: () => deleteClient(c) }] : []),
  ]);
}
const folderDup = (c, name, exceptId) => c.folders.find((f) => f.id !== exceptId && f.name.trim().toLowerCase() === name.trim().toLowerCase());
async function addFolderFlow(c) {
  if (!canAddAssets()) return denied();
  const v = await formDialog({ title: `New folder in ${c.name}`, fields: [{ key: 'name', label: 'Folder name', placeholder: 'e.g. Social templates' }], okText: 'Create folder',
    validate: (x) => (!x.name ? 'Enter a folder name' : folderDup(c, x.name) ? `There is already a folder named “${folderDup(c, x.name).name}”.` : null) });
  if (!v) return;
  newFolder(c, v.name); persist(0); render();
}
function folderMenu(anchor, c, f) {
  if (!canEditFolder(c, f)) return;
  showMenu(anchor, [
    { label: 'Rename folder', icon: 'edit', run: async () => {
      const v = await formDialog({ title: 'Rename folder', fields: [{ key: 'name', label: 'Folder name', value: f.name }], okText: 'Save',
        validate: (x) => (!x.name ? 'Enter a folder name' : folderDup(c, x.name, f.id) ? `There is already a folder named “${folderDup(c, x.name, f.id).name}”.` : null) });
      if (v) { f.name = v.name; persist(0); render(); }
    } },
    { label: 'Move left', icon: 'chev-left', run: () => { const i = c.folders.indexOf(f); if (i > 0) { c.folders.splice(i, 1); c.folders.splice(i - 1, 0, f); persist(0); render(); } } },
    { label: 'Move right', icon: 'chev-right', run: () => { const i = c.folders.indexOf(f); if (i < c.folders.length - 1) { c.folders.splice(i, 1); c.folders.splice(i + 1, 0, f); persist(0); render(); } } },
    ...(canDelFolder(c, f) ? ['-', { label: 'Delete folder', icon: 'trash', danger: true, run: async () => {
      const ok = await dialog({ title: `Delete “${f.name}”?`, body: f.files.length ? `Its ${f.files.length} file${f.files.length === 1 ? '' : 's'} will be moved to the Trash. Copies already pasted into tasks stay.` : 'This folder is empty.', okText: 'Delete folder', danger: true });
      if (!ok) return;
      c.folders = c.folders.filter((x) => x.id !== f.id);
      if (f.files.length) assetNotify(c, f, 'removed', f.files.map((a) => a.name));
      persist(0); render();
      // the files go once the server has the change (it only lets people remove what they're allowed to)
      Promise.resolve(typeof Sync !== 'undefined' && Sync.push ? Sync.push() : null).catch(() => {}).then(() => safeTrash([...f.files.flatMap((a) => [a.path, '.thumbs/' + a.id]), f.dir]));
    } }] : []),
  ]);
}
// Files added to or removed from Client Assets: an Inbox update (and phone notification) for everyone working on that
// client's tasks (assignees, creators, watchers), its Account Managers, and every Admin. Not the person who did it.
function assetNotify(c, f, verb, names) {
  if (!c || !names.length) return;
  const projs = db.projects.filter((p) => p.clientId === c.id);
  const pids = new Set(projs.map((p) => p.id));
  const to = new Set();
  db.tasks.filter((t) => pids.has(t.projectId) || (t.parentId && pids.has((task(t.parentId) || {}).projectId))).forEach((t) => {
    (t.assignees || []).forEach((id) => to.add(id));
    if (t.createdBy) to.add(t.createdBy);
    (t.watchers || []).forEach((id) => to.add(id));
  });
  projs.forEach((p) => (p.ams || []).forEach((a) => to.add(a.id)));
  db.users.forEach((u) => { if (isAdm(u)) to.add(u.id); });
  const n = names.length;
  const text = `${verb} ${n === 1 ? 'a file' : n + ' files'} ${verb === 'added' ? 'to' : verb === 'replaced' ? 'in' : 'from'} ${c.name} › ${f.name}`;
  const snippet = names.slice(0, 4).join(', ') + (n > 4 ? ` +${n - 4} more` : '');
  to.forEach((id) => {
    const u = userById(id);
    if (!u || id === currentUserId || u.active === false || isFinUser(u)) return;
    if (u.role === 'freelancer' && !projs.some((p) => (u.projectIds || []).includes(p.id))) return;   // only their own clients
    db.notifications.push({ id: uid(), to: id, from: currentUserId, kind: 'asset', clientId: c.id, folderId: f.id, text, snippet, at: nowISO(), read: false });
  });
}
function curFolder() { const c = clientById(ui.clientId); return c ? { c, f: c.folders.find((x) => x.id === ui.folderId) || null } : { c: null, f: null }; }
async function pickIntoFolder() {
  const { c, f } = curFolder();
  if (!f || !canAddAssets()) return;
  try {
    const r = await Host.call('pickAttachments', { dest: f.dir });
    const files = (r.files || []).map((x) => ({ ...x, addedAt: nowISO(), addedBy: currentUserId }));
    if (!files.length) return;
    f.files.push(...files); assetNotify(c, f, 'added', files.map((x) => x.name)); persist(0); render();
    autoLogo(c, f, files);
    toast(`Added ${files.length} file${files.length === 1 ? '' : 's'} to ${c.name} › ${f.name}`);
  } catch (e) { toast('Could not add files: ' + e.message); }
}
// Drag-and-drop upload in 2 MB pieces with a progress row per file
async function uploadIntoFolder(fileList) {
  const { c, f } = curFolder();
  if (!f || !canAddAssets()) return;
  const box = $('#ca-uploads');
  const rows = [...fileList].map((file) => {
    const el = document.createElement('div'); el.className = 'sr-item';
    el.innerHTML = `<span class="ficon">${esc((fileExt(file.name) || 'file').slice(0, 4))}</span><div class="sr-meta"><div class="sr-name">${esc(file.name)}</div><div class="sr-bar"><i style="width:0%"></i></div><small>Waiting…</small></div>`;
    if (box) box.appendChild(el);
    return { file, el };
  });
  let added = 0;
  for (const { file, el } of rows) {
    const bar = $('.sr-bar i', el), note = $('small', el);
    try {
      let path = null, last = null;
      for (let off = 0; off < Math.max(file.size, 1); off += CHUNK) {
        const b64 = await readChunkB64(file.slice(off, off + CHUNK));
        last = await Host.call('writeChunk', { dest: f.dir, name: file.name, path, b64 });
        path = last.path;
        const p = Math.min(1, (off + CHUNK) / Math.max(file.size, 1));
        bar.style.width = Math.round(p * 100) + '%'; note.textContent = `Uploading… ${Math.round(p * 100)}%`;
      }
      f.files.push({ id: uid(), name: last.name || file.name, path, size: last.size != null ? last.size : file.size, addedAt: nowISO(), addedBy: currentUserId });
      added++; el.classList.add('ok'); note.textContent = 'Uploaded';
      persist(300);
    } catch (e) { el.classList.add('err'); note.textContent = 'Upload failed — ' + e.message; }
  }
  if (added) { assetNotify(c, f, 'added', f.files.slice(-added).map((x) => x.name)); persist(0); Promise.resolve(Sync.push()).catch(() => {}).then(() => autoLogo(c, f, f.files.slice(-added))); }
  if (added && ui.view === 'client' && ui.folderId === f.id) { render(); toast(`Added ${added} file${added === 1 ? '' : 's'} to ${c.name} › ${f.name}`); }
}
async function removeClientFile(id) {
  const { f } = curFolder();
  const a = f && f.files.find((x) => x.id === id);
  if (!a || !canDelAsset(a)) return;
  const ok = await dialog({ title: `Delete “${a.name}”?`, body: `It moves to the Trash, where it can be restored within ${TRASH_DAYS} days. Copies already pasted into tasks stay.`, okText: 'Delete', danger: true });
  if (!ok) return;
  const { c } = curFolder();
  f.files = f.files.filter((x) => x.id !== id);
  toTrash('cafile', { clientId: c.id, folderId: f.id, file: a }, { key: 'clients:' + c.id, where: `${c.name} › ${f.name}` });
  assetNotify(c, f, 'removed', [a.name]);
  persist(0); render();
}
function downloadClientFiles(list, folderName) {
  if (!list.length) return;
  Host.call('exportFiles', { folder: folderName, paths: list.map((a) => a.path) })
    .then((r) => toast(`Saved ${r.count} file${r.count === 1 ? '' : 's'} to Downloads › ${r.dir.split('/').pop()}`))
    .catch((e) => toast('Could not download: ' + e.message));
}
function projectClientMenu(anchor, p) {
  const list = clientsSorted();
  showMenu(anchor, [
    { html: `<div class="mi-note">${icon('folder')}Link ${esc(p.name)} to a client</div>` },
    ...list.map((c) => ({ html: `<div class="mi ${p.clientId === c.id ? 'cur' : ''}">${clientLogoHTML(c, 18)}${esc(c.name)}</div>`, run: () => { p.clientId = c.id; persist(0); render(); toast(`${p.name} linked to ${c.name}`); } })),
    ...(p.clientId ? ['-', { label: 'No client', icon: 'x', run: () => { delete p.clientId; persist(0); render(); } }] : []),
    ...(!list.length ? [{ html: '<div class="mi-note">No clients yet — add one in Client Assets</div>' }] : []),
  ].map((it, i) => (it && it.html && it.run ? { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) } : it)));
}
// Drag files from Finder onto a folder page
document.addEventListener('dragover', (e) => {
  const pg = e.target.closest && e.target.closest('.ca-folder');
  if (!pg || dragId || !canAddAssets() || !e.dataTransfer || ![...(e.dataTransfer.types || [])].includes('Files')) return;
  e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; pg.classList.add('dropping');
});
document.addEventListener('dragleave', (e) => { const pg = $('.ca-folder.dropping'); if (pg && (!e.relatedTarget || !pg.contains(e.relatedTarget))) pg.classList.remove('dropping'); });
document.addEventListener('drop', (e) => {
  const pg = e.target.closest && e.target.closest('.ca-folder');
  if (!pg || dragId || !canAddAssets()) return;
  e.preventDefault(); pg.classList.remove('dropping');
  if (e.dataTransfer.files && e.dataTransfer.files.length) uploadIntoFolder(e.dataTransfer.files);
});



/* ================= CD Review workflow ================= */
// One Creative Director at a time (db.meta.cdUserId). An Admin can set a temporary Acting CD;
// the permanent CD is remembered in db.meta.cdHomeId while someone is acting.
const cdUserId = () => { const id = db && db.meta.cdUserId; const u = id && userById(id); return u && u.active !== false ? id : null; };
const isCD = (id = currentUserId) => !!id && id === cdUserId();
const cdActing = () => !!(db && db.meta.cdActing && cdUserId());
const cdTitle = () => (cdActing() ? 'Acting CD' : 'Creative Director');
const firstName = (id) => fullName(userById(id)).split(' ')[0];
// "Needs CD review" is set per task by Account Managers / Admins
const needsCD = (t) => !!t && !t.parentId && !!t.needsCD;
// The CD's own part never goes through approval
const reviewersOf = (t) => (t.assignees || []).filter((u) => u !== cdUserId());
const epochOf = (t) => t.reviewEpoch || 0;
function lastReview(t, u) {
  const list = (t.reviews || []).filter((r) => r.by === u && (r.epoch || 0) === epochOf(t) && r.state !== 'withdrawn');
  return list[list.length - 1] || null;
}
// none | pending | approved | amend | reopened
const reviewState = (t, u = currentUserId) => { const r = lastReview(t, u); return r ? r.state : 'none'; };
const reviewPending = (t) => needsCD(t) && reviewersOf(t).some((u) => reviewState(t, u) === 'pending');
const statusLocked = (t) => reviewPending(t);
const LOCK_MSG = 'The status is locked while files are with the CD for review';
const iReview = (t) => needsCD(t) && isMine(t) && !isCD();
// Files can be submitted once the task has left To Do
const canSubmitNow = (t) => !t.done && !cdLocked(t);
const soloReview = (t) => (t.assignees || []).length === 1 && reviewersOf(t).length === 1;
const cdOK = (t) => !needsCD(t) || t.cdStatus === 'approved' || reviewersOf(t).length === 0;
const secNamed = (t, re) => statusList(t).find((s) => re.test(String(s.name).trim()));
const SEC_PROGRESS = /^in ?-?progress$/i, SEC_REVIEW = /^(internal )?review$/i, SEC_CTR = /^ctr$/i;
function allReviews() {
  const out = [];
  db.tasks.forEach((t) => (t.reviews || []).forEach((r) => out.push({ t, r })));
  return out;
}
function findReview(id) { for (const t of db.tasks) { const r = (t.reviews || []).find((x) => x.id === id); if (r) return { t, r }; } return null; }
const activeReviews = () => allReviews().filter(({ t, r }) => r.state === 'pending' && needsCD(t) && (r.epoch || 0) === epochOf(t) && !t.done).sort((a, b) => a.r.at.localeCompare(b.r.at));
const REVIEWED_DAYS = 15;
const reviewedRecent = () => allReviews().filter(({ r }) => (r.state === 'approved' || r.state === 'amend') && r.decidedAt && (Date.now() - new Date(r.decidedAt)) < REVIEWED_DAYS * 864e5).sort((a, b) => b.r.decidedAt.localeCompare(a.r.decidedAt));

// Work out the task's CD Status from everyone's latest submission
function syncCD(t) {
  if (!needsCD(t)) return;
  const rv = reviewersOf(t);
  if (!rv.length) return;
  const st = rv.map((u) => reviewState(t, u));
  const prev = t.cdStatus || '';
  t.cdStatus = st.includes('pending') ? 'review' : st.every((s) => s === 'approved') ? 'approved' : '';
  if (prev === t.cdStatus) return;
  if (prev && t.cdStatus) logChange(t, 'the <b>CD Status</b>', CD[prev].label, CD[t.cdStatus].label);
  else if (t.cdStatus) logActivity(t, `CD Status is now <b>${esc(CD[t.cdStatus].label)}</b>`);
  else logActivity(t, `CD Status cleared ${struck(CD[prev].label)}`);
}
function moveToSection(t, re) {
  const s = secNamed(t, re);
  if (s && t.sectionId !== s.id) moveTask(t.id, s.id, null, false);
}

function submitReview(t, files) {
  if (!iReview(t) || !files.length) return;
  t.reviews = t.reviews || [];
  const round = (t.reviews || []).filter((r) => r.by === currentUserId && r.state !== 'withdrawn').length + 1;
  const r = { id: uid(), by: currentUserId, at: nowISO(), files: files.map((f) => f.id), state: 'pending', epoch: epochOf(t), round };
  t.reviews.push(r);
  files.forEach((f) => t.attachments.push({ ...f, addedAt: nowISO(), reviewId: r.id }));
  logActivity(t, `submitted ${files.length === 1 ? `<b>${esc(files[0].name)}</b>` : `<b>${files.length} files</b>`} for CD review${round > 1 ? ` (round ${round})` : ''}`);
  const cd = cdUserId();
  if (cd) pushNotif(cd, t, 'review', `submitted ${files.length === 1 ? '1 file' : files.length + ' files'} for your review on`);
  moveToSection(t, SEC_REVIEW);
  syncCD(t);
  t.updatedAt = nowISO();
  commit();
  toast(cd ? `Sent to ${fullName(userById(cd))} for review` : 'Submitted — no Creative Director is set yet, an Admin needs to choose one');
}

async function withdrawReview(t) {
  const r = lastReview(t, currentUserId);
  if (!r || r.state !== 'pending') return;
  const ok = await dialog({ title: 'Withdraw your submission?', body: 'The files you submitted will be removed so you can upload the right ones.', okText: 'Withdraw', danger: true });
  if (!ok) return;
  r.state = 'withdrawn';
  const gone = t.attachments.filter((a) => a.reviewId === r.id);
  t.attachments = t.attachments.filter((a) => a.reviewId !== r.id);
  if (gone.length) safeTrash(gone.flatMap((a) => [a.path, '.thumbs/' + a.id]));
  logActivity(t, 'withdrew their submission for CD review');
  const cd = cdUserId();
  if (cd) pushNotif(cd, t, 'review-wd', 'withdrew their submission for');
  if (!reviewPending(t)) moveToSection(t, SEC_PROGRESS);
  syncCD(t);
  t.updatedAt = nowISO();
  commit();
}

function decideReview(t, r, decision, noteHtml) {
  if (!isCD() || r.state !== 'pending') return;
  r.decidedAt = nowISO(); r.decidedBy = currentUserId;
  const who = fullName(userById(r.by));
  if (decision === 'approve') {
    r.state = 'approved';
    t.partsDone = t.partsDone || {};
    t.partsDone[r.by] = nowISO();
    logActivity(t, `approved <b>${esc(who)}</b>’s files`);
    pushNotif(r.by, t, 'review-ok', 'approved your files for');
    postApprovedFiles(t, r);
    const rv = reviewersOf(t);
    const allOK = rv.every((u) => reviewState(t, u) === 'approved');
    syncCD(t);
    if (allOK) {
      moveToSection(t, SEC_CTR);
      if (t.createdBy && t.createdBy !== r.by) pushNotif(t.createdBy, t, 'review-ok', 'approved all files — it moved to CTR:');
    } else if (!reviewPending(t)) moveToSection(t, SEC_PROGRESS);
  } else {
    r.state = 'amend';
    r.noteHtml = noteHtml;
    if (t.partsDone) delete t.partsDone[r.by];
    const c = { id: uid(), text: 'Amendments required: ' + notifPlainHTML(noteHtml), html: `<b>Amendments required</b> for <span class="mention" data-user="${esc(r.by)}" contenteditable="false">@${esc(who)}</span><br>${noteHtml}`, at: nowISO(), attachments: [], parentId: null, reactions: {}, authorId: currentUserId };
    t.comments.push(c);
    logActivity(t, `asked <b>${esc(who)}</b> for amendments`);
    pushNotif(r.by, t, 'review-amend', 'requested amendments on your submission for', { snippet: notifPlainHTML(noteHtml).slice(0, 160), commentId: c.id });
    if (t.createdBy && t.createdBy !== r.by) pushNotif(t.createdBy, t, 'review-amend', `requested amendments from <b>${esc(who)}</b> on`, { commentId: c.id });
    if (!reviewPending(t)) moveToSection(t, SEC_PROGRESS);
    syncCD(t);
  }
  t.updatedAt = nowISO();
  commit();
}
// After approval, the submitter "posts" the approved files in the comments for the task creator
// Files sent for CD review stay out of the task's Attachments until the CD approves them
// (they're still in the review request, and the submitter's review panel)
function shownAtts(t) {
  const ok = new Set((t.reviews || []).filter((r) => r.state === 'approved').map((r) => r.id));
  return (t.attachments || []).filter((a) => !a.reviewId || ok.has(a.reviewId));
}
function postApprovedFiles(t, r) {
  const files = (r.files || []).map((id) => t.attachments.find((a) => a.id === id)).filter(Boolean);
  if (!files.length) return;
  const cr = t.createdBy && userById(t.createdBy) ? t.createdBy : null;
  const hello = cr ? `Hello <span class="mention" data-user="${esc(cr)}" contenteditable="false">@${esc(fullName(userById(cr)))}</span>, ` : 'Hello, ';
  const text = `${cr ? 'Hello @' + fullName(userById(cr)) + ', ' : 'Hello, '}here are the final files (Approved) by the CD, ready to be sent to client for review.`;
  const c = { id: uid(), text, html: `${hello}here are the final files (<b>Approved</b>) by the CD, ready to be sent to client for review.`, at: nowISO(),
    attachments: files.map((a) => ({ ...a, id: uid(), linked: true })), parentId: null, reactions: {}, authorId: r.by, auto: true };
  t.comments.push(c);
  if (cr && cr !== r.by && userById(cr).active !== false) {
    db.notifications.push({ id: uid(), to: cr, from: r.by, taskId: t.id, kind: 'mention', text: 'mentioned you in a comment on', snippet: text, commentId: c.id, at: nowISO(), read: false });
  }
}
function notifPlainHTML(html) { const d = document.createElement('div'); d.innerHTML = String(html || '').replace(/<(br|\/p|\/li|\/div)>/gi, ' $&'); return d.textContent.replace(/\s+/g, ' ').trim(); }

// A small dialog with several choices; resolves with the chosen value (null = cancelled)
function choiceDialog({ title, body = '', choices }) {
  return new Promise((resolve) => {
    const root = $('#overlay-root');
    root.innerHTML = `<div class="scrim"><div class="dialog choice-dlg" role="dialog">
      <h2>${esc(title)}</h2>${body ? `<p>${esc(body)}</p>` : ''}
      <div class="actions">${choices.map((c, i) => `<button class="btn ${c.primary ? 'primary' : c.danger ? 'danger' : ''}" data-i="${i}">${esc(c.label)}</button>`).join('')}</div>
    </div></div>`;
    const done = (v) => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); resolve(v); };
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); done(null); } };
    document.addEventListener('keydown', onKey, true);
    const scrim = $('.scrim', root);
    scrim.addEventListener('mousedown', (e) => { if (e.target === scrim) done(null); });
    $$('[data-i]', root).forEach((b) => b.addEventListener('click', () => done(choices[+b.dataset.i].value == null ? null : choices[+b.dataset.i].value)));
    setTimeout(() => { const p = $('.btn.primary', root); if (p) p.focus(); }, 20);
  });
}

// Every status change from the interface goes through here (status menu, ▶ next, drag and drop)
async function changeStatus(t, sectionId, targetId = null, after = false) {
  if (!t) return false;
  if (t.sectionId !== sectionId && statusLocked(t)) { toast(LOCK_MSG); return false; }
  const list = statusList(t);
  const from = list.findIndex((x) => x.id === t.sectionId), to = list.findIndex((x) => x.id === sectionId);
  const fromS = list[from], toS = list[to];
  const backFromClient = !t.parentId && fromS && toS && to < from && (SEC_CTR.test(fromS.name.trim()) || isDoneName(fromS.name)) && !(SEC_CTR.test(toS.name.trim()) || isDoneName(toS.name));
  if (backFromClient) {
    const allowed = (me() && (isAdm(me()) || me().role === 'am')) || t.createdBy === currentUserId;
    if (!allowed) { toast('Only an Account Manager or the person who created this task can send it back'); return false; }
    const ans = await choiceDialog({
      title: 'Does this need CD review again?',
      body: 'The task is going back for changes. Choose whether the updated work goes to the Creative Director before it returns to the client.',
      choices: [{ label: 'Cancel', value: null }, { label: 'No, skip CD review', value: 'no' }, { label: 'Yes, needs CD review', value: 'yes', primary: true }],
    });
    if (!ans) return false;
    t.partsDone = {};
    if (ans === 'yes') {
      t.needsCD = true; t.reviewEpoch = epochOf(t) + 1;
      if (t.cdStatus) logChange(t, 'the <b>CD Status</b>', CD[t.cdStatus] ? CD[t.cdStatus].label : '', '');
      t.cdStatus = '';
      logActivity(t, 'sent it back for changes — <b>needs CD review again</b>');
    } else {
      t.needsCD = false;
      logActivity(t, 'sent it back for changes — <b>no CD review needed</b>');
    }
  }
  if (t.done) setDone(t, false);
  moveTask(t.id, sectionId, targetId, after);
  commit();
  return true;
}

function setNeedsCD(t, on) {
  if (!(me() && (isAdm(me()) || me().role === 'am'))) return denied();
  if (reviewPending(t)) { toast('Files are waiting for CD review — this can be changed after the CD decides'); return; }
  if (!!t.needsCD === !!on) return;
  t.needsCD = !!on;
  logActivity(t, on ? 'turned on <b>CD review</b> for this task' : 'turned off <b>CD review</b> for this task');
  if (on) syncCD(t);
  t.updatedAt = nowISO();
  commit();
}

/* ---- Task page pieces ---- */
const SUBMIT_TIP = 'Move the task to In Progress to submit files for review';
function submitBtn(t) {
  const ready = canSubmitNow(t);
  return `<button class="submit-btn ${ready ? '' : 'off'}" ${ready ? 'data-action="submit-review"' : ''} title="${ready ? 'Upload your files and send them to the Creative Director' : SUBMIT_TIP}">${icon('upload')}Submit Files for Review</button>`;
}
function pendingPill(t, withdraw = true) {
  return `<span class="ir-pill" title="Waiting for the Creative Director">${icon('clock')}Internal Review</span>${withdraw ? `<button class="icon-btn xs ir-x" data-action="withdraw-review" title="Withdraw your submission">${icon('x')}</button>` : ''}`;
}
// Status row: the CD Status chip, or the submit button for a one-person task
function cdArea(t) {
  if (!showsCD(t)) return '';
  if (!needsCD(t)) return t.cdStatus ? cdChipBig(t) : '';
  if (soloReview(t) && iReview(t)) {
    const st = reviewState(t);
    if (st === 'pending') return cdChipBig(t) + `<button class="icon-btn xs ir-x" data-action="withdraw-review" title="Withdraw your submission">${icon('x')}</button>`;
    if (st !== 'approved') return submitBtn(t);
  }
  return cdChipBig(t);
}
function cdChipBig(t) {
  const c = CD[t.cdStatus];
  const tip = c ? `CD Status: ${c.label} — set automatically by the review` : 'CD Status is set automatically when files are submitted and reviewed';
  return `<span class="cd-btn ro ${c ? '' : 'empty'}" ${c ? `style="background:${c.color};color:${textOn(c.color)}"` : ''} title="${tip}"><span class="cd-k">CD</span>${c ? esc(c.label) : 'Not submitted'}</span>`;
}
// Parts row: what the current person can do with their own part
function myPartControl(t) {
  if (!isMine(t)) return '';
  if (!iReview(t)) {
    return partDone(t) ? `<button class="part-btn on" data-action="my-part" data-v="0" title="Undo — move it back to your To Do">${icon('check')}My part is done<small>Undo</small></button>`
      : `<button class="part-btn" data-action="my-part" data-v="1">${icon('check')}Mark my part done</button>`;
  }
  const st = reviewState(t);
  if (st === 'approved') return `<span class="part-btn on static" title="Approved by the Creative Director">${icon('check')}Approved</span>`;
  if (soloReview(t)) return '';
  if (st === 'pending') return pendingPill(t);
  return submitBtn(t);
}
function cdReviewRow(t) {
  if (t.parentId || t.done) return '';
  const canSet = me() && (isAdm(me()) || me().role === 'am');
  const cd = cdUserId();
  const who = cd ? `${esc(fullName(userById(cd)))}${cdActing() ? ' (Acting CD)' : ''}` : 'No Creative Director set';
  return `<div class="prop prop-cdreq"><label>${icon('shield')}CD review</label><div class="pv">
    <label class="tg ${canSet ? '' : 'ro'}" title="${canSet ? 'Files must be approved by the Creative Director before this task can go to the client' : 'Set by Account Managers'}"><input type="checkbox" data-action="needs-cd" ${t.needsCD ? 'checked' : ''} ${canSet ? '' : 'disabled'}><i></i><span>Needs CD review</span></label>
    ${t.needsCD ? `<span class="cdr-who">${icon('user')}${who}</span>` : ''}
  </div></div>`;
}

/* ---- Submit files pop-up ---- */
const CHUNK = 2 * 1024 * 1024;
function readChunkB64(blob) {
  return new Promise((resolve, reject) => {
    const fr = new FileReader();
    fr.onload = () => resolve(String(fr.result).split(',')[1] || '');
    fr.onerror = () => reject(fr.error || new Error('Could not read the file'));
    fr.readAsDataURL(blob);
  });
}
function submitDialog(t) {
  if (!iReview(t)) return;
  if (!canSubmitNow(t)) { toast(SUBMIT_TIP); return; }
  const items = [];
  let closed = false;
  const root = $('#overlay-root');
  const cd = cdUserId();
  root.innerHTML = `<div class="scrim"><div class="dialog sr-dlg" role="dialog">
    <h2>Submit files for review</h2>
    <p>${cd ? `Your files go to <b>${esc(fullName(userById(cd)))}</b> (${cdTitle()}) for approval.` : 'No Creative Director is set yet — an Admin needs to choose one on the Team page.'}</p>
    <div class="sr-drop" id="sr-drop">${icon('upload')}<b>Drag and drop files here</b><span>or</span><button class="btn" id="sr-pick">Select files from your computer</button></div>
    <div class="sr-list" id="sr-list"></div>
    <div class="actions"><button class="btn" id="sr-cancel">Cancel</button><button class="btn primary" id="sr-submit" disabled>Submit</button></div>
  </div></div>`;
  const list = $('#sr-list', root), submit = $('#sr-submit', root), drop = $('#sr-drop', root);
  const paint = () => {
    list.innerHTML = items.map((it, i) => `<div class="sr-item ${it.error ? 'err' : it.done ? 'ok' : ''}">
      <span class="ficon">${esc((fileExt(it.name) || 'file').slice(0, 4))}</span>
      <div class="sr-meta"><div class="sr-name">${esc(it.name)}</div>
        <div class="sr-bar"><i style="width:${Math.round((it.p || 0) * 100)}%"></i></div>
        <small>${it.error ? esc(it.error) : it.done ? `Uploaded · ${fmtSize(it.size)}` : `Uploading… ${Math.round((it.p || 0) * 100)}%`}</small></div>
      <button class="icon-btn sm" data-sr-x="${i}" title="Remove">${icon('x')}</button>
    </div>`).join('');
    const ok = items.length && items.every((x) => x.done && !x.error);
    submit.disabled = !ok;
    submit.textContent = items.length && !ok && items.some((x) => !x.done) ? 'Uploading…' : 'Submit';
  };
  const discard = (it) => { if (it.att) Host.call('trashMany', { paths: [it.att.path] }).catch(() => {}); };
  const close = (keep) => {
    closed = true;
    if (!keep) items.forEach(discard);
    root.innerHTML = '';
    document.removeEventListener('keydown', onKey, true);
  };
  const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(false); } };
  document.addEventListener('keydown', onKey, true);
  // Files chosen in the macOS picker are copied by the app; show their progress the same way
  $('#sr-pick', root).addEventListener('click', async () => {
    try {
      const res = await Host.call('pickAttachments', { taskId: t.id });
      (res.files || []).forEach((f) => {
        const it = { name: f.name, size: f.size, p: 0, done: false, att: f };
        items.push(it);
        const t0 = performance.now();
        const step = () => { if (closed) return; it.p = Math.min(1, (performance.now() - t0) / 450); if (it.p >= 1) it.done = true; paint(); if (!it.done) requestAnimationFrame(step); };
        requestAnimationFrame(step);
      });
      paint();
    } catch (e) { toast('Could not add files: ' + e.message); }
  });
  const upload = async (file) => {
    const it = { name: file.name, size: file.size, p: 0, done: false };
    items.push(it); paint();
    try {
      let path = null, last = null;
      for (let off = 0; off < Math.max(file.size, 1); off += CHUNK) {
        if (closed || it.removed) { if (path) Host.call('trashMany', { paths: [path] }).catch(() => {}); return; }
        const b64 = await readChunkB64(file.slice(off, off + CHUNK));
        last = await Host.call('writeChunk', { taskId: t.id, name: file.name, path, b64 });
        path = last.path;
        it.p = Math.min(1, (off + CHUNK) / Math.max(file.size, 1));
        paint();
      }
      it.att = { id: uid(), name: last.name || file.name, path, size: last.size != null ? last.size : file.size };
      it.name = it.att.name;
      it.done = true; it.p = 1;
      if (it.removed) discard(it);
    } catch (e) { it.error = 'Upload failed — ' + e.message; it.done = true; }
    if (!closed) paint();
  };
  const scrim = $('.scrim', root);
  ['dragenter', 'dragover'].forEach((ev) => scrim.addEventListener(ev, (e) => { e.preventDefault(); e.stopPropagation(); drop.classList.add('over'); }));
  scrim.addEventListener('dragleave', (e) => { if (!scrim.contains(e.relatedTarget)) drop.classList.remove('over'); });
  scrim.addEventListener('drop', (e) => {
    e.preventDefault(); e.stopPropagation(); drop.classList.remove('over');
    [...(e.dataTransfer.files || [])].forEach(upload);
  });
  list.addEventListener('click', (e) => {
    const b = e.target.closest('[data-sr-x]');
    if (!b) return;
    const it = items[+b.dataset.srX];
    it.removed = true;
    if (it.done) discard(it);
    items.splice(+b.dataset.srX, 1);
    paint();
  });
  $('#sr-cancel', root).addEventListener('click', () => close(false));
  submit.addEventListener('click', () => {
    if (submit.disabled) return;
    const files = items.map((x) => x.att);
    close(true);
    submitReview(t, files);
  });
}

/* ---- Review Requests page (Creative Director only) ---- */
function rrTile(t, a) {
  const kind = fileKind(a);
  let inner;
  if (kind === 'image' && Host.isNative) inner = `<img src="${imgUrl(a, 640)}" alt="" loading="lazy">`;
  else if (Host.isNative) inner = thumbImg(a, 'tile').replace('data-thumb-for="', `data-thumb-task="${t.id}" data-thumb-for="`);
  else inner = `<div class="thumb-ph"><span class="ext">${esc(fileExt(a.name) || 'file')}</span></div>`;
  return `<div class="tile rr-tile" data-action="rr-file" data-task-id="${t.id}" data-id="${a.id}" title="${esc(a.name)} — click to preview">
    <div class="tile-img">${inner}${kind === 'video' ? `<span class="tile-play">${icon('play')}</span>` : ''}</div>
    <div class="tile-meta"><span>${esc(a.name)}</span><small>${fmtSize(a.size)}</small></div>
  </div>`;
}
function reviewCard(t, r, reviewed) {
  const p = proj(t.projectId);
  const files = (r.files || []).map((id) => t.attachments.find((a) => a.id === id)).filter(Boolean);
  const desc = t.notesHtml ? notifPlainHTML(t.notesHtml) : t.notes;
  const decision = reviewed ? (r.state === 'approved'
    ? `<span class="rr-dec ok">${icon('check')}Approved</span>`
    : `<span class="rr-dec amend">${icon('edit')}Amendments</span>`) : '';
  return `<div class="rr-card ${reviewed ? 'done' : ''}" data-review="${r.id}">
    <div class="rr-head">
      <div class="rr-info">
        <div class="rr-top"><a class="rr-title" data-action="rr-open" data-id="${t.id}">${esc(t.title || 'Untitled task')}</a>${p ? `<span class="rr-proj"><i style="background:${p.color}"></i>${esc(p.name)}</span>` : ''}</div>
        ${desc ? `<a class="rr-desc" data-action="rr-open" data-id="${t.id}">${esc(desc)}</a>` : '<div class="rr-desc ph">No description</div>'}
        <div class="rr-by">${avatarHTML(r.by, 20)}<span><b>${esc(fullName(userById(r.by)))}</b> submitted ${files.length} file${files.length === 1 ? '' : 's'} · ${esc(timeAgo(r.at))}${r.round > 1 ? ` · Round ${r.round}` : ''}</span></div>
      </div>
      <div class="rr-acts">
        ${files.length ? `<button class="icon-btn" data-action="rr-download" data-id="${r.id}" title="Download all files">${icon('download')}</button>` : ''}
        ${reviewed ? decision : `<button class="btn primary" data-action="rr-decide" data-id="${r.id}">Review decision</button>`}
      </div>
    </div>
    ${files.length ? `<div class="rr-files">${files.map((a) => rrTile(t, a)).join('')}</div>` : ''}
    ${reviewed && r.state === 'amend' && r.noteHtml ? `<div class="rr-note"><b>Changes requested</b>${sanitizeHTML(r.noteHtml, true)}</div>` : ''}
    ${reviewed ? `<div class="rr-when">${r.state === 'approved' ? 'Approved' : 'Sent back'} ${esc(timeAgo(r.decidedAt))}${r.decidedBy && r.decidedBy !== currentUserId ? ' by ' + esc(fullName(userById(r.decidedBy))) : ''} · leaves this list after ${REVIEWED_DAYS} days</div>` : ''}
  </div>`;
}
function viewReviews() {
  if (!isCD()) return `<div class="empty rr-empty"><div class="big">Only the Creative Director can see review requests</div>An Admin sets the Creative Director on the Team page.</div>`;
  const tab = ui.rrTab === 'reviewed' ? 'reviewed' : 'active';
  const act = activeReviews(), done = reviewedRecent();
  const rows = tab === 'active' ? act : done;
  return `<div class="rr">
    <div class="ib-tabs rr-tabs">
      <button class="ib-tab ${tab === 'active' ? 'on' : ''}" data-action="rr-tab" data-tab="active">${icon('inbox')}<span><b>Active</b><small>${act.length ? act.length + ' waiting' : 'Nothing waiting'}</small></span></button>
      <button class="ib-tab ${tab === 'reviewed' ? 'on' : ''}" data-action="rr-tab" data-tab="reviewed">${icon('check')}<span><b>Reviewed</b><small>Last ${REVIEWED_DAYS} days</small></span></button>
    </div>
    <div class="rr-list">${rows.length ? rows.map(({ t, r }) => reviewCard(t, r, tab === 'reviewed')).join('')
      : `<div class="empty rr-empty"><div class="big">${tab === 'active' ? 'All caught up' : 'Nothing reviewed yet'}</div>${tab === 'active' ? 'New submissions appear here, and you get a notification.' : `Decisions from the last ${REVIEWED_DAYS} days appear here.`}</div>`}</div>
  </div>`;
}
function decisionDialog(id) {
  const f = findReview(id);
  if (!f || !isCD()) return;
  const { t, r } = f;
  const root = $('#overlay-root');
  root.innerHTML = `<div class="scrim"><div class="dialog rd-dlg" role="dialog">
    <h2>Review decision</h2>
    <p><b>${esc(t.title || 'Untitled task')}</b> · ${esc(fullName(userById(r.by)))}${r.round > 1 ? ` · Round ${r.round}` : ''}</p>
    <div class="rd-choices">
      <button class="rd-btn ok" data-d="approve">${icon('check')}<b>Approve</b><small>The files are ready to go to the client</small></button>
      <button class="rd-btn amend" data-d="amend">${icon('edit')}<b>Amendments</b><small>Send it back with the changes needed</small></button>
    </div>
    <div class="rd-amend" hidden>
      <label class="dlg-label">Describe the changes required</label>
      <div class="composer rd-comp"><div class="rt-editor" contenteditable="true" id="rd-note" data-placeholder="e.g. 0:10 remove the text, use the new end frame…"></div><div class="cb-foot">${fmtToolbar()}</div></div>
      <div class="actions"><button class="btn" data-d="back">Back</button><button class="btn primary" data-d="send">Submit</button></div>
    </div>
  </div></div>`;
  const scrim = $('.scrim', root);
  const close = () => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); };
  const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); } };
  document.addEventListener('keydown', onKey, true);
  scrim.addEventListener('mousedown', (e) => { if (e.target === scrim) close(); });
  scrim.addEventListener('click', (e) => {
    const b = e.target.closest('[data-d]');
    if (!b) return;
    const d = b.dataset.d;
    if (d === 'approve') { close(); decideReview(t, r, 'approve'); toast(`Approved — ${firstName(r.by)} has been notified`); }
    else if (d === 'amend') { $('.rd-choices', root).hidden = true; $('.rd-amend', root).hidden = false; setTimeout(() => $('#rd-note', root).focus(), 20); }
    else if (d === 'back') { $('.rd-choices', root).hidden = false; $('.rd-amend', root).hidden = true; }
    else if (d === 'send') {
      const ed = $('#rd-note', root);
      if (editorEmpty(ed)) { ed.focus(); toast('Describe the changes required'); return; }
      const html = sanitizeHTML(ed.innerHTML);
      close();
      decideReview(t, r, 'amend', html);
      toast(`Sent back to ${firstName(r.by)} with your notes`);
    }
  });
}
async function downloadReviewFiles(id) {
  const f = findReview(id);
  if (!f) return;
  const files = (f.r.files || []).map((x) => f.t.attachments.find((a) => a.id === x)).filter(Boolean);
  try {
    await Host.call('exportFiles', { paths: files.map((a) => a.path), folder: `${f.t.title || 'Task'} — ${fullName(userById(f.r.by))}${f.r.round > 1 ? ' — Round ' + f.r.round : ''}` });
    toast(`Saved ${files.length} file${files.length === 1 ? '' : 's'} to your Downloads folder`);
  } catch (e) { toast('Could not download: ' + e.message); }
}

/* ---- Team page: Creative Director switch ---- */
function cdCell(u, admin) {
  const on = isCD(u.id);
  const home = !on && db.meta.cdHomeId === u.id && cdActing();
  const badge = on ? `<span class="cd-badge">${cdActing() ? 'Acting CD' : 'Creative Director'}</span>` : home ? '<span class="cd-badge away">CD · away</span>' : '';
  if (!admin || u.active === false) return `<div class="tt-cd">${badge}</div>`;
  return `<div class="tt-cd"><label class="tg" title="${on ? 'Turn off' : 'Make ' + esc(fullName(u)) + ' the Creative Director'}"><input type="checkbox" data-action="cd-toggle" data-id="${u.id}" ${on ? 'checked' : ''}><i></i></label><small>${on ? (cdActing() ? 'Acting CD' : 'Creative Director') : home ? 'CD · away' : 'Make Creative Director'}</small></div>`;
}
async function cdToggleFlow(id) {
  if (!can('manageUsers')) { denied(); renderContent(); return; }
  const u = userById(id);
  const cur = cdUserId();
  let acting = false;
  if (cur === id) {
    const ok = await dialog({ title: `Remove ${fullName(u)} as ${cdTitle()}?`, body: db.meta.cdHomeId && cdActing() ? `${fullName(userById(db.meta.cdHomeId))} will be Creative Director again.` : 'Review requests will wait until someone else is made Creative Director.', okText: 'Remove', danger: true });
    if (!ok) { renderContent(); return; }
    if (cdActing() && db.meta.cdHomeId && userById(db.meta.cdHomeId)) { db.meta.cdUserId = db.meta.cdHomeId; db.meta.cdHomeId = null; db.meta.cdActing = false; toast(`${fullName(userById(db.meta.cdUserId))} is Creative Director again`); }
    else { db.meta.cdUserId = null; db.meta.cdActing = false; db.meta.cdHomeId = null; toast('There is no Creative Director now'); }
    persist(0); render(); return;
  }
  if (cur) {
    const curName = fullName(userById(cur));
    const returning = db.meta.cdHomeId === id;
    const choices = [{ label: 'Cancel', value: null }];
    if (!returning) choices.push({ label: `Acting CD while ${firstName(cur)} is away`, value: 'acting' });
    choices.push({ label: returning ? `Make ${firstName(id)} CD again` : `Make ${firstName(id)} Creative Director`, value: 'cd', primary: true });
    const ans = await choiceDialog({
      title: 'Are you sure?',
      body: `${curName} is the ${cdTitle()}. Only one person can be CD at a time — ${curName} will be switched off and all pending review requests move to ${fullName(u)}.`,
      choices,
    });
    if (!ans) { renderContent(); return; }
    acting = ans === 'acting';
    if (acting) db.meta.cdHomeId = cdActing() ? db.meta.cdHomeId : cur;
    else db.meta.cdHomeId = null;
  } else {
    const ok = await dialog({ title: 'Are you sure?', body: `Make ${fullName(u)} the Creative Director? They will review every file submitted for CD review.`, okText: 'Make Creative Director' });
    if (!ok) { renderContent(); return; }
  }
  db.meta.cdUserId = id;
  db.meta.cdActing = acting;
  persist(0); render();
  toast(`${fullName(u)} is now ${acting ? 'Acting CD' : 'the Creative Director'}`);
}

/* ================= Inbox ================= */
const myNotifs = () => (db && currentUserId ? db.notifications.filter((n) => n.to === currentUserId) : []);
const NOTIF_ICON = { claim: 'coin', 'claim-ok': 'check', 'claim-paid': 'coin', trash: 'trash', restore: 'reply', review: 'upload', 'review-ok': 'check', 'review-amend': 'edit', 'review-wd': 'x', part: 'check-circle', allparts: 'check-circle', assigned: 'user', unassigned: 'user', comment: 'chat', mention: 'chat', status: 'check-circle', cd: 'shield', done: 'check', due: 'cal', priority: 'flag', attach: 'clip' };
function notifPlain(n) { const d = document.createElement('div'); d.innerHTML = n.text; return d.textContent; }
const IB_FILTERS = { all: 'All updates', comments: 'Comments & mentions', assigned: 'Assigned to me', status: 'Status & CD review', dates: 'Dates & priority' };
const ibMatch = (n, f) => f === 'all' || !f ? true : f === 'comments' ? ['comment', 'mention'].includes(n.kind) : f === 'assigned' ? ['assigned', 'unassigned'].includes(n.kind) : f === 'status' ? ['status', 'cd', 'done', 'review', 'review-ok', 'review-amend', 'review-wd'].includes(n.kind) : ['due', 'priority'].includes(n.kind);
function ibTime(iso) {
  const d = new Date(iso);
  if (dayDiff(ymd(d)) === 0) return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', ...(d.getFullYear() === new Date().getFullYear() ? {} : { year: 'numeric' }) });
}
function ibGroup(iso) {
  const d = new Date(iso), diff = dayDiff(ymd(d)), now = new Date();
  if (diff === 0) return 'Today';
  if (diff >= -7) return 'Last 7 days';
  if (d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()) return 'Earlier this month';
  return d.toLocaleDateString('en-US', { month: 'long', ...(d.getFullYear() === now.getFullYear() ? {} : { year: 'numeric' }) });
}
// The message part of an Inbox row, with coloured status / CD / priority chips like the task page
function notifMsg(n, t) {
  const who = `<b>${esc(fullName(userById(n.from)))}</b>`;
  const val = ((n.text.match(/<b>([^<]*)<\/b>(?![^]*<b>)/) || [])[1] || '').replace(/&amp;/g, '&');
  if (n.kind === 'status' && val) {
    const st = t ? statusList(t).find((x) => x.name === val) : null;
    const c = st ? st.color : '#87909e';
    return `${who} changed Status to: <span class="ib-chip" style="background:${c};color:${textOn(c)}">${esc(val)}</span>`;
  }
  if (n.kind === 'cd' && val) {
    const c = val === 'Approved' ? CD.approved.color : CD.review.color;
    return `${who} set CD Status to: <span class="ib-chip" style="background:${c};color:${textOn(c)}">${esc(val)}</span>`;
  }
  if (/^claim/.test(n.kind)) return `${who} ${n.text}${n.snippet ? ` <span class="ib-dim">· ${esc(n.snippet)}</span>` : ''}`;
  if (n.kind === 'asset') return `${who} ${esc(n.text)}${n.snippet ? ` <span class="ib-dim">· ${esc(n.snippet)}</span>` : ''}`;
  if (n.kind === 'review-amend' && n.snippet) return `${who} <span class="ib-dim">requested amendments:</span> ${esc(n.snippet)}`;
  if (n.kind === 'review-ok' && /your files/.test(n.text)) return `${who} approved your files <span class="ib-chip" style="background:${CD.approved.color};color:${textOn(CD.approved.color)}">APPROVED</span>`;
  if ((n.kind === 'comment' || n.kind === 'mention') && n.snippet) {
    const snip = esc(n.snippet).replace(/@([A-Z][\w.'-]*(?: [A-Z][\w.'-]*){0,2})/g, '<span class="mention">@$1</span>');
    return `${who} <span class="ib-dim">${n.kind === 'mention' ? 'mentioned you:' : n.text.includes('repl') ? 'replied:' : 'commented:'}</span> ${snip}`;
  }
  return `${who} ${n.text.replace(/ (on|to|from|of|for)$/, '').replace(/ —[^<]*:$|:$/, '')}${n.kind === 'assigned' ? ' this task' : n.kind === 'unassigned' ? ' this task' : ''}`;
}
function viewInbox() {
  const tab = ['all', 'cleared'].includes(ui.inboxTab) ? ui.inboxTab : 'primary';
  const f = ui.inboxFilter || 'all';
  const mine = myNotifs().filter((n) => ibMatch(n, f));
  const unreadN = myNotifs().filter((n) => !n.read).length;
  const list = tab === 'primary' ? mine.filter((n) => !n.read) : tab === 'cleared' ? mine.filter((n) => n.read) : mine;
  // one row per task: latest update + how many updates
  const byTask = new Map();
  list.slice().sort((a, b) => b.at.localeCompare(a.at)).forEach((n) => {
    const k = notifKey(n);
    if (!byTask.has(k)) byTask.set(k, { latest: n, items: [] });
    byTask.get(k).items.push(n);
  });
  const groups = [];
  [...byTask.values()].slice(0, 300).forEach((g) => {
    const name = ibGroup(g.latest.at);
    let grp = groups.find((x) => x.name === name);
    if (!grp) { grp = { name, rows: [] }; groups.push(grp); }
    grp.rows.push(g);
  });
  const row = ({ latest: n, items }) => {
    const t = task(n.taskId);
    const unread = items.some((x) => !x.read);
    const isRev = (x) => /^review/.test(x.kind);
    // opens what needs you first (an unread review or @mention); otherwise the update the row shows
    const target = items.find((x) => isRev(x) && !x.read) || items.find((x) => x.kind === 'mention' && !x.read) || n;
    const shown = isRev(target) ? target : n;
    const lead = ['comment', 'mention', 'review-amend', 'review-ok', 'review', 'claim', 'claim-ok', 'claim-paid', 'asset'].includes(shown.kind) ? avatarHTML(shown.from, 22) : `<span class="ib-kic">${icon(NOTIF_ICON[shown.kind] || 'bell')}</span>`;
    return `<div class="ib-row ${unread ? 'unread' : ''}" data-action="open-notif" data-id="${target.id}">
      <span class="ib-title">${n.kind === 'asset' ? `<span class="st-ic ib-coin">${icon('assets')}</span><span class="ib-tname">${esc(assetTitle(n))}</span>` : `${t ? statusIcon(t) : /^claim/.test(n.kind) ? `<span class="st-ic ib-coin">${icon('coin')}</span>` : `<span class="st-ic">${statusIconSVG('#87909e', 'todo', 0)}</span>`}<span class="ib-tname">${t ? esc(t.title || 'Untitled task') : /^claim/.test(n.kind) ? 'Expense claims' : '<i>Deleted task</i>'}</span>`}</span>
      <span class="ib-lead">${lead}</span>
      <span class="ib-msg">${notifMsg(shown, t)}</span>
      <span class="ib-count">${items.length > 1 ? `<i>${items.length}</i>` : ''}</span>
      <span class="ib-time" title="${fmtDateTime(n.at)}">${ibTime(n.at)}</span>
 <button class="ib-clear" data-action="notif-clear" data-id="${esc(notifKey(n))}" data-read="${unread ? '0' : '1'}">${unread ? `${icon('check')}Clear` : 'Mark unread'}</button>
    </div>`;
  };
  return `<div class="inbox">
    <div class="ib-tabs">
      <button class="ib-tab ${tab === 'primary' ? 'on' : ''}" data-action="inbox-tab" data-tab="primary">${icon('inbox')}<span><b>Primary</b>${unreadN ? `<small>${unreadN} unread</small>` : ''}</span></button>
      <button class="ib-tab ${tab === 'all' ? 'on' : ''}" data-action="inbox-tab" data-tab="all">${icon('activity')}<span><b>All</b></span></button>
      <button class="ib-tab ${tab === 'cleared' ? 'on' : ''}" data-action="inbox-tab" data-tab="cleared">${icon('check')}<span><b>Cleared</b></span></button>
    </div>
    <div class="ib-tools">
      <button class="pill-btn ${f !== 'all' ? 'on' : ''}" data-action="ib-filter">${icon('list')}${f === 'all' ? 'Filter' : esc(IB_FILTERS[f])}</button>
      <span class="spacer"></span>
      ${unreadN ? `<button class="pill-btn" data-action="mark-all-read">${icon('check')}Clear all</button>` : ''}
    </div>
    ${groups.map((g) => `<div class="ib-group">${g.name}</div><div class="ib-card">${g.rows.map(row).join('')}</div>`).join('')
      || `<div class="empty ib-empty"><div class="big">${tab === 'primary' ? 'Inbox zero 🎉' : 'Nothing here yet'}</div>${tab === 'primary' ? 'You’re all caught up. New updates on your tasks and @mentions land here.' : 'Updates on tasks you’re assigned to or created will appear here.'}</div>`}
  </div>`;
}
function inboxFilterMenu(anchor) {
  showMenu(anchor, Object.entries(IB_FILTERS).map(([k, l]) => ({ html: `<div class="mi ${(ui.inboxFilter || 'all') === k ? 'cur' : ''}">${esc(l)}</div>`, run: () => { ui.inboxFilter = k; renderContent(); } })).map((it, i) => ({ ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) })));
}
// Inbox rows: a task's updates together; Client Assets updates together per client
const notifKey = (n) => n.taskId || (n.kind === 'asset' ? 'asset:' + n.clientId : n.id);
const assetTitle = (n) => `${(clientById(n.clientId) || {}).name || 'A client'} · Client Assets`;
function clearTaskNotifs(taskId, read) {
  myNotifs().forEach((n) => { if (notifKey(n) === taskId) n.read = read; });
  persist(); renderSidebar(); renderContent();
}
function openNotif(id) {
  const n = db.notifications.find((x) => x.id === id);
  if (!n) return;
  if (/^claim/.test(n.kind)) { myNotifs().forEach((x) => { if (x.claimId && x.claimId === n.claimId) x.read = true; }); persist(); renderSidebar(); return Claims.openNotif(n); }
  if (n.kind === 'asset') {
    myNotifs().forEach((x) => { if (notifKey(x) === notifKey(n)) x.read = true; }); persist(); renderSidebar();
    if (!clientById(n.clientId)) { toast('That client’s assets aren’t available'); return; }
    const c = clientById(n.clientId);
    return openClient(c.id, c.folders.some((x) => x.id === n.folderId) ? n.folderId : null);
  }
  myNotifs().forEach((x) => { if (x.taskId === n.taskId) x.read = true; });
  persist(); renderSidebar(); renderContent();
  const t = task(n.taskId);
  if (!t) {
    const inTrash = trashList().find((x) => (x.type === 'task' || x.type === 'project') && (x.key === 'tasks:' + n.taskId || ((x.data || {}).tasks || []).some((t) => t.id === n.taskId)));
    if (inTrash && isManager()) { ui.trashQ = trashTitle(inTrash); ui.trashFilter = 'all'; closeDetail(); go('trash'); toast('That task is in the Trash — restore it from here'); }
    else toast(isManager() ? 'That task has been deleted' : 'That task is in the Trash — ask an Account Manager if it should come back');
    return;
  }
  if ((n.kind === 'review' || n.kind === 'review-wd') && isCD()) {
    // the submission this update is about: scroll to it on Review Requests and highlight it briefly
    const rs = (t.reviews || []).filter((r) => r.by === n.from && r.state !== 'withdrawn');
    const r = rs.filter((x) => x.at <= n.at).pop() || rs[rs.length - 1] || null;
    ui.rrTab = r && r.state !== 'pending' && reviewedRecent().some((x) => x.r.id === r.id) ? 'reviewed' : 'active';
    closeDetail(); go('reviews');
    if (r) flashReview(r.id);
    return;
  }
  let c = null;
  if (n.kind === 'review-amend' && n.commentId) c = t.comments.find((x) => x.id === n.commentId) || null;
  if (n.kind === 'comment' || n.kind === 'mention') {
    // older notifications have no comment id: find the author's comment closest in time
    c = (n.commentId && t.comments.find((x) => x.id === n.commentId))
      || t.comments.filter((x) => x.authorId === n.from).sort((a, b) => Math.abs(new Date(a.at) - new Date(n.at)) - Math.abs(new Date(b.at) - new Date(n.at)))[0] || null;
  }
  if (c) {
    ui.sideTab = ui.forceTab = 'comments';
    ui.activityFilter = 'comments';
    ui.pendingThread = c.parentId || null;
    ui.replyTo = null;
    ui.focusComment = c.id;
  } else if (n.kind === 'mention') {
    ui.sideTab = 'details';
    ui.descOpen[t.id] = true;
    ui.focusDesc = true;
  }
  openTask(n.taskId);
}
// Smoothly bring a comment into view and flash it
function flashReview(rid) {
  const run = (k) => {
    const el = $(`#content [data-review="${rid}"]`);
    if (!el) { if (k < 5) setTimeout(() => run(k + 1), 120); return; }
    el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash');
    setTimeout(() => el.classList.remove('flash'), 2600);
  };
  setTimeout(() => run(0), 80);
}
function focusCommentInFeed(cid) {
  const el = $(`#detail [data-comment="${cid}"]`);
  const feed = $('#detail .tm-feed');
  if (!el || !feed) return;
  const go = () => {
    const top = el.getBoundingClientRect().top - feed.getBoundingClientRect().top + feed.scrollTop - feed.clientHeight / 2 + el.offsetHeight / 2;
    feed.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
  };
  setTimeout(go, 120);
  setTimeout(go, 600);
  el.classList.add('flash');
  setTimeout(() => el.classList.remove('flash'), 2600);
}

/* ---- Alerts: in-app card + chime when the app is in front, macOS banner + sound when it isn't ---- */
let audioCtx = null;
function chime() {
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    const t0 = audioCtx.currentTime;
    [[880, 0], [1318.5, 0.11]].forEach(([f, d]) => {
      const o = audioCtx.createOscillator(), g = audioCtx.createGain();
      o.type = 'sine'; o.frequency.value = f;
      g.gain.setValueAtTime(0.0001, t0 + d);
      g.gain.exponentialRampToValueAtTime(0.18, t0 + d + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + d + 0.55);
      o.connect(g).connect(audioCtx.destination);
      o.start(t0 + d); o.stop(t0 + d + 0.6);
    });
  } catch (e) { /* no audio */ }
}
function alertUser({ title, body, taskId, from, open, stay }, force) {
  const u = me();
  const sound = !u || u.prefs.sound !== false;
  const front = document.hasFocus();
  if (front || force) {
    let root = $('#notif-root');
    if (!root) { root = document.createElement('div'); root.id = 'notif-root'; document.body.appendChild(root); }
    const el = document.createElement('div');
    el.className = 'notif-card';
    el.innerHTML = `${from ? avatarHTML(from, 32) : `<span class="nc-ic">${icon('bell')}</span>`}<div><b>${esc(title)}</b><span>${esc(body)}</span></div><button class="icon-btn sm">${icon('x')}</button>`;
    root.appendChild(el);
    const close = () => { el.classList.add('out'); setTimeout(() => el.remove(), 250); };
    const timer = setTimeout(close, stay || 6000);
    el.addEventListener('click', (e) => { clearTimeout(timer); close(); if (e.target.closest('button')) return; if (open) open(); else if (taskId && task(taskId)) openTask(taskId); });
    if (sound) chime();
  }
  if (!front || force) Host.call('notify', { title, body, sound: sound && !front ? 'Glass' : null }).catch(() => {});
}
// Occasion reminders (Social, AMs, Admins; 45, 30, 14 and 7 days before, 10:30 Dubai): the server sends them to
// phones with notifications on; an open app shows each one once per device that day. Tapping opens the calendar.
const OccRemind = (() => {
  let busy = false;
  async function check() {
    if (busy || !Host.isServer || !db || !currentUserId || typeof Cal === 'undefined' || !Cal.canSee(me())) return;
    busy = true;
    try {
      const r = await api('GET', '/api/occ-reminders');
      const list = r.list || [];
      if (!list.length) return;
      const pushed = await Digest.pushOn();
      for (const x of list) {
        const k = `e11-occ-${currentUserId}-${x.id}-${x.step}`;
        let seen = null; try { seen = localStorage.getItem(k); } catch (e) { /* storage off */ }
        if (seen) continue;
        try { localStorage.setItem(k, r.day); } catch (e) { /* storage off */ }
        if (pushed) continue;                // this phone already got it as a notification
        alertUser({ title: x.title, body: x.body, stay: 15000, open: () => go('calendar') }, true);
      }
    } catch (e) { /* offline: try again later */ } finally { busy = false; }
  }
  function start() {
    setTimeout(check, 5000);
    setInterval(check, 5 * 60_000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) setTimeout(check, 2000); });
  }
  return { start, check };
})();
// Morning summary (Production / Social, 10:30 Dubai, Monday to Friday): the server sends it to phones with
// notifications on; an open app shows it as a banner, once per device per day, until midnight. Not in the Inbox.
const Digest = (() => {
  const key = () => 'e11-digest-' + currentUserId;
  const wants = (u) => !!u && (u.role === 'production' || u.role === 'social') && !((u.prefs || {}).digestOff);
  async function pushOn() {
    try { const reg = navigator.serviceWorker && await navigator.serviceWorker.getRegistration(); return !!(reg && reg.pushManager && await reg.pushManager.getSubscription()); } catch (e) { return false; }
  }
  let busy = false;
  async function check() {
    if (busy || !Host.isServer || !db || !currentUserId || !wants(me())) return;
    busy = true;
    try {
      const r = await api('GET', '/api/digest');
      if (!r.due) return;
      let seen = null; try { seen = localStorage.getItem(key()); } catch (e) { /* storage off */ }
      if (seen === r.day) return;
      try { localStorage.setItem(key(), r.day); } catch (e) { /* storage off */ }
      if (await pushOn()) return;          // this phone already got it as a notification
      alertUser({ title: r.title, body: r.body, stay: 12000 }, true);
    } catch (e) { /* offline: try again later */ } finally { busy = false; }
  }
  function start() {
    setTimeout(check, 4000);
    setInterval(check, 60_000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) setTimeout(check, 1500); });
  }
  async function test() {
    try {
      const r = await api('POST', '/api/digest/test', {});
      if (r.phones) toast(`Sent to your phone${r.phones > 1 ? 's' : ''}`);
      alertUser({ title: r.title, body: r.body, stay: 12000 }, true);
    } catch (e) { toast(e.message); }
  }
  return { start, check, test, wants, pushOn };
})();
// Show alerts for notifications this person hasn't been alerted about yet
function deliverPending() {
  const u = me();
  if (!u) return;
  const since = u.lastAlertAt || '';
  // Finance-only people only hear about expense claims
  const fresh = myNotifs().filter((n) => !n.read && n.at > since && (!isFinUser() || /^claim/.test(n.kind))).sort((a, b) => a.at.localeCompare(b.at));
  u.lastAlertAt = nowISO();
  if (!fresh.length) return;
  persist();
  if (fresh.length === 1) {
    const n = fresh[0], t = task(n.taskId);
    alertUser({ title: fullName(userById(n.from)), body: `${notifPlain(n)} ${t ? '“' + (t.title || 'Untitled task') + '”' : ''}${n.snippet ? ' — ' + n.snippet : ''}`, taskId: n.taskId, from: n.from, open: /^claim/.test(n.kind) ? () => { n.read = true; persist(); Claims.openNotif(n); } : n.kind === 'asset' ? () => openNotif(n.id) : null });
  } else if (isFinUser()) {
    alertUser({ title: 'E11 Console', body: `${fresh.length} new expense claims`, open: () => go('fin-reimb') });
  } else {
    alertUser({ title: 'E11 Console', body: `You have ${fresh.length} new notifications in your Inbox` });
  }
}

/* ================= Team members (admin) ================= */
function viewTeam() {
  const admin = can('manageUsers');
  const all = db.users.slice().sort((a, b) => fullName(a).localeCompare(fullName(b)));
  const current = all.filter((u) => u.active !== false), past = all.filter((u) => u.active === false);
  const tab = ui.teamTab === 'past' ? 'past' : 'active';
  const users = tab === 'past' ? past : current;
  return `<div class="team">
    <div class="team-head">
      <div><div class="team-title">${current.length} member${current.length === 1 ? '' : 's'}</div><div class="team-sub">${admin ? (Host.isServer ? `Only Admins can add people. New members sign in at ${esc(location.host)} with their email — no password needed.` : 'Only Admins can add people. New members sign in with the email and temporary password you give them, then set their own password.') : 'Only Admins can add or change team members.'}</div>${admin && Host.isServer ? '<div class="cf-status" id="cf-status"></div>' : ''}</div>
      <span class="spacer"></span>
      ${admin ? `<button class="btn primary" data-action="add-member">${icon('plus')}Add member</button>` : ''}
    </div>
    <div class="mt-tabs team-tabs" role="tablist">
      <button class="mt-tab ${tab === 'active' ? 'on' : ''}" role="tab" aria-selected="${tab === 'active'}" data-action="team-tab" data-tab="active">Active members <span>${current.length}</span></button>
      <button class="mt-tab ${tab === 'past' ? 'on' : ''}" role="tab" aria-selected="${tab === 'past'}" data-action="team-tab" data-tab="past">Past members <span>${past.length}</span></button>
    </div>
    ${tab === 'past' && !past.length ? '<div class="empty"><div class="big">No past members</div>People you remove from the team show here, and you can restore their access.</div>' : `<div class="team-table">
      <div class="tt-row tt-head"><div>Name</div><div>Email</div><div>Role</div><div>Status</div><div>Creative Director</div><div></div></div>
      ${users.map((u) => `<div class="tt-row ${u.active === false ? 'inactive' : ''}">
        <div class="tt-name">${avatarHTML(u.id, 30)}<span>${esc(fullName(u))}${u.id === currentUserId ? ' <small>(you)</small>' : ''}</span></div>
        <div class="tt-email">${esc(u.email)}</div>
        <div><span class="role-pill r-${u.role}">${esc(ROLES[u.role] || u.role)}</span>${u.admin && u.role !== 'admin' ? '<span class="role-pill r-admin xtra">+ Admin</span>' : ''}${u.fin && !isFinUser(u) ? `<span class="role-pill r-finance_${u.fin} xtra">+ ${esc(FIN_ACCESS[u.fin])}</span>` : ''}${u.role === 'freelancer' ? `<button class="tt-proj" ${admin ? `data-action="member-projects" data-id="${u.id}"` : ''} title="Clients they can see">${(u.projectIds || []).length} project${(u.projectIds || []).length === 1 ? '' : 's'}</button>` : ''}</div>
        <div>${u.active === false ? '<span class="st-txt off">Removed</span>' : u.setup ? `<span class="st-txt on">Active</span>` : '<span class="st-txt pend">Hasn’t signed in yet</span>'}</div>
        ${cdCell(u, admin)}
        <div>${admin ? `<button class="icon-btn sm" data-action="member-menu" data-id="${u.id}" title="Manage">${icon('more')}</button>` : ''}</div>
      </div>`).join('')}
    </div>`}
    <div class="role-guide">
      <div><span class="role-pill r-admin">Admin</span> Full access, and the only role that can add or manage team members.</div>
      <div><span class="role-pill r-am">Account Manager</span> Can do everything except add or manage team members.</div>
      <div><span class="role-pill r-freelancer">Freelancer</span> Same as Production, but only sees the clients an Admin chooses for them, plus those clients’ Client Assets. Can sign in with a personal email (Gmail, Outlook…).</div>
      <div><span class="role-pill r-production">Production</span> <span class="role-pill r-social">Social</span> Can update status, submit files for CD review, change dates, add tags, checklist items, files and comments. Can’t create or delete tasks/subtasks, change title, description, client or priority, assign people, remove tags or delete checklist items.</div>
      <div><span class="role-pill r-finance_admin">Finance only</span> Only sees the Finance pages (Dashboard, Clients, Expenses) — no tasks app. As Admin they add subscriptions, reimbursements and expenses; as Viewer they only look.</div>
      <div><span class="role-pill r-admin">+ Admin</span> <span class="role-pill r-finance_admin">+ Finance Admin / Viewer</span> Extras anyone can have on top of their role (••• menu): full Admin rights, or the Finance pages. A task’s Finance status is set by Account Managers and Admins.</div>
    </div>
  </div>`;
}

// Small form dialog: fields = [{ key, label, type, value, options, readonly, placeholder }]
function formDialog({ title, intro = '', fields, okText = 'Save', validate }) {
  return new Promise((resolve) => {
    const root = $('#overlay-root');
    root.innerHTML = `<div class="scrim"><form class="dialog form-dlg" autocomplete="off">
      <h2>${esc(title)}</h2>${intro ? `<p>${esc(intro)}</p>` : ''}
      ${fields.map((f) => `<label class="dlg-label">${esc(f.label)}</label>${f.type === 'select'
        ? `<select class="field" name="${f.key}">${f.options.map(([v, l]) => `<option value="${esc(v)}" ${v === f.value ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`
        : `<input class="field" name="${f.key}" type="${f.type || 'text'}" value="${esc(f.value || '')}" placeholder="${esc(f.placeholder || '')}" ${f.readonly ? 'readonly' : ''}>`}${f.hint ? `<div class="dlg-hint">${esc(f.hint)}</div>` : ''}`).join('')}
      <div class="dlg-err"></div>
      <div class="actions"><button type="button" class="btn" data-r="0">Cancel</button><button type="submit" class="btn primary">${esc(okText)}</button></div>
    </form></div>`;
    const form = $('form', root), err = $('.dlg-err', root);
    const close = (v) => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); resolve(v); };
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(null); } else e.stopPropagation(); };
    document.addEventListener('keydown', onKey, true);
    $('[data-r="0"]', root).addEventListener('click', () => close(null));
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const v = {}; fields.forEach((f) => { v[f.key] = (form.elements[f.key].value || '').trim(); });
      const problem = validate ? validate(v) : null;
      if (problem) { err.textContent = problem; return; }
      close(v);
    });
    setTimeout(() => { const first = $('input:not([readonly]), select', form); if (first) first.focus(); }, 20);
  });
}

async function addMemberFlow() {
  if (!can('manageUsers')) return denied();
  const v = await formDialog({
    title: 'Add team member', okText: 'Add member',
    intro: Host.isServer ? `They sign in at ${location.host} with this email — a one-time code is emailed to them. No password needed.` : 'They’ll sign in with this email and temporary password, then choose their own password.',
    fields: [
      { key: 'name', label: 'Full name (optional — they can set it themselves)', placeholder: 'e.g. Sara Khan' },
      { key: 'email', label: 'Email', type: 'email', placeholder: 'name@e11-digital.com' },
      ...(Host.isServer ? [] : [{ key: 'pw', label: 'Temporary password', type: 'text', value: tempPassword(), hint: 'Share this with them privately. At least 6 characters.' }]),
      { key: 'role', label: 'Role', type: 'select', value: 'production', options: Object.entries(ROLES) },
      { key: 'admin', label: 'Admin rights on top of their role', type: 'select', value: '', options: [['', 'No'], ['yes', 'Yes — they can also do everything an Admin can']], hint: 'Not needed for the Admin role or Finance-only people.' },
      { key: 'fin', label: 'Finance access', type: 'select', value: '', options: Object.entries(FIN_ACCESS), hint: 'Finance Admin adds subscriptions, reimbursements and expenses; Finance Viewer only looks. Finance-only people already have it.' },
    ],
    validate: (v) => {
      if (!validEmail(v.email)) return 'Enter a valid email address';
      if (db.users.some((u) => u.email.toLowerCase() === v.email.toLowerCase() && u.active !== false)) return 'Someone with this email is already on the team';
      if (!Host.isServer && v.pw.length < 6) return 'The temporary password needs at least 6 characters';
      return null;
    },
  });
  if (!v) return;
  let u = db.users.find((x) => x.email.toLowerCase() === v.email.toLowerCase());
  if (u) { u.active = true; u.setup = false; u.role = v.role; if (v.name) u.name = v.name; }
  else { u = { id: 'u-' + uid(), email: v.email.toLowerCase(), name: v.name, role: v.role, avatar: null, setup: false, active: true, createdAt: nowISO(), createdBy: currentUserId, prefs: {} }; db.users.push(u); }
  const finOnly = v.role === 'finance_admin' || v.role === 'finance_viewer';
  u.admin = v.admin === 'yes' && v.role !== 'admin' && !finOnly ? true : undefined;
  u.fin = v.fin && !finOnly ? v.fin : undefined;
  if (!Host.isServer) setPassword(u, v.pw);
  persist(0); renderContent();
  toast(`Added ${v.email} as ${ROLES[v.role]}`);
  if (v.role === 'freelancer') projectAccessDialog(u);
}
function tempPassword() { const c = 'abcdefghjkmnpqrstuvwxyz23456789'; let s = ''; for (let i = 0; i < 10; i++) s += c[Math.floor(Math.random() * c.length)]; return s; }

// Freelancers only see the projects ticked here (and the Client Assets of those projects' clients)
function projectAccessDialog(u) {
  if (!can('manageUsers')) return denied();
  const chosen = new Set(Array.isArray(u.projectIds) ? u.projectIds : []);
  const root = $('#overlay-root');
  const list = db.projects.slice().sort(byOrder);
  root.innerHTML = `<div class="scrim"><form class="dialog form-dlg pa-dlg">
    <h2>Clients ${esc(fullName(u))} can see</h2>
    <p>Freelancers only see these clients, their tasks and files, and their Client Assets. Everything else stays hidden.</p>
    <div class="pa-list">${list.length ? list.map((p) => `<label class="pa-row"><input type="checkbox" value="${p.id}" ${chosen.has(p.id) ? 'checked' : ''}><i style="background:${p.color}"></i><span>${esc(p.name)}</span>${clientOfProject(p) ? `<small>${esc(clientOfProject(p).name)}</small>` : ''}</label>`).join('') : '<div class="ph">No clients yet</div>'}</div>
    <div class="actions"><button type="button" class="btn" data-r="0">Cancel</button><button type="submit" class="btn primary">Save</button></div>
  </form></div>`;
  const close = () => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); };
  const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); } };
  document.addEventListener('keydown', onKey, true);
  $('[data-r="0"]', root).addEventListener('click', close);
  $('form', root).addEventListener('submit', (e) => {
    e.preventDefault();
    u.projectIds = $$('.pa-list input:checked', root).map((x) => x.value);
    close(); persist(0); renderContent();
    toast(`${fullName(u)} can see ${u.projectIds.length} client${u.projectIds.length === 1 ? '' : 's'}`);
  });
}

function memberMenu(anchor, id) {
  const u = userById(id);
  if (!u) return;
  // Your own row: only the extras (Finance access) — you can't change your own role or remove yourself
  if (u.id === currentUserId) {
    const own = [{ html: '<div class="menu-label">Your Finance access</div>' }];
    Object.entries(FIN_ACCESS).forEach(([k, l]) => own.push({ html: `<div class="mi">${icon('coin')}${esc(l)}${(u.fin || '') === k ? `<span class="wf-ck">${icon('check')}</span>` : ''}</div>`, run: () => {
      u.fin = k || undefined; persist(); renderContent(); Fin.init(); renderSidebar(); toast(k ? `You now have ${l} access` : 'You no longer have Finance access');
    } }));
    showMenu(anchor, own.map((it, i) => (it.run ? { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) } : it)));
    return;
  }
  const items = [{ html: '<div class="menu-label">Change role</div>' }];
  Object.entries(ROLES).forEach(([k, l]) => items.push({ html: `<div class="mi ${u.role === k ? 'cur' : ''}"><span class="role-pill r-${k}">${esc(l)}</span></div>`, run: () => {
    if (isAdm(u) && k !== 'admin' && !u.admin && db.users.filter((x) => isAdm(x) && x.active !== false).length < 2) return toast('There must be at least one Admin');
    u.role = k; persist(); renderContent(); toast(`${fullName(u)} is now ${l}`);
    if (k === 'freelancer') setTimeout(() => projectAccessDialog(u), 0);
  } }));
  items.push('-');
  const finOnly = isFinUser(u);
  if (u.role !== 'admin' && !finOnly) items.push({ html: `<div class="mi">${icon('shield')}Admin rights${u.admin ? `<span class="wf-ck">${icon('check')}</span>` : ''}</div>`, run: () => {
    if (u.admin && db.users.filter((x) => isAdm(x) && x.active !== false).length < 2) return toast('There must be at least one Admin');
    u.admin = u.admin ? undefined : true; persist(); renderContent(); toast(u.admin ? `${fullName(u)} now also has Admin rights` : `${fullName(u)} no longer has Admin rights`);
  } });
  if (!finOnly) Object.entries(FIN_ACCESS).forEach(([k, l]) => items.push({ html: `<div class="mi">${icon('coin')}${esc(l)}${(u.fin || '') === k ? `<span class="wf-ck">${icon('check')}</span>` : ''}</div>`, run: () => {
    u.fin = k || undefined; persist(); renderContent(); toast(k ? `${fullName(u)} now has ${l} access` : `${fullName(u)} no longer has Finance access`);
  } }));
  items.push('-');
  if (u.role === 'freelancer') items.push({ label: 'Clients they can see…', icon: 'folder', run: () => projectAccessDialog(u) });
  if (u.active === false) items.push({ label: 'Restore access', icon: 'user', run: () => { u.active = true; persist(); renderContent(); } });
  else {
    if (!Host.isServer) items.push({ label: 'Reset password…', icon: 'lock', run: () => resetPasswordFlow(u) });
    items.push({ label: 'Remove from team', icon: 'trash', danger: true, run: () => removeMemberFlow(u) });
  }
  showMenu(anchor, items.map((it, i) => (it === '-' || it.label ? it : { ...it, html: it.html.replace('<div class="mi', `<div data-mi="${i}" class="mi`) })));
}
async function resetPasswordFlow(u) {
  const v = await formDialog({ title: `Reset password for ${fullName(u)}`, okText: 'Reset password', intro: 'They’ll sign in with this temporary password and be asked to choose a new one.',
    fields: [{ key: 'pw', label: 'Temporary password', value: tempPassword() }], validate: (x) => (x.pw.length < 6 ? 'At least 6 characters' : null) });
  if (!v) return;
  setPassword(u, v.pw); u.setup = false; persist(0); renderContent();
  toast('Password reset — share the temporary password with them privately');
}
async function removeMemberFlow(u) {
  if (isAdm(u) && db.users.filter((x) => isAdm(x) && x.active !== false).length < 2) return toast('There must be at least one Admin');
  const n = db.tasks.filter((t) => (t.assignees || []).includes(u.id)).length;
  const ok = await dialog({ title: `Remove ${fullName(u)}?`, body: `They won’t be able to sign in${n ? ` and will be unassigned from ${n} task${n === 1 ? '' : 's'}` : ''}. Their comments stay. You can restore access later.`, okText: 'Remove', danger: true });
  if (!ok) return;
  u.active = false;
  db.tasks.forEach((t) => { if ((t.assignees || []).includes(u.id)) { t.assignees = t.assignees.filter((x) => x !== u.id); if (t.prio) delete t.prio[u.id]; logActivity(t, `unassigned ${struck(fullName(u))}`); } });
  persist(0); render();
}

/* ================= My profile ================= */
function viewProfile() {
  const u = me();
  const sound = u.prefs.sound !== false;
  return `<div class="profile">
    <div class="pf-card">
      <div class="pf-photo">${avatarHTML(u.id, 96, 'pf-av')}<div class="pf-photo-btns"><button class="btn sm" data-action="change-photo">${icon('camera')}${u.avatar ? 'Change photo' : 'Add photo'}</button>${u.avatar ? `<button class="btn ghost sm" data-action="remove-photo">Remove</button>` : ''}</div></div>
      <label class="dlg-label">Full name</label><input class="field" id="pf-name" value="${esc(u.name || '')}" placeholder="Your full name">
      <label class="dlg-label">Email</label><div class="field ro">${icon('lock')}${esc(u.email)}</div>
      <label class="dlg-label">Office</label><input class="field" id="pf-office" value="${esc(u.office || '')}" maxlength="80" placeholder="e.g. Dubai — Business Bay office">
      <label class="dlg-label">Role</label><div class="pf-role"><span class="role-pill r-${u.role}">${esc(ROLES[u.role])}</span>${u.admin && u.role !== 'admin' ? '<span class="role-pill r-admin">+ Admin</span>' : ''}${u.fin && !isFinUser(u) ? `<span class="role-pill r-finance_${u.fin}">+ ${esc(FIN_ACCESS[u.fin])}</span>` : ''}${u.id === cdUserId() ? `<span class="role-pill r-cd">${esc(cdTitle())}</span>` : ''}<small>People see this and your office when they hover your name.</small></div>
      <div class="pf-actions"><button class="btn primary" data-action="save-profile">Save changes</button>${Host.isServer ? '' : `<button class="btn" data-action="change-password">${icon('lock')}Change password</button>`}</div>
    </div>
    ${Host.isServer && AppIcon.isOwner() ? appIconCard() : ''}
    ${typeof Phone !== 'undefined' && Phone.on ? '' : `<div class="pf-card pf-appearance">
      <div class="pa-txt"><h3>Appearance</h3><p>Choose light or dark mode, or switch automatically with sunrise and sunset in Dubai${Theme.mode() === 'auto' ? ` — today ${esc(Theme.times())}` : ''}.</p></div>
      ${Theme.cards()}
    </div>`}
    ${Announce.card()}
    ${Host.isServer && !isFinUser() && !(typeof Phone !== 'undefined' && Phone.on) ? `<div class="pf-card pf-claims">
      <div><h3>${icon('coin')}My reimbursements</h3><p>Fill in your monthly expense claim, attach receipts and sign it. Finance is told when you submit, and you can follow it here until it’s paid.</p></div>
      <button class="btn" data-action="go-claims">Open My reimbursements</button>
    </div>` : ''}
    <div class="pf-card">
      <h3>${icon('bell')}Notifications</h3>
      <div class="pf-opt"><div><b>Sound</b><span>Play a sound with new notifications</span></div><button class="switch ${sound ? 'on' : ''}" data-action="toggle-sound"><i></i></button></div>
      ${Host.isServer && !Host.isMacApp && 'Notification' in window ? `<div class="pf-opt"><div><b>Desktop notifications</b><span>${Notification.permission === 'granted' ? 'On — you’ll see alerts even when this window is in the background' : Notification.permission === 'denied' ? 'Blocked in your browser settings for this site' : 'Show alerts when this window is in the background'}</span></div>${Notification.permission === 'default' ? '<button class="btn sm primary" data-action="allow-notifs">Turn on</button>' : ''}</div>` : ''}
      <div class="pf-opt"><div><b>Test</b><span>See and hear what a notification looks like</span></div><button class="btn sm" data-action="test-notif">Send test</button></div>
      <div class="pf-opt"><div><b>Seasonal decorations</b><span>Santa hat and snow from 16 to 31 December, on the Mac app and website.</span></div><div class="pf-opt-btns"><button class="switch ${(u.prefs || {}).seasonOff ? '' : 'on'}" data-action="toggle-season" aria-label="Seasonal decorations"><i></i></button></div></div>
      ${Host.isServer && (u.role === 'production' || u.role === 'social' || isAdm(u)) ? `<div class="pf-opt"><div><b>Morning summary</b><span>${u.role === 'production' || u.role === 'social' ? 'At 10:30 am, Monday to Friday: how your day looks. Switch it off for holidays or leave.' : 'Production and Social get a summary of their day at 10:30 am, Monday to Friday. Send yourself one to see it.'}</span></div><div class="pf-opt-btns"><button class="btn sm" data-action="digest-test">Send test</button>${u.role === 'production' || u.role === 'social' ? `<button class="switch ${(u.prefs || {}).digestOff ? '' : 'on'}" data-action="toggle-digest" aria-label="Morning summary"><i></i></button>` : ''}</div></div>` : ''}
      <h4 class="pf-sub">Notify me about</h4>
      ${notifToggles(u, false)}
      ${u.id === cdUserId() ? `<h4 class="pf-sub">As ${esc(cdTitle())}</h4>${notifToggles(u, true)}` : ''}
      <p class="pf-note">You’re notified about tasks you’re assigned to or created: comments, status and CD Status changes, due dates, priority, files, completion, and when someone @mentions you. Remove yourself from a task to stop getting its updates.</p>
    </div>
  </div>`;
}
function appIconCard() {
  const i = AppIcon.info();
  return `<div class="pf-card ai-card">
      <h3>${icon('image')}Mac app icon</h3>
      <div class="ai-row">
        <div class="ai-dock" aria-hidden="true"><img src="${AppIcon.url()}" alt=""></div>
        <div class="ai-txt"><b>${i.custom ? 'Custom icon' : 'Default icon'}</b><span>${i.custom && i.at ? `Changed ${esc(timeAgo(i.at))}` : 'The icon that comes with the Mac app'}. It shows in everyone’s Dock and changes on every Mac as soon as you upload a new one.</span></div>
      </div>
      <div class="pf-actions"><button class="btn primary" data-action="appicon-upload">${icon('upload')}Upload new icon</button>${i.custom ? '<button class="btn" data-action="appicon-reset">Reset to default</button>' : ''}</div>
      <p class="pf-note">Square PNG or JPG, 512 × 512 or larger. Only you can see this. Macs need the Mac app installed once after this update — then every change arrives by itself.</p>
    </div>`;
}
// Pick an image (Mac app: native picker; browser: file input) and return it as a Blob
async function pickIconImage() {
  if (Host.isMacApp) {
    const r = await NativeMac.call('pickLocalFiles', { multiple: false, images: true, prompt: 'Use as icon', message: 'Choose a square image for the Mac app icon' });
    const f = (r.files || [])[0];
    if (!f) return null;
    if (f.size > 15 * 1024 * 1024) { toast('That image is too large (15 MB at most)'); return null; }
    const c = await NativeMac.call('readLocalChunk', { token: f.token, offset: 0, length: f.size, last: true });
    const bin = atob(c.b64 || ''); const arr = new Uint8Array(bin.length);
    for (let k = 0; k < bin.length; k++) arr[k] = bin.charCodeAt(k);
    return new Blob([arr]);
  }
  const files = await ServerHost.pickFiles({ multiple: false, accept: 'image/png,image/jpeg,image/webp' });
  return files[0] || null;
}
// Client logos are stored as a square: transparent logos sit on a dark background if they're light and on
// a light one if they're dark; logos with their own background get a square of their edge colour. The same
// square is used everywhere (client cards, folders, menus), so it always shows edge to edge.
const isSquareLogo = (p) => /(^|\/)client-sq-[^/]*$/.test(String(p || ''));
async function squareLogo(blob) {
  const im = await loadImage(blob);
  const W = im.naturalWidth || im.width, H = im.naturalHeight || im.height;
  if (!W || !H) throw new Error('That image is empty');
  const k = Math.min(1, 256 / Math.max(W, H));
  const a = document.createElement('canvas'); a.width = Math.max(1, Math.round(W * k)); a.height = Math.max(1, Math.round(H * k));
  const g = a.getContext('2d', { willReadFrequently: true }); g.drawImage(im, 0, 0, a.width, a.height);
  const d = g.getImageData(0, 0, a.width, a.height).data;
  let clear = 0, lum = 0, weight = 0; const px = d.length / 4;
  for (let i = 0; i < d.length; i += 4) {
    const al = d[i + 3];
    if (al < 200) clear++;
    if (al > 40) { lum += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255 * al; weight += al; }
  }
  let bg, pad;
  if (clear / px > 0.04) {
    const L = weight ? lum / weight : 0;
    bg = L > 0.6 ? '#121317' : '#f5f4f0'; pad = 0.16;
  } else {
    let r = 0, gg = 0, b = 0, n = 0;
    const edge = (x, y) => { const i = (y * a.width + x) * 4; r += d[i]; gg += d[i + 1]; b += d[i + 2]; n++; };
    for (let x = 0; x < a.width; x++) { edge(x, 0); edge(x, a.height - 1); }
    for (let y = 0; y < a.height; y++) { edge(0, y); edge(a.width - 1, y); }
    bg = `rgb(${Math.round(r / n)},${Math.round(gg / n)},${Math.round(b / n)})`; pad = 0.06;
  }
  const S = 800, c = document.createElement('canvas'); c.width = c.height = S;
  const cg = c.getContext('2d'); cg.fillStyle = bg; cg.fillRect(0, 0, S, S);
  const box = S * (1 - pad * 2), sc = Math.min(box / W, box / H), w = W * sc, h = H * sc;
  cg.imageSmoothingQuality = 'high'; cg.drawImage(im, (S - w) / 2, (S - h) / 2, w, h);
  const out = await new Promise((res) => c.toBlob(res, 'image/png'));
  return new File([out], 'logo.png', { type: 'image/png' });
}
// One-time: older client logos become squares too (done by an Admin / Account Manager opening Client Assets)
let logoMigration = null;
// The client's logo: an Admin's or AM's choice (Client options › Add / Change logo) always wins. Without one, the first
// image added to the Logos folder becomes the logo (made square), and the sidebar shows it instead of the colour.
const LOGO_EXT = /\.(png|jpe?g|webp|gif|svg)$/i;
let autoLogoBusy = false;
async function autoLogo(c, f, files) {
  if (!c || c.logo || autoLogoBusy || !Host.isServer || !f || f.name !== 'Logos' || !isAutoFolder(c, f)) return;
  const a = (files || f.files).find((x) => LOGO_EXT.test(x.name || ''));
  if (!a) return;
  autoLogoBusy = true;
  try {
    const blob = await fetch(fileUrl(a), { credentials: 'same-origin' }).then((r) => (r.ok ? r.blob() : null));
    if (!blob) return;
    const sq = await squareLogo(blob);
    const up = await ServerHost.uploadMany([sq], { taskId: '_uploads' });
    const r = await api('POST', '/api/host/processImage', { path: up[0].path, kind: 'logo', userId: 'client-sq' });
    const cur = clientById(c.id);
    if (r.path && cur && !cur.logo) { cur.logo = r.path; cur.logoAuto = true; persist(0); renderSidebar(); if (ui.view === 'client' || ui.view === 'clients') render(); }
  } catch (e) { /* no logo then; the colour stays */ } finally { autoLogoBusy = false; }
}
function migrateClientLogos() {
  if (logoMigration || !Host.isServer || !canAssets()) return;
  const todo = (db.clients || []).filter((c) => c.logo && !isSquareLogo(c.logo) && !/\.svg$/i.test(c.logo));
  if (!todo.length) return;
  logoMigration = (async () => {
    for (const c of todo) {
      try {
        const blob = await fetch(fileUrl({ path: c.logo }), { credentials: 'same-origin' }).then((r) => (r.ok ? r.blob() : null));
        if (!blob) continue;
        const sq = await squareLogo(blob);
        const up = await ServerHost.uploadMany([sq], { taskId: '_uploads' });
        const r = await api('POST', '/api/host/processImage', { path: up[0].path, kind: 'logo', userId: 'client-sq' });
        if (r.path && clientById(c.id)) { const old = c.logo; c.logo = r.path; safeTrash([old]); }
      } catch (e) { /* leave it as it is */ }
    }
    persist(0); render();
  })();
}
function loadImage(blob) {
  return new Promise((res, rej) => { const url = URL.createObjectURL(blob); const im = new Image(); im.onload = () => res(im); im.onerror = () => { URL.revokeObjectURL(url); rej(new Error('That file isn’t an image this app can read')); }; im.src = url; });
}
// The glass edge macOS 26 draws on updated apps, painted into the picture: a bright rim (strongest top-left and
// bottom-right), a soft inner glow along the edge, a sheen across the top and a little depth along the bottom.
function paintGlass(g, path, o, box) {
  g.save(); path(); g.clip();
  const sheen = g.createLinearGradient(0, o, 0, o + box * .4);
  sheen.addColorStop(0, 'rgba(255,255,255,.23)'); sheen.addColorStop(.55, 'rgba(255,255,255,.035)'); sheen.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = sheen;
  g.beginPath(); g.moveTo(o, o); g.lineTo(o + box, o); g.lineTo(o + box, o + box * .401);
  g.bezierCurveTo(o + box * .801, o + box * .316, o + box * .243, o + box * .291, o, o + box * .364); g.closePath(); g.fill();
  const glow = g.createRadialGradient(o + box / 2, o + box * 1.05, 0, o + box / 2, o + box * 1.05, box * .75);
  glow.addColorStop(0, 'rgba(255,255,255,.14)'); glow.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = glow; g.fillRect(o, o, box, box);
  const deep = g.createLinearGradient(0, o, 0, o + box);
  deep.addColorStop(0, 'rgba(0,0,0,0)'); deep.addColorStop(.7, 'rgba(0,0,0,0)'); deep.addColorStop(1, 'rgba(0,0,0,.22)');
  g.fillStyle = deep; g.fillRect(o, o, box, box);
  // soft inner light along the edge (layered strokes, so it works without canvas blur)
  [[34, .035], [24, .05], [14, .07], [7, .08]].forEach(([w, a]) => { g.lineWidth = w; g.strokeStyle = `rgba(255,255,255,${a})`; path(); g.stroke(); });
  g.restore();
  const rim = g.createLinearGradient(o, o, o + box, o + box);
  [[0, .95], [.28, .35], [.55, .08], [.8, .25], [1, .7]].forEach(([at, a]) => rim.addColorStop(at, `rgba(255,255,255,${a})`));
  g.save(); g.lineWidth = 5; g.strokeStyle = rim; path(); g.stroke(); g.restore();
}
// 1024 × 1024 PNG. rounded = the Mac shape: 824 px rounded square with a soft shadow, centred; glass = the glass edge on top.
function renderIcon(im, rounded, glass) {
  const S = 1024, c = document.createElement('canvas'); c.width = c.height = S;
  const g = c.getContext('2d');
  const side = Math.min(im.naturalWidth, im.naturalHeight), sx = (im.naturalWidth - side) / 2, sy = (im.naturalHeight - side) / 2;
  g.imageSmoothingQuality = 'high';
  if (!rounded) { g.drawImage(im, sx, sy, side, side, 0, 0, S, S); return c; }
  const box = 824, o = (S - box) / 2, r = 185;
  const path = () => { g.beginPath(); g.moveTo(o + r, o); g.arcTo(o + box, o, o + box, o + box, r); g.arcTo(o + box, o + box, o, o + box, r); g.arcTo(o, o + box, o, o, r); g.arcTo(o, o, o + box, o, r); g.closePath(); };
  g.save(); g.shadowColor = 'rgba(0,0,0,.28)'; g.shadowBlur = 28; g.shadowOffsetY = 12; path(); g.fillStyle = '#000'; g.fill(); g.restore();
  g.save(); path(); g.clip(); g.drawImage(im, sx, sy, side, side, o, o, box, box); g.restore();
  if (glass) paintGlass(g, path, o, box);
  return c;
}
async function appIconUploadFlow() {
  let blob;
  try { blob = await pickIconImage(); } catch (e) { toast(e.message); return; }
  if (!blob) return;
  let im;
  try { im = await loadImage(blob); } catch (e) { toast(e.message); return; }
  const side = Math.min(im.naturalWidth, im.naturalHeight);
  if (side < 256) { toast(`That image is ${im.naturalWidth} × ${im.naturalHeight} — use at least 512 × 512`); return; }
  const squareNote = im.naturalWidth !== im.naturalHeight ? '<p class="ai-warn">This image isn’t square, so the middle of it will be used.</p>' : '';
  let rounded = true, glass = true;
  const root = $('#overlay-root');
  const draw = () => {
    const url = renderIcon(im, rounded, rounded && glass).toDataURL('image/png');
    $$('.ai-prev img', root).forEach((x) => { x.src = url; });
    const sw = $('.ai-round .switch', root); if (sw) sw.classList.toggle('on', rounded);
    const gw = $('.ai-glass', root); if (gw) { gw.hidden = !rounded; $('.switch', gw).classList.toggle('on', glass); }
  };
  root.innerHTML = `<div class="scrim"><div class="dialog ai-dlg" role="dialog" aria-label="New Mac app icon">
    <h2>New Mac app icon</h2>
    <p>This is how it will look in the Dock on every Mac.</p>
    <div class="ai-prev">
      <div class="ai-dockbar dark"><span class="ai-other"></span><img alt="New icon, dark Dock"><span class="ai-other"></span></div>
      <div class="ai-dockbar light"><span class="ai-other"></span><img alt="New icon, light Dock"><span class="ai-other"></span></div>
    </div>
    ${squareNote}
    <div class="pf-opt ai-round"><div><b>Mac-style rounded corners</b><span>Turn off if your image already has the Mac shape and its own padding</span></div><button class="switch on" data-r="round" aria-label="Rounded corners"><i></i></button></div>
    <div class="pf-opt ai-glass"><div><b>Glass edge</b><span>The bright rim and sheen of updated Mac apps, painted into the icon</span></div><button class="switch on" data-r="glass" aria-label="Glass edge"><i></i></button></div>
    <div class="actions"><button class="btn" data-r="0">Cancel</button><button class="btn primary" data-r="1">Use this icon for everyone</button></div>
  </div></div>`;
  draw();
  const done = () => { root.innerHTML = ''; document.removeEventListener('keydown', onKey, true); };
  const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); done(); } };
  document.addEventListener('keydown', onKey, true);
  $('.scrim', root).addEventListener('click', async (e) => {
    if (e.target.classList.contains('scrim')) return done();
    const b = e.target.closest('[data-r]'); if (!b) return;
    if (b.dataset.r === 'round') { rounded = !rounded; draw(); return; }
    if (b.dataset.r === 'glass') { glass = !glass; draw(); return; }
    if (b.dataset.r === '0') return done();
    b.disabled = true; b.textContent = 'Uploading…';
    try {
      const out = await new Promise((res) => renderIcon(im, rounded, rounded && glass).toBlob(res, 'image/png'));
      const r = await api('POST', '/api/app-icon', { png: await AppIcon.toB64(out) });
      done();
      AppIcon.sync(r);
      toast('New icon set — every open Mac app updates now');
      renderContent();
    } catch (err) { b.disabled = false; b.textContent = 'Use this icon for everyone'; toast('Couldn’t change the icon: ' + err.message); }
  });
}
async function appIconResetFlow() {
  const ok = await dialog({ title: 'Go back to the default icon?', body: 'Every Mac app goes back to the icon it was installed with.', okText: 'Reset icon' });
  if (!ok) return;
  try { const r = await api('POST', '/api/app-icon/reset', {}); AppIcon.sync(r); toast('Back to the default icon'); renderContent(); } catch (e) { toast('Couldn’t reset the icon: ' + e.message); }
}
function notifToggles(u, cdOnly) {
  const off = (u.prefs || {}).notifOff || {};
  return NOTIF_TYPES.filter((x) => !!x.cd === cdOnly).map((x) => `<div class="pf-opt nt-opt"><div><b>${esc(x.l)}</b><span>${esc(x.d)}</span></div><button class="switch ${off[x.k] ? '' : 'on'}" data-action="toggle-notif-type" data-k="${x.k}" title="${off[x.k] ? 'Off' : 'On'}"><i></i></button></div>`).join('');
}
async function pickAvatar() {
  if (!Host.isNative) { toast('Photos can be added in the Mac app'); return null; }
  try { const r = await Host.call('pickImage', { userId: currentUserId }); return r.path || null; }
  catch (e) { toast('Could not use that photo: ' + e.message); return null; }
}
async function changePhoto() {
  const path = await pickAvatar();
  if (!path) return;
  const u = me();
  if (u.avatar) Host.call('trashPath', { path: u.avatar }).catch(() => {});
  u.avatar = path; persist(0); render();
}
function saveProfile() {
  const u = me();
  const name = ($('#pf-name').value || '').trim();
  if (!name) { toast('Please enter your name'); return; }
  u.name = name;
  u.office = (($('#pf-office') || {}).value || '').trim();
  persist(0); render(); toast('Profile saved');
}
async function changePasswordFlow() {
  const u = me();
  const v = await formDialog({ title: 'Change password', okText: 'Change password', fields: [
    { key: 'cur', label: 'Current password', type: 'password' },
    { key: 'pw', label: 'New password', type: 'password', hint: 'At least 8 characters' },
    { key: 'pw2', label: 'Confirm new password', type: 'password' },
  ], validate: (x) => (!checkPassword(u, x.cur) ? 'Current password is incorrect' : pwProblem(x.pw, x.pw2, x.cur)) });
  if (!v) return;
  setPassword(u, v.pw); persist(0); toast('Password changed');
}
function pwProblem(pw, pw2, old) {
  if (pw.length < 8) return 'Use at least 8 characters for your new password';
  if (pw !== pw2) return 'The two passwords don’t match';
  if (old && pw === old) return 'Choose a password different from the temporary one';
  return null;
}

/* ---- Sidebar: signed-in person ---- */
function renderMeChip() {
  const el = $('#me-chip');
  const u = me();
  if (!el || !u) return;
  el.innerHTML = `${avatarHTML(u.id, 28)}<span class="me-txt"><b>${esc(fullName(u))}</b><small>${esc(ROLES[u.role])}</small></span>${icon('chev')}`;
}
function meMenu(anchor) {
  if (isFinUser()) return Fin.meMenu(anchor, typeof ViewAs !== 'undefined' && ViewAs.viewing() ? [{ label: 'Back to me', icon: 'reply', run: ViewAs.back }] : []);
  showMenu(anchor, [
    { label: 'My profile', icon: 'user', run: () => go('profile') },
    ...(Host.isServer ? [{ label: 'My reimbursements', icon: 'coin', run: () => go('claims') }] : []),
    { label: 'Team members', icon: 'users', run: () => go('team') },
    ...(isAdm(me()) ? [{ label: 'Edit client list', icon: 'folder', run: () => go('clientlist') }] : []),
    ...(Host.isServer && isAdm(me()) ? [{ label: 'App updates', icon: 'download', run: () => go('updates') }] : []),
    ...(Host.isServer ? [{ label: 'What’s new', icon: 'info', run: () => whatsNewDialog(false) }] : []),
    ...(Host.isServer && !Host.isMacApp ? [{ label: 'Get the Mac app', icon: 'download', run: macAppDialog }] : []),
    ...(Host.isMacApp ? [{ label: 'Update Mac app', icon: 'download', run: () => MacUpdate.run() }] : []),
    ...(isTestCopy() && isAdm(me()) ? [{ label: 'Fill with sample data', icon: 'users', run: fillSampleData }] : []),
    ...(typeof ViewAs !== 'undefined' && ViewAs.available() ? [{ label: ViewAs.viewing() ? 'View as someone else…' : 'View as… (test site)', icon: 'users', run: ViewAs.pick }, ...(ViewAs.viewing() ? [{ label: 'Back to me', icon: 'reply', run: ViewAs.back }] : [])] : []),
    ...Fin.addItems(),
    '-',
    { label: 'Sign out', icon: 'logout', run: signOut },
  ]);
}

/* ================= Sign in & first-time setup ================= */
function authShell(inner) {
  const root = $('#auth');
  root.innerHTML = `<div class="auth-bg"><div class="sp-orb sp-orb1"></div><div class="sp-orb sp-orb2"></div></div><div class="auth-card">${inner}</div><div class="auth-foot">© ${new Date().getFullYear()} E11 Agency</div>`;
  root.classList.add('on');
  document.getElementById('app').classList.add('locked');
  return root;
}
function showLogin(prefillEmail = '') {
  const root = authShell(`
    <img class="auth-logo" src="logo-wordmark.png" alt="E11 Console">
    <h1>Sign in</h1>
    <p class="auth-sub">Use the email and password your admin gave you.</p>
    <form id="login-form" autocomplete="on">
      <label class="dlg-label">Email</label>
      <input class="field" name="email" type="email" value="${esc(prefillEmail)}" placeholder="name@e11-digital.com" autocomplete="username">
      <label class="dlg-label">Password</label>
      <div class="pw-wrap"><input class="field" name="pw" type="password" placeholder="Password" autocomplete="current-password"><button type="button" class="pw-eye" tabindex="-1">Show</button></div>
      <div class="dlg-err"></div>
      <button class="btn primary auth-go" type="submit">Sign in</button>
    </form>
    <p class="auth-help">No account? Ask an Admin to add you — there’s no sign-up.</p>`);
  wirePwEyes(root);
  const form = $('#login-form');
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const email = form.elements.email.value.trim().toLowerCase(), pw = form.elements.pw.value;
    const u = db.users.find((x) => x.email.toLowerCase() === email && x.active !== false);
    if (!u || !checkPassword(u, pw)) {
      $('.dlg-err', root).textContent = 'That email and password don’t match. Try again.';
      $('.auth-card').classList.remove('shake'); void $('.auth-card').offsetWidth; $('.auth-card').classList.add('shake');
      return;
    }
    currentUserId = u.id;
    u.lastLoginAt = nowISO();
    if (!u.setup) { showWelcome(pw); return; }
    savePref('session', u.id);
    enterApp();
  });
  setTimeout(() => form.elements[prefillEmail ? 'pw' : 'email'].focus(), 50);
}
function wirePwEyes(root) {
  $$('.pw-eye', root).forEach((b) => b.addEventListener('click', () => { const i = b.previousElementSibling; i.type = i.type === 'password' ? 'text' : 'password'; b.textContent = i.type === 'password' ? 'Show' : 'Hide'; }));
}
function showWelcome(tempPw) {
  const u = me();
  let photo = u.avatar;
  const root = authShell(`
    <div class="wl-confetti">${Array.from({ length: 18 }, (_, i) => `<i style="--i:${i}"></i>`).join('')}</div>
    <div class="wl-badge">${icon('users')}</div>
    <h1 class="wl-title">Welcome to the team</h1>
    <p class="auth-sub">Let’s set up your account. This only takes a minute.</p>
    <form id="welcome-form" autocomplete="off">
      <div class="wl-photo"><button type="button" class="wl-av" id="wl-av" title="Add a profile photo">${avatarHTML(u.id, 84)}<span class="wl-cam">${icon('camera')}</span></button><span class="wl-photo-txt">Add a profile photo<small>Optional · click the circle</small></span></div>
      <label class="dlg-label">Full name</label>
      <input class="field" name="name" value="${esc(u.name || '')}" placeholder="Your full name">
      <label class="dlg-label">Email</label>
      <div class="field ro">${icon('lock')}${esc(u.email)}</div>
      ${Host.isServer ? '' : `<label class="dlg-label">New password</label>
      <div class="pw-wrap"><input class="field" name="pw" type="password" placeholder="At least 8 characters" autocomplete="new-password"><button type="button" class="pw-eye" tabindex="-1">Show</button></div>
      <label class="dlg-label">Confirm new password</label>
      <div class="pw-wrap"><input class="field" name="pw2" type="password" placeholder="Type it again" autocomplete="new-password"><button type="button" class="pw-eye" tabindex="-1">Show</button></div>`}
      <div class="dlg-err"></div>
      <button class="btn primary auth-go" type="submit">Get started</button>
      <button class="btn ghost auth-back" type="button" id="wl-back">Use a different account</button>
    </form>`);
  root.querySelector('.auth-card').classList.add('welcome');
  wirePwEyes(root);
  $('#wl-av').addEventListener('click', async () => {
    const path = await pickAvatar();
    if (!path) return;
    if (photo && photo !== u.avatar) Host.call('trashPath', { path: photo }).catch(() => {});
    photo = path;
    const keep = u.avatar; u.avatar = photo;
    $('#wl-av').innerHTML = `${avatarHTML(u.id, 84)}<span class="wl-cam">${icon('camera')}</span>`;
    u.avatar = keep;
  });
  $('#wl-back').addEventListener('click', () => { if (Host.isServer) { location.href = '/cdn-cgi/access/logout'; return; } currentUserId = null; showLogin(); });
  const form = $('#welcome-form');
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const name = form.elements.name.value.trim();
    if (!name) { $('.dlg-err', root).textContent = 'Please enter your full name'; return; }
    const problem = Host.isServer ? null : pwProblem(form.elements.pw.value, form.elements.pw2.value, tempPw);
    if (problem) { $('.dlg-err', root).textContent = problem; return; }
    u.name = name;
    if (photo && photo !== u.avatar) { if (u.avatar) Host.call('trashPath', { path: u.avatar }).catch(() => {}); u.avatar = photo; }
    if (!Host.isServer) setPassword(u, form.elements.pw.value);
    u.setup = true;
    u.setupAt = nowISO();
    savePref('session', u.id);
    persist(0);
    enterApp();
    setTimeout(() => toast(`Welcome aboard, ${name.split(' ')[0]}! 🎉`), 400);
  });
  setTimeout(() => form.elements.name.focus(), 50);
}
function enterApp() {
  const root = $('#auth');
  root.classList.add('leaving');
  document.getElementById('app').classList.remove('locked');
  setTimeout(() => { root.classList.remove('on', 'leaving'); root.innerHTML = ''; }, 450);
  ui.view = isFinUser() ? 'fin-dash' : 'home'; ui.taskId = null; ui.search = '';
  if (typeof Phone !== 'undefined' && Phone.check) Phone.check();
  Fin.init();
  initSidebar();
  render();
  purgeOldCompleted();
  Draft.sweep();
  setTimeout(() => { Announce.check(); Claims.tick(); Fin.invoiceTick(); }, 2500);
  setTimeout(deliverPending, 900);
}
// The test copy (test.e11hq.com) can be filled with sample people, tasks and comments
const isTestCopy = () => Host.isServer && /-test\./.test(String(Sync.version || ''));
async function fillSampleData() {
  const ok = await dialog({ title: 'Fill the test copy with sample data?', body: 'Adds E11 people, clients, tasks, comments with replies and Inbox updates, dated around today. Only on the test copy — the live app is never touched. You can run it again any time.', okText: 'Add sample data' });
  if (!ok) return;
  try {
    const r = await api('POST', '/api/sample', {});
    toast(`Added ${r.tasks} tasks and ${r.people} people — they appear in a moment`);
  } catch (e) { toast('Could not add sample data: ' + e.message); }
}
function signOut() {
  flushEdit();
  if (Host.isServer) { Sync.push(); setTimeout(() => { location.href = '/cdn-cgi/access/logout'; }, 300); return; }
  const email = me() ? me().email : '';
  savePref('session', null);
  currentUserId = null;
  const nr = $('#notif-root'); if (nr) nr.innerHTML = '';
  ui.taskId = null;
  renderDetail();
  $('#content').innerHTML = '';
  persist(0);
  showLogin(email);
}

/* ================= @mentions in comments and the description ================= */
const Mention = { el: null, editor: null, items: [], idx: 0, range: null };
function mentionQuery() {
  const sel = window.getSelection();
  if (!sel.rangeCount || !sel.isCollapsed) return null;
  const r = sel.getRangeAt(0);
  const node = r.startContainer;
  if (node.nodeType !== 3) return null;
  const before = node.nodeValue.slice(0, r.startOffset);
  const m = before.match(/(?:^|[\s (])@([^\s@]{0,30})$/);
  if (!m) return null;
  return { node, end: r.startOffset, start: r.startOffset - m[1].length - 1, q: m[1].toLowerCase() };
}
function closeMention() { if (Mention.el) Mention.el.remove(); Mention.el = null; Mention.editor = null; }
function updateMention(editor) {
  const q = mentionQuery();
  if (!q) return closeMention();
  const list = activeUsers().filter((u) => fullName(u).toLowerCase().includes(q.q) || u.email.toLowerCase().includes(q.q)).slice(0, 8);
  if (!list.length) return closeMention();
  Mention.editor = editor; Mention.items = list; Mention.q = q;
  if (Mention.idx >= list.length) Mention.idx = 0;
  if (!Mention.el) { Mention.el = document.createElement('div'); Mention.el.className = 'menu mention-pop'; document.body.appendChild(Mention.el); Mention.idx = 0; }
  Mention.el.innerHTML = `<div class="menu-label">Mention someone</div>` + list.map((u, i) => `<div class="mi asg-mi ${i === Mention.idx ? 'hl' : ''}" data-mention="${u.id}">${avatarHTML(u.id, 22)}<span class="asg-n">${esc(fullName(u))}<small>${esc(u.email)}</small></span></div>`).join('');
  const rr = document.createRange(); rr.setStart(q.node, q.start); rr.setEnd(q.node, q.end);
  const rect = rr.getBoundingClientRect();
  const h = Mention.el.offsetHeight, w = Mention.el.offsetWidth;
  let y = rect.bottom + 6; if (y + h > innerHeight - 8) y = rect.top - h - 6;
  Mention.el.style.left = Math.max(8, Math.min(rect.left, innerWidth - w - 8)) + 'px';
  Mention.el.style.top = Math.max(8, y) + 'px';
}
function pickMention(userId) {
  const q = Mention.q, ed = Mention.editor;
  const u = userById(userId);
  closeMention();
  if (!q || !ed || !u) return;
  ed.focus();
  const r = document.createRange(); r.setStart(q.node, q.start); r.setEnd(q.node, q.end);
  const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
  document.execCommand('insertHTML', false, `<span class="mention" data-user="${esc(u.id)}" contenteditable="false">@${esc(fullName(u))}</span>&nbsp;`);
  ed.dispatchEvent(new Event('input', { bubbles: true }));
}
document.addEventListener('input', (e) => { const ed = e.target.closest && e.target.closest('.rt-editor'); if (ed && currentUserId) updateMention(ed); else closeMention(); });
document.addEventListener('keydown', (e) => {
  if (!Mention.el) return;
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); e.stopPropagation(); Mention.idx = (Mention.idx + (e.key === 'ArrowDown' ? 1 : -1) + Mention.items.length) % Mention.items.length; updateMention(Mention.editor); }
  else if ((e.key === 'Enter' || e.key === 'Tab') && !e.metaKey && !e.ctrlKey) { e.preventDefault(); e.stopPropagation(); pickMention(Mention.items[Mention.idx].id); }
  else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeMention(); }
}, true);
document.addEventListener('mousedown', (e) => {
  const it = e.target.closest && e.target.closest('[data-mention]');
  if (it) { e.preventDefault(); pickMention(it.dataset.mention); return; }
  if (Mention.el && !e.target.closest('.mention-pop')) closeMention();
}, true);
document.addEventListener('focusout', (e) => { if (Mention.editor && e.target === Mention.editor) setTimeout(() => { if (document.activeElement !== Mention.editor) closeMention(); }, 150); });

/* ================= Tooltips (replace the slow native ones) ================= */
const Tip = { el: null, target: null, timer: null };
function tipHide() { clearTimeout(Tip.timer); Tip.target = null; if (Tip.el) Tip.el.classList.remove('on'); }
function tipShow(t) {
  const raw = t.dataset.tip || '';
  if (!raw || !document.body.contains(t)) return;
  const m = raw.match(/^(.*?)\s*\((⌘[^)]{1,8}|⇧[^)]{1,8}|Esc|Enter|⌘ Enter)\)$/);
  const text = m ? m[1] : raw, key = m ? m[2] : '';
  if (!Tip.el) { Tip.el = document.createElement('div'); Tip.el.className = 'tip'; document.body.appendChild(Tip.el); }
  Tip.el.innerHTML = `<span>${esc(text)}</span>${key ? `<kbd>${esc(key)}</kbd>` : ''}`;
  const r = t.getBoundingClientRect();
  const el = Tip.el;
  el.className = 'tip';
  const left = r.right > innerWidth - 140 || t.closest('.tm-rail');
  el.style.left = '0px'; el.style.top = '0px';
  const w = el.offsetWidth, h = el.offsetHeight;
  let x, y;
  if (left) { x = r.left - w - 10; y = r.top + r.height / 2 - h / 2; el.classList.add('left'); }
  else { x = r.left + r.width / 2 - w / 2; y = r.bottom + 8; el.classList.add('below'); if (y + h > innerHeight - 6) { y = r.top - h - 8; el.classList.replace('below', 'above'); } }
  el.style.left = Math.max(6, Math.min(x, innerWidth - w - 6)) + 'px';
  el.style.top = Math.max(6, y) + 'px';
  el.style.setProperty('--ax', (r.left + r.width / 2 - Math.max(6, Math.min(x, innerWidth - w - 6))) + 'px');
  requestAnimationFrame(() => el.classList.add('on'));
}
document.addEventListener('mouseover', (e) => {
  const t = e.target.closest && e.target.closest('[title], [data-tip]');
  if (!t || t === Tip.target) return;
  if (t.hasAttribute('title')) { const v = t.getAttribute('title'); t.removeAttribute('title'); if (!v) return; t.dataset.tip = v; }
  tipHide();
  Tip.target = t;
  Tip.timer = setTimeout(() => { if (Tip.target === t) tipShow(t); }, 380);
});
document.addEventListener('mouseout', (e) => { if (Tip.target && (!e.relatedTarget || !Tip.target.contains(e.relatedTarget))) tipHide(); });
document.addEventListener('mousedown', tipHide, true);
document.addEventListener('scroll', tipHide, true);
document.addEventListener('keydown', tipHide, true);

/* ================= Boot ================= */
// ---------- Startup screen ----------
// Startup screen: shows a checklist of what the app is loading, ticked off with real numbers.
// The look (light/dark) and the first name come from this device's last session, so it's right from the first frame.
const SPLASH_MIN = 3000;   // the icon assembles (~2 s), then the checklist ticks
const SPLASH_ICON = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 300 : 2150;
const Splash = (() => {
  const el = document.getElementById('splash');
  let start = performance.now(), gone = false, skipResolve = null;
  const skipped = new Promise((r) => { skipResolve = r; });
  const TICK = '<svg viewBox="0 0 16 16" fill="none" stroke="#0c0d0f" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m3.5 8.5 3 3 6-7"/></svg>';
  const remembered = () => { try { return JSON.parse(localStorage.getItem('e11-splash') || '{}') || {}; } catch (e) { return {}; } };
  function greeting(name) {
    const h = new Date().getHours();
    const part = Occasions.greeting(todayStr()) || (h < 5 ? 'Working late' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening');
    return name && !Occasions.alone(part) ? `${part}, ${name}` : part;
  }
  let rows = [];
  function init() {
    if (!el) return;
    const mem = remembered();
    const light = (mem.themeMode === 'light' || mem.themeMode === 'dark' ? mem.themeMode : sunTheme()) === 'light';
    el.classList.toggle('light', light);
    // the page behind the startup screen matches it, so no dark edges show around it on the iPhone
    document.documentElement.style.backgroundColor = light ? '#ffffff' : '#0c0d0f';
    // the iPhone paints anything outside the page (e.g. under a startup screen that comes up short) in the theme colour
    const tc = document.querySelector('meta[name="theme-color"]'); if (tc) tc.content = light ? '#ffffff' : '#0c0d0f';
    document.getElementById('sp-greet').textContent = greeting(mem.name);
    document.getElementById('sp-date').textContent = new Date().toLocaleDateString(undefined, { weekday: 'long', month: window.innerWidth <= 760 ? 'short' : 'long', day: 'numeric' });
    document.getElementById('sp-hint').textContent = window.innerWidth <= 760 ? 'Tap to skip' : 'Click or press any key to skip';
    const labels = ['Clients', 'Your tasks', 'Inbox', mem.cd ? 'Review requests' : 'Client Assets'];
    document.getElementById('sp-rows').innerHTML = labels.map((l) => `<div class="sp-row"><span class="sp-box">${TICK}</span><span class="sp-lbl">${l}</span><span class="sp-val">…</span></div>`).join('');
    rows = $$('.sp-row', el);
    const skip = () => skipResolve();
    el.addEventListener('click', skip);
    window.addEventListener('keydown', function k() { if (!gone) skip(); window.removeEventListener('keydown', k); });
  }
  // Remember the look and name for the next startup on this device
  function remember(extra) { try { localStorage.setItem('e11-splash', JSON.stringify({ ...remembered(), ...extra })); } catch (e) { /* storage off */ } }
  function values() {
    if (!db || !currentUserId) return null;
    const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
    const D = Work.day();
    const open = D.tasks.filter(D.open).length;
    const today = D.tasks.filter((t) => D.open(t) && t.due && dayDiff(t.due) === 0).length;
    const unread = myNotifs().filter((n) => !n.read).length;
    const cd = isCD();
    const fourth = cd ? (activeReviews().length ? `${activeReviews().length} waiting` : 'none waiting') : plural((db.clients || []).length, 'client', 'clients');
    return {
      cd,
      list: [`${(db.projects || []).filter((p) => !p.archived).length} synced`, `${open} open · ${today} today`, unread ? `${unread > 99 ? '99+' : unread} new` : 'all read', fourth],
      label4: cd ? 'Review requests' : 'Client Assets',
    };
  }
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  // Data is in: tick the rows one by one, then fade into the app
  async function finish() {
    if (!el || gone) return;
    const v = values();
    const bar = el.querySelector('.sp-bar i'), n = document.getElementById('sp-n');
    if (v) {
      const u = me();
      remember({ name: u ? firstName(u.id) : '', cd: v.cd });
      // let the icon finish assembling and the checklist appear before it starts ticking
      await Promise.race([wait(Math.max(0, SPLASH_ICON - (performance.now() - start))), skipped]);
      document.getElementById('sp-greet').textContent = greeting(u ? firstName(u.id) : '');
      rows[3].querySelector('.sp-lbl').textContent = v.label4;
      const fast = await Promise.race([wait(0).then(() => false), skipped.then(() => true)]);
      for (let i = 0; i < rows.length && !fast; i++) {
        const r = await Promise.race([wait(i ? 220 : 120).then(() => false), skipped.then(() => true)]);
        if (r) break;
        rows.forEach((x) => x.classList.remove('now'));
        rows[i].classList.add('done', 'now');
        rows[i].querySelector('.sp-val').textContent = v.list[i];
        n.textContent = `${i + 1}/${rows.length}`;
        bar.style.width = ((i + 1) / rows.length * 100) + '%';
      }
      await Promise.race([wait(Math.max(420, SPLASH_MIN - (performance.now() - start))), skipped]);
    }
    gone = true;
    el.classList.add('out');
    document.getElementById('app').classList.add('enter');
    setTimeout(() => { el.remove(); document.documentElement.style.backgroundColor = ''; document.getElementById('app').classList.remove('enter'); }, 500);
  }
  init();
  return { finish, remember };
})();

async function boot() {
  hydrateIcons();
  try { await bootInner(); } finally { Splash.finish(); }
}
async function bootInner() {
  if (Host.isServer) return bootServer();
  let res;
  try {
    res = await Host.call('load');
  } catch (err) {
    return fatal('E11 Console could not open its data folder.', err.message);
  }
  dataDir = res.dataDir || '';
  if (res.data) {
    try { db = normalize(JSON.parse(res.data)); }
    catch (err) {
      readOnly = true;
      return fatal('Your data file could not be read.', 'Nothing has been changed. Check the “backups” folder inside “E11 Console Data” on your Desktop — copy the newest backup over e11-data.json, then reopen the app.');
    }
  } else {
    db = normalize({});
    seed();
    persist(0);
  }
  setSaveState('saved');
  applyThemePref();
  // Signed in before on this Mac? Go straight in; otherwise show the sign-in screen
  const sess = db.meta.prefs && db.meta.prefs.session;
  const su = sess && userById(sess);
  if (su && su.active !== false && su.setup) { currentUserId = su.id; enterApp(); }
  else showLogin();
  setInterval(() => { if (currentUserId) { deliverPending(); renderSidebar(); Announce.check(); Claims.tick(); Fin.invoiceTick(); } }, 30000);
  // Tidy attachment folders left behind (e.g. app quit right after deleting a task)
  if (Host.isNative) {
    const attIds = db.tasks.flatMap((t) => t.attachments.concat(...t.comments.map((c) => c.attachments || [])).map((a) => a.id))
      .concat((db.clients || []).flatMap((c) => c.folders.flatMap((f) => f.files.map((a) => a.id))));
    setTimeout(() => Host.call('sweepOrphans', { taskIds: db.tasks.map((t) => t.id).concat('_avatars'), attIds }).catch(() => {}), 4000);
  }
  // Refresh relative dates when the day changes; daily clean-up
  let day = todayStr();
  setInterval(() => { if (todayStr() !== day) { day = todayStr(); if (currentUserId) { purgeOldCompleted(); render({ keepDetail: true }); } } }, 60000);
}

// On the server: sign-in is done by Cloudflare, data comes from the office server
async function bootServer() {
  let me;
  try { me = await Sync.start(); }
  catch (err) {
    if (err.auth) { document.body.innerHTML = `<div class="fatal" style="margin:20vh auto;max-width:440px;text-align:center"><h2>No access yet</h2><p>${esc(err.message)}</p></div>`; return; }
    return fatal('Can’t reach the office server.', err.message + ' — check your internet connection and reload.');
  }
  setSaveState('saved');
  applyThemePref();
  currentUserId = me.id;
  const u = me && userById(me.id);
  if (u && !u.setup) showWelcome(null); else { enterApp(); maybeShowWhatsNew(); }
  if (u) { u.lastLoginAt = nowISO(); persist(2000); }
  setInterval(() => { if (currentUserId) { deliverPending(); renderSidebar(); Announce.check(); Claims.tick(); Fin.invoiceTick(); } }, 30000);
  Digest.start();
  OccRemind.start();
  let day = todayStr();
  setInterval(() => { if (todayStr() !== day) { day = todayStr(); if (currentUserId) { purgeOldCompleted(); render({ keepDetail: true }); } } }, 60000);
}

// Preferences live in the data file (E11 Console Data), so they survive restarts and reinstalls.
// On the server they are kept per person on this device instead of being shared with the team.
function savePref(key, value) {
  if (!db) return;
  db.meta.prefs = db.meta.prefs || {};
  if (db.meta.prefs[key] === value) return;
  db.meta.prefs[key] = value;
  if (Host.isServer) { Sync.savePrefs(); return; }
  persist();
}
function setTheme(mode) {
  document.documentElement.dataset.theme = mode;
  // (the iPhone status-bar style is fixed in index.html: changing it while open makes iOS resize the page)
  const tc = document.querySelector('meta[name="theme-color"]');
  if (tc) tc.content = mode === 'light' ? '#f7f7f8' : '#0c0d0f';
  paintThemeButtons();
  savePref('theme', mode);
  Splash.remember({ theme: mode });
  Host.call('setAppearance', { mode }).catch(() => {});
}
// The sun/moon button shows the current appearance: sun = light, moon = dark, half circle = Automatic
function paintThemeButtons() {
  const light = document.documentElement.dataset.theme === 'light';
  const pm = ((typeof db !== 'undefined' && db && db.meta && db.meta.prefs) || {}).themeMode;
  const auto = pm !== 'light' && pm !== 'dark';
  const title = `${auto ? `Automatic — ${light ? 'light' : 'dark'} now` : light ? 'Light mode' : 'Dark mode'}. Click for ${light ? 'dark' : 'light'} mode`;
  document.querySelectorAll('.theme-toggle').forEach((b) => { b.innerHTML = icon(auto ? 'theme-auto' : light ? 'sun' : 'moon'); b.title = title; b.setAttribute('aria-label', title); });
}
function setSidebarCollapsed(on) {
  document.getElementById('app').classList.toggle('sb-collapsed', on);
  document.querySelectorAll('.sb-toggle').forEach((b) => { b.title = on ? 'Expand sidebar' : 'Collapse sidebar'; });
  savePref('sidebarCollapsed', on);
}
/* ---------- Light / dark: Automatic (default) follows sunrise and sunset in Dubai; anyone can pick
   Light or Dark instead (My profile → Appearance, the phone's Me tab, or the sun/moon button). ---------- */
// Sunrise / sunset at the E11 office in Dubai (the standard "sunrise equation", accurate to a minute or two).
// A plain function so the startup screen can use it before everything else has loaded.
function sunTimesDubai(d) {
  const LAT = 25.2048, LNG = 55.2708, rad = Math.PI / 180;
  const J0 = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), 12) / 86400000 + 2440587.5;
  const Js = Math.round(J0 - 2451545.0 + 0.0008) - LNG / 360;
  const M = (357.5291 + 0.98560028 * Js) % 360;
  const C = 1.9148 * Math.sin(M * rad) + 0.02 * Math.sin(2 * M * rad) + 0.0003 * Math.sin(3 * M * rad);
  const L = (M + C + 180 + 102.9372) % 360;
  const Jt = 2451545.0 + Js + 0.0053 * Math.sin(M * rad) - 0.0069 * Math.sin(2 * L * rad);
  const dec = Math.asin(Math.sin(L * rad) * Math.sin(23.4397 * rad));
  const w = Math.acos((Math.sin(-0.833 * rad) - Math.sin(LAT * rad) * Math.sin(dec)) / (Math.cos(LAT * rad) * Math.cos(dec))) / rad;
  const at = (j) => new Date((j - 2440587.5) * 86400000);
  return { rise: at(Jt - w / 360), set: at(Jt + w / 360) };
}
function sunTheme(now = new Date()) { const t = sunTimesDubai(now); return now >= t.rise && now < t.set ? 'light' : 'dark'; }
const Theme = (() => {
  const sun = sunTimesDubai;
  const autoTheme = (now = new Date()) => { const t = sun(now); return now >= t.rise && now < t.set ? 'light' : 'dark'; };
  const mode = () => { const m = ((db && db.meta.prefs) || {}).themeMode; return m === 'light' || m === 'dark' ? m : 'auto'; };
  const apply = () => setTheme(mode() === 'auto' ? autoTheme() : mode());
  function setMode(m) { const v = m === 'light' || m === 'dark' ? m : 'auto'; savePref('themeMode', v); Splash.remember({ themeMode: v }); apply(); }
  setInterval(() => { if (db && currentUserId && mode() === 'auto') apply(); }, 60000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden && db && currentUserId && mode() === 'auto') apply(); });
  const times = () => { const t = sun(new Date()); const f = (d) => d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }); return `light from ${f(t.rise)}, dark from ${f(t.set)}`; };
  const LABELS = { auto: 'Automatic', light: 'Light', dark: 'Dark' };
  const picker = (cls = '') => `<div class="seg theme-seg ${cls}">${Object.entries(LABELS).map(([k, l]) => `<button class="${mode() === k ? 'on' : ''}" data-action="theme-mode" data-mode="${k}">${l}</button>`).join('')}</div>`;
  // Desktop: three little window previews to pick from
  const mini = (t) => `<span class="tp-win tp-${t}"><span class="tp-side"><i class="a"></i><i></i><i></i></span><span class="tp-main"><i class="tp-l1"></i><i class="tp-l2"></i><i class="tp-pill"></i><i class="tp-dot"></i><i class="tp-l3"></i><i class="tp-l4"></i><i class="tp-sq"></i></span></span>`;
  const cards = () => `<div class="tp-cards">${[['light', 'Light'], ['dark', 'Dark'], ['auto', 'Auto']].map(([k, l]) => `<button class="tp-card ${mode() === k ? 'on' : ''}" data-action="theme-mode" data-mode="${k}" title="${k === 'auto' ? 'Light from sunrise, dark from sunset (Dubai)' : l + ' all the time'}"><span class="tp-frame">${k === 'auto' ? `<span class="tp-split">${mini('light')}${mini('dark')}</span>` : mini(k)}</span><span class="tp-l">${l}</span></button>`).join('')}</div>`;
  return { apply, setMode, mode, autoTheme, sun, times, picker, cards };
})();
function applyThemePref() { Theme.apply(); }
function initSidebar() {
  const y = $('#copy-year');
  if (y) y.textContent = String(new Date().getFullYear());
  const prefs = (db.meta.prefs = db.meta.prefs || {});
  // one-time move of older settings kept in browser storage
  try {
    if (prefs.theme == null && localStorage.getItem('e11-theme')) prefs.theme = localStorage.getItem('e11-theme');
    if (prefs.sidebarCollapsed == null && localStorage.getItem('e11-sidebar-collapsed')) prefs.sidebarCollapsed = localStorage.getItem('e11-sidebar-collapsed') === '1';
    if (prefs.detailMode == null && localStorage.getItem('e11-detail-mode')) prefs.detailMode = localStorage.getItem('e11-detail-mode');
  } catch (e) { /* ignore */ }
  const on = !!prefs.sidebarCollapsed;
  setSidebarCollapsed(on);
  Theme.apply();
  ui.detailMode = ['side', 'full'].includes(prefs.detailMode) ? prefs.detailMode : 'modal';
}

function fatal(title, detail) {
  $('#content').innerHTML = `<div class="fatal"><h2>${esc(title)}</h2><p>${esc(detail || '')}</p>${Host.isServer ? '<button class="btn" onclick="location.reload()">Try again</button>' : `<button class="btn" onclick="Host.call('revealData')">Show data folder</button>`}</div>`;
  setSaveState('error', 'data unavailable');
}

boot();
