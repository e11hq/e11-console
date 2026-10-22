// Files: attachments, client assets, logos and avatars live under DATA_DIR/files, using the same
// relative paths as the Mac app (attachments/<taskId>/…, Clients/<client>/<folder>/…, .thumbs/…).
// These functions back the app's "host" commands so the interface works unchanged in the browser.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { execFile } from 'node:child_process';

export const MIME = {
  html: 'text/html; charset=utf-8', css: 'text/css; charset=utf-8', js: 'text/javascript; charset=utf-8', json: 'application/json', webmanifest: 'application/manifest+json',
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp', svg: 'image/svg+xml', ico: 'image/x-icon',
  heic: 'image/heic', bmp: 'image/bmp', tif: 'image/tiff', tiff: 'image/tiff',
  mp4: 'video/mp4', m4v: 'video/x-m4v', mov: 'video/quicktime', webm: 'video/webm',
  mp3: 'audio/mpeg', m4a: 'audio/mp4', aac: 'audio/aac', wav: 'audio/wav', aif: 'audio/aiff', aiff: 'audio/aiff',
  pdf: 'application/pdf', txt: 'text/plain; charset=utf-8', md: 'text/plain; charset=utf-8', csv: 'text/plain; charset=utf-8', log: 'text/plain; charset=utf-8', xml: 'text/plain; charset=utf-8',
  otf: 'font/otf', ttf: 'font/ttf', woff: 'font/woff', woff2: 'font/woff2', zip: 'application/zip',
};
export const mimeOf = (p) => MIME[String(p).split('.').pop().toLowerCase()] || 'application/octet-stream';
const safeName = (n) => String(n || 'file').replace(/[\/\\:\0]/g, '-').replace(/^\.+/, '_').slice(0, 200) || 'file';
const run = (cmd, args, timeout = 20000) => new Promise((resolve) => execFile(cmd, args, { timeout }, (err) => resolve(!err)));
export const OFFICE = ['doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'odt', 'odp', 'ods', 'rtf'];
export const IMAGES = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'tif', 'tiff', 'heic'];
let officeChecked = null;
const hasOffice = () => (officeChecked = officeChecked || new Promise((ok) => execFile('soffice', ['--version'], { timeout: 20000 }, (err) => ok(!err))));
let officeQueue = Promise.resolve(); // one conversion at a time (LibreOffice is heavy on the NAS)

export function createFiles(root) {
  const FILES = path.join(root, 'files');
  const TRASH = path.join(root, 'trash');
  fs.mkdirSync(FILES, { recursive: true });

  // Turn a relative path from the app into a real path, refusing anything outside the files folder
  function resolve(rel) {
    const r = String(rel || '').replace(/^\/+/, '');
    if (!r || r.split(/[\\/]/).includes('..') || r.includes('\0')) throw httpError(400, 'Invalid path');
    const full = path.resolve(FILES, r);
    if (full !== FILES && !full.startsWith(FILES + path.sep)) throw httpError(400, 'Invalid path');
    return full;
  }
  const rel = (full) => path.relative(FILES, full).split(path.sep).join('/');
  function uploadDir(a) {
    if (a && a.dest) {
      const d = String(a.dest);
      if (!d.startsWith('Clients/') && !d.startsWith('Finance/')) throw httpError(400, 'Invalid folder');
      return resolve(d);
    }
    return resolve('attachments/' + safeName((a && a.taskId) || 'misc'));
  }
  function uniquePath(dir, name) {
    const dot = name.lastIndexOf('.');
    const base = dot > 0 ? name.slice(0, dot) : name, ext = dot > 0 ? name.slice(dot) : '';
    let p = path.join(dir, name), i = 2;
    while (fs.existsSync(p)) { p = path.join(dir, `${base} (${i})${ext}`); i++; }
    return p;
  }

  const zips = new Map();

  const commands = {
    // Upload in pieces: the first call creates the file, later calls append to it
    writeChunk(a) {
      const data = Buffer.from(String(a.b64 || ''), 'base64');
      let dest;
      if (!a.path) {
        const dir = uploadDir(a);
        fs.mkdirSync(dir, { recursive: true });
        dest = uniquePath(dir, safeName(a.name));
        fs.writeFileSync(dest, data, { flag: 'wx' });
      } else {
        dest = resolve(a.path);
        if (!fs.existsSync(dest)) throw httpError(400, 'Upload file missing');
        fs.appendFileSync(dest, data);
      }
      return { ok: true, path: rel(dest), name: path.basename(dest), size: fs.statSync(dest).size };
    },
    makeDir(a) { fs.mkdirSync(uploadDir({ dest: a.path }), { recursive: true }); return { ok: true }; },
    // "Trash" keeps deleted files for 30 days in DATA_DIR/trash/<date>/… before they are removed
    trashMany(a) {
      let n = 0;
      const day = new Date().toISOString().slice(0, 10);
      for (const p of a.paths || []) {
        try {
          const src = resolve(p);
          if (!fs.existsSync(src)) continue;
          const dst = uniquePath(path.join(TRASH, day, path.dirname(rel(src))), path.basename(src));
          fs.mkdirSync(path.dirname(dst), { recursive: true });
          fs.renameSync(src, dst);
          n++;
        } catch { /* skip bad paths */ }
      }
      return { ok: true, trashed: n };
    },
    trashPath(a) { return commands.trashMany({ paths: [a.path] }); },
    // Word / PowerPoint / Excel → PDF with LibreOffice, made once and kept in .thumbs/<id>/preview.pdf.
    // Returns { pdf: null, unavailable: true } when LibreOffice isn't installed (older server image).
    async docPreview(a) {
      const src = resolve(a.path);
      if (!fs.existsSync(src)) return { ok: true, pdf: null };
      const ext = src.split('.').pop().toLowerCase();
      if (!OFFICE.includes(ext)) return { ok: true, pdf: null };
      const id = safeName(a.id || crypto.createHash('sha1').update(a.path).digest('hex').slice(0, 12));
      const dir = resolve('.thumbs/' + id);
      const out = path.join(dir, 'preview.pdf');
      if (fs.existsSync(out)) return { ok: true, pdf: rel(out) };
      if (!(await hasOffice())) return { ok: true, pdf: null, unavailable: true };
      fs.mkdirSync(dir, { recursive: true });
      const job = officeQueue.then(async () => {
        if (fs.existsSync(out)) return;
        const tmp = fs.mkdtempSync(path.join(dir, 'lo-'));
        const copy = path.join(tmp, 'doc.' + ext);
        fs.copyFileSync(src, copy);
        await run('soffice', ['-env:UserInstallation=file:///tmp/e11-libreoffice', '--headless', '--norestore', '--convert-to', 'pdf', '--outdir', tmp, copy], 120000);
        const made = path.join(tmp, 'doc.pdf');
        if (fs.existsSync(made)) fs.renameSync(made, out);
        fs.rmSync(tmp, { recursive: true, force: true });
      });
      officeQueue = job.catch(() => {});
      await job.catch(() => {});
      return { ok: true, pdf: fs.existsSync(out) ? rel(out) : null };
    },
    // Preview image: photos and logos are resized, videos get a frame, PDFs and Office files their first page
    async thumb(a) {
      const src = resolve(a.path);
      if (!fs.existsSync(src)) return { ok: true, thumb: null };
      const id = safeName(a.id || crypto.createHash('sha1').update(a.path).digest('hex').slice(0, 12));
      const dir = resolve('.thumbs/' + id);
      const out = path.join(dir, 'thumb.png');
      if (fs.existsSync(out)) return { ok: true, thumb: rel(out) };
      fs.mkdirSync(dir, { recursive: true });
      const ext = src.split('.').pop().toLowerCase();
      let ok = false;
      if (ext === 'pdf') {
        ok = await run('pdftoppm', ['-png', '-singlefile', '-f', '1', '-l', '1', '-scale-to', '640', src, path.join(dir, 'thumb')]);
      } else if (OFFICE.includes(ext)) {
        const r = await commands.docPreview(a);
        if (r.pdf) ok = await run('pdftoppm', ['-png', '-singlefile', '-f', '1', '-l', '1', '-scale-to', '640', resolve(r.pdf), path.join(dir, 'thumb')]);
      } else if (['mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv'].includes(ext)) {
        ok = await run('ffmpeg', ['-y', '-v', 'error', '-ss', '1', '-i', src, '-frames:v', '1', '-vf', 'scale=640:-2', out]);
        if (!ok) ok = await run('ffmpeg', ['-y', '-v', 'error', '-i', src, '-frames:v', '1', '-vf', 'scale=640:-2', out]);
      } else if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'tif', 'tiff', 'heic'].includes(ext)) {
        ok = await run('ffmpeg', ['-y', '-v', 'error', '-i', src, '-frames:v', '1', '-vf', "scale='min(640,iw)':-2", out]);
      }
      if (!ok || !fs.existsSync(out)) { fs.rmSync(dir, { recursive: true, force: true }); return { ok: true, thumb: null }; }
      return { ok: true, thumb: rel(out) };
    },
    // Profile photos (400px JPEG) and client logos (600px PNG) from an uploaded image
    async processImage(a) {
      const src = resolve(a.path);
      if (!fs.existsSync(src)) throw httpError(400, 'Image missing');
      const logo = a.kind === 'logo';
      const dir = resolve(logo ? 'Clients/_logos' : 'attachments/_avatars');
      fs.mkdirSync(dir, { recursive: true });
      const ext = src.split('.').pop().toLowerCase();
      const stem = `${safeName(a.userId || (logo ? 'client' : 'user'))}-${Date.now().toString(36)}`;
      let dest;
      if (logo && ext === 'svg') { dest = path.join(dir, stem + '.svg'); fs.copyFileSync(src, dest); }
      else {
        dest = path.join(dir, stem + (logo ? '.png' : '.jpg'));
        const size = logo ? 600 : 400;
        const ok = await run('ffmpeg', ['-y', '-v', 'error', '-i', src, '-frames:v', '1', '-vf', `scale='if(gt(iw,ih),min(${size},iw),-2)':'if(gt(iw,ih),-2,min(${size},ih))'`, ...(logo ? [] : ['-q:v', '3']), dest]);
        if (!ok) { dest = path.join(dir, stem + '.' + ext); fs.copyFileSync(src, dest); }
      }
      if (src.includes(`${path.sep}_uploads${path.sep}`)) fs.rmSync(src, { force: true });
      return { ok: true, path: rel(dest) };
    },
    // "Download all": the browser downloads one zip
    exportFiles(a) {
      const token = crypto.randomBytes(12).toString('hex');
      const paths = (a.paths || []).map((p) => { try { return resolve(p); } catch { return null; } }).filter((p) => p && fs.existsSync(p));
      zips.set(token, { name: safeName(a.folder || 'E11 files') + '.zip', paths, at: Date.now() });
      for (const [k, v] of zips) if (Date.now() - v.at > 3600_000) zips.delete(k);
      return { ok: true, count: paths.length, url: `/api/zip/${token}`, dir: safeName(a.folder || 'E11 files') };
    },
    sweepOrphans() { return { ok: true, trashed: 0 }; },
  };

  // Remove trash folders older than 30 days
  function purgeTrash(days = 30) {
    if (!fs.existsSync(TRASH)) return 0;
    let n = 0;
    const cutoff = Date.now() - days * 86400_000;
    for (const d of fs.readdirSync(TRASH)) {
      const t = Date.parse(d);
      if (!Number.isNaN(t) && t < cutoff) { fs.rmSync(path.join(TRASH, d), { recursive: true, force: true }); n++; }
    }
    return n;
  }

  // Serve a file with byte ranges (videos stream and seek)
  function serve(req, res, relPath) {
    let full;
    try { full = resolve(relPath); } catch { res.writeHead(400).end(); return; }
    let st;
    try { st = fs.statSync(full); } catch { res.writeHead(404).end('Not found'); return; }
    if (!st.isFile()) { res.writeHead(404).end('Not found'); return; }
    const type = mimeOf(full);
    const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
    const headers = { 'Content-Type': type, 'Accept-Ranges': 'bytes', 'Cache-Control': 'private, max-age=3600', 'X-Content-Type-Options': 'nosniff' };
    if (type.startsWith('text/html') || type === 'image/svg+xml') headers['Content-Security-Policy'] = "default-src 'none'; style-src 'unsafe-inline'; img-src data:";
    if (range && (range[1] || range[2])) {
      let start = range[1] ? Number(range[1]) : Math.max(0, st.size - Number(range[2]));
      let end = range[1] && range[2] ? Math.min(Number(range[2]), st.size - 1) : st.size - 1;
      if (start >= st.size || start > end) { res.writeHead(416, { 'Content-Range': `bytes */${st.size}` }).end(); return; }
      res.writeHead(206, { ...headers, 'Content-Range': `bytes ${start}-${end}/${st.size}`, 'Content-Length': end - start + 1 });
      if (req.method === 'HEAD') { res.end(); return; }
      fs.createReadStream(full, { start, end }).pipe(res);
      return;
    }
    res.writeHead(200, { ...headers, 'Content-Length': st.size });
    if (req.method === 'HEAD') { res.end(); return; }
    fs.createReadStream(full).pipe(res);
  }

  // A smaller copy of an image (made once with ffmpeg, kept in .thumbs/_sized) so lists and tiles load fast.
  // Photos become JPEG; PNG/GIF/WebP keep transparency as PNG. Anything that fails falls back to the original.
  const SIZES = [160, 320, 640, 1280];
  const sizing = new Map();
  async function serveSized(req, res, relPath, want) {
    let full, st;
    try { full = resolve(relPath); st = fs.statSync(full); } catch { return serve(req, res, relPath); }
    const ext = full.split('.').pop().toLowerCase();
    const w = SIZES.find((x) => x >= Number(want)) || 1280;
    if (!IMAGES.includes(ext) || st.size < 60000) return serve(req, res, relPath);
    const key = crypto.createHash('sha1').update(relPath + '|' + st.size + '|' + st.mtimeMs).digest('hex').slice(0, 20);
    const outExt = ['png', 'gif', 'webp'].includes(ext) ? 'png' : 'jpg';
    const out = path.join(resolve('.thumbs/_sized'), `${key}-${w}.${outExt}`);
    if (!fs.existsSync(out)) {
      if (!sizing.has(out)) {
        fs.mkdirSync(path.dirname(out), { recursive: true });
        const tmp = out + '.tmp.' + outExt;
        sizing.set(out, run('ffmpeg', ['-y', '-v', 'error', '-i', full, '-frames:v', '1', '-vf', `scale='min(${w},iw)':-2`, ...(outExt === 'jpg' ? ['-q:v', '4'] : []), tmp])
          .then((ok) => { if (ok && fs.existsSync(tmp) && fs.statSync(tmp).size < st.size) fs.renameSync(tmp, out); else fs.rmSync(tmp, { force: true }); })
          .finally(() => sizing.delete(out)));
      }
      await sizing.get(out);
    }
    if (!fs.existsSync(out)) return serve(req, res, relPath);
    return serve(req, res, rel(out));
  }

  // Simple uncompressed zip (design files are already compressed), streamed piece by piece so
  // large videos never have to fit in memory. Uses "data descriptors" so sizes come after the data.
  async function serveZip(res, token) {
    const z = zips.get(token);
    if (!z) { res.writeHead(404).end('This download link has expired'); return; }
    res.writeHead(200, { 'Content-Type': 'application/zip', 'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(z.name)}` });
    const write = (buf) => new Promise((ok) => { if (res.write(buf)) ok(); else res.once('drain', ok); });
    const central = [];
    let offset = 0;
    const used = new Set();
    for (const full of z.paths) {
      const base = path.basename(full);
      let name = base, i = 2;
      while (used.has(name)) { const d = base.lastIndexOf('.'); name = d > 0 ? `${base.slice(0, d)} (${i})${base.slice(d)}` : `${base} (${i})`; i++; }
      used.add(name);
      const nameBuf = Buffer.from(name, 'utf8');
      const local = Buffer.alloc(30);
      local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(0x0808, 6);
      local.writeUInt16LE(nameBuf.length, 26);
      await write(local); await write(nameBuf);
      let crc = 0, size = 0;
      for await (const chunk of fs.createReadStream(full)) { crc = zlib.crc32(chunk, crc); size += chunk.length; await write(chunk); }
      const desc = Buffer.alloc(16);
      desc.writeUInt32LE(0x08074b50, 0); desc.writeUInt32LE(crc >>> 0, 4); desc.writeUInt32LE(size, 8); desc.writeUInt32LE(size, 12);
      await write(desc);
      const c = Buffer.alloc(46);
      c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(0x0808, 8);
      c.writeUInt32LE(crc >>> 0, 16); c.writeUInt32LE(size, 20); c.writeUInt32LE(size, 24);
      c.writeUInt16LE(nameBuf.length, 28); c.writeUInt32LE(offset, 42);
      central.push(Buffer.concat([c, nameBuf]));
      offset += 30 + nameBuf.length + size + 16;
    }
    const cd = Buffer.concat(central);
    const endRec = Buffer.alloc(22);
    endRec.writeUInt32LE(0x06054b50, 0); endRec.writeUInt16LE(central.length, 8); endRec.writeUInt16LE(central.length, 10);
    endRec.writeUInt32LE(cd.length, 12); endRec.writeUInt32LE(offset, 16);
    res.end(Buffer.concat([cd, endRec]));
  }

  return { commands, serve, serveSized, serveZip, resolve, purgeTrash, root: FILES };
}

export function httpError(status, message) { const e = new Error(message); e.status = status; return e; }
