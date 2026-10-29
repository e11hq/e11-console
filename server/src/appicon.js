// The Mac app's Dock icon, chosen by the owner (ADMIN_EMAIL) and fetched by every Mac app.
// Stored in the database as a PNG; "default" means the icon that ships with the installer.
import fs from 'node:fs';
import crypto from 'node:crypto';

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const MAX = 4 * 1024 * 1024;

export function createAppIcon({ store, defaultFile }) {
  const read = () => { try { return JSON.parse(store.kv.get('appicon') || 'null'); } catch { return null; } };
  // The default icon's fingerprint: when the icon that ships with the app changes, Mac apps installed
  // earlier switch to it too (they apply it like a custom one)
  let defHash;
  const def = () => {
    if (defHash === undefined) { try { defHash = crypto.createHash('sha1').update(fs.readFileSync(defaultFile)).digest('hex').slice(0, 10); } catch { defHash = null; } }
    return defHash;
  };
  // auto: each app shows the seasonal icon of the day by itself (only on its occasion's days) (the default); the owner can pick one instead
  const isAuto = (x) => !x || x.auto === true || (!x.png && x.auto === undefined);
  function info() {
    const x = read();
    const auto = isAuto(x);
    const custom = !auto && !!(x && x.png);
    // preset: one of the ready-made seasonal icons (the startup animation takes on its look)
    return { v: custom ? String(x.v) : 'default-' + (def() || '0'), custom, def: custom ? null : def(), at: (x && x.at) || null, by: (x && x.by) || null, preset: custom && x.preset ? x.preset : null, auto };
  }
  function png() {
    const x = read();
    if (x && x.png && !isAuto(x)) return Buffer.from(x.png, 'base64');
    return defaultFile && fs.existsSync(defaultFile) ? fs.readFileSync(defaultFile) : null;
  }
  function set(b64, by, preset) {
    const buf = Buffer.from(String(b64 || ''), 'base64');
    if (buf.length < 100 || !buf.subarray(0, 8).equals(PNG)) throw Object.assign(new Error('The icon must be a PNG image'), { status: 400 });
    if (buf.length > MAX) throw Object.assign(new Error('The icon is too large (4 MB at most)'), { status: 413 });
    const w = buf.readUInt32BE(16), h = buf.readUInt32BE(20);
    if (w !== h) throw Object.assign(new Error('The icon must be square'), { status: 400 });
    if (w < 256) throw Object.assign(new Error('The icon must be at least 256 × 256'), { status: 400 });
    const pre = /^[a-z][a-z-]{1,30}$/.test(String(preset || '')) ? String(preset) : null;
    store.kv.set('appicon', JSON.stringify({ v: Date.now(), png: buf.toString('base64'), by, at: new Date().toISOString(), preset: pre, auto: false }));
    return info();
  }
  function reset(by) {
    store.kv.set('appicon', JSON.stringify({ v: Date.now(), png: null, by, at: new Date().toISOString(), auto: false }));
    return info();
  }
  function setAuto(by) {
    store.kv.set('appicon', JSON.stringify({ v: Date.now(), png: null, by, at: new Date().toISOString(), auto: true }));
    return info();
  }
  return { info, png, set, reset, setAuto };
}
