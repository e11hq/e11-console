// Seasonal decorations, every year from 16 to 31 December, on the Mac app and website only (never the phone):
// - a Santa hat on the E11 icon (startup screen and sidebar logo)
// - snow caps on the purple buttons, a snow bank along the bottom of the window and gently falling snow
//   (none with Reduce Motion)
// Anyone can switch them off in My profile (u.prefs.seasonOff); that choice is also kept on the device so the
// startup screen knows before the data has loaded.
const Season = (() => {
  const FROM = '12-16', TO = '12-31';
  const KEY = 'e11-season-off';
  const pad = (n) => String(n).padStart(2, '0');
  const md = (d = new Date()) => `${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const inSeason = (d = new Date()) => { const m = md(d); return m >= FROM && m <= TO; };
  const offHere = () => { try { return localStorage.getItem(KEY) === '1'; } catch (e) { return false; } };
  let forced = null;
  // the phone layout (narrow screens, never the Mac app); phone.js sets html.phone later, so check the width too
  const isPhone = () => (typeof Phone !== 'undefined' ? document.documentElement.classList.contains('phone') : matchMedia('(max-width: 760px)').matches);

  const HAT = (id) => `
    <defs>
      <linearGradient id="${id}r" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff5a52"/><stop offset=".55" stop-color="#d81f2a"/><stop offset="1" stop-color="#9c0f1a"/></linearGradient>
      <radialGradient id="${id}w" cx=".35" cy=".3" r=".9"><stop offset="0" stop-color="#fff"/><stop offset=".7" stop-color="#f1f0f6"/><stop offset="1" stop-color="#cfd3e2"/></radialGradient>
      <filter id="${id}s" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#1a0f3c" flood-opacity=".35"/></filter>
    </defs>
    <g filter="url(#${id}s)">
      <path d="M-150 6 C-128 -120 -40 -238 70 -252 C150 -262 214 -214 236 -132 L206 -120 C192 -168 150 -196 104 -186 C84 -110 118 -40 158 6 Z" fill="url(#${id}r)"/>
      <path d="M-96 -40 C-70 -120 -10 -200 60 -222" fill="none" stroke="#fff" stroke-opacity=".22" stroke-width="16" stroke-linecap="round"/>
      <rect x="-182" y="-26" width="368" height="84" rx="42" fill="url(#${id}w)"/>
      <g fill="#fff" opacity=".9"><circle cx="-130" cy="-6" r="10"/><circle cx="-70" cy="2" r="8"/><circle cx="-6" cy="-8" r="11"/><circle cx="62" cy="0" r="9"/><circle cx="126" cy="-4" r="10"/></g>
      <circle cx="228" cy="-118" r="44" fill="url(#${id}w)"/>
    </g>`;

  function addHats() {
    const svg = document.querySelector('#splash .sp-mark');
    if (svg && !svg.querySelector('.xm-hat')) {
      const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
      g.setAttribute('class', 'xm-hat');
      g.setAttribute('transform', 'translate(770 196) rotate(24) scale(.78)');
      g.innerHTML = `<g class="xm-hat-in">${HAT('xh')}</g>`;
      svg.appendChild(g);
    }
    const logo = document.querySelector('.brand-logo');
    if (logo && !logo.querySelector('.xm-hat-s')) logo.insertAdjacentHTML('afterbegin', `<svg class="xm-hat-s" viewBox="-200 -280 460 360" aria-hidden="true">${HAT('xs')}</svg>`);
  }
  function addSnow() {
    if (document.querySelector('.xm-drift')) return;
    document.body.insertAdjacentHTML('beforeend', `<div class="xm-drift" aria-hidden="true"><svg viewBox="0 0 1440 46" preserveAspectRatio="none">
      <defs><linearGradient id="xmd" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#e3e8f4"/></linearGradient>
      <filter id="xmds"><feDropShadow dx="0" dy="-2" stdDeviation="3" flood-color="#5a6b9a" flood-opacity=".35"/></filter></defs>
      <path class="xm-d1" filter="url(#xmds)" fill="url(#xmd)" d="M0 22 C60 9 120 7 190 19 C250 28 300 22 360 25 C430 28 470 15 540 16 C620 18 660 29 740 28 C820 26 860 12 940 13 C1020 15 1060 26 1130 25 C1200 23 1240 10 1310 12 C1370 13 1410 20 1440 19 L1440 46 L0 46 Z"/>
      <path fill="#fff" opacity=".7" d="M0 35 C120 30 220 38 340 33 C470 29 560 38 700 35 C840 32 960 39 1100 35 C1240 30 1340 38 1440 33 L1440 46 L0 46 Z"/></svg></div>`);
    const f = document.createElement('div');
    f.className = 'xm-flakes'; f.setAttribute('aria-hidden', 'true');
    let seed = 11; const r = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
    let html = '';
    for (let i = 0; i < 42; i++) {
      const s = 3 + r() * 5, dur = 14 + r() * 16, delay = -r() * dur;
      html += `<i style="left:${(r() * 100).toFixed(2)}%;width:${s.toFixed(1)}px;height:${s.toFixed(1)}px;opacity:${(.35 + r() * .5).toFixed(2)};--sway:${Math.round(20 + r() * 50) * (r() < .5 ? -1 : 1)}px;animation-duration:${dur.toFixed(1)}s;animation-delay:${delay.toFixed(1)}s"></i>`;
    }
    f.innerHTML = html;
    document.body.appendChild(f);
  }
  function removeAll() {
    document.querySelectorAll('.xm-hat, .xm-hat-s, .xm-drift, .xm-flakes').forEach((el) => el.remove());
  }
  // decide and paint; cheap enough to call on every sidebar render
  function sync(prefsOff) {
    if (prefsOff !== undefined) { try { prefsOff ? localStorage.setItem(KEY, '1') : localStorage.removeItem(KEY); } catch (e) {} }
    const on = forced !== null ? forced : inSeason() && !isPhone() && !(prefsOff !== undefined ? prefsOff : offHere());
    document.documentElement.classList.toggle('xm-season', on);
    if (on) { addHats(); addSnow(); } else if (document.querySelector('.xm-drift, .xm-hat, .xm-hat-s')) removeAll();
    return on;
  }
  const force = (v) => { forced = v; return sync(); };
  // from 16 December the decorations appear without reopening the app; they go on 1 January
  setInterval(() => sync(), 10 * 60 * 1000);
  sync();
  return { sync, force, inSeason, FROM, TO };
})();
