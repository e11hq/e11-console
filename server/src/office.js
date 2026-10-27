/* Fast office use (planned with Haris 2026-10-27; claude/nas-copy-and-light-copies-plan.md). Mac app only.

   1. Copy inside the NAS: a file picked in the Mac app that's on the NAS shared folder "E11 Share" isn't uploaded.
      The app sends its place in the share and a fingerprint (SHA-256 of its first and last MB); the server finds it
      in its READ-ONLY mount of the share (SHARE_DIR, /share), checks size + fingerprint (so only a file the person
      actually has open, never any other file in the share), and copies it into the task / Client Assets folder.
   2. The office network: in the office (the request comes from OFFICE_IP, through Cloudflare as usual) the server
      gives the Mac app a short pass for one upload or one download, and the Mac app sends/fetches the file
      straight to/from the NAS on the office network (LOCAL_URL → this server's LOCAL_PORT, HTTPS with its own
      certificate, which the Mac app pins by fingerprint). Never through Europe and back.
   Both are off until the NAS is set up (SHARE_DIR mounted / LOCAL_PORT, LOCAL_URL, OFFICE_IP set). Anything that
   doesn't work falls back to the normal upload by itself. */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import https from 'node:https';
import { selfSignedCert } from './selfcert.js';

const b64u = (b) => Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = (s) => Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');
const MB = 1024 * 1024;

// SHA-256 of the first MB and the last MB of a file (the whole file when it's smaller); the Mac app does the same
export function fingerprint(full, size) {
  const fd = fs.openSync(full, 'r');
  try {
    const n = Math.min(MB, size);
    const head = Buffer.alloc(n), tail = Buffer.alloc(n);
    fs.readSync(fd, head, 0, n, 0);
    fs.readSync(fd, tail, 0, n, Math.max(0, size - n));
    return crypto.createHash('sha256').update(head).update(tail).digest('hex');
  } finally { fs.closeSync(fd); }
}

export function createOffice({ store, files, cfg = {}, ipOf, now = () => Date.now(), log = console }) {
  const shareDir = cfg.shareDir !== undefined ? cfg.shareDir : (fs.existsSync('/share') ? '/share' : null);
  const shareName = cfg.shareName || 'E11 Share';
  const officeIps = String(cfg.officeIp || '').split(',').map((x) => x.trim()).filter(Boolean);
  const localUrl = String(cfg.localUrl || '').replace(/\/+$/, '');
  const shareOn = () => { try { return !!shareDir && fs.statSync(shareDir).isDirectory(); } catch { return false; } };
  const inOffice = (req) => officeIps.length > 0 && officeIps.includes(ipOf(req));

  // the certificate for the office port, made once and kept (its fingerprint is what the Mac app checks)
  function tls() {
    let t = null;
    try { t = JSON.parse(store.kv.get('office-tls') || 'null'); } catch { t = null; }
    if (!t || !t.cert || !t.key) { t = selfSignedCert(); store.kv.set('office-tls', JSON.stringify(t)); }
    return t;
  }
  function secret() {
    let s = store.kv.get('office-secret');
    if (!s) { s = crypto.randomBytes(32).toString('hex'); store.kv.set('office-secret', s); }
    return s;
  }
  // a pass: who, what (one upload into a target, or one file to download), until when; signed by the server
  function sign(payload) {
    const body = b64u(JSON.stringify(payload));
    return body + '.' + b64u(crypto.createHmac('sha256', secret()).update(body).digest());
  }
  function verify(token) {
    const [body, mac] = String(token || '').split('.');
    if (!body || !mac) return null;
    const want = crypto.createHmac('sha256', secret()).update(body).digest();
    const got = unb64u(mac);
    if (got.length !== want.length || !crypto.timingSafeEqual(got, want)) return null;
    let p; try { p = JSON.parse(unb64u(body).toString('utf8')); } catch { return null; }
    if (!p || !p.exp || p.exp < now()) return null;
    return p;
  }

  /* ---------- 1. copies from E11 Share ---------- */
  const jobs = new Map();   // job id → { userId, state, done, size, file, error, at }
  function shareFile(rel) {
    if (!shareOn()) throw Object.assign(new Error('The shared folder isn’t connected to the app'), { status: 409 });
    const clean = String(rel || '').replace(/^\/+/, '');
    if (!clean || clean.split('/').includes('..') || clean.includes('\0')) throw Object.assign(new Error('Invalid path'), { status: 400 });
    const root = fs.realpathSync(shareDir);
    const full = fs.realpathSync(path.join(root, clean));
    if (!full.startsWith(root + path.sep)) throw Object.assign(new Error('Invalid path'), { status: 400 });
    const st = fs.statSync(full);
    if (!st.isFile()) throw Object.assign(new Error('Not a file'), { status: 404 });
    return { full, size: st.size };
  }
  // start a copy (checks first; the copy itself runs in the background, followed with status())
  function startCopy(u, target, { rel, size, fp }) {
    let src;
    try { src = shareFile(rel); } catch (e) { if (e.code === 'ENOENT') throw Object.assign(new Error('Not found in the shared folder'), { status: 404 }); throw e; }
    if (Number(size) !== src.size) throw Object.assign(new Error('The file in the shared folder is different'), { status: 409 });
    if (fingerprint(src.full, src.size) !== String(fp || '')) throw Object.assign(new Error('The file in the shared folder is different'), { status: 409 });
    const name = path.basename(src.full);
    const out = files.newUploadFile(target, name);
    const id = crypto.randomBytes(8).toString('hex');
    const job = { userId: u.id, state: 'copying', done: 0, size: src.size, file: null, error: null, at: now() };
    jobs.set(id, job);
    for (const [k, j] of jobs) if (now() - j.at > 6 * 3600_000) jobs.delete(k);
    const rs = fs.createReadStream(src.full), ws = fs.createWriteStream(out.full);
    rs.on('data', (c) => { job.done += c.length; });
    const fail = (e) => { if (job.state !== 'copying') return; job.state = 'error'; job.error = 'The copy failed'; log.error('share copy failed', e && e.message); rs.destroy(); ws.destroy(); fs.rmSync(out.full, { force: true }); };
    rs.on('error', fail); ws.on('error', fail);
    ws.on('finish', () => { if (job.state !== 'copying') return; job.state = 'done'; job.file = { path: out.rel, name: path.basename(out.full), size: src.size }; });
    rs.pipe(ws);
    job.cancel = () => { if (job.state === 'copying') { job.state = 'cancelled'; rs.destroy(); ws.destroy(); fs.rmSync(out.full, { force: true }); } };
    return id;
  }
  function status(u, id) {
    const j = jobs.get(String(id || ''));
    if (!j || j.userId !== u.id) return null;
    return { state: j.state, done: j.done, size: j.size, file: j.file, error: j.error };
  }
  function cancel(u, id) { const j = jobs.get(String(id || '')); if (j && j.userId === u.id && j.cancel) j.cancel(); }

  /* ---------- 2. the office network ---------- */
  function ticket(u, what) {
    const p = { u: u.id, exp: now() + (what.k === 'up' ? 60 : 15) * 60_000, n: crypto.randomBytes(6).toString('hex'), ...what };
    return { url: localUrl, token: sign(p), cert: tls().sha256 };
  }
  // the office port's own little server: a ping, uploads with a pass, downloads with a pass
  function localHandler({ readRaw, json, users, uploads, canStill }) {
    const upPath = new Map();   // pass nonce → the file it's writing
    return async (req, res) => {
      const url = new URL(req.url, 'https://office');
      try {
        if (url.pathname === '/local/ping') return json(res, 200, { ok: true, app: 'e11-console' });
        const p = verify(url.searchParams.get('t'));
        const u = p && users(p.u);
        if (!p || !u || u.active === false) return json(res, 403, { ok: false, error: 'This pass isn’t valid — try again' });
        if (url.pathname === '/local/upload' && req.method === 'POST' && p.k === 'up') {
          if (!canStill(u, p.target)) return json(res, 403, { ok: false, error: 'Not allowed' });
          const data = await readRaw(req, 72 * MB);
          const offset = Number(url.searchParams.get('offset') || 0);
          let rel = upPath.get(p.n) || null;
          if (!rel) { if (offset !== 0) return json(res, 400, { ok: false, error: 'Start from the beginning' }); }
          const out = await files.commands.writeChunk({ ...p.target, name: p.name, path: rel, offset: rel ? offset : null, data }, u);
          upPath.set(p.n, out.path);
          if (uploads) uploads.set(out.path, { userId: u.id, at: now() });
          return json(res, 200, out);
        }
        if (url.pathname === '/local/file' && (req.method === 'GET' || req.method === 'HEAD') && p.k === 'file') {
          if (!canStill(u, null, p.path)) return json(res, 403, { ok: false, error: 'Not allowed' });
          return files.serve(req, res, p.path);
        }
        return json(res, 404, { ok: false, error: 'Not found' });
      } catch (e) { return json(res, e.status || 500, { ok: false, error: e.message }); }
    };
  }
  let local = null;
  function listen(port, handler) {
    if (!port) return null;
    const t = tls();
    local = https.createServer({ key: t.key, cert: t.cert }, handler);
    local.on('error', (e) => log.error('office port:', e.message));
    local.listen(Number(port), '0.0.0.0');
    return local;
  }
  return {
    info: (req) => ({ share: shareOn(), shareName, local: !!localUrl && inOffice(req) }),
    inOffice, shareOn, startCopy, status, cancel, ticket, verify, localHandler, listen,
    close: () => new Promise((ok) => (local ? local.close(() => ok()) : ok())),
    certSha256: () => tls().sha256,
  };
}
