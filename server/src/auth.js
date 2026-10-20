// Sign-in: Cloudflare Access checks who someone is (email code / Google) before any request
// reaches the NAS, then sends a signed token with every request. We verify that token with
// Cloudflare's public keys and look the email up in the team list.
import crypto from 'node:crypto';

const b64urlJSON = (s) => JSON.parse(Buffer.from(s, 'base64url').toString('utf8'));

export function createAuth({ team, aud, dev = false, fetchImpl = fetch, now = () => Date.now() }) {
  const issuer = team ? `https://${team}.cloudflareaccess.com` : null;
  let keys = new Map();
  let fetchedAt = 0;

  async function loadKeys(force) {
    if (!issuer) return;
    if (!force && keys.size && now() - fetchedAt < 3600_000) return;
    const res = await fetchImpl(`${issuer}/cdn-cgi/access/certs`);
    if (!res.ok) throw new Error(`Could not load Cloudflare keys (${res.status})`);
    const body = await res.json();
    const next = new Map();
    (body.keys || []).forEach((jwk) => { try { next.set(jwk.kid, crypto.createPublicKey({ key: jwk, format: 'jwk' })); } catch { /* skip */ } });
    keys = next; fetchedAt = now();
  }

  async function verify(token) {
    const parts = String(token || '').split('.');
    if (parts.length !== 3) throw new Error('Malformed token');
    const header = b64urlJSON(parts[0]);
    const payload = b64urlJSON(parts[1]);
    if (header.alg !== 'RS256') throw new Error('Unexpected token type');
    await loadKeys(false);
    if (!keys.has(header.kid)) await loadKeys(true);
    const key = keys.get(header.kid);
    if (!key) throw new Error('Unknown signing key');
    const ok = crypto.verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), key, Buffer.from(parts[2], 'base64url'));
    if (!ok) throw new Error('Bad signature');
    const t = Math.floor(now() / 1000);
    if (payload.exp && payload.exp < t - 30) throw new Error('Token expired');
    if (payload.nbf && payload.nbf > t + 30) throw new Error('Token not yet valid');
    if (payload.iss !== issuer) throw new Error('Wrong issuer');
    const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (!aud || !auds.includes(aud)) throw new Error('Wrong application');
    if (!payload.email) throw new Error('No email in token');
    return { email: String(payload.email).toLowerCase(), sub: payload.sub || null };
  }

  const cookie = (req, name) => {
    const m = String(req.headers.cookie || '').match(new RegExp('(?:^|;\\s*)' + name + '=([^;]+)'));
    return m ? decodeURIComponent(m[1]) : null;
  };

  // Returns { email } for the person making the request, or throws
  async function identify(req) {
    const token = req.headers['cf-access-jwt-assertion'] || cookie(req, 'CF_Authorization');
    if (token && issuer && aud) return verify(token);
    if (dev) {
      const url = new URL(req.url, 'http://x');
      const email = req.headers['x-dev-email'] || url.searchParams.get('as') || cookie(req, 'e11_dev_email');
      if (email) return { email: String(email).toLowerCase(), dev: true };
      throw new Error('Development mode: send X-Dev-Email');
    }
    if (!issuer || !aud) throw new Error('Sign-in is not set up yet (CF_TEAM / CF_AUD missing)');
    throw new Error('Not signed in through Cloudflare');
  }

  return { identify, verify, configured: !!(issuer && aud) };
}
