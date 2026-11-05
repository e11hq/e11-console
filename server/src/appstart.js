// What the iPhone app needs to start on its own (Part B step 8, 2026-11-05) — GET /api/app/start. It is also how the app
// asks whether it is signed in: an answer here means yes (Cloudflare's sign-in, or the App Review copy's, stands in front
// of it otherwise). The startup screen's memo, as the page sent it to the app (app.js Splash toAppMemo): the first name,
// whether the fourth row is the CD's Review requests, and for the next three weeks each day's greeting (an occasion's:
// "Ramadan Kareem" — web/calendar.js Occasions, as the page has it) and Dubai's sunrise / sunset (the Automatic look —
// app.js sunTimesDubai). The look itself (Light / Dark / Automatic) is the phone's own: the app keeps it.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const DAY = 86400000;
const pad = (n) => String(n).padStart(2, '0');
const dubaiDay = (ms) => new Date(ms + 4 * 3600000).toISOString().slice(0, 10);
const plus = (ymd, n) => new Date(Date.parse(ymd + 'T00:00:00Z') + n * DAY).toISOString().slice(0, 10);
// (a time as Dubai's clock shows it, HH:MM)
const hm = (d) => { const x = new Date(d.getTime() + 4 * 3600000); return `${pad(x.getUTCHours())}:${pad(x.getUTCMinutes())}`; };

export function createAppStart({ webDir }) {
  // the page's own code for both, read from its files (as server/src/holidays.js does with Occasions)
  let occSrc = null, sunFn = null, at = '';
  function load() {
    const cal = path.join(webDir, 'calendar.js'), app = path.join(webDir, 'app.js');
    const stamp = `${fs.statSync(cal).mtimeMs}|${fs.statSync(app).mtimeMs}`;
    if (stamp === at && occSrc && sunFn) return;
    occSrc = fs.readFileSync(cal, 'utf8').split('const Cal =')[0];
    const a = fs.readFileSync(app, 'utf8');
    const i = a.indexOf('function sunTimesDubai('), j = a.indexOf('function sunTheme(', i);
    if (i < 0 || j < 0) throw new Error('sunTimesDubai not found in app.js');
    sunFn = vm.runInNewContext(`${a.slice(i, j)}; sunTimesDubai`, { Date, Math });
    at = stamp;
  }
  const occasions = (meta) => vm.runInNewContext(`${occSrc}; Occasions`, { db: { meta }, Intl, Date, Math, Number, String, Object, Array, JSON, parseInt });

  // u: the person signed in (as the app sees them — View as… included); meta: the shared settings; now: ms
  function start(u, meta, now = Date.now()) {
    load();
    const O = occasions(meta || {});
    const today = dubaiDay(now);
    const days = {};
    for (let i = 0; i < 21; i++) {
      const ds = plus(today, i);
      const [y, m, d] = ds.split('-').map(Number);
      const t = sunFn(new Date(y, m - 1, d, 12));   // (the day itself, whatever the server's own time zone)
      let g = ''; try { g = O.greeting(ds) || ''; } catch { /* none */ }
      days[ds] = { g, alone: !!(g && O.alone(g)), rise: hm(t.rise), set: hm(t.set) };
    }
    const cdU = meta && meta.cdUserId;
    const cd = !!cdU && cdU === u.id;
    const name = String(u.name || String(u.email || '').split('@')[0] || '').trim().split(/\s+/)[0] || '';
    return { me: u.id, name, cd, label4: cd ? 'Review requests' : 'Client Assets', days };
  }
  return { start };
}
