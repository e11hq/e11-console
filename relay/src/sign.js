// Signatures between the office and the hub (TALK-CF-A): nothing added on the NAS. Each side makes its own Ed25519 key
// and keeps it in its own database; each fetches the other's public key from the other's own address over HTTPS.
// A signed request: x-e11-ts (ms) and x-e11-sig = base64(sign(METHOD \n PATH \n TS \n BODY)), within 5 minutes.
const enc = new TextEncoder();
const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const unb64 = (s) => Uint8Array.from(atob(String(s || '')), (c) => c.charCodeAt(0));
export const SKEW = 5 * 60_000;
const text = (method, path, ts, body) => enc.encode(`${method.toUpperCase()}\n${path}\n${ts}\n${body || ''}`);

export async function newKey() {
  const k = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  return { priv: JSON.stringify(await crypto.subtle.exportKey('jwk', k.privateKey)), pub: b64(await crypto.subtle.exportKey('raw', k.publicKey)) };
}
export async function signHeaders(privJwk, method, path, body, now = Date.now()) {
  const key = await crypto.subtle.importKey('jwk', JSON.parse(privJwk), { name: 'Ed25519' }, false, ['sign']);
  const ts = String(now);
  return { 'x-e11-ts': ts, 'x-e11-sig': b64(await crypto.subtle.sign({ name: 'Ed25519' }, key, text(method, path, ts, body))) };
}
export async function verify(pubB64, method, path, body, headers, now = Date.now()) {
  const ts = headers.get('x-e11-ts'), sig = headers.get('x-e11-sig');
  if (!pubB64 || !ts || !sig || Math.abs(now - Number(ts)) > SKEW) return false;
  try {
    const key = await crypto.subtle.importKey('raw', unb64(pubB64), { name: 'Ed25519' }, false, ['verify']);
    return await crypto.subtle.verify({ name: 'Ed25519' }, key, unb64(sig), text(method, path, ts, body));
  } catch { return false; }
}
// a phone's sign-in, as a fingerprint (never kept itself): what it sends the office with every request
export async function fingerprint(headers) {
  const parts = ['cookie', 'authorization', 'cf-access-jwt-assertion', 'x-talk-key'].map((h) => `${h}=${headers.get(h) || ''}`).join('\n');
  return b64(await crypto.subtle.digest('SHA-256', enc.encode(parts)));
}
