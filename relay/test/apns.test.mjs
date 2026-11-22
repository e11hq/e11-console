import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { makeApns } from '../src/apns.js';

test('Cloudflare’s own notification: Apple’s token signed right, the same notification as the office’s, to each phone', async () => {
  const k = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const pem = k.privateKey.export({ type: 'pkcs8', format: 'pem' });
  const calls = [];
  const go = async (url, o) => { calls.push({ url, o }); return new Response(null, { status: 200 }); };
  const a = makeApns({ key: pem, keyId: 'KEY1234567', teamId: 'TEAM123456', subs: () => ({ u2: [{ token: 'ab'.repeat(32), env: 'production' }, { token: 'cd'.repeat(32), env: 'sandbox' }] }), go });
  const r = await a.sendTo('u2', { title: 'Shoot', body: 'Haris: Are you there?', kind: 'talk', groupId: 'g1', msgId: 'm1', tag: 'g1' });
  assert.equal(r.sent, 2);
  const prod = calls.find((c) => c.url.startsWith('https://api.push.apple.com/3/device/' + 'ab'.repeat(32)));
  assert.ok(prod); assert.ok(calls.some((c) => c.url.startsWith('https://api.sandbox.push.apple.com/3/device/' + 'cd'.repeat(32))));
  const h = prod.o.headers, body = JSON.parse(prod.o.body);
  assert.equal(h['apns-topic'], 'ae.e11.talk.ios');
  assert.equal(body.aps.alert.body, 'Haris: Are you there?'); assert.equal(body.aps['mutable-content'], 1); assert.equal(body.aps['content-available'], 1);
  assert.deepEqual(body.e11, { kind: 'talk', groupId: 'g1', msgId: 'm1', tag: 'g1' });
  const [hd, pl, sig] = h.authorization.slice(7).split('.');
  assert.deepEqual(JSON.parse(Buffer.from(hd, 'base64url')), { alg: 'ES256', kid: 'KEY1234567' });
  assert.equal(JSON.parse(Buffer.from(pl, 'base64url')).iss, 'TEAM123456');
  assert.ok(crypto.verify('sha256', Buffer.from(hd + '.' + pl), { key: k.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(sig, 'base64url')), 'Apple can check it');
  assert.equal((await makeApns({ subs: () => ({}) }).sendTo('u2', {})).sent, 0, 'no key: nothing');
});

test('the message rides in the notification when it fits Apple’s 4 KB — else without it, as before', async () => {
  const { makeApns } = await import('../src/apns.js');
  const { generateKeyPairSync } = await import('node:crypto');
  const pem = generateKeyPairSync('ec', { namedCurve: 'P-256' }).privateKey.export({ type: 'pkcs8', format: 'pem' });
  const calls = [];
  const a = makeApns({ key: pem, keyId: 'K', teamId: 'T', subs: () => ({ u2: [{ token: 'a'.repeat(64), env: 'production' }] }), go: async (u, o) => { calls.push(JSON.parse(o.body)); return { status: 200, json: async () => ({}) }; } });
  const m = { seq: 5, group: 'g1', type: 'msg', at: 1, by: 'u1', id: 'm1', kind: 'text', text: 'Hello' };
  await a.sendTo('u2', { title: 'G', body: 'Haris: Hello', kind: 'talk', groupId: 'g1', msgId: 'm1', m });
  assert.deepEqual(calls[0].e11.m, m, 'small: it rides along');
  await a.sendTo('u2', { title: 'G', body: 'x', kind: 'talk', groupId: 'g1', msgId: 'm2', m: { ...m, text: 'y'.repeat(5000) } });
  assert.equal(calls[1].e11.m, undefined, 'too big: left out');
  assert.ok(JSON.stringify(calls[1]).length < 4096);
  await a.sendTo('u2', { title: 'G', body: 'x', kind: 'talk', groupId: 'g1', msgId: 'm3', m: { ...m, kind: 'photo', file: { id: 'f', kind: 'photo', thumb: 'z'.repeat(3850) } } });
  assert.ok(calls[2].e11.m && calls[2].e11.m.file && calls[2].e11.m.file.thumb === undefined, 'its small picture dropped to fit');
});
