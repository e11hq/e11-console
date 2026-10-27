// iPhone app notifications (APNs): a device token per person; every notification also goes to Apple's push service
// with a valid ES256 token, the right topic and the details to open it; dead tokens are removed
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http2 from 'node:http2';
import crypto from 'node:crypto';
import { createServer } from '../src/server.js';
import { selfSignedCert } from '../src/selfcert.js';

const OWNER = 'haris@e11-digital.com', AM = 'areej@e11-digital.com';
const GOOD = 'a'.repeat(64), DEAD = 'b'.repeat(64);
let app, dir, base, fake, got = [], pub;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-apns-'));
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  pub = publicKey;
  const keyFile = path.join(dir, 'AuthKey_TESTKEY123.p8');
  fs.writeFileSync(keyFile, privateKey.export({ type: 'pkcs8', format: 'pem' }));
  const tls = selfSignedCert();
  fake = http2.createSecureServer({ key: tls.key, cert: tls.cert });
  fake.on('stream', (stream, h) => {
    let body = ''; stream.on('data', (c) => { body += c; });
    stream.on('end', () => {
      got.push({ h, body: JSON.parse(body) });
      const token = h[':path'].split('/').pop();
      if (token === DEAD) { stream.respond({ ':status': 410 }); return stream.end(JSON.stringify({ reason: 'Unregistered' })); }
      stream.respond({ ':status': 200 }); stream.end();
    });
  });
  await new Promise((r) => fake.listen(0, '127.0.0.1', r));
  const host = `https://127.0.0.1:${fake.address().port}`;
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, apnsKeyFile: keyFile, apnsKeyId: 'TESTKEY123', apnsTeamId: 'TEAM123456', apnsHosts: { production: host, sandbox: host }, apnsConnectOpts: { rejectUnauthorized: false },
    digest: false, holidays: false, occRemind: false, birthdays: false, scheduled: false, daily: false, views: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({ users: [{ id: 'u-h', email: OWNER, name: 'Haris', role: 'admin', active: true }, { id: 'u-a', email: AM, name: 'Areej', role: 'am', active: true }], projects: [], tasks: [], statuses: [] }, 'test');
});
after(async () => { await app.close(); fake.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const post = (who, p, body) => fetch(base + p, { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('an iPhone registers; a notification reaches Apple with a valid token and what to open', async () => {
  assert.equal((await post(AM, '/api/apns/register', { token: 'not-a-token' })).status, 400);
  assert.equal((await post(AM, '/api/apns/register', { token: GOOD, env: 'production' })).status, 200);
  assert.equal((await post(AM, '/api/apns/register', { token: DEAD, env: 'sandbox' })).status, 200);
  assert.equal(app.apns.devices('u-a'), 2);
  const r = await app.apns.sendTo('u-a', { title: 'Haris', body: 'mentioned you “Banner”', taskId: 't1', nid: 'n1', kind: 'mention', badge: 3 });
  assert.equal(r.sent, 1); assert.equal(r.removed, 1);
  assert.equal(app.apns.devices('u-a'), 1, 'the dead token is removed');
  const m = got.find((x) => x.h[':path'] === '/3/device/' + GOOD);
  assert.equal(m.h['apns-topic'], 'ae.e11.console.ios');
  assert.equal(m.h['apns-push-type'], 'alert');
  assert.deepEqual(m.body.aps.alert, { title: 'Haris', body: 'mentioned you “Banner”' });
  assert.equal(m.body.aps.badge, 3);
  assert.deepEqual(m.body.e11, { taskId: 't1', nid: 'n1', kind: 'mention' });
  const [head, claims, sig] = m.h.authorization.replace('bearer ', '').split('.');
  assert.deepEqual(JSON.parse(Buffer.from(head, 'base64url')), { alg: 'ES256', kid: 'TESTKEY123' });
  assert.equal(JSON.parse(Buffer.from(claims, 'base64url')).iss, 'TEAM123456');
  assert.ok(crypto.verify('sha256', Buffer.from(head + '.' + claims), { key: pub, dsaEncoding: 'ieee-p1363' }, Buffer.from(sig, 'base64url')), 'signed with the push key');
});
test('every phone notification goes to the iPhone app too; a phone signed in as someone else moves over', async () => {
  got = [];
  const r = await app.webPush.sendTo('u-a', { title: 'Test', body: 'hello', nid: 'n2' });
  assert.equal(r.sent, 1);
  assert.equal(got.length, 1);
  await post(OWNER, '/api/apns/register', { token: GOOD, env: 'production' });
  assert.equal(app.apns.devices('u-a'), 0); assert.equal(app.apns.devices('u-h'), 1);
  await post(OWNER, '/api/apns/unregister', { token: GOOD });
  assert.equal(app.apns.devices('u-h'), 0, 'signing out removes it');
});
