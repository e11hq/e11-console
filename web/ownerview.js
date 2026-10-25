/* ================= Owner view (LIVE SITE ONLY) =================
   The owner can use the app day to day with another role (e.g. Production) and quietly step in with Admin rights from
   the last card on My profile. Nobody else sees it: their role stays as it is for everyone, nothing is announced, and it
   only applies on this device. It starts LOOK ONLY (the server refuses every change and the app puts back anything that
   was changed) until "Allow changes". It ends with "Back to Production", after 15 minutes without use, and on every
   reload. Never offered on the test site (the server refuses it there). Keep this on the live site in future updates. */
const OwnerView = (() => {
  const IDLE = 15 * 60000;
  let can = false, mode = null, last = Date.now(), lastPing = 0, warned = 0;
  const on = () => !!mode;
  const lookOnly = () => mode === 'look';
  function init(meInfo) {
    can = !!(meInfo && meInfo.canOwnerView);
    mode = (meInfo && meInfo.ownerView) || null;
    paint();
  }
  async function set(next) {
    if (next === mode) return;
    const was = mode;
    try { if (was !== 'look') await Sync.push(); } catch (e) { /* offline: fine */ }
    let r;
    try { r = await api('POST', '/api/owner-view', { mode: next || 'off' }); } catch (e) { toast(e.message || 'Could not switch'); return; }
    mode = r.mode || null;
    last = Date.now();
    // stepping in or out changes what this device may see: reconnect and reload the data
    if (!was !== !mode) { Sync.reconnect(0); await Sync.resync(); if (typeof Fin !== 'undefined') Fin.init(); renderSidebar(); }
    paint(); render();
    toast(!mode ? 'Back to Production' : mode === 'look' ? (was ? 'Look only — nothing you do is saved' : 'Owner view: look only') : 'Changes allowed — they show under your name');
  }
  async function allowChanges() {
    const ok = await dialog({ title: 'Allow changes?', body: 'What you change from now on is saved and shows under your name, and the usual notifications go out — just as if an Admin did it. Your role stays as it is.', okText: 'Allow changes' });
    if (ok) set('edit');
  }
  // the app tried to save something while looking: put it back (the server would refuse it anyway)
  function blocked() {
    if (Date.now() - warned > 4000) { warned = Date.now(); toast('Owner view is look only — choose Allow changes to change anything'); }
  }
  function card() {
    if (!can) return '';
    return `<div class="pf-card ov-card">
      <h3>${icon('shield')}Owner view</h3>
      <p class="pf-note">${on()
        ? `You’re in Owner view on this device${lookOnly() ? ', <b>look only</b>' : ', with <b>changes allowed</b>'}. It ends after 15 minutes without use, or when the app reloads.`
        : 'Step in with Admin rights and Finance Admin on this device only. Nobody is told and your role stays the same for everyone. It starts look only — nothing can be changed until you choose Allow changes. It ends after 15 minutes without use, or when the app reloads.'}</p>
      <div class="pf-actions">${on() ? '<button class="btn" data-ov="off">Back to Production</button>' : '<button class="btn" data-ov="look">Step in as Admin (look only)</button>'}</div>
    </div>`;
  }
  function paint() {
    document.documentElement.classList.toggle('ov-on', on());
    document.documentElement.classList.toggle('ov-edit', mode === 'edit');
    let bar = document.getElementById('ov-bar');
    if (!on()) { if (bar) bar.remove(); return; }
    if (!bar) { bar = document.createElement('div'); bar.id = 'ov-bar'; document.body.appendChild(bar); }
    const two = (long, short) => `<i class="ov-l">${long}</i><i class="ov-s">${short}</i>`;
    bar.innerHTML = lookOnly()
      ? `${icon('shield')}<span><b>Owner view</b><small>Look only</small></span><button class="btn sm" data-ov="edit">${two('Allow changes', 'Allow changes')}</button><button class="btn primary sm" data-ov="off">${two('Back to Production', 'Back')}</button>`
      : `${icon('info')}<span><b>Owner view</b><small>Changes ON</small></span><button class="btn sm" data-ov="look">${two('Look only', 'Look only')}</button><button class="btn primary sm" data-ov="off">${two('Back to Production', 'Back')}</button>`;
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-ov]'); if (!b) return;
    e.preventDefault(); e.stopPropagation();
    const v = b.dataset.ov;
    if (v === 'edit') allowChanges(); else set(v === 'off' ? null : v);
  }, true);
  // 15 minutes without use: back to Production. While in use, keep the server's side alive.
  ['pointerdown', 'keydown', 'wheel', 'touchstart', 'scroll'].forEach((t) => document.addEventListener(t, () => { last = Date.now(); }, { capture: true, passive: true }));
  setInterval(() => {
    if (!on()) return;
    if (Date.now() - last > IDLE) { set(null).then(() => toast('Owner view ended after 15 minutes without use')); return; }
    if (Date.now() - lastPing > 4 * 60000 && Date.now() - last < 4 * 60000) { lastPing = Date.now(); api('POST', '/api/owner-view', { mode }).catch(() => {}); }
  }, 20000);
  return { init, on, lookOnly, blocked, card, set };
})();
