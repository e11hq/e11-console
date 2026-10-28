// Link previews for comments: the server (never people's browsers) reads a pasted link's page and returns its site
// name, title, description and picture, so the site never sees who is looking. Pictures and site icons are fetched
// and served by the server too. Only public web addresses: anything that resolves to a private, local or internal
// address is refused (checked on every connection, redirects included). Answers are kept for a day.
// WeTransfer: the number of files, total size and expiry date when WeTransfer shares them; otherwise just the card.
import http from 'node:http';
import https from 'node:https';
import dns from 'node:dns';
import net from 'node:net';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const UA = 'Mozilla/5.0 (compatible; E11ConsoleLinkPreview/1.0; +https://console.e11hq.com)';
const HTML_MAX = 1_000_000, IMG_MAX = 4_000_000, TIMEOUT = 7000, KEEP = 24 * 3600_000;

// private, loopback, link-local, carrier-grade NAT, multicast and other non-public ranges
export function privateIp(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split('.').map(Number);
    return a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31)
      || (a === 192 && b === 168) || (a === 192 && b === 0) || (a === 198 && (b === 18 || b === 19)) || a >= 224;
  }
  if (net.isIPv6(ip)) {
    const s = ip.toLowerCase();
    if (s === '::' || s === '::1') return true;
    const m = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(s);
    if (m) return privateIp(m[1]);
    return /^(fc|fd|fe8|fe9|fea|feb|ff)/.test(s) || s.startsWith('64:ff9b:') || s.startsWith('2001:db8');
  }
  return true;
}
function safeLookup(host, opts, cb) {
  dns.lookup(host, { ...opts, all: true }, (err, addrs) => {
    if (err) return cb(err);
    const list = (addrs || []).filter((a) => !privateIp(a.address));
    if (!list.length || list.length !== addrs.length) return cb(Object.assign(new Error('Not a public address'), { code: 'EPRIVATE' }));
    if (opts && opts.all) return cb(null, list);
    cb(null, list[0].address, list[0].family);
  });
}
export function publicUrl(u) {
  let x;
  try { x = new URL(String(u)); } catch { return null; }
  if (!/^https?:$/.test(x.protocol) || x.username || x.password) return null;
  if (x.port && !['80', '443'].includes(x.port)) return null;
  const h = x.hostname.replace(/^\[|\]$/g, '');
  if (net.isIP(h) && privateIp(h)) return null;
  if (!h.includes('.') || /\.(local|internal|lan|home|localhost)$/i.test(h) || /^localhost$/i.test(h)) return null;
  return x;
}

// GET (or POST with a JSON body) with redirects followed by hand, each hop checked; a size cap and a time limit
export function fetchSafe(u, { max = HTML_MAX, accept = 'text/html,application/xhtml+xml', method = 'GET', body = null, headers = {}, hops = 5 } = {}) {
  return new Promise((resolve, reject) => {
    const url = publicUrl(u);
    if (!url) return reject(new Error('Not a public web address'));
    const lib = url.protocol === 'https:' ? https : http;
    const req = lib.request(url, { method, lookup: safeLookup, timeout: TIMEOUT, headers: { 'User-Agent': UA, Accept: accept, 'Accept-Language': 'en', ...(body ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } : {}), ...headers } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        if (hops <= 0) return reject(new Error('Too many redirects'));
        const next = new URL(res.headers.location, url).toString();
        return fetchSafe(next, { max, accept, method: res.statusCode === 307 || res.statusCode === 308 ? method : 'GET', body: res.statusCode === 307 || res.statusCode === 308 ? body : null, headers, hops: hops - 1 }).then(resolve, reject);
      }
      const chunks = [];
      let n = 0;
      res.on('data', (c) => { n += c.length; if (n > max) { req.destroy(); resolve({ status: res.statusCode, url: url.toString(), type: String(res.headers['content-type'] || ''), body: Buffer.concat(chunks), cut: true }); return; } chunks.push(c); });
      res.on('end', () => resolve({ status: res.statusCode, url: url.toString(), type: String(res.headers['content-type'] || ''), body: Buffer.concat(chunks) }));
      res.on('error', reject);
    });
    req.on('timeout', () => req.destroy(new Error('Timed out')));
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

const decode = (s) => String(s || '').replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16))).replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
  .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
// <meta property="og:title" content="…"> and friends, <title>, and the site icon
export function readMeta(html, base) {
  const head = String(html).slice(0, 400_000);
  const metas = {};
  for (const m of head.matchAll(/<meta\b[^>]*>/gi)) {
    const tag = m[0];
    const key = (/\b(?:property|name|itemprop)\s*=\s*["']([^"']+)["']/i.exec(tag) || [])[1];
    const val = (/\bcontent\s*=\s*"([^"]*)"/i.exec(tag) || /\bcontent\s*=\s*'([^']*)'/i.exec(tag) || [])[1];
    if (key && val != null && !(key.toLowerCase() in metas)) metas[key.toLowerCase()] = decode(val);
  }
  const title = metas['og:title'] || metas['twitter:title'] || decode((/<title[^>]*>([\s\S]*?)<\/title>/i.exec(head) || [])[1]);
  const abs = (v) => { try { return v ? new URL(v, base).toString() : null; } catch { return null; } };
  let icon = null;
  for (const m of head.matchAll(/<link\b[^>]*>/gi)) {
    const rel = (/\brel\s*=\s*["']([^"']+)["']/i.exec(m[0]) || [])[1] || '';
    const href = (/\bhref\s*=\s*["']([^"']+)["']/i.exec(m[0]) || [])[1];
    if (href && /(^|\s)(icon|shortcut icon|apple-touch-icon)(\s|$)/i.test(rel)) { icon = abs(href); if (/apple-touch-icon/i.test(rel)) break; }
  }
  return {
    title: (title || '').slice(0, 200),
    desc: (metas['og:description'] || metas['twitter:description'] || metas.description || '').slice(0, 300),
    image: abs(metas['og:image'] || metas['og:image:url'] || metas['twitter:image'] || metas['twitter:image:src']),
    site: (metas['og:site_name'] || '').slice(0, 80),
    icon: icon || abs('/favicon.ico'),
  };
}

// Well-known sites: a tidy name even when the page says little
const SITES = [
  [/(^|\.)wetransfer\.com$|(^|\.)we\.tl$/i, 'WeTransfer', 'wetransfer'],
  [/(^|\.)drive\.google\.com$|(^|\.)docs\.google\.com$/i, 'Google Drive', 'gdrive'],
  [/(^|\.)dropbox\.com$|(^|\.)db\.tt$/i, 'Dropbox', 'dropbox'],
  [/(^|\.)youtube\.com$|(^|\.)youtu\.be$/i, 'YouTube', 'youtube'],
  [/(^|\.)figma\.com$/i, 'Figma', 'figma'],
  [/(^|\.)instagram\.com$/i, 'Instagram', 'instagram'],
  [/(^|\.)vimeo\.com$/i, 'Vimeo', 'vimeo'],
  [/(^|\.)frame\.io$/i, 'Frame.io', 'frameio'],
  [/(^|\.)onedrive\.live\.com$|(^|\.)1drv\.ms$|sharepoint\.com$/i, 'OneDrive', 'onedrive'],
  [/(^|\.)canva\.com$/i, 'Canva', 'canva'],
  [/(^|\.)behance\.net$/i, 'Behance', 'behance'],
  [/(^|\.)linkedin\.com$/i, 'LinkedIn', 'linkedin'],
  [/(^|\.)tiktok\.com$/i, 'TikTok', 'tiktok'],
];
export const siteOf = (host) => { for (const [re, name, key] of SITES) if (re.test(host)) return { name, key }; return null; };

// WeTransfer: the transfer's id and security hash from its page address; WeTransfer's own page asks its API for the
// transfer's details the same way (unofficial, so anything missing just leaves the card plain)
async function weTransfer(finalUrl, fetcher) {
  const m = /\/downloads\/([0-9a-f]{20,})\/(?:[0-9a-f]{20,}\/)?([0-9a-f]{4,})/i.exec(new URL(finalUrl).pathname);
  if (!m) return null;
  try {
    const r = await fetcher(`https://wetransfer.com/api/v4/transfers/${m[1]}/prepare-download`, { method: 'POST', body: JSON.stringify({ security_hash: m[2] }), accept: 'application/json', max: 300_000,
      headers: { 'X-Requested-With': 'XMLHttpRequest', Origin: 'https://wetransfer.com', Referer: finalUrl } });
    if (r.status >= 400) return null;
    const j = JSON.parse(r.body.toString('utf8'));
    const files = Array.isArray(j.files) ? j.files : Array.isArray(j.items) ? j.items : null;
    return {
      files: files ? files.length : (Number(j.files_count || j.number_of_files) || null),
      size: Number(j.size || j.total_size) || (files ? files.reduce((a, f) => a + (Number(f.size) || 0), 0) : null) || null,
      expires: j.expires_at || j.expiry_date || null,
      state: j.state || null,
      names: files ? files.slice(0, 3).map((f) => String(f.name || '')).filter(Boolean) : [],
      title: String(j.display_name || '').slice(0, 120),
    };
  } catch { return null; }
}

async function oEmbed(key, url, fetcher) {
  const api = key === 'youtube' ? `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(url)}` : `https://vimeo.com/api/oembed.json?url=${encodeURIComponent(url)}`;
  try {
    const r = await fetcher(api, { accept: 'application/json', max: 200_000 });
    if (r.status >= 400) return null;
    const j = JSON.parse(r.body.toString('utf8'));
    return { title: String(j.title || '').slice(0, 200), author: String(j.author_name || '').slice(0, 120), image: j.thumbnail_url && /^https:\/\//.test(j.thumbnail_url) ? j.thumbnail_url : null };
  } catch { return null; }
}

export function createLinks({ store, dataDir, fetcher = fetchSafe, now = () => Date.now(), log = console }) {
  const dir = path.join(dataDir, '.thumbs', '_links');
  const key = (u) => crypto.createHash('sha256').update('v2:' + String(u)).digest('hex').slice(0, 32);   // (v2: YouTube / Vimeo details)
  const mem = new Map();
  const inflight = new Map();
  const cached = (k) => {
    const v = mem.get(k) || (() => { try { return JSON.parse(store.kv.get('lp:' + k) || 'null'); } catch { return null; } })();
    return v && now() - v.at < KEEP ? v : null;
  };
  const save = (k, v) => { mem.set(k, v); try { store.kv.set('lp:' + k, JSON.stringify(v)); } catch { /* fine */ } if (mem.size > 500) mem.delete(mem.keys().next().value); };

  async function look(raw) {
    const url = publicUrl(raw);
    if (!url) return { ok: false, url: raw, error: 'Not a public web address' };
    const k = key(url.toString());
    const hit = cached(k);
    if (hit) return hit.v;
    if (inflight.has(k)) return inflight.get(k);
    const p = (async () => {
      const host = url.hostname.replace(/^www\./, '');
      let out = { ok: true, url: url.toString(), host, site: (siteOf(url.hostname) || {}).name || host, key: (siteOf(url.hostname) || {}).key || null, title: '', desc: '', image: null, icon: null };
      try {
        const r = await fetcher(url.toString());
        const finalUrl = r.url || url.toString();
        const fhost = new URL(finalUrl).hostname;
        const s = siteOf(fhost) || siteOf(url.hostname);
        if (s) { out.site = s.name; out.key = s.key; }
        if (/html|xml/i.test(r.type) || !r.type) {
          const m = readMeta(r.body.toString('utf8'), finalUrl);
          out = { ...out, title: m.title, desc: m.desc, image: m.image, icon: m.icon, site: s ? s.name : m.site || out.site };
        }
        // YouTube and Vimeo show a sign-in or cookie page to servers: their own oEmbed gives the video's title,
        // channel and picture
        if ((out.key === 'youtube' || out.key === 'vimeo') && (!out.title || !out.image || /^(youtube|vimeo)$/i.test(out.title))) {
          const o = await oEmbed(out.key, url.toString(), fetcher);
          if (o) { out.title = o.title || out.title; out.desc = o.author ? `${o.author}` : out.desc; out.image = o.image || out.image; }
        }
        if (out.key === 'wetransfer') {
          const w = await weTransfer(finalUrl, fetcher);
          if (w) out.wt = w;
          if (!out.title || /^wetransfer$/i.test(out.title)) out.title = w && w.title ? w.title : 'WeTransfer files';
        }
        // a page title that's only the site's name says nothing
        if (out.title && out.site && out.title.toLowerCase() === out.site.toLowerCase() && out.key !== 'wetransfer') out.title = '';
      } catch (e) {
        out.error = e.code === 'EPRIVATE' ? 'Not a public web address' : 'Couldn’t read the page';
        if (e.code === 'EPRIVATE') out.ok = false;
      }
      save(k, { at: now(), v: out });
      return out;
    })().finally(() => inflight.delete(k));
    inflight.set(k, p);
    return p;
  }

  // a picture or icon from a preview, fetched once and kept on disk (pictures only, up to 4 MB; no SVG, which can
  // carry scripts)
  async function image(raw) {
    const url = publicUrl(raw);
    if (!url) return null;
    const k = key('img:' + url.toString());
    const file = path.join(dir, k), metaFile = file + '.type';
    try {
      const st = fs.statSync(file);
      if (now() - st.mtimeMs < 7 * KEEP) return { file, type: fs.readFileSync(metaFile, 'utf8') };
    } catch { /* not kept yet */ }
    const r = await fetcher(url.toString(), { max: IMG_MAX, accept: 'image/avif,image/webp,image/png,image/jpeg,image/gif,image/x-icon,image/*' });
    const type = String(r.type || '').split(';')[0].trim().toLowerCase();
    if (r.status >= 400 || r.cut || !/^image\/(png|jpe?g|gif|webp|avif|x-icon|vnd\.microsoft\.icon)$/.test(type)) return null;
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(file, r.body);
    fs.writeFileSync(metaFile, type);
    return { file, type };
  }
  return { look, image };
}
