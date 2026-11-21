// E11 Talk on Cloudflare — the front door (TALK-CF-A, claude/talk-cloudflare-relay-plan.md).
// A phone's request: who it is comes from the office, with the phone's own sign-in (asked once, remembered as a
// fingerprint, so a phone already signed in is let in while the office is down). Then the hub.
// The office's requests (signed) and the hub's public key go straight to the hub.
import { fingerprint } from './sign.js';
import { serveR2 } from './r2.js';
export { TalkHub } from './hub.js';

const DAY = 86400_000, KEEP = 30 * DAY;
// (the hub made in Cloudflare's Middle East — near the team; the place is fixed when it's first made, Haris 2026-11-22)
const hubOf = (env) => env.HUB.get(env.HUB.idFromName(env.HUB_NAME || 'live'), { locationHint: 'me' });
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url), p = url.pathname;
    const hub = hubOf(env);
    if (p === '/hub/key' || p === '/hub/status' || p.startsWith('/office/')) return hub.fetch(req);
    // (a file's own address — the token says what's allowed; no hub needed)
    if (p.startsWith('/r2/')) return serveR2(req, env, p);
    if (!(p === '/line' || p.startsWith('/api/talk/'))) return json({ ok: false, error: 'Not here' }, 404);
    const email = await whoIs(req, env, ctx);
    if (!email) return json({ ok: false, error: 'Sign in again' }, 401);
    const h = new Headers(req.headers); h.set('x-hub-email', email);
    return hub.fetch(new Request(req, { headers: h }));
  },
};

// who this phone is: the office says (its own sign-in check, unchanged); remembered for 30 days by fingerprint only
async function whoIs(req, env, ctx) {
  const fp = await fingerprint(req.headers);
  const kv = hubOf(env);
  const known = await kv.fetch(new Request('https://hub/who-cache?fp=' + encodeURIComponent(fp))).then((r) => r.json()).catch(() => null);
  const fresh = known && known.email && Date.now() - known.at < DAY;
  if (fresh) return known.email;
  const ask = askOffice(req, env).then(async (email) => {
    if (email) await kv.fetch(new Request('https://hub/who-cache', { method: 'POST', body: JSON.stringify({ fp, email }) }));
    return email;
  });
  // (remembered but a day old: let in now, checked with the office meanwhile; the office down — still let in for 30 days)
  if (known && known.email && Date.now() - known.at < KEEP) { ctx.waitUntil(ask.catch(() => null)); return known.email; }
  return ask.catch(() => null);
}
async function askOffice(req, env) {
  const h = {};
  for (const k of ['cookie', 'authorization', 'cf-access-jwt-assertion', 'x-talk-key', 'x-talk-device']) { const v = req.headers.get(k); if (v) h[k] = v; }
  const r = await fetch(String(env.OFFICE).replace(/\/$/, '') + '/api/talk/relay/who', { headers: h });
  if (!r.ok) return null;
  const j = await r.json().catch(() => null);
  return j && j.ok && j.email ? String(j.email) : null;
}
