// File links (Haris 2026-11-03): "Copy link" on any file — Client Assets, a task's files, a comment's — gives one short
// link, files.e11hq.com/f/<token>, the same every time for that file. Pasted in the app it's still the file (a chip);
// opened by E11 staff it opens the iPhone or Mac app at the file (universal links: /.well-known/apple-app-site-
// association); for everyone else it's a branded E11 page with the file's preview and Download — no sign-in. A link
// works until its file is deleted; staff can turn it off (and on again). Never for expense claims or Finance files.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const KEY = 'flinks';
const PRIVATE = /^(Claims|Finance)\//;
const IMAGES = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'svg'];
const VIDEOS = ['mp4', 'mov', 'm4v', 'webm'];
const TOKEN = /^[A-Za-z0-9]{6,16}$/;

export function createFileLinks({ store, files, views, base, teamId, bundleId = 'ae.e11.console.ios', brandSvg = '' }) {
  const load = () => { try { return JSON.parse(store.kv.get(KEY) || '{}'); } catch { return {}; } };
  const save = (m) => store.kv.set(KEY, JSON.stringify(m));
  const newToken = () => { const a = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; let s = ''; for (const b of crypto.randomBytes(8)) s += a[b % a.length]; return s; };
  let lastOrigin = '';
  const urlOf = (tok, origin) => `${String(base || origin || lastOrigin).replace(/\/+$/, '')}/f/${tok}`;

  // where a file is used now (a client's folder, a task's files, a comment) — nothing: it's been deleted
  function find(rel) {
    for (const c of store.list('clients')) {
      for (const f of c.folders || []) {
        const a = (f.files || []).find((x) => x && x.path === rel);
        if (a) return { att: a, where: { kind: 'asset', client: c.id, folder: f.id, file: a.id } };
      }
    }
    for (const t of store.list('tasks')) {
      if (t.deleted) continue;
      const a = (t.attachments || []).find((x) => x && x.path === rel);
      if (a) return { att: a, where: { kind: 'task', task: t.id, file: a.id } };
      for (const c of t.comments || []) {
        const b = (c.attachments || []).find((x) => x && x.path === rel);
        if (b && !c.deleted) return { att: b, where: { kind: 'comment', task: t.id, comment: c.id, file: b.id } };
      }
    }
    return null;
  }
  const onDisk = (rel) => { try { return fs.statSync(files.resolve(rel)).isFile(); } catch { return false; } };

  // the link for a file (made once, then always the same)
  function linkFor(u, rel, origin) {
    if (origin) lastOrigin = origin;
    rel = String(rel || '');
    if (!rel || PRIVATE.test(rel) || rel.includes('..')) return { ok: false, error: 'This file can’t have a link' };
    const m = load();
    m.byPath = m.byPath || {}; m.links = m.links || {};
    let tok = m.byPath[rel];
    if (!tok || !m.links[tok]) {
      if (!find(rel)) return { ok: false, error: 'That file isn’t in E11 Console any more' };
      do { tok = newToken(); } while (m.links[tok]);
      m.byPath[rel] = tok; m.links[tok] = { path: rel, by: u.id, at: new Date().toISOString(), off: false };
      save(m);
    }
    return { ok: true, token: tok, url: urlOf(tok, origin), off: !!m.links[tok].off };
  }
  function setOff(u, rel, off, origin) {
    const r = linkFor(u, rel, origin);
    if (!r.ok) return r;
    const m = load();
    m.links[r.token].off = !!off; m.links[r.token].offBy = u.id; m.links[r.token].offAt = new Date().toISOString();
    save(m);
    return { ...r, off: !!off };
  }
  // what a link is (staff: where its file is, to open it in the app)
  function resolveToken(tok) {
    if (!TOKEN.test(String(tok || ''))) return null;
    const l = (load().links || {})[tok];
    if (!l) return null;
    const hit = find(l.path);
    return { ...l, hit, live: !!hit && !l.off && onDisk(l.path) };
  }
  const extOf = (n) => String(n || '').split('.').pop().toLowerCase();
  const size = (n) => (n >= 1e9 ? (n / 1e9).toFixed(1) + ' GB' : n >= 1e6 ? (n / 1e6).toFixed(1) + ' MB' : n >= 1e3 ? Math.round(n / 1e3) + ' KB' : (n || 0) + ' B');
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const year = () => new Date().getFullYear();

  // the branded page: the E11 word mark, E11 AGENCY, the file's preview, its name, type · size, Download
  function page(tok, r) {
    const live = r && r.live;
    const a = live ? r.hit.att : null;
    const name = a ? a.name || path.basename(r.path) : '';
    const ext = a ? extOf(name) : '';
    const meta = a ? `${(ext || 'file').toUpperCase()} · ${size(a.size || 0)}` : '';
    const me = `/f/${tok}`;
    const hasThumb = a && (IMAGES.includes(ext) || a.thumb || ['pdf', 'mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'].includes(ext));
    const preview = !a ? '' : VIDEOS.includes(ext)
      ? `<video controls playsinline preload="metadata" poster="${me}/thumb" src="${me}/view"></video>`
      : IMAGES.includes(ext) ? `<img src="${me}/view" alt="${esc(name)}">`
        : hasThumb ? `<img src="${me}/thumb" alt="${esc(name)}" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'tile',textContent:'${esc((ext || 'file').toUpperCase())}'}))">`
          : `<span class="tile">${esc((ext || 'file').toUpperCase())}</span>`;
    const body = a
      ? `<div class="card"><div class="prev">${preview}</div><div class="fn">${esc(name)}</div><div class="meta">${esc(meta)}</div><a class="btn" href="${me}/file" download>${'<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7 10l5 5 5-5M5 20h14"/></svg>'}Download</a></div>`
      : `<div class="card off"><div class="ic"><svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M6 18 18 6"/></svg></div><b>This link isn’t available</b><small>It was turned off, or the file was removed. Ask the person who sent it for a new one.</small></div>`;
    const og = a ? `<meta property="og:title" content="${esc(name)}"><meta property="og:description" content="${esc(meta)}"><meta property="og:site_name" content="E11 Agency"><meta property="og:url" content="${esc(urlOf(tok))}">${hasThumb && ext !== 'svg' ? `<meta property="og:image" content="${esc(urlOf(tok))}/thumb"><meta name="twitter:card" content="summary_large_image">` : ''}`
      : '<meta property="og:title" content="E11 Agency">';
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${a ? esc(name) + ' · E11 Agency' : 'E11 Agency'}</title>${og}<meta name="robots" content="noindex">
<meta name="color-scheme" content="light dark"><link rel="icon" href="data:,">
<style>
:root{--bg:#f5f5f7;--card:#fff;--prev:#eef0f4;--t:#17181b;--sub:#8a8a8e;--btn:#17181b;--btnt:#fff}
@media (prefers-color-scheme:dark){:root{--bg:#0c0d0f;--card:#17181c;--prev:#202127;--t:#e9eaee;--sub:#8e8e93;--btn:#fff;--btnt:#111}}
*{box-sizing:border-box;margin:0}
html,body{background:var(--bg);color:var(--t);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Inter",system-ui,sans-serif;-webkit-font-smoothing:antialiased}
body{min-height:100vh;min-height:100dvh;display:flex;flex-direction:column;align-items:center;padding:44px 16px calc(22px + env(safe-area-inset-bottom))}
.brand{display:flex;flex-direction:column;align-items:center;gap:8px;margin-bottom:28px;color:var(--t)}
.brand svg{height:34px;width:auto}.brand svg path{fill:currentColor}
.brand span{font-size:10.5px;font-weight:700;letter-spacing:3.2px;color:var(--sub)}
.card{background:var(--card);border-radius:24px;padding:16px;width:100%;max-width:460px}
.prev{border-radius:16px;background:var(--prev);display:flex;align-items:center;justify-content:center;overflow:hidden;min-height:220px;max-height:62vh}
.prev img,.prev video{display:block;max-width:100%;max-height:62vh;object-fit:contain}
.prev video{width:100%;background:#000}
.tile{font-size:34px;font-weight:800;color:var(--sub);letter-spacing:1px}
.fn{font-size:18px;font-weight:650;margin:14px 4px 0;word-break:break-word}.meta{font-size:13.5px;color:var(--sub);margin:3px 4px 0}
.btn{margin-top:16px;height:48px;border-radius:14px;background:var(--btn);color:var(--btnt);font-weight:600;font-size:16px;display:flex;align-items:center;justify-content:center;gap:8px;text-decoration:none}
.off{display:flex;flex-direction:column;align-items:center;text-align:center;gap:8px;padding:34px 18px}
.off .ic{width:54px;height:54px;border-radius:27px;background:var(--prev);display:flex;align-items:center;justify-content:center;color:var(--sub)}
.off b{font-size:18px}.off small{font-size:14px;color:var(--sub);line-height:1.4}
.foot{margin-top:auto;padding-top:28px;font-size:11px;color:var(--sub);letter-spacing:1.6px;font-weight:600}
</style></head><body>
<div class="brand">${brandSvg}<span>E11 AGENCY</span></div>
${body}
<div class="foot">© ${year()} E11 AGENCY</div>
</body></html>`;
  }

  // the public part (no sign-in): the page, the file (Download), its view (pictures, videos — ranges) and picture
  async function serve(req, res, p) {
    if (p === '/.well-known/apple-app-site-association' || p === '/apple-app-site-association') {
      const ids = teamId ? [`${teamId}.${bundleId}`] : [];
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' });
      return res.end(JSON.stringify({ applinks: { details: [{ appIDs: ids, components: [{ '/': '/f/*', comment: 'File links open in the E11 Console app' }] }] } })), true;
    }
    const m = /^\/f\/([A-Za-z0-9]{6,16})(?:\/(file|view|thumb))?\/?$/.exec(p);
    if (!m) return false;
    const [, tok, what] = m;
    const r = resolveToken(tok);
    const head = { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'X-Robots-Tag': 'noindex' };
    if (!what) {
      res.writeHead(r && r.live ? 200 : 404, { ...head, 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache',
        'Content-Security-Policy': "default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'" });
      return res.end(req.method === 'HEAD' ? undefined : page(tok, r)), true;
    }
    if (!r || !r.live) { res.writeHead(404, head); return res.end('Not available'), true; }
    const a = r.hit.att, ext = extOf(a.name || r.path);
    if (what === 'file') {
      const name = String(a.name || path.basename(r.path)).replace(/[\r\n"]/g, '');
      const orig = res.writeHead.bind(res);
      res.writeHead = (st, h) => orig(st, { ...(h || {}), ...head, 'Content-Disposition': `attachment; filename="${name.replace(/[^\x20-\x7e]/g, '_')}"; filename*=UTF-8''${encodeURIComponent(name)}`, 'Cache-Control': 'private, max-age=300' });
      files.serve(req, res, r.path); return true;
    }
    if (what === 'view') {
      if (VIDEOS.includes(ext)) { files.serve(req, res, views ? views.viewPath(r.path) : r.path); return true; }
      if (ext === 'svg') { files.serve(req, res, r.path); return true; }   // (served with its own no-script rules — files.serve)
      if (IMAGES.includes(ext)) { await files.serveSized(req, res, r.path, 1280); return true; }
      res.writeHead(404, head); return res.end(), true;
    }
    // its picture: a smaller copy of a photo, else the picture made for its thumbnail (PDF page, video frame, Office)
    if (IMAGES.includes(ext) && ext !== 'svg') { await files.serveSized(req, res, r.path, 640); return true; }
    let t = a.thumb && onDisk(a.thumb) ? a.thumb : null;
    if (!t) { try { const x = await files.commands.thumb({ id: a.id, path: r.path }); t = x && x.thumb; } catch { t = null; } }
    if (!t) { res.writeHead(404, head); return res.end(), true; }
    files.serve(req, res, t); return true;
  }
  // for staff with the app: where the file is, so the app opens it there
  function where(u, tok, canRead) {
    const r = resolveToken(tok);
    if (!r) return { ok: false, error: 'That link isn’t in E11 Console' };
    if (!r.hit) return { ok: false, error: 'That file has been deleted' };
    if (!canRead(u, r.path)) return { ok: false, error: 'That file is for the people working on it' };
    const a = r.hit.att;
    return { ok: true, path: r.path, off: !!r.off, where: r.hit.where, att: { id: a.id, name: a.name, path: a.path, size: a.size || 0, ...(a.thumb ? { thumb: a.thumb } : {}), ...(a.type ? { type: a.type } : {}) } };
  }
  return { linkFor, setOff, resolveToken, serve, where, urlOf, find };
}
