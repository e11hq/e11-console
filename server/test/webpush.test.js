import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { encryptPayload } from '../src/webpush.js';

// A pretend phone: makes its own keys and can read what the server sends it (RFC 8291, receiving side)
function makePhone(endpoint) {
  const ecdh = crypto.createECDH('prime256v1'); ecdh.generateKeys();
  const auth = crypto.randomBytes(16);
  return {
    sub: { endpoint, keys: { p256dh: ecdh.getPublicKey().toString('base64url'), auth: auth.toString('base64url') } },
    read(body) {
      const salt = body.subarray(0, 16), idlen = body[20], asPublic = body.subarray(21, 21 + idlen), data = body.subarray(21 + idlen);
      const shared = ecdh.computeSecret(asPublic);
      const info = Buffer.concat([Buffer.from('WebPush: info\0'), ecdh.getPublicKey(), asPublic]);
      const ikm = Buffer.from(crypto.hkdfSync('sha256', shared, auth, info, 32));
      const cek = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: aes128gcm\0'), 16));
      const nonce = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: nonce\0'), 12));
      const d = crypto.createDecipheriv('aes-128-gcm', cek, nonce);
      d.setAuthTag(data.subarray(data.length - 16));
      const plain = Buffer.concat([d.update(data.subarray(0, data.length - 16)), d.final()]);
      assert.equal(plain[plain.length - 1], 2, 'last-record padding delimiter');
      return JSON.parse(plain.subarray(0, plain.length - 1).toString());
    },
  };
}

test('encrypted messages can be read only by the phone they are for', () => {
  const a = makePhone('https://push.example/a'), b = makePhone('https://push.example/b');
  const body = encryptPayload(a.sub, JSON.stringify({ hi: 'there' }));
  assert.deepEqual(a.read(body), { hi: 'there' });
  assert.throws(() => b.read(body));
});

let app, base, dir;
const delivered = [];
let status = 201;
const pushFetch = async (url, opts) => { delivered.push({ url, headers: opts.headers, body: opts.body }); return { status }; };

before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11p-'));
  app = createServer({ dataDir: dir, dev: true, pushFetch });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    users: [
      { id: 'u-areej', email: 'areej@e11-digital.com', role: 'am', active: true, name: 'Areej Masri' },
      { id: 'u-carine', email: 'carine@e11-digital.com', role: 'am', active: true, name: 'Carine Abou Jaoude' },
    ],
    tasks: [{ id: 't1', title: 'Ford | Offroad EDM', comments: [], attachments: [] }],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const call = async (who, p, body) => {
  const res = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const CARINE = 'carine@e11-digital.com', AREEJ = 'areej@e11-digital.com';

test('a phone turns notifications on, and new notifications reach it encrypted and signed', async () => {
  const key = (await call(CARINE, '/api/push/key')).body.key;
  assert.equal(Buffer.from(key, 'base64url').length, 65);
  const phone = makePhone('https://web.push.apple.com/abc123');
  assert.equal((await call(CARINE, '/api/push/subscribe', { subscription: phone.sub })).body.devices, 1);
  assert.equal((await call(CARINE, '/api/push/status', { endpoint: phone.sub.endpoint })).body.on, true);
  assert.equal((await call(AREEJ, '/api/push/status', { endpoint: phone.sub.endpoint })).body.on, false);

  // Areej's app saves a notification for Carine
  const n = { id: 'n1', to: 'u-carine', from: 'u-areej', taskId: 't1', kind: 'review', text: 'submitted 1 file for your review on', snippet: '', at: new Date().toISOString(), read: false };
  await call(AREEJ, '/api/push', { changes: [{ kind: 'notifications', id: 'n1', data: n }] });
  await new Promise((r) => setTimeout(r, 100));
  assert.equal(delivered.length, 1);
  const d = delivered[0];
  assert.equal(d.url, phone.sub.endpoint);
  assert.equal(d.headers['Content-Encoding'], 'aes128gcm');
  const msg = phone.read(d.body);
  assert.equal(msg.title, 'Areej Masri');
  assert.equal(msg.body, 'submitted 1 file for your review on “Ford | Offroad EDM”');
  assert.equal(msg.taskId, 't1');
  assert.equal(msg.badge, 1);

  // the VAPID signature checks out against the server's public key, for Apple's push service
  const m = d.headers.Authorization.match(/^vapid t=([^,]+), k=(.+)$/);
  assert.equal(m[2], key);
  const [h, c, s] = m[1].split('.');
  const claims = JSON.parse(Buffer.from(c, 'base64url'));
  assert.equal(claims.aud, 'https://web.push.apple.com');
  const raw = Buffer.from(key, 'base64url');
  const pub = crypto.createPublicKey({ key: { kty: 'EC', crv: 'P-256', x: raw.subarray(1, 33).toString('base64url'), y: raw.subarray(33).toString('base64url') }, format: 'jwk' });
  assert.ok(crypto.verify('sha256', Buffer.from(`${h}.${c}`), { key: pub, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url')));

  // saving the same notification again (marking it read) does not send it twice
  await call(AREEJ, '/api/push', { changes: [{ kind: 'notifications', id: 'n1', data: { ...n, read: true }, base: n }] });
  await new Promise((r) => setTimeout(r, 100));
  assert.equal(delivered.length, 1);
});

test('nobody gets a push for their own actions, and dead phones are forgotten', async () => {
  delivered.length = 0;
  const own = { id: 'n2', to: 'u-carine', from: 'u-carine', taskId: 't1', kind: 'comment', text: 'commented on', at: new Date().toISOString(), read: false };
  await call(CARINE, '/api/push', { changes: [{ kind: 'notifications', id: 'n2', data: own }] });
  await new Promise((r) => setTimeout(r, 100));
  assert.equal(delivered.length, 0);

  status = 410; // the phone deleted the app
  await call(CARINE, '/api/push/test', {});
  assert.equal(delivered.length, 1);
  assert.equal((await call(CARINE, '/api/push/status', { endpoint: 'https://web.push.apple.com/abc123' })).body.devices, 0);
  status = 201;
});

test('bad subscriptions are refused', async () => {
  assert.equal((await call(CARINE, '/api/push/subscribe', { subscription: { endpoint: 'http://insecure', keys: {} } })).status, 400);
});
