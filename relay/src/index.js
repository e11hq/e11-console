// E11 Talk on Cloudflare — the front door (TALK-CF-A, claude/talk-cloudflare-relay-plan.md).
// A phone's request: who it is comes from the office, with the phone's own sign-in (asked once, remembered as a
// fingerprint, so a phone already signed in is let in while the office is down). Then the hub.
// The office's requests (signed) and the hub's public key go straight to the hub.
import { fingerprint } from './sign.js';
import { serveR2 } from './r2.js';
export { TalkHub } from './hub.js';

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
    // (who this phone is: the hub works it out itself — one trip to the hub, not two; the sign-in's fingerprint only)
    const h = new Headers(req.headers); h.delete('x-hub-email'); h.set('x-hub-fp', await fingerprint(req.headers));
    return hub.fetch(new Request(req, { headers: h }));
  },
};
