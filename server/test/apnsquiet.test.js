// Inbox updates read on the Mac or the website reach the iPhone quietly (Haris 2026-11-16): the icon's count as it is now
// (a count-only notification) and the read ones listed for the app to take off Notification Centre; an E11 Talk-style
// "links" word on the live stream when a link is turned off
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http2 from 'node:http2';
import crypto from 'node:crypto';
import { createServer } from '../src/server.js';
import { selfSignedCert } from '../src/selfcert.js';

const OWNER = 'haris@e11-digital.com', AM = 'areej@e11-digital.com', TOK = 'c'.repeat(64);
let app, dir, base, fake, got = [];
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-quiet-'));
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const keyFile = path.join(dir, 'AuthKey_TESTKEY123.p8');
  fs.writeFileSync(keyFile, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  const tls = selfSignedCert();
  fake = http2.createSecureServer({ key: tls.key, cert: tls.cert });
  fake.on('stream', (stream, h) => { let b = ''; stream.on('data', (c) => { b += c; }); stream.on('end', () => { got.push({ h, body: JSON.parse(b) }); stream.respond({ ':status': 200 }); stream.end(); }); });
  await new Promise((r) => fake.listen(0, '127.0.0.1', r));
  const host = `https://127.0.0.1:${fake.address().port}`;
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, apnsKeyFile: keyFile, apnsKeyId: 'TESTKEY123', apnsTeamId: 'TEAM123456', apnsHosts: { production: host, sandbox: host }, apnsConnectOpts: { rejectUnauthorized: false },
    quietWait: 50, digest: false, holidays: false, occRemind: false, birthdays: false, scheduled: false, daily: false, views: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  const old = new Date(Date.now() - 3600_000).toISOString();
  app.store.importAll({ users: [{ id: 'u-h', email: OWNER, name: 'Haris', role: 'admin', active: true }, { id: 'u-a', email: AM, name: 'Areej', role: 'am', active: true }], projects: [], tasks: [],
    notifications: [{ id: 'n1', to: 'u-a', from: 'u-h', kind: 'mention', text: 'a', at: old, read: false }, { id: 'n2', to: 'u-a', from: 'u-h', kind: 'mention', text: 'b', at: old, read: false }] }, 'u-h');
});
after(async () => { await app.close(); fake.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const post = (who, p, body) => fetch(base + p, { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

test('an update read elsewhere: the iPhone gets its new count and which to take off, quietly', async () => {
  assert.equal((await post(AM, '/api/apns/register', { token: TOK, env: 'production' })).status, 200);
  got = [];
  const n1 = app.store.get('notifications', 'n1');
  const r = await post(AM, '/api/push', { changes: [{ kind: 'notifications', id: 'n1', data: { ...n1, read: true } }] });
  assert.equal(r.status, 200);
  await wait(400);
  const badge = got.find((x) => x.h['apns-push-type'] === 'alert');
  const bg = got.find((x) => x.h['apns-push-type'] === 'background');
  assert.ok(badge && bg, 'a count-only notification and a background one ' + JSON.stringify(got.map((x) => x.h['apns-push-type'])));
  assert.deepEqual(badge.body, { aps: { badge: 1 } }, 'no banner, no sound — the count only');
  assert.equal(badge.h['apns-priority'], '5');
  assert.deepEqual(bg.body.aps, { 'content-available': 1 });
  assert.deepEqual(bg.body.e11, { quiet: true, badge: 1, read: ['n1'] });
});

test('a new update brings its own notification — no quiet one for it', async () => {
  got = [];
  await post(AM, '/api/push', { changes: [{ kind: 'notifications', id: 'n3', data: { id: 'n3', to: 'u-a', from: 'u-h', kind: 'mention', text: 'c', at: new Date().toISOString(), read: false } }] });
  await wait(300);
  assert.equal(got.filter((x) => x.body.e11 && x.body.e11.quiet).length, 0);
});
