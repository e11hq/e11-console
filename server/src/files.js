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

// A small PDF made of JPEG images, one per A4 page. full: the image fills the page (the claim sheet);
// otherwise it is fitted inside a margin (a receipt photo).
function jpegSize(buf) {
  let i = 2;
  while (i < buf.length) {
    if (buf[i] !== 0xff) { i++; continue; }
    const m = buf[i + 1];
    if (m >= 0xc0 && m <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(m)) return { h: buf.readUInt16BE(i + 5), w: buf.readUInt16BE(i + 7) };
    i += 2 + buf.readUInt16BE(i + 2);
  }
  return { w: 1, h: 1 };
}
export function jpegPdf(images, full) {
  const W = 595.28, H = 841.89, M = full ? 0 : 28;
  const chunks = []; const offsets = []; let len = 0;
  const put = (b) => { const buf = Buffer.isBuffer(b) ? b : Buffer.from(b, 'binary'); chunks.push(buf); len += buf.length; };
  const obj = (n, body) => { offsets[n] = len; put(`${n} 0 obj\n`); body(); put('\nendobj\n'); };
  put('%PDF-1.4\n%\xe2\xe3\xcf\xd3\n');
  const list = images.length ? images : [];
  const pageIds = list.map((_, k) => 3 + k * 3);
  obj(1, () => put('<< /Type /Catalog /Pages 2 0 R >>'));
  obj(2, () => put(`<< /Type /Pages /Kids [${pageIds.map((id) => `${id} 0 R`).join(' ')}] /Count ${list.length} >>`));
  list.forEach((img, k) => {
    const pid = 3 + k * 3, cid = pid + 1, iid = pid + 2;
    const { w, h } = jpegSize(img);
    const s = Math.min((W - 2 * M) / w, (H - 2 * M) / h);
    const dw = full ? W : w * s, dh = full ? H : h * s, x = (W - dw) / 2, y = (H - dh) / 2;
    const content = `q ${dw.toFixed(2)} 0 0 ${dh.toFixed(2)} ${x.toFixed(2)} ${y.toFixed(2)} cm /Im0 Do Q`;
    obj(pid, () => put(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /XObject << /Im0 ${iid} 0 R >> >> /Contents ${cid} 0 R >>`));
    obj(cid, () => put(`<< /Length ${content.length} >>\nstream\n${content}\nendstream`));
    obj(iid, () => { put(`<< /Type /XObject /Subtype /Image /Width ${w} /Height ${h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${img.length} >>\nstream\n`); put(img); put('\nendstream'); });
  });
  const n = 3 + list.length * 3;
  const xref = len;
  put(`xref\n0 ${n}\n0000000000 65535 f \n`);
  for (let k = 1; k < n; k++) put(`${String(offsets[k]).padStart(10, '0')} 00000 n \n`);
  put(`trailer\n<< /Size ${n} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
  return Buffer.concat(chunks);
}

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
      if (!d.startsWith('Clients/') && !d.startsWith('Finance/') && !d.startsWith('Claims/')) throw httpError(400, 'Invalid folder');
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

  // A second name for a file in another folder (a hard link — no extra space, and it stays if the first is removed);
  // a copy where links aren't possible
  function linkInto(srcRel, destDirRel, name) {
    const src = resolve(srcRel);
    const dir = resolve(destDirRel);
    if (!String(destDirRel).startsWith('Clients/')) throw httpError(400, 'Invalid folder');
    fs.mkdirSync(dir, { recursive: true });
    const dest = uniquePath(dir, safeName(name || path.basename(src)));
    try { fs.linkSync(src, dest); } catch { fs.copyFileSync(src, dest, fs.constants.COPYFILE_EXCL); }
    return { path: rel(dest), name: path.basename(dest), size: fs.statSync(dest).size };
  }

  const zips = new Map();

  const commands = {
    // Upload in pieces: the first call creates the file, later calls add to it.
    // With an offset, each piece is written at its own place, so pieces can arrive in any order and a piece
    // sent twice (the phone lost the answer and tried again) is simply written again — never doubled.
    // Without one (older apps), pieces are appended in order.
    writeChunk(a) {
      const data = Buffer.isBuffer(a.data) ? a.data : Buffer.from(String(a.b64 || ''), 'base64');
      const at = a.offset == null || a.offset === '' ? null : Number(a.offset);
      if (at != null && (!Number.isFinite(at) || at < 0)) throw httpError(400, 'Bad offset');
      let dest;
      if (!a.path) {
        const dir = uploadDir(a);
        fs.mkdirSync(dir, { recursive: true });
        dest = uniquePath(dir, safeName(a.name));
        fs.writeFileSync(dest, data, { flag: 'wx' });
      } else {
        dest = resolve(a.path);
        if (!fs.existsSync(dest)) throw httpError(400, 'Upload file missing');
        if (at == null) fs.appendFileSync(dest, data);
        else { const fd = fs.openSync(dest, 'r+'); try { fs.writeSync(fd, data, 0, data.length, at); } finally { fs.closeSync(fd); } }
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
    // Phone viewer: every page of a PDF (or an Office file's PDF) as an image that fits the screen width.
    // Phones show PDFs at their printed size and can't fit them, so pages are drawn once and kept in
    // .thumbs/<id>/pages/. Up to MAX_PAGES pages; returns { pages: [paths], total }.
    async pdfPages(a) {
      const MAX_PAGES = 40;
      const src0 = resolve(a.path);
      if (!fs.existsSync(src0)) return { ok: true, pages: [], total: 0 };
      const ext = src0.split('.').pop().toLowerCase();
      let src = src0;
      if (OFFICE.includes(ext)) { const r = await commands.docPreview(a); if (!r.pdf) return { ok: true, pages: [], total: 0, unavailable: !!r.unavailable }; src = resolve(r.pdf); }
      else if (ext !== 'pdf') return { ok: true, pages: [], total: 0 };
      const id = safeName(a.id || crypto.createHash('sha1').update(a.path).digest('hex').slice(0, 12));
      const dir = resolve('.thumbs/' + id + '/pages');
      const list = () => (fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => /^p-\d+\.png$/.test(f)).sort((x, y) => parseInt(x.slice(2), 10) - parseInt(y.slice(2), 10)).map((f) => rel(path.join(dir, f))) : []);
      const done = path.join(dir, 'done.json');
      if (fs.existsSync(done)) { let total = 0; try { total = JSON.parse(fs.readFileSync(done, 'utf8')).total || 0; } catch { /* ignore */ } return { ok: true, pages: list(), total }; }
      fs.mkdirSync(dir, { recursive: true });
      const total = await new Promise((ok) => execFile('pdfinfo', [src], { timeout: 20000 }, (err, out) => ok(err ? 0 : parseInt((String(out).match(/^Pages:\s+(\d+)/m) || [])[1] || '0', 10))));
      const last = Math.max(1, Math.min(total || 1, MAX_PAGES));
      const okRun = await run('pdftoppm', ['-png', '-r', '110', '-scale-to-x', '1240', '-scale-to-y', '-1', '-f', '1', '-l', String(last), src, path.join(dir, 'p')], 120000);
      if (!okRun) { fs.rmSync(dir, { recursive: true, force: true }); return { ok: true, pages: [], total: 0 }; }
      // pdftoppm pads page numbers (p-01.png); keep its names, sorted by number
      fs.writeFileSync(done, JSON.stringify({ total: total || last }));
      return { ok: true, pages: list(), total: total || last };
    },
    // Expense claim PDF: the claim sheet (drawn by the app as A4 page images) followed by the receipts.
    // Image receipts become their own pages; PDF receipts are added as they are (poppler's pdfunite).
    async claimPdf(a) {
      const month = String(a.month || '');
      if (!/^\d{4}-\d{2}$/.test(month)) throw httpError(400, 'Invalid month');
      const dir = resolve(`Claims/${safeName(String(a.userId || 'x'))}/${month}`);
      fs.mkdirSync(dir, { recursive: true });
      const tmp = fs.mkdtempSync(path.join(dir, '.pdf-'));
      try {
        const parts = [];
        const sheet = path.join(tmp, 'sheet.pdf');
        fs.writeFileSync(sheet, jpegPdf((a.pages || []).map((b) => Buffer.from(String(b), 'base64')), true));
        parts.push(sheet);
        let i = 0;
        for (const r of a.receipts || []) {
          const src = resolve(String(r));
          if (!fs.existsSync(src)) continue;
          const ext = src.split('.').pop().toLowerCase();
          if (ext === 'pdf') { parts.push(src); continue; }
          if (!IMAGES.includes(ext)) continue;
          const jpg = path.join(tmp, `r${i++}.jpg`);
          const ok = await run('ffmpeg', ['-y', '-v', 'error', '-i', src, '-frames:v', '1', '-vf', "scale='min(1600,iw)':-2", '-q:v', '3', jpg]);
          if (!ok || !fs.existsSync(jpg)) continue;
          const one = path.join(tmp, `r${i}.pdf`);
          fs.writeFileSync(one, jpegPdf([fs.readFileSync(jpg)], false));
          parts.push(one);
        }
        const name = safeName(String(a.name || 'Expense claim.pdf')).replace(/\.pdf$/i, '') + '.pdf';
        const out = path.join(dir, name);
        let ok = parts.length === 1;
        if (ok) fs.copyFileSync(sheet, out);
        else ok = await run('pdfunite', [...parts, out], 60000);
        if (!ok || !fs.existsSync(out)) fs.copyFileSync(sheet, out);   // receipts couldn't be joined: the sheet alone
        return { ok: true, path: rel(out), name, size: fs.statSync(out).size };
      } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
    },
    // Expenses report (Finance → Expenses → Download report): the report pages drawn by the app as
    // A4 JPEGs become one PDF in Finance/_reports/. With files, a .zip is offered instead: the PDF plus
    // each invoice / receipt under Attachments/<YYYY-MM>/<name the report refers to>.
    expenseReport(a) {
      const dir = resolve('Finance/_reports');
      fs.mkdirSync(dir, { recursive: true });
      for (const f of fs.readdirSync(dir)) { const full = path.join(dir, f); try { if (Date.now() - fs.statSync(full).mtimeMs > 86400_000) fs.rmSync(full, { recursive: true, force: true }); } catch { /* gone */ } }
      const base = safeName(String(a.name || 'E11 expenses report')).replace(/\.pdf$/i, '');
      const sub = fs.mkdtempSync(path.join(dir, 'r-'));
      const out = path.join(sub, base + '.pdf');
      fs.writeFileSync(out, jpegPdf((a.pages || []).map((b) => Buffer.from(String(b), 'base64')), true));
      const res = { ok: true, path: rel(out), name: base + '.pdf', size: fs.statSync(out).size };
      if (!a.zip) return res;
      const entries = [{ full: out, name: base + '.pdf' }];
      for (const f of a.files || []) {
        let full; try { full = resolve(String(f.path || '')); } catch { continue; }
        if (!fs.existsSync(full) || !fs.statSync(full).isFile()) continue;
        const as = String(f.as || path.basename(full)).split('/').map((x) => safeName(x)).filter(Boolean).slice(-2).join('/');
        entries.push({ full, name: 'Attachments/' + as });
      }
      const token = crypto.randomBytes(12).toString('hex');
      zips.set(token, { name: base + '.zip', entries, at: Date.now() });
      for (const [k, v] of zips) if (Date.now() - v.at > 3600_000) zips.delete(k);
      return { ...res, zip: true, url: `/api/zip/${token}`, name: base + '.zip', count: entries.length };
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
    for (const { full, name: want } of z.entries || z.paths.map((f) => ({ full: f, name: path.basename(f) }))) {
      const base = want;
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

  return { commands, serve, serveSized, serveZip, resolve, purgeTrash, linkInto, root: FILES };
}

export function httpError(status, message) { const e = new Error(message); e.status = status; return e; }
