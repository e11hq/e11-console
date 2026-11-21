// E11 Talk, "Ask the group" (Haris 2026-11-20 21:36, claude/talk-ask-the-group-plan.md): a message's file gone from the server
// comes back from a phone in the group that still has it — same group only, within 90 days, not a file deleted for everyone.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import { createServer } from '../src/server.js';

let clock = Date.parse('2026-11-21T10:00:00Z');
let app, base, dir, r2srv;
const objects = new Map();
before(async () => {
  r2srv = http.createServer((req, res) => {
    const u = new URL(req.url, 'http://x'), key = decodeURIComponent(u.pathname);
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks);
      if (req.method === 'PUT') { objects.set(key, body); res.writeHead(200, { ETag: '"x"' }); res.end(); return; }
      const o = objects.get(key);
      if (req.method === 'DELETE') { objects.delete(key); res.writeHead(204); res.end(); return; }
      if (!o) { res.writeHead(404); res.end(); return; }
      if (req.method === 'HEAD') { res.writeHead(200, { 'Content-Length': o.length }); res.end(); return; }
      res.writeHead(200, { 'Content-Length': o.length }); res.end(o);
    });
  });
  await new Promise((r) => r2srv.listen(0, '127.0.0.1', r));
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11talkask-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false, birthdays: false, daily: false, scheduled: false, views: false, holidays: false, pruneInbox: false,
    r2Account: 'acc', r2KeyId: 'kid', r2Secret: 'sec', r2Bucket: 'e11-talk-files', r2Endpoint: `http://127.0.0.1:${r2srv.address().port}` });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({
    users: [
      { id: 'u-am', email: 'am@x.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-des', email: 'des@x.com', role: 'production', active: true, name: 'Yousef' },
      { id: 'u-out', email: 'out@x.com', role: 'production', active: true, name: 'Sara' },
    ],
    clients: [{ id: 'c1', name: 'Northline', folders: [] }],
    projects: [{ id: 'p1', name: 'Northline', color: '#3a7bd5', clientId: 'c1', order: 1, ams: [{ id: 'u-am' }] }],
  }, 'test');
});
after(async () => { await app.close(); r2srv.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const H = (who, dev) => ({ 'X-Dev-Email': who + '@x.com', 'Content-Type': 'application/json', ...(dev ? { 'X-Talk-Device': dev } : {}) });
const post = async (who, dev, p, b) => (await fetch(base + p, { method: 'POST', headers: H(who, dev), body: JSON.stringify(b) })).json();
const get = async (who, dev, p) => (await fetch(base + p, { headers: H(who, dev) })).json();
const take = async (who, dev) => { const s = await get(who, dev, '/api/talk/sync?after=0'); if (s.last) await post(who, dev, '/api/talk/ack', { upto: s.last }); return s; };
// (plain requests, a fresh connection each: the file's answer is a redirect or the file)
const status = (who, dev, id, q = '') => new Promise((ok, no) => http.get(base + '/api/talk/file/' + id + q, { headers: H(who, dev), agent: false }, (x) => { x.resume(); x.on('end', () => setTimeout(() => ok(x.statusCode), 30)); }).on('error', no));
const AM = 'am-phone-000000000001', AM2 = 'am-new-phone-00000002', DES = 'des-phone-00000000003', OUT = 'out-phone-0000000004';
const sendPhoto = async (G) => {
  const key = crypto.randomBytes(32).toString('base64'), body = crypto.randomBytes(50 * 1024);
  const s = await post('am', AM, '/api/talk/r2/start', { name: 'IMG.jpg', size: body.length });
  await fetch(s.put, { method: 'PUT', body });
  await post('am', AM, '/api/talk/r2/done', { id: s.id });
  const m = await post('am', AM, '/api/talk/act', { act: 'send', group: G, file: { id: s.id, kind: 'photo', key } });
  return { id: s.id, msg: m.id, body, key };
};

let G, P;
test('a file gone from the server comes back from a phone that had it', async () => {
  for (const [w, d] of [['am', AM], ['am', AM2], ['des', DES], ['out', OUT]]) await get(w, d, '/api/talk/sync?after=0');
  G = (await post('am', AM, '/api/talk/act', { act: 'newGroup', client: 'p1', name: 'Shoot', members: ['u-des'] })).group.id;
  P = await sendPhoto(G);
  await take('des', DES); await take('am', AM2); await take('am', AM);   // (every phone has picked the message up)
  assert.equal(await status('des', DES, P.id, '?r2=1'), 302, 'Yousef’s phone downloads it');
  assert.equal(await status('am', AM2, P.id, '?r2=1'), 302, 'and Leila’s second phone');
  clock += 25 * 3600000; app.talk.sweep();
  assert.equal(await status('am', AM2, P.id), 404, 'gone from the server');
  // (Leila's phone lost it — she asks)
  const a = await post('am', AM2, '/api/talk/ask', { group: G, file: P.id });
  assert.ok(a.ok && a.asked, 'asked');
  const asks = await get('des', DES, '/api/talk/asks');
  assert.deepEqual(asks.asks.map((x) => x.file), [P.id], 'Yousef’s phone sees the ask (it had the file)');
  assert.equal((await get('out', OUT, '/api/talk/asks')).asks.length, 0, 'someone not in the group sees nothing');
  // (Yousef's phone sends it again, locked with a key of its own)
  const k2 = crypto.randomBytes(32).toString('base64');
  const s = await post('des', DES, '/api/talk/resend/start', { file: P.id, size: P.body.length });
  assert.ok(s.ok && s.put && s.id === P.id, 'under the file’s own id');
  await fetch(s.put, { method: 'PUT', body: P.body });
  assert.ok((await post('des', DES, '/api/talk/r2/done', { id: P.id, back: true, key: k2 })).ok);
  const ev = (await get('am', AM2, '/api/talk/sync?after=0')).events.find((e) => e.type === 'back');
  assert.ok(ev && ev.file === P.id && ev.key === k2 && ev.msg === P.msg, 'Leila’s phone is told, with the key');
  assert.equal(await status('am', AM2, P.id, '?r2=1'), 302, 'and downloads it');
  assert.equal((await get('des', DES, '/api/talk/asks')).asks.length, 0, 'the ask is answered');
});

test('the rules: only members ask; a file deleted for everyone isn’t asked back; 90 days at most', async () => {
  const Q = await sendPhoto(G);
  assert.equal((await post('out', OUT, '/api/talk/ask', { group: G, file: Q.id })).ok, false, 'not a member: no');
  assert.ok((await post('am', AM, '/api/talk/act', { act: 'del', msg: Q.msg })).ok);
  assert.equal((await post('am', AM2, '/api/talk/ask', { group: G, file: Q.id })).ok, false, 'deleted for everyone: never asked back');
  const R = await sendPhoto(G);
  clock += 91 * 86400000;
  const r = await post('am', AM2, '/api/talk/ask', { group: G, file: R.id });
  assert.equal(r.ok, false, 'over 90 days: gone for good');
  app.talk.sweep();
  assert.equal((await post('des', DES, '/api/talk/resend/start', { file: R.id, size: 10 })).ok, false, 'and nothing to send');
});

test('“Show them the chat history?”: the adder’s phone shares the group’s earlier messages with the people just added (Haris 2026-11-20 21:53)', async () => {
  const G2 = (await post('am', AM, '/api/talk/act', { act: 'newGroup', client: 'p1', name: 'Launch', members: ['u-des'] })).group.id;
  const m1 = await post('am', AM, '/api/talk/act', { act: 'send', group: G2, text: 'Brief is in' });
  const m2 = await post('des', DES, '/api/talk/act', { act: 'send', group: G2, text: 'Looks good' });
  const m3 = await post('am', AM, '/api/talk/act', { act: 'send', group: G2, text: 'oops' });
  await post('am', AM, '/api/talk/act', { act: 'del', msg: m3.id });
  const other = await post('am', AM, '/api/talk/act', { act: 'send', group: G, text: 'another group' });
  const msgs = [
    { id: m1.id, by: 'u-am', at: clock, kind: 'text', text: 'Brief is in' },
    { id: m2.id, by: 'u-des', at: clock, kind: 'text', text: 'Looks good' },
    { id: m3.id, by: 'u-am', at: clock, kind: 'text', text: 'oops' },
    { id: other.id, by: 'u-am', at: clock, kind: 'text', text: 'another group' },
    { id: m2.id + 'x', by: 'u-des', at: clock, kind: 'text', text: 'made up' },
  ];
  assert.equal((await post('am', AM, '/api/talk/history/share', { group: G2, to: ['u-out'], msgs })).ok, false, 'not added yet: no');
  assert.ok((await post('am', AM, '/api/talk/act', { act: 'addPeople', group: G2, ids: ['u-out'] })).ok);
  assert.equal((await post('des', DES, '/api/talk/history/share', { group: G2, to: ['u-out'], msgs })).ok, false, 'only the one who added them');
  const r = await post('am', AM, '/api/talk/history/share', { group: G2, to: ['u-out'], msgs, since: 0 });
  assert.ok(r.ok);
  assert.equal(r.shared, 2, 'only this group’s real messages, not deleted for everyone');
  const ev = (await get('out', OUT, '/api/talk/sync?after=0')).events.find((e) => e.type === 'history');
  assert.deepEqual(ev.msgs.map((m) => m.text), ['Brief is in', 'Looks good']);
  const line = (await get('des', DES, '/api/talk/sync?after=0')).events.filter((e) => e.kind === 'sys').map((e) => e.text).pop();
  assert.match(line, /Leila shared the chat history with Sara/, 'the group is told');
  assert.ok(!(await get('des', DES, '/api/talk/sync?after=0')).events.some((e) => e.type === 'history'), 'the others don’t get it');
  clock += 2 * 3600000;
  assert.equal((await post('am', AM, '/api/talk/history/share', { group: G2, to: ['u-out'], msgs })).ok, false, 'not hours later');
});
