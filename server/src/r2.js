// E11 Talk's photos and files in Cloudflare R2 (Haris 2026-11-20 17:12–17:52: "make it direct") — the phone sends a file
// straight to R2 and the other phones fetch it straight from there; this server only says who may, with links that work
// for a short time (S3's "presigned" links, signed here with AWS Signature V4 — no outside packages). The bucket's keys stay
// on this server (R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET); without them nothing goes to R2 and
// everything works as before.
import crypto from 'node:crypto';

const enc = (s) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());
const hmac = (k, s) => crypto.createHmac('sha256', k).update(s).digest();
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const amzDate = (t) => new Date(t).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');

// a presigned address: anyone holding it may do that one thing (method) to that one object until it runs out
export function presign({ method, host, path, query = {}, keyId, secret, region = 'auto', expires = 900, now = Date.now() }) {
  const date = amzDate(now), day = date.slice(0, 8), scope = `${day}/${region}/s3/aws4_request`;
  const q = { ...query, 'X-Amz-Algorithm': 'AWS4-HMAC-SHA256', 'X-Amz-Credential': `${keyId}/${scope}`, 'X-Amz-Date': date,
    'X-Amz-Expires': String(expires), 'X-Amz-SignedHeaders': 'host' };
  const qs = Object.keys(q).sort().map((k) => `${enc(k)}=${enc(String(q[k]))}`).join('&');
  const uri = path.split('/').map(enc).join('/');
  const canonical = [method, uri, qs, `host:${host}\n`, 'host', 'UNSIGNED-PAYLOAD'].join('\n');
  const toSign = ['AWS4-HMAC-SHA256', date, scope, sha(canonical)].join('\n');
  const key = hmac(hmac(hmac(hmac('AWS4' + secret, day), region), 's3'), 'aws4_request');
  return `https://${host}${uri}?${qs}&X-Amz-Signature=${hmac(key, toSign).toString('hex')}`;
}

export function createR2({ account, keyId, secret, bucket, endpoint = '', now = () => Date.now(), fetchImpl = null } = {}) {
  const on = !!(account && keyId && secret && bucket);
  const host = endpoint ? new URL(endpoint).host : `${account}.r2.cloudflarestorage.com`;
  const base = endpoint ? new URL(endpoint).origin : `https://${host}`;
  const go = fetchImpl || ((...a) => fetch(...a));
  const url = (method, key, query = {}, expires = 900) => {
    const u = presign({ method, host, path: `/${bucket}/${key}`, query, keyId, secret, expires, now: now() });
    return endpoint ? base + u.slice(`https://${host}`.length) : u;
  };
  const PART = 8 * 1024 * 1024;
  return {
    on, PART,
    // a phone sending a file: one address to put it at, or (over 8 MB) one per 8 MB part — for an hour
    async start(key, size) {
      if (size <= PART) return { put: url('PUT', key, {}, 3600) };
      const r = await go(url('POST', key, { uploads: '' }), { method: 'POST' });
      const x = await r.text();
      const up = /<UploadId>([^<]+)<\/UploadId>/.exec(x);
      if (!r.ok || !up) throw new Error('R2 didn’t start the upload (' + r.status + ')');
      const n = Math.ceil(size / PART);
      return { upload: up[1], part: PART, urls: Array.from({ length: n }, (_, i) => url('PUT', key, { partNumber: String(i + 1), uploadId: up[1] }, 3600)) };
    },
    // its parts put together, in order (each part's ETag as R2 gave it to the phone)
    async complete(key, upload, etags) {
      const body = '<CompleteMultipartUpload>' + etags.map((e, i) => `<Part><PartNumber>${i + 1}</PartNumber><ETag>${String(e).replace(/[<>&]/g, '')}</ETag></Part>`).join('') + '</CompleteMultipartUpload>';
      const r = await go(url('POST', key, { uploadId: upload }), { method: 'POST', body, headers: { 'Content-Type': 'application/xml' } });
      const x = await r.text();
      if (!r.ok || /<Error>/.test(x)) throw new Error('R2 didn’t put the parts together (' + r.status + ')');
    },
    // how big it is there (null: not there)
    async size(key) {
      const r = await go(url('HEAD', key), { method: 'HEAD' });
      return r.ok ? Number(r.headers.get('content-length')) : null;
    },
    // a phone fetching it: straight from R2, for 15 minutes
    getUrl: (key) => url('GET', key, {}, 900),
    // this server reading it (for apps that fetch through the server)
    get: (key, range) => go(url('GET', key), range ? { headers: { Range: range } } : {}),
    async del(key) { const r = await go(url('DELETE', key), { method: 'DELETE' }); return r.ok || r.status === 404; },
  };
}
