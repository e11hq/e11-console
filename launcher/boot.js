// What the NAS container runs: the updater (launcher.js) — the newest one, from the releases it has installed
// (/data/app/launcher/launcher.js, put there by the updater itself), or the one in the container image if there's none
// yet or it won't load. When an update brings a newer updater, it's switched to in place: no new image, Pull or Recreate.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const DATA = process.env.DATA_DIR || '/data';
const ADOPTED = path.join(DATA, 'app', 'launcher', 'launcher.js');
const BUNDLED = fileURLToPath(new URL('./launcher.js', import.meta.url));
const log = (...a) => console.log(new Date().toISOString(), '[boot]', ...a);
let cur = null, n = 0, switching = false, stopping = false;

async function load(file) { return import(pathToFileURL(file).href + '?v=' + (++n)); }
async function run(useAdopted = true) {
  let file = BUNDLED, m = null;
  if (useAdopted && fs.existsSync(ADOPTED)) {
    try { m = await load(ADOPTED); file = ADOPTED; } catch (e) { log('the newer updater would not load, using the one in the image:', e.message); }
  }
  if (!m) m = await load(BUNDLED);
  log(`updater: ${file === ADOPTED ? 'the newer one from the releases' : 'the one in the image'}`);
  cur = m.createLauncher({ selfPath: file, onNewLauncher: relaunch });
  try { await cur.start(); }
  catch (e) {
    log('updater failed to start:', e.message);
    if (file === ADOPTED) { try { await cur.stop(); } catch { /* fine */ } return run(false); }
    throw e;
  }
}
async function relaunch() {
  if (switching || stopping) return;
  switching = true;
  try { if (cur) await cur.stop(); } catch (e) { log('stopping the old updater:', e.message); }
  cur = null;
  try { await run(true); } finally { switching = false; }
}
const stop = async () => { stopping = true; try { if (cur) await cur.stop(); } finally { process.exit(0); } };
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
run(true).catch((e) => { log('could not start:', e.message); process.exit(1); });
