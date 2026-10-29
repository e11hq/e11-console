// E11 Console launcher — the only thing the NAS container runs.
// It downloads E11 Console releases from GitHub (e11hq/e11-console), runs the current version,
// and updates it: automatically at a quiet hour, or when an Admin clicks "Update now".
// Before every update it copies the database; if a new version doesn't start, it goes straight
// back to the previous one. No outside packages — only Node 22 and the system `tar`.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';

export function createLauncher(opts = {}) {
  const env = { ...process.env, ...(opts.env || {}) };
  const DATA = env.DATA_DIR || '/data';
  const APP_DIR = path.join(DATA, 'app');
  const VERSIONS = path.join(APP_DIR, 'versions');
  const STATE_FILE = path.join(APP_DIR, 'state.json');
  const DB_FILE = path.join(DATA, 'db', 'e11.sqlite');
  const BACKUPS = path.join(DATA, 'backups');
  const REPO = env.GITHUB_REPO || 'e11hq/e11-console';
  const TOKEN = env.GITHUB_TOKEN || '';
  const API = env.GITHUB_API || 'https://api.github.com';
  const CHANNEL = env.UPDATE_CHANNEL === 'staging' ? 'staging' : 'stable';
  const PORT = Number(env.PORT || 8080);
  const CONTROL_PORT = Number(env.LAUNCHER_PORT || 8090);
  // stable: install at 2 AM · 'now': as soon as a new release is found (the App Review copy, which follows live) · 'off': only on a click
  const NOW = String(env.UPDATE_HOUR || '').toLowerCase() === 'now';
  const UPDATE_HOUR = env.UPDATE_HOUR === 'off' || NOW ? null : Number(env.UPDATE_HOUR || 2);
  const CHECK_MIN = Number(env.CHECK_EVERY_MIN || (CHANNEL === 'staging' ? 5 : 60));
  const HEALTH_TIMEOUT = Number(env.HEALTH_TIMEOUT_MS || 30000);
  const log = opts.log || ((...a) => console.log(new Date().toISOString(), '[launcher]', ...a));
  const fetchImpl = opts.fetch || fetch;

  fs.mkdirSync(VERSIONS, { recursive: true });
  let state = readState();
  let child = null, childVersion = null, busy = false, stopping = false, timer = null, control = null, fallback = null, lastResult = null;

  function readState() {
    try { return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')); } catch { return { current: null, previous: null, history: [], available: null, lastCheck: null, lastError: null }; }
  }
  function saveState() { fs.writeFileSync(STATE_FILE + '.tmp', JSON.stringify(state, null, 1)); fs.renameSync(STATE_FILE + '.tmp', STATE_FILE); }
  const versionDir = (v) => path.join(VERSIONS, v.replace(/[^\w.+-]/g, '_'));
  const installed = (v) => !!v && fs.existsSync(path.join(versionDir(v), 'server', 'src', 'index.js'));
  const gh = (url, accept = 'application/vnd.github+json') => fetchImpl(url.startsWith('http') ? url : API + url, {
    headers: { Accept: accept, 'User-Agent': 'e11-console-launcher', 'X-GitHub-Api-Version': '2022-11-28', ...(TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {}) }, redirect: 'follow',
  });

  /* ---------- running the app ---------- */
  async function startChild(v) {
    await stopFallback();
    const dir = versionDir(v);
    child = spawn(process.execPath, [path.join(dir, 'server', 'src', 'index.js')], {
      env: { ...env, WEB_DIR: path.join(dir, 'web'), APP_VERSION: v, PORT: String(PORT), LAUNCHER_URL: `http://127.0.0.1:${CONTROL_PORT}` },
      stdio: opts.childStdio || 'inherit',
    });
    childVersion = v;
    const me = child;
    child.on('exit', (code, sig) => {
      if (child !== me) return;
      child = null;
      if (stopping) return;
      log(`E11 Console ${v} stopped (${sig || code}); restarting in 3 s`);
      setTimeout(() => { if (!child && !stopping && !busy) startChild(state.current || v); }, 3000);
    });
    log(`started E11 Console ${v}`);
  }
  function stopChild() {
    return new Promise((resolve) => {
      if (!child) return resolve();
      const c = child;
      child = null;
      const t = setTimeout(() => { try { c.kill('SIGKILL'); } catch { /* gone */ } }, 15000);
      c.once('exit', () => { clearTimeout(t); resolve(); });
      try { c.kill('SIGTERM'); } catch { clearTimeout(t); resolve(); }
    });
  }
  async function healthy(v) {
    const until = Date.now() + HEALTH_TIMEOUT;
    while (Date.now() < until) {
      try {
        const r = await fetchImpl(`http://127.0.0.1:${PORT}/api/health`);
        if (r.ok) { const j = await r.json(); if (j.version === v) return true; }
      } catch { /* not up yet */ }
      await new Promise((r) => setTimeout(r, 500));
    }
    return false;
  }
  // Before anything is installed: a simple page explaining what's happening
  function startFallback(message) {
    if (fallback) { fallback.message = message; return; }
    const srv = http.createServer((req, res) => {
      if (req.url === '/api/health') { res.writeHead(503, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify({ ok: false, version: null, message: srv.message })); }
      res.writeHead(503, { 'Content-Type': 'text/html; charset=utf-8', 'Retry-After': '30' });
      res.end(`<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="30"><title>E11 Console</title><body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#0e0e11;color:#ececf1;font:15px/1.5 -apple-system,Segoe UI,sans-serif;text-align:center"><div style="max-width:460px;padding:24px"><div style="font-size:20px;font-weight:700;margin-bottom:8px">E11 Console is getting ready</div><div style="color:#9d9da8">${String(srv.message).replace(/[<>&]/g, '')}</div></div>`);
    });
    srv.message = message;
    srv.listen(PORT, '0.0.0.0');
    fallback = srv;
  }
  function stopFallback() {
    if (!fallback) return Promise.resolve();
    const f = fallback; fallback = null;
    return new Promise((ok) => { f.close(() => ok()); f.closeAllConnections?.(); });
  }

  /* ---------- finding and downloading releases ---------- */
  // stable  = the newest published release (v1.2.0 …)
  // staging = the release tagged "staging", rebuilt on every change for the test copy
  async function latestRelease() {
    const r = await gh(CHANNEL === 'staging' ? `/repos/${REPO}/releases/tags/staging` : `/repos/${REPO}/releases/latest`);
    if (r.status === 404) return null;
    if (!r.ok) throw new Error(r.status === 401 || r.status === 403 ? 'GitHub refused access — check GITHUB_TOKEN' : `GitHub error ${r.status}`);
    const rel = await r.json();
    const asset = (rel.assets || []).find((a) => /^e11-console-.+\.tar\.gz$/.test(a.name));
    if (!asset) return null;
    const version = asset.name.replace(/^e11-console-/, '').replace(/\.tar\.gz$/, '');
    return { version, notes: rel.body || '', name: rel.name || version, publishedAt: rel.published_at || null, assetUrl: asset.url, size: asset.size };
  }
  async function download(rel) {
    if (installed(rel.version)) return;
    const tmp = path.join(APP_DIR, `download-${Date.now()}`);
    fs.mkdirSync(tmp, { recursive: true });
    try {
      const r = await gh(rel.assetUrl, 'application/octet-stream');
      if (!r.ok) throw new Error(`Download failed (${r.status})`);
      const file = path.join(tmp, 'bundle.tar.gz');
      fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
      const out = path.join(tmp, 'x');
      fs.mkdirSync(out);
      execFileSync('tar', ['-xzf', file, '-C', out, '--strip-components=1', '--no-same-owner']);
      if (!fs.existsSync(path.join(out, 'server', 'src', 'index.js'))) throw new Error('The downloaded release is incomplete');
      fs.rmSync(versionDir(rel.version), { recursive: true, force: true });
      fs.renameSync(out, versionDir(rel.version));
      fs.writeFileSync(path.join(versionDir(rel.version), 'RELEASE.json'), JSON.stringify({ version: rel.version, name: rel.name, notes: rel.notes, publishedAt: rel.publishedAt }, null, 1));
      log(`downloaded ${rel.version}`);
    } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  }
  async function check() {
    state.lastCheck = new Date().toISOString();
    try {
      const rel = await latestRelease();
      state.available = rel && rel.version !== state.current ? { version: rel.version, name: rel.name, notes: rel.notes, publishedAt: rel.publishedAt } : null;
      state.lastError = null;
      saveState();
      return rel;
    } catch (e) { state.lastError = e.message; saveState(); log('update check failed:', e.message); return null; }
  }

  /* ---------- switching versions ---------- */
  function backupDb(label) {
    if (!fs.existsSync(DB_FILE)) return null;
    fs.mkdirSync(BACKUPS, { recursive: true });
    const name = `before-${label}-${new Date().toISOString().replace(/[:.]/g, '-')}.sqlite`;
    fs.copyFileSync(DB_FILE, path.join(BACKUPS, name));
    for (const ext of ['-wal', '-shm']) if (fs.existsSync(DB_FILE + ext)) fs.copyFileSync(DB_FILE + ext, path.join(BACKUPS, name + ext));
    const old = fs.readdirSync(BACKUPS).filter((f) => /^before-.+\.sqlite$/.test(f)).sort();
    while (old.length > 10) { const f = old.shift(); for (const ext of ['', '-wal', '-shm']) fs.rmSync(path.join(BACKUPS, f + ext), { force: true }); }
    return name;
  }
  async function switchTo(v, reason) {
    const from = state.current;
    log(`switching ${from || '(none)'} → ${v} (${reason})`);
    await stopChild();
    const backup = backupDb(`${reason}-${from || 'none'}-to-${v}`.replace(/[^\w.+-]/g, '_'));
    await startChild(v);
    if (await healthy(v)) {
      if (from !== v) { state.previous = from; state.current = v; }
      state.history = [{ version: v, at: new Date().toISOString(), reason, backup }, ...(state.history || [])].slice(0, 30);
      if (state.available && state.available.version === v) state.available = null;
      state.lastError = null;
      saveState();
      pruneVersions();
      log(`now running ${v}`);
      if (reason !== 'rollback') adoptLauncher(v);
      return { ok: true, version: v };
    }
    // Didn't start: go back
    log(`${v} did not start — going back to ${from}`);
    await stopChild();
    state.lastError = `Version ${v} did not start, so E11 Console went back to ${from || 'the previous version'}.`;
    saveState();
    if (from && installed(from)) { await startChild(from); await healthy(from); }
    return { ok: false, error: state.lastError };
  }
  // The updater updates itself: each release carries its own launcher.js; when it differs from the one running, it's
  // kept in /data/app/launcher and boot.js switches to it (no new container image, Pull or Recreate needed)
  function adoptLauncher(v) {
    try {
      const src = path.join(versionDir(v), 'launcher', 'launcher.js');
      if (!fs.existsSync(src) || !opts.selfPath || !opts.onNewLauncher) return;
      const next = fs.readFileSync(src, 'utf8');
      if (!next.includes('export function createLauncher')) return;
      let mine = ''; try { mine = fs.readFileSync(opts.selfPath, 'utf8'); } catch { /* none */ }
      if (next === mine) return;
      const dir = path.join(APP_DIR, 'launcher'); fs.mkdirSync(dir, { recursive: true });
      const tmp = path.join(dir, 'launcher.js.new'); fs.writeFileSync(tmp, next); fs.renameSync(tmp, path.join(dir, 'launcher.js'));
      log(`a new updater came with ${v}: switching to it`);
      setTimeout(() => { opts.onNewLauncher(); }, 1000);
    } catch (e) { log('could not take the new updater:', e.message); }
  }
  function pruneVersions() {
    const keep = new Set([state.current, state.previous].filter(Boolean));
    (state.history || []).slice(0, 4).forEach((h) => keep.add(h.version));
    for (const d of fs.readdirSync(VERSIONS)) if (![...keep].some((v) => versionDir(v) === path.join(VERSIONS, d))) fs.rmSync(path.join(VERSIONS, d), { recursive: true, force: true });
  }
  async function exclusive(fn) {
    if (busy) return { ok: false, error: 'An update is already in progress' };
    busy = true;
    try { return await fn(); } finally { busy = false; }
  }
  const updateNow = (reason = 'update') => exclusive(async () => {
    const rel = await latestRelease().catch((e) => { state.lastError = e.message; saveState(); return null; });
    if (!rel) return { ok: false, error: state.lastError || 'No release found' };
    if (rel.version === state.current && child) return { ok: true, version: rel.version, upToDate: true };
    await download(rel);
    return switchTo(rel.version, reason);
  });
  const rollback = () => exclusive(async () => {
    if (!state.previous || !installed(state.previous)) return { ok: false, error: 'There is no previous version to go back to' };
    const target = state.previous;
    const res = await switchTo(target, 'rollback');
    if (res.ok) state.available = null, saveState();
    return res;
  });

  /* ---------- schedule ---------- */
  function hourNow() {
    return Number(new Intl.DateTimeFormat('en-GB', { hour: '2-digit', hour12: false, timeZone: env.TZ || 'Asia/Dubai' }).format(new Date()));
  }
  async function tick() {
    if (busy) return;
    const rel = await check();
    if (!rel || rel.version === state.current) return;
    // test copy: install straight away · live copy: wait for the quiet hour (or an Admin's click)
    if (CHANNEL === 'staging' || NOW || (UPDATE_HOUR != null && hourNow() === UPDATE_HOUR)) await updateNow('scheduled');
  }

  /* ---------- control API for the app (inside the container only) ---------- */
  function startControl() {
    control = http.createServer(async (req, res) => {
      const send = (code, body) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(body)); };
      try {
        if (req.method === 'GET' && req.url === '/status') return send(200, status());
        if (req.method === 'POST' && req.url === '/check') { await check(); return send(200, status()); }
        // From the app these return at once ("started"): switching versions restarts the app that asked
        const wait = /[?&]wait=1/.test(req.url);
        const route = req.url.split('?')[0];
        if (req.method === 'POST' && (route === '/update' || route === '/rollback')) {
          if (busy) return send(200, { ok: false, error: 'An update is already in progress', status: status() });
          const run = () => (route === '/update' ? updateNow('admin') : rollback());
          if (wait) { const r = await run(); return send(200, { ...r, status: status() }); }
          const at = new Date().toISOString();
          send(202, { ok: true, started: true, status: { ...status(), busy: true } });
          // start a moment later, so the app can pass this answer on before it is restarted
          setTimeout(() => { run().then((r) => { lastResult = { ...r, action: route.slice(1), at }; }).catch((e) => { lastResult = { ok: false, error: e.message, action: route.slice(1), at }; }); }, 1500);
          return;
        }
        send(404, { ok: false });
      } catch (e) { send(500, { ok: false, error: e.message }); }
    });
    return new Promise((ok) => control.listen(CONTROL_PORT, '127.0.0.1', ok));
  }
  function status() {
    let notes = null;
    try { notes = JSON.parse(fs.readFileSync(path.join(versionDir(state.current || ''), 'RELEASE.json'), 'utf8')); } catch { /* none */ }
    return { ok: true, channel: CHANNEL, running: childVersion, lastResult, current: state.current, previous: state.previous, available: state.available, lastCheck: state.lastCheck, lastError: state.lastError, busy, updateHour: NOW ? 'now' : UPDATE_HOUR, history: (state.history || []).slice(0, 10), currentNotes: notes, tokenSet: !!TOKEN };
  }

  async function start() {
    await startControl();
    if (installed(state.current)) await startChild(state.current);
    else {
      startFallback(TOKEN ? 'Downloading the latest version from GitHub…' : 'GITHUB_TOKEN is not set, so the app can’t be downloaded. Add it in Container Station and restart.');
      if (TOKEN) {
        let r = await updateNow('first install');
        while (!r.ok && !stopping) { startFallback(`Couldn’t download E11 Console yet: ${r.error}. Retrying every minute.`); await new Promise((ok) => setTimeout(ok, 60000)); r = await updateNow('first install'); }
      }
    }
    timer = setInterval(() => { tick().catch((e) => log('tick failed', e.message)); }, CHECK_MIN * 60000);
    // (installing as soon as found: a version waiting since before this start goes in now, not an interval later)
    setTimeout(() => { (NOW ? tick() : check()).catch(() => {}); }, 5000);
  }
  async function stop() { stopping = true; clearInterval(timer); await stopFallback(); await stopChild(); if (control) await new Promise((ok) => control.close(ok)); }

  return { start, stop, check, updateNow, rollback, status, tick, _state: () => state };
}

// Run when started directly (in the container)
if (process.argv[1] && import.meta.url === new URL('file://' + path.resolve(process.argv[1])).href) {
  const l = createLauncher();
  l.start();
  const stop = () => l.stop().then(() => process.exit(0));
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
}
