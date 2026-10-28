// The App Review copy (review.e11hq.com) — ONLY when REVIEW_PASSWORD is set, which is only ever on the third NAS app,
// "review", with its own data folder. Apple's reviewer can't pass the Cloudflare sign-in (only E11 emails get the
// code), so this copy has its own: one demo account with a password, and nothing but made-up data (demo.js) that
// starts fresh every night at 3:00 Dubai. The live and test copies never have REVIEW_PASSWORD, so none of this
// exists there — and this copy never looks at Cloudflare at all.
import crypto from 'node:crypto';

const DAY = 86400000;
const SESSION_DAYS = 30;
const TRIES = 5, TRY_WINDOW = 15 * 60000;   // 5 wrong passwords in 15 minutes → wait

export const REVIEW_USER_ID = 'u-review';

export function createReview({ store, password, email = 'review@e11hq.com', now = () => Date.now() }) {
  const user = String(email).toLowerCase();
  const hash = (s) => crypto.createHash('sha256').update(String(s)).digest();
  const want = hash(password);
  const fails = new Map();   // internet address → times of wrong tries

  const load = () => { try { return JSON.parse(store.kv.get('review-sessions') || '{}'); } catch { return {}; } };
  const save = (s) => store.kv.set('review-sessions', JSON.stringify(s));
  const cookieOf = (req) => { const m = String(req.headers.cookie || '').match(/(?:^|;\s*)e11_rv=([^;]+)/); return m ? decodeURIComponent(m[1]) : null; };

  function identify(req) {
    const tok = cookieOf(req);
    const s = tok && load()[hash(tok).toString('hex')];
    if (!s || s.exp < now()) throw new Error('Please sign in with the App Review account');
    return { email: user, review: true };
  }
  function blocked(ip) {
    const list = (fails.get(ip) || []).filter((t) => now() - t < TRY_WINDOW);
    fails.set(ip, list);
    return list.length >= TRIES;
  }
  // { ok, token } or { ok: false, error, wait }
  function signIn(ip, em, pw) {
    if (blocked(ip)) return { ok: false, wait: true, error: 'Too many tries. Please wait 15 minutes and try again.' };
    const okUser = String(em || '').trim().toLowerCase() === user;
    const okPw = crypto.timingSafeEqual(hash(pw || ''), want);
    if (!okUser || !okPw) { fails.get(ip).push(now()); return { ok: false, error: 'That email or password isn’t right.' }; }
    fails.delete(ip);
    const tok = crypto.randomBytes(32).toString('base64url');
    const all = load();
    for (const [k, v] of Object.entries(all)) if (v.exp < now()) delete all[k];
    all[hash(tok).toString('hex')] = { exp: now() + SESSION_DAYS * DAY, at: new Date(now()).toISOString() };
    save(all);
    return { ok: true, token: tok };
  }
  function signOut(req) {
    const tok = cookieOf(req);
    if (!tok) return;
    const all = load(); delete all[hash(tok).toString('hex')]; save(all);
  }
  const cookie = (req, tok) => `e11_rv=${tok ? encodeURIComponent(tok) : ''}; Path=/; HttpOnly; SameSite=Lax${/https/.test(String(req.headers['x-forwarded-proto'] || '')) || req.socket.encrypted ? '; Secure' : ''}${tok ? `; Max-Age=${SESSION_DAYS * 86400}` : '; Max-Age=0'}`;

  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function page({ error = '', email: em = '' } = {}) {
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>E11 Console · App Review</title><meta name="color-scheme" content="dark light">
<style>
:root{--bg:#0e0e11;--card:#17171c;--line:#2a2a33;--text:#ececf1;--dim:#9d9da8;--accent:#7b68ee;--err:#ff6b6b}
@media (prefers-color-scheme: light){:root{--bg:#f5f5f7;--card:#fff;--line:#dcdce3;--text:#16161a;--dim:#6b6b76;--err:#c62828}}
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);color:var(--text);font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,sans-serif;padding:24px 16px}
.box{width:100%;max-width:380px}.logo{width:56px;height:56px;border-radius:14px;background:var(--accent);display:grid;place-items:center;font-weight:800;font-size:20px;color:#fff;margin:0 auto 18px}
h1{font-size:22px;margin:0 0 6px;text-align:center}p.sub{margin:0 0 22px;color:var(--dim);text-align:center;font-size:14.5px}
form{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:20px}
label{display:block;font-size:13px;color:var(--dim);margin:0 0 6px}input{width:100%;font:inherit;color:var(--text);background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:12px;margin:0 0 14px;outline:none}
input:focus{border-color:var(--accent)}button{width:100%;font:inherit;font-weight:600;color:#fff;background:var(--accent);border:0;border-radius:10px;padding:13px;margin-top:4px}
.err{color:var(--err);font-size:14px;margin:0 0 14px}.foot{margin-top:18px;text-align:center;font-size:13.5px;color:var(--dim)}.foot a{color:var(--accent);text-decoration:none}
</style></head><body><div class="box">
<div class="logo">E11</div><h1>App Review sign-in</h1><p class="sub">A demo copy of E11 Console with made-up data, for Apple’s App Review.</p>
<form method="post" action="/review/sign-in" autocomplete="on">
${error ? `<div class="err" role="alert">${esc(error)}</div>` : ''}
<label for="em">Email</label><input id="em" name="email" type="email" autocapitalize="off" autocorrect="off" autocomplete="username" value="${esc(em)}" required>
<label for="pw">Password</label><input id="pw" name="password" type="password" autocomplete="current-password" required>
<button type="submit">Sign in</button></form>
<div class="foot">E11 team member? <a href="https://console.e11hq.com/" id="e11-back">Sign in to E11 Console</a></div>
</div></body></html>`;
  }
  return { identify, signIn, signOut, cookie, page, user };
}

// When the demo data starts fresh: once a day from 3:00 Dubai (or straight away on an empty copy)
export function resetDue(store, at = Date.now()) {
  const d = new Date(at + 4 * 3600000);   // Dubai is UTC+4, all year
  const day = d.toISOString().slice(0, 10);
  let last = null; try { last = JSON.parse(store.kv.get('demo-loaded') || 'null'); } catch { last = null; }
  if (!last || !last.day) return { due: true, day };
  if (last.day === day) return { due: false, day };
  return { due: d.getUTCHours() >= 3, day };
}
