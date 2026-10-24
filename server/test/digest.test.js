import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { dubaiNow } from '../src/digest.js';

// A pretend phone that can read what it's sent (same as webpush.test.js)
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
      return JSON.parse(plain.subarray(0, plain.length - 1).toString());
    },
  };
}

// Dubai time = UTC + 4. Monday 26 Oct 2026.
const at = (iso) => Date.parse(iso);
let clock = at('2026-10-26T06:00:00Z'); // 10:00 Dubai, Monday
let app, base, dir;
const delivered = [];
const pushFetch = async (url, opts) => { delivered.push({ url, headers: opts.headers, body: opts.body }); return { status: 201 }; };
const phones = {};

before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11d-'));
  app = createServer({ dataDir: dir, dev: true, pushFetch, now: () => clock, digest: false });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({
    users: [
      { id: 'u-yousef', email: 'yousef@e11-digital.com', role: 'production', active: true, name: 'Yousef Al Hwij', prefs: {} },
      { id: 'u-zahir', email: 'zahir@e11-digital.com', role: 'social', active: true, name: 'Zahir Hameed', prefs: { digestOff: true } },
      { id: 'u-areej', email: 'areej@e11-digital.com', role: 'am', active: true, name: 'Areej Masri', prefs: {} },
      { id: 'u-sam', email: 'sam@e11-digital.com', role: 'production', active: true, name: 'Sam', prefs: {} },
    ],
    tasks: [
      { id: 't1', title: 'Ford | Ranger Raptor – Print Ad', assignees: ['u-yousef'], due: '2026-10-26', prio: { 'u-yousef': 2 } },
      { id: 't2', title: 'ALAIN | Tower render', assignees: ['u-yousef'], due: '2026-10-26', prio: { 'u-yousef': 'urgent' } },
      { id: 't3', title: 'KOREA 360 | Recap', assignees: ['u-yousef'], due: '2026-10-22' },
      { id: 't4', title: 'Lincoln | Teasers', assignees: ['u-yousef'], needsCD: true, reviews: [{ id: 'r1', by: 'u-yousef', state: 'pending', epoch: 0 }] },
      { id: 't5', title: 'Done one', assignees: ['u-yousef'], due: '2026-10-26', done: true },
      { id: 't6', title: 'My part done', assignees: ['u-yousef', 'u-sam'], due: '2026-10-26', partsDone: { 'u-yousef': '2026-10-25T10:00:00Z' } },
      { id: 't7', title: 'Sub', parentId: 't1', assignees: ['u-yousef'], due: '2026-10-26' },
    ],
  }, 'test');
  for (const [email, id] of [['yousef@e11-digital.com', 'y'], ['zahir@e11-digital.com', 'z'], ['areej@e11-digital.com', 'a']]) {
    phones[id] = makePhone('https://web.push.apple.com/' + id);
    await call(email, '/api/push/subscribe', { subscription: phones[id].sub });
  }
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const call = async (who, p, body) => {
  const res = await fetch(base + p, { method: body ? 'POST' : 'GET', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const forPhone = (id) => delivered.filter((d) => d.url.endsWith('/' + id));

test('Dubai time: weekday and minutes', () => {
  const t = dubaiNow(at('2026-10-26T06:30:00Z'));
  assert.deepEqual([t.day, t.weekday, t.minutes], ['2026-10-26', 1, 630]);
  assert.equal(dubaiNow(at('2026-10-26T20:30:00Z')).day, '2026-10-27'); // 00:30 Tuesday in Dubai
});

test('nothing before 10:30', async () => {
  clock = at('2026-10-26T06:29:00Z');
  assert.equal(await app.digest.tick(), 0);
  assert.equal(delivered.length, 0);
  assert.equal((await call('yousef@e11-digital.com', '/api/digest')).body.due, false);
});

test('at 10:30 Production / Social phones get their day — once, not the AM, not someone on holiday', async () => {
  clock = at('2026-10-26T06:30:00Z');
  await app.digest.tick();
  assert.equal(forPhone('y').length, 1);
  assert.equal(forPhone('z').length, 0, 'switched off for the holiday');
  assert.equal(forPhone('a').length, 0, 'Account Managers do not get it');
  const m = phones.y.read(forPhone('y')[0].body);
  assert.equal(m.title, 'Good morning, Yousef');
  assert.equal(m.body, '2 due today · 1 overdue · 1 waiting for CD review. First up: KOREA 360 | Recap');
  assert.equal(m.taskId, undefined, 'not tied to a task');
  const ttl = Number(forPhone('y')[0].headers.TTL);
  assert.ok(ttl > 13 * 3600 - 60 && ttl <= 13.5 * 3600, `expires at midnight (${ttl}s)`);
  clock = at('2026-10-26T09:00:00Z');
  await app.digest.tick();
  assert.equal(forPhone('y').length, 1, 'only once a day');
});

test('an open app gets today’s summary until midnight; nothing at the weekend', async () => {
  clock = at('2026-10-26T19:59:00Z'); // 23:59
  const r = (await call('yousef@e11-digital.com', '/api/digest')).body;
  assert.equal(r.due, true);
  assert.equal(r.title, 'Good morning, Yousef');
  assert.equal((await call('zahir@e11-digital.com', '/api/digest')).body.due, false);
  assert.equal((await call('areej@e11-digital.com', '/api/digest')).body.due, false);
  clock = at('2026-10-31T07:00:00Z'); // Saturday 11:00
  assert.equal((await call('yousef@e11-digital.com', '/api/digest')).body.due, false);
  await app.digest.tick();
  assert.equal(forPhone('y').length, 1);
});

test('a clear day still gets a message; the next weekday sends again', async () => {
  clock = at('2026-11-02T06:31:00Z'); // Monday
  await app.digest.tick();
  assert.equal(forPhone('y').length, 2);
  const r = (await call('sam@e11-digital.com', '/api/digest')).body;
  assert.equal(r.body, 'Nothing due today · 1 overdue. First up: My part done');
});

test('a test send reaches your own phone any time', async () => {
  clock = at('2026-10-31T07:00:00Z');
  const r = (await call('areej@e11-digital.com', '/api/digest/test', {})).body;
  assert.equal(r.phones, 1);
  assert.equal(phones.a.read(forPhone('a')[0].body).title, 'Good morning, Areej');
});
