// Start the E11 Console server. Settings come from environment variables (see docker-compose.yml).
import path from 'node:path';
import fs from 'node:fs';
import { createServer } from './server.js';

const env = process.env;
const dataDir = env.DATA_DIR || '/data';
const cfg = {
  dataDir,
  webDir: env.WEB_DIR || path.resolve(path.dirname(new URL(import.meta.url).pathname), '../../web'),
  cfTeam: env.CF_TEAM || '',
  cfAud: env.CF_AUD || '',
  dev: env.AUTH_DEV === '1',
  adminEmail: env.ADMIN_EMAIL || '',
  version: env.APP_VERSION || readVersion(),
  // Optional: keep Cloudflare Access in step with the Team page (freelancers)
  cfAccountId: env.CF_ACCOUNT_ID || '',
  cfApiToken: env.CF_API_TOKEN || '',
  cfGroupId: env.CF_FREELANCER_GROUP_ID || '',
  launcherUrl: env.LAUNCHER_URL || '',
  holidaysUrl: env.HOLIDAYS_ICS_URL || '',
  viewMinSize: env.VIEW_MIN_SIZE ? Number(env.VIEW_MIN_SIZE) : undefined,
  // Fast office use (office.js): the NAS shared folder mounted read-only, and the office-network port
  shareDir: env.SHARE_DIR !== undefined ? env.SHARE_DIR : undefined,   // default /share when it's there
  shareName: env.SHARE_NAME || 'E11 Share',
  officeIp: env.OFFICE_IP || '',                // the office's internet address(es), comma separated
  localUrl: env.LOCAL_URL || '',                // how office Macs reach this copy, e.g. https://192.168.1.20:8443
  localPort: env.LOCAL_PORT ? Number(env.LOCAL_PORT) : 0,   // the port inside the container (8443)
  // Notifications for the native iPhone app (apns.js): the push key from the Apple Developer account
  apnsKeyFile: env.APNS_KEY_FILE || '',
  apnsKeyId: env.APNS_KEY_ID || '',
  apnsTeamId: env.APNS_TEAM_ID || '',
  apnsTopic: env.APNS_TOPIC || 'ae.e11.console.ios',
  // The App Review copy only (review.js): the demo account's password — set on the NAS's "review" app, never elsewhere
  reviewPassword: env.REVIEW_PASSWORD || '',
  reviewEmail: env.REVIEW_EMAIL || '',
};
function readVersion() {
  try { return fs.readFileSync(path.resolve(path.dirname(new URL(import.meta.url).pathname), '../../VERSION'), 'utf8').trim(); } catch { return '0.0.0-dev'; }
}
if (cfg.reviewPassword && cfg.reviewPassword.length < 10) { console.error('REVIEW_PASSWORD is too short (10 characters or more).'); process.exit(1); }
if (cfg.reviewPassword) console.log('App Review copy: its own sign-in, made-up demo data only.');
if (cfg.dev) console.warn('WARNING: AUTH_DEV=1 — sign-in checks are OFF. Never use this on the NAS.');

const app = createServer(cfg);
const port = Number(env.PORT || 8080);

// Daily housekeeping: a copy of the database (last 14 kept) and emptying 30-day-old trash
function housekeeping() {
  try {
    const dir = path.join(dataDir, 'backups');
    const file = path.join(dir, `e11-${new Date().toISOString().slice(0, 10)}.sqlite`);
    if (!fs.existsSync(file)) app.store.backup(file);
    const old = fs.readdirSync(dir).filter((f) => /^e11-\d{4}-\d{2}-\d{2}\.sqlite$/.test(f)).sort();
    while (old.length > 14) fs.rmSync(path.join(dir, old.shift()), { force: true });
    app.files.purgeTrash(30);
  } catch (e) { console.error('housekeeping failed', e); }
}

app.listen(port, '0.0.0.0').then((p) => {
  console.log(`E11 Console ${cfg.version} listening on :${p} (data in ${dataDir}${cfg.cfTeam ? `, Cloudflare team ${cfg.cfTeam}` : ''})`);
  housekeeping();
  setInterval(housekeeping, 6 * 3600_000);
  app.cfSync.schedule();
});
const stop = () => app.close().then(() => process.exit(0));
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
