// E11 Talk's files on Cloudflare: the same R2 bucket the office uses, reached through the Worker's own binding — no R2
// keys anywhere (TALK-CF-A). Talk's own code asks for the same things as of the office's r2.js (start / complete / size /
// del); the phone gets addresses on this relay instead of R2's own, each signed for one thing to one file for a while:
// /r2/put/<token> (the file, or one 8 MB part) and /r2/get/<token> (fetching it). The phone locks every file before it
// leaves (AES-GCM) — R2 and this relay only ever hold locked bytes.
const enc = new TextEncoder();
const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = (s) => Uint8Array.from(atob(String(s).replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
export const PART = 8 * 1024 * 1024;

async function hmac(secret) { return crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']); }
export async function token(secret, o) {
  const body = b64u(enc.encode(JSON.stringify(o)));
  return body + '.' + b64u(await crypto.subtle.sign('HMAC', await hmac(secret), enc.encode(body)));
}
export async function readToken(secret, t, now = Date.now()) {
  const [body, sig] = String(t || '').split('.');
  if (!body || !sig) return null;
  try {
    if (!(await crypto.subtle.verify('HMAC', await hmac(secret), unb64u(sig), enc.encode(body)))) return null;
    const o = JSON.parse(new TextDecoder().decode(unb64u(body)));
    return o && o.e > now ? o : null;
  } catch { return null; }
}

// what Talk's own code calls (talk.js r2Start / r2Done / sweep): bucket = env.TALK_FILES, base = this relay's address
export function bindingR2({ bucket, secret, base, now = () => Date.now() }) {
  const put = (o) => token(secret, { ...o, m: 'put', e: now() + 3600_000 });
  return {
    on: !!(bucket && secret && base), PART,
    async start(key, size) {
      if (size <= PART) return { put: `${base}/r2/put/${await put({ k: key })}` };
      const up = await bucket.createMultipartUpload(key);
      const n = Math.ceil(size / PART), urls = [];
      for (let i = 1; i <= n; i++) urls.push(`${base}/r2/put/${await put({ k: key, u: up.uploadId, p: i })}`);
      return { upload: up.uploadId, part: PART, urls };
    },
    async complete(key, upload, etags) {
      const up = bucket.resumeMultipartUpload(key, upload);
      await up.complete(etags.map((e, i) => ({ partNumber: i + 1, etag: String(e).replace(/"/g, '') })));
    },
    async size(key) { const h = await bucket.head(key); return h ? h.size : null; },
    async del(key) { await bucket.delete(key); return true; },
    // fetching it: for 15 minutes, as the office's links
    getUrl: async (key) => `${base}/r2/get/${await token(secret, { k: key, m: 'get', e: now() + 900_000 })}`,
  };
}

// the Worker's side of those addresses (no hub needed — the token says what's allowed)
export async function serveR2(req, env, path) {
  const [, , kind, t] = path.split('/');   // /r2/put/<t> · /r2/get/<t>
  const o = await readToken(env.R2_LINK_SECRET, t);
  const bucket = env.TALK_FILES;
  const cors = { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'ETag, Content-Length, Content-Range' };
  if (!o || o.m !== kind || !bucket) return new Response('This address has run out', { status: 403, headers: cors });
  if (kind === 'put' && req.method === 'PUT') {
    const body = await req.arrayBuffer();
    if (body.byteLength > PART) return new Response('Too big', { status: 413, headers: cors });
    const etag = o.u ? (await bucket.resumeMultipartUpload(o.k, o.u).uploadPart(o.p, body)).etag : (await bucket.put(o.k, body)).etag;
    return new Response(null, { status: 200, headers: { ...cors, ETag: `"${etag}"` } });
  }
  if (kind === 'get' && (req.method === 'GET' || req.method === 'HEAD')) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.get('range') || '');
    const range = m && (m[1] || m[2]) ? (m[1] ? { offset: Number(m[1]), ...(m[2] ? { length: Number(m[2]) - Number(m[1]) + 1 } : {}) } : { suffix: Number(m[2]) }) : undefined;
    const obj = req.method === 'HEAD' ? await bucket.head(o.k) : await bucket.get(o.k, range ? { range } : {});
    if (!obj) return new Response('That file has gone', { status: 404, headers: cors });
    const h = new Headers(cors);
    h.set('content-type', 'application/octet-stream'); h.set('accept-ranges', 'bytes'); h.set('cache-control', 'private, max-age=900'); h.set('etag', obj.httpEtag);
    if (range && obj.range) {
      const off = obj.range.offset ?? (obj.size - obj.range.suffix), len = obj.range.length ?? (obj.size - off);
      h.set('content-range', `bytes ${off}-${off + len - 1}/${obj.size}`); h.set('content-length', String(len));
      return new Response(req.method === 'HEAD' ? null : obj.body, { status: 206, headers: h });
    }
    h.set('content-length', String(obj.size));
    return new Response(req.method === 'HEAD' ? null : obj.body, { status: 200, headers: h });
  }
  return new Response('Not here', { status: 405, headers: cors });
}
