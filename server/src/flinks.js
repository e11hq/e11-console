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

  const THUMBED = ['pdf', 'mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'];
  const hasPic = (a) => { const e = extOf(a.name || a.path); return IMAGES.includes(e) || !!a.thumb || THUMBED.includes(e); };
  const offCard = `<div class="card off"><div class="ic"><svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M6 18 18 6"/></svg></div><b>This link isn’t available</b><small>It was turned off, or it was removed. Ask the person who sent it for a new one.</small></div>`;
  // a file's card: its preview, name, type · size, Download (me: where its /file, /view, /thumb are)
  function fileCard(me, a) {
    const name = a.name || path.basename(a.path || '');
    const ext = extOf(name);
    const meta = `${(ext || 'file').toUpperCase()} · ${size(a.size || 0)}`;
    const preview = VIDEOS.includes(ext)
      ? `<video controls playsinline preload="metadata" poster="${me}/thumb" src="${me}/view"></video>`
      : IMAGES.includes(ext) ? `<img src="${me}/view" alt="${esc(name)}">`
        : hasPic(a) ? `<img src="${me}/thumb" alt="${esc(name)}" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'tile',textContent:'${esc((ext || 'file').toUpperCase())}'}))">`
          : `<span class="tile">${esc((ext || 'file').toUpperCase())}</span>`;
    return `<div class="card"><div class="prev">${preview}</div><div class="fn">${esc(name)}</div><div class="meta">${esc(meta)}</div><a class="btn" href="${me}/file" download><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7 10l5 5 5-5M5 20h14"/></svg>Download</a>${appBtn}</div>`;
  }
  // (Haris 2026-11-03: "Open in E11 Console" — the Mac / iPhone app's own link, e11console://f/<tok> (the test site's
  //  app: e11console-test://); for Chrome, which never hands web links to an app. Someone without the app: nothing.)
  const appBtn = `<a class="app" href="#" onclick="location.href=(location.host.indexOf('-test')>=0?'e11console-test':'e11console')+'://'+location.pathname.replace(/^\\//,'');return false"><svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>Open in E11 Console</a>`;
  const ogFor = (title, desc, url, img) => `<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:site_name" content="E11 Agency"><meta property="og:url" content="${esc(url)}">${img ? `<meta property="og:image" content="${esc(img)}"><meta name="twitter:card" content="summary_large_image">` : ''}`;
  // the branded page around it: the E11 word mark, E11 AGENCY, …, © E11 AGENCY
  function shell(title, og, body) {
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${title ? esc(title) + ' · E11 Agency' : 'E11 Agency'}</title>${og || '<meta property="og:title" content="E11 Agency">'}<meta name="robots" content="noindex">
<meta name="color-scheme" content="light dark"><link rel="icon" href="data:,">
<style>
:root{--bg:#f5f5f7;--card:#fff;--prev:#eef0f4;--t:#17181b;--sub:#8a8a8e;--btn:#17181b;--btnt:#fff;--link:#0a84ff}
@media (prefers-color-scheme:dark){:root{--bg:#0c0d0f;--card:#17181c;--prev:#202127;--t:#e9eaee;--sub:#8e8e93;--btn:#fff;--btnt:#111;--link:#409cff}}
*{box-sizing:border-box;margin:0}
html,body{background:var(--bg);color:var(--t);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Inter",system-ui,sans-serif;-webkit-font-smoothing:antialiased}
body{min-height:100vh;min-height:100dvh;display:flex;flex-direction:column;align-items:center;padding:44px 16px calc(22px + env(safe-area-inset-bottom))}
a{color:inherit;text-decoration:none}
.brand{display:flex;flex-direction:column;align-items:center;gap:8px;margin-bottom:28px;color:var(--t)}
.brand svg{height:34px;width:auto}.brand svg path{fill:currentColor}
.brand span{font-size:10.5px;font-weight:700;letter-spacing:3.2px;color:var(--sub)}
.card{background:var(--card);border-radius:24px;padding:16px;width:100%;max-width:460px}
.prev{border-radius:16px;background:var(--prev);display:flex;align-items:center;justify-content:center;overflow:hidden;min-height:220px;max-height:62vh}
.prev img,.prev video{display:block;max-width:100%;max-height:62vh;object-fit:contain}
.prev video{width:100%;background:#000}
.tile{font-size:34px;font-weight:800;color:var(--sub);letter-spacing:1px}
.fn{font-size:18px;font-weight:650;margin:14px 4px 0;word-break:break-word}.meta{font-size:13.5px;color:var(--sub);margin:3px 4px 0}
.app{margin-top:12px;height:36px;display:flex;align-items:center;justify-content:center;gap:6px;font-size:14px;font-weight:550;color:var(--sub)}.app:hover{color:inherit}
.btn{margin-top:16px;height:48px;border-radius:14px;background:var(--btn);color:var(--btnt);font-weight:600;font-size:16px;display:flex;align-items:center;justify-content:center;gap:8px}
.off{display:flex;flex-direction:column;align-items:center;text-align:center;gap:8px;padding:34px 18px}
.off .ic{width:54px;height:54px;border-radius:27px;background:var(--prev);display:flex;align-items:center;justify-content:center;color:var(--sub)}
.off b{font-size:18px}.off small{font-size:14px;color:var(--sub);line-height:1.4}
.back{align-self:center;width:100%;max-width:460px;font-size:15px;color:var(--link);margin:0 0 12px 8px}
.wide{width:100%;max-width:760px}.wide.back,.back.w{max-width:760px}
.fh{display:flex;align-items:center;gap:12px;margin:0 4px 16px}
.fic{width:44px;height:44px;border-radius:12px;background:#0a84ff;display:flex;align-items:center;justify-content:center;color:#fff;flex:none}
.fh b{font-size:20px;display:block;word-break:break-word}.fh small{font-size:13px;color:var(--sub)}
.sec{font-size:12px;font-weight:600;letter-spacing:.4px;color:var(--sub);text-transform:uppercase;margin:6px 6px 8px}
.subs{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:10px;margin-bottom:16px}
.sf{background:var(--card);border-radius:16px;padding:12px;display:flex;align-items:center;gap:10px}
.sf i{width:30px;height:24px;border-radius:6px;flex:none}
.sf b{font-size:14px;display:block}.sf small{font-size:12px;color:var(--sub)}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
@media (max-width:560px){.grid{grid-template-columns:repeat(3,1fr);gap:8px}.subs{grid-template-columns:repeat(2,1fr)}}
.gt{background:var(--card);border-radius:14px;padding:6px 6px 8px;display:block}
.th{aspect-ratio:1;border-radius:10px;background:var(--prev);display:flex;align-items:center;justify-content:center;overflow:hidden;position:relative;font-weight:800;font-size:14px;color:var(--sub)}
.th img{width:100%;height:100%;object-fit:cover;display:block}
.th .pl{position:absolute;width:30px;height:30px;border-radius:15px;background:rgba(0,0,0,.45);color:#fff;display:flex;align-items:center;justify-content:center;font-size:12px}
.tn{font-size:12px;margin:6px 2px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.ts{font-size:11px;color:var(--sub);margin:1px 2px 0}
.none{color:var(--sub);font-size:14px;text-align:center;padding:30px}
.foot{margin-top:auto;padding-top:28px;font-size:11px;color:var(--sub);letter-spacing:1.6px;font-weight:600}
</style></head><body>
<div class="brand">${brandSvg}<span>E11 AGENCY</span></div>
${body}
<div class="foot">© ${year()} E11 AGENCY</div>
</body></html>`;
  }
  // the file page (a file link)
  function page(tok, r) {
    if (!r || !r.live) return shell('', '', offCard);
    const a = r.hit.att, name = a.name || path.basename(r.path), ext = extOf(name);
    return shell(name, ogFor(name, `${(ext || 'file').toUpperCase()} · ${size(a.size || 0)}`, urlOf(tok), hasPic(a) && ext !== 'svg' ? urlOf(tok) + '/thumb' : null), fileCard(`/f/${tok}`, a));
  }

  // ---------- folders (Haris 2026-11-03): a Client Assets folder's link — the folder as it is now, its folders and
  // files; a file opens on its own page (preview, Download) — no Download all. Not "Files" itself, only the folders in
  // it. Until the folder is deleted; Turn off link as for files.
  const isFilesTop = (f) => !!f && !f.parentId && f.name === 'Files';
  const kids = (c, f) => (c.folders || []).filter((x) => x.parentId === f.id);
  const tree = (c, f) => kids(c, f).flatMap((x) => [x, ...tree(c, x)]);
  const allFiles = (c, f) => [f, ...tree(c, f)].flatMap((x) => x.files || []);
  const folderOf = (cid, fid) => { const c = store.get('clients', cid); const f = c && (c.folders || []).find((x) => x.id === fid); return c && f ? { c, f } : null; };
  const furlOf = (tok, origin) => `${String(base || origin || lastOrigin).replace(/\/+$/, '')}/d/${tok}`;
  function folderLink(u, cid, fid, origin) {
    if (origin) lastOrigin = origin;
    const hit = folderOf(cid, fid);
    if (!hit) return { ok: false, error: 'That folder isn’t in Client Assets any more' };
    if (isFilesTop(hit.f)) return { ok: false, error: 'Files holds every job’s folder — share a folder inside it' };
    const m = load(); m.byFolder = m.byFolder || {}; m.links = m.links || {};
    const key = `${cid}/${fid}`;
    let tok = m.byFolder[key];
    if (!tok || !m.links[tok]) {
      do { tok = newToken(); } while (m.links[tok]);
      m.byFolder[key] = tok; m.links[tok] = { kind: 'folder', client: cid, folder: fid, by: u.id, at: new Date().toISOString(), off: false };
      save(m);
    }
    return { ok: true, token: tok, url: furlOf(tok, origin), off: !!m.links[tok].off };
  }
  function folderSetOff(u, cid, fid, off, origin) {
    const r = folderLink(u, cid, fid, origin);
    if (!r.ok) return r;
    const m = load(); Object.assign(m.links[r.token], { off: !!off, offBy: u.id, offAt: new Date().toISOString() }); save(m);
    return { ...r, off: !!off };
  }
  function resolveFolder(tok) {
    if (!TOKEN.test(String(tok || ''))) return null;
    const l = (load().links || {})[tok];
    if (!l || l.kind !== 'folder') return null;
    const hit = folderOf(l.client, l.folder);
    return { ...l, hit, live: !!hit && !l.off && !isFilesTop(hit.f) };
  }
  const COLORS = ['#ff9f0a', '#af52de', '#0a84ff', '#34c759', '#30b0c7', '#ff375f', '#5e5ce6'];
  function folderPage(tok, r, subId) {
    if (!r || !r.live) return shell('', '', offCard);
    const { c, f: root } = r.hit;
    const inside = [root, ...tree(c, root)];
    const f = subId ? inside.find((x) => x.id === subId) : root;
    if (!f) return shell('', '', offCard);
    const me = `/d/${tok}`;
    const subs = kids(c, f), fs_ = f.files || [];
    const all = allFiles(c, f);
    const line = [subs.length ? `${subs.length} folder${subs.length === 1 ? '' : 's'}` : '', `${all.length} file${all.length === 1 ? '' : 's'}`, size(all.reduce((n, a) => n + (a.size || 0), 0))].filter(Boolean).join(' · ');
    const parent = f !== root ? inside.find((x) => x.id === f.parentId) || root : null;
    const back = parent ? `<a class="back w" href="${parent === root ? me : `${me}/s/${parent.id}`}">‹ ${esc(parent.name)}</a>` : '';
    const tiles = fs_.map((a) => {
      const e = extOf(a.name);
      const pic = hasPic(a) && e !== 'svg' ? `<img src="${me}/f/${a.id}/thumb" alt="" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('span'),{textContent:'${esc((e || 'file').toUpperCase())}'}))">` : e === 'svg' ? `<img src="${me}/f/${a.id}/view" alt="" loading="lazy">` : `<span>${esc((e || 'file').toUpperCase())}</span>`;
      return `<a class="gt" href="${me}/f/${a.id}"><span class="th">${pic}${VIDEOS.includes(e) ? '<span class="pl">▶</span>' : ''}</span><div class="tn">${esc(a.name || 'File')}</div><div class="ts">${esc(size(a.size || 0))}</div></a>`;
    }).join('');
    const folders = subs.map((x, i) => `<a class="sf" href="${me}/s/${x.id}"><i style="background:${COLORS[i % COLORS.length]}"></i><span><b>${esc(x.name)}</b><small>${allFiles(c, x).length} file${allFiles(c, x).length === 1 ? '' : 's'}</small></span></a>`).join('');
    const body = `${back}<div class="wide"><div class="fh"><span class="fic"><svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M3 6.5A2.5 2.5 0 0 1 5.5 4h4l2 2.2h7A2.5 2.5 0 0 1 21 8.7v8.8a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z"/></svg></span><div><b>${esc(f.name)}</b><small>${esc(line)}</small></div></div>
      ${folders ? `<div class="sec">Folders</div><div class="subs">${folders}</div>` : ''}
      ${tiles ? `<div class="sec">Files</div><div class="grid">${tiles}</div>` : `<div class="none">No files here yet</div>`}${appBtn}</div>`;
    const cover = all.find((a) => hasPic(a) && extOf(a.name) !== 'svg');
    return shell(f.name, ogFor(f.name, line, furlOf(tok), cover ? `${furlOf(tok)}/f/${cover.id}/thumb` : null), body);
  }
  // a file inside a shared folder (any depth)
  function folderFile(r, fileId) {
    if (!r || !r.live) return null;
    const { c, f } = r.hit;
    for (const x of [f, ...tree(c, f)]) { const a = (x.files || []).find((y) => y.id === fileId); if (a && a.path && onDisk(a.path)) return { a, in: x }; }
    return null;
  }

  const HEAD = { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'X-Robots-Tag': 'noindex' };
  const CSP = "default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'";
  const html = (req, res, ok, body) => { res.writeHead(ok ? 200 : 404, { ...HEAD, 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache', 'Content-Security-Policy': CSP }); res.end(req.method === 'HEAD' ? undefined : body); return true; };
  // a file's bytes: the download, its view (pictures, videos — ranges) or its picture
  async function sendAtt(req, res, what, a, rel) {
    const ext = extOf(a.name || rel);
    if (what === 'file') {
      const name = String(a.name || path.basename(rel)).replace(/[\r\n"]/g, '');
      const orig = res.writeHead.bind(res);
      res.writeHead = (st, h) => orig(st, { ...(h || {}), ...HEAD, 'Content-Disposition': `attachment; filename="${name.replace(/[^\x20-\x7e]/g, '_')}"; filename*=UTF-8''${encodeURIComponent(name)}`, 'Cache-Control': 'private, max-age=300' });
      files.serve(req, res, rel); return true;
    }
    if (what === 'view') {
      if (VIDEOS.includes(ext)) { files.serve(req, res, views ? views.viewPath(rel) : rel); return true; }
      if (ext === 'svg') { files.serve(req, res, rel); return true; }   // (served with its own no-script rules — files.serve)
      if (IMAGES.includes(ext)) { await files.serveSized(req, res, rel, 1280); return true; }
      res.writeHead(404, HEAD); res.end(); return true;
    }
    // its picture: a smaller copy of a photo, else the picture made for its thumbnail (PDF page, video frame, Office)
    if (IMAGES.includes(ext) && ext !== 'svg') { await files.serveSized(req, res, rel, 640); return true; }
    let t = a.thumb && onDisk(a.thumb) ? a.thumb : null;
    if (!t) { try { const x = await files.commands.thumb({ id: a.id, path: rel }); t = x && x.thumb; } catch { t = null; } }
    if (!t) { res.writeHead(404, HEAD); res.end(); return true; }
    files.serve(req, res, t); return true;
  }
  // the public part (no sign-in): file links /f/<token>[/file|view|thumb]; folder links /d/<token>, its folders
  // /d/<token>/s/<folder>, its files /d/<token>/f/<file>[/file|view|thumb]
  async function serve(req, res, p) {
    if (p === '/.well-known/apple-app-site-association' || p === '/apple-app-site-association') {
      const ids = teamId ? [`${teamId}.${bundleId}`] : [];
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' });
      res.end(JSON.stringify({ applinks: { details: [{ appIDs: ids, components: [{ '/': '/f/*', comment: 'File links open in the E11 Console app' }, { '/': '/d/*', comment: 'Folder links open in the E11 Console app' }] }] } }));
      return true;
    }
    let m = /^\/f\/([A-Za-z0-9]{6,16})(?:\/(file|view|thumb))?\/?$/.exec(p);
    if (m) {
      const [, tok, what] = m;
      const r = resolveToken(tok);
      if (!what) return html(req, res, r && r.live, page(tok, r));
      if (!r || !r.live) { res.writeHead(404, HEAD); res.end('Not available'); return true; }
      return sendAtt(req, res, what, r.hit.att, r.path);
    }
    m = /^\/d\/([A-Za-z0-9]{6,16})(?:\/s\/([\w-]{1,80}))?\/?$/.exec(p);
    if (m) { const r = resolveFolder(m[1]); const body = folderPage(m[1], r, m[2] || null); return html(req, res, r && r.live && !body.includes('This link isn’t available'), body); }
    m = /^\/d\/([A-Za-z0-9]{6,16})\/f\/([\w-]{1,80})(?:\/(file|view|thumb))?\/?$/.exec(p);
    if (m) {
      const [, tok, fid, what] = m;
      const r = resolveFolder(tok), hit = folderFile(r, fid);
      if (!what) {
        if (!hit) return html(req, res, false, shell('', '', offCard));
        const { a } = hit, name = a.name || 'File', ext = extOf(name);
        const back = `<a class="back" href="/d/${tok}${hit.in.id === r.hit.f.id ? '' : '/s/' + hit.in.id}">‹ ${esc(hit.in.name)}</a>`;
        return html(req, res, true, shell(name, ogFor(name, `${(ext || 'file').toUpperCase()} · ${size(a.size || 0)}`, `${furlOf(tok)}/f/${fid}`, hasPic(a) && ext !== 'svg' ? `${furlOf(tok)}/f/${fid}/thumb` : null), back + fileCard(`/d/${tok}/f/${fid}`, a)));
      }
      if (!hit) { res.writeHead(404, HEAD); res.end('Not available'); return true; }
      return sendAtt(req, res, what, hit.a, hit.a.path);
    }
    return false;
  }
  // for staff with the app: where the file is, so the app opens it there
  function where(u, tok, canRead) {
    const fr = resolveFolder(tok);
    if (fr) {
      if (!fr.hit) return { ok: false, error: 'That folder has been deleted' };
      if (!canRead(u, (fr.hit.f.dir || fr.hit.c.dir || 'Clients/x') + '/_')) return { ok: false, error: 'That folder is for the people working on it' };
      return { ok: true, off: !!fr.off, where: { kind: 'folder', client: fr.client, folder: fr.folder }, name: fr.hit.f.name };
    }
    const r = resolveToken(tok);
    if (!r) return { ok: false, error: 'That link isn’t in E11 Console' };
    if (!r.hit) return { ok: false, error: 'That file has been deleted' };
    if (!canRead(u, r.path)) return { ok: false, error: 'That file is for the people working on it' };
    const a = r.hit.att;
    return { ok: true, path: r.path, off: !!r.off, where: r.hit.where, att: { id: a.id, name: a.name, path: a.path, size: a.size || 0, ...(a.thumb ? { thumb: a.thumb } : {}), ...(a.type ? { type: a.type } : {}) } };
  }
  // (which of these are turned off: file paths, and folders as "d:<client>/<folder>")
  const offOf = (paths) => { const m = load(); return paths.filter((x) => { const t = /^d:/.test(x) ? (m.byFolder || {})[x.slice(2)] : (m.byPath || {})[x]; return t && m.links[t] && m.links[t].off; }); };
  return { linkFor, setOff, resolveToken, serve, where, urlOf, find, offOf, folderLink, folderSetOff, resolveFolder };
}
