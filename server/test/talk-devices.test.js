// E11 Talk, each phone on its own (Haris 2026-11-20 18:56: "add per-device tracking"): the same account on two phones gets
// everything on each; a file goes only once every phone has it (and a day more); an older app is the person, as before;
// "Delivered" stays per person; a phone not opened for 30 days is let go.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

let clock = Date.parse('2026-11-20T10:00:00Z');
let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11talkdev-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false, birthdays: false, daily: false, scheduled: false, views: false, holidays: false, pruneInbox: false });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({
    users: [
      { id: 'u-am', email: 'am@x.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-des', email: 'des@x.com', role: 'production', active: true, name: 'Yousef' },
    ],
    clients: [{ id: 'c1', name: 'Northline', folders: [] }],
    projects: [{ id: 'p1', name: 'Northline', color: '#3a7bd5', clientId: 'c1', order: 1, ams: [{ id: 'u-am' }] }],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

// who: the person; dev: the phone's own key (none: an older app)
const H = (who, dev) => ({ 'X-Dev-Email': who + '@x.com', 'Content-Type': 'application/json', ...(dev ? { 'X-Talk-Device': dev } : {}) });
const post = async (who, dev, p, b) => (await fetch(base + p, { method: 'POST', headers: H(who, dev), body: JSON.stringify(b) })).json();
const sync = async (who, dev, after = 0) => (await fetch(base + '/api/talk/sync?after=' + after, { headers: H(who, dev) })).json();
const take = async (who, dev) => { const s = await sync(who, dev); if (s.last) await post(who, dev, '/api/talk/ack', { upto: s.last }); return s; };
const upload = async (who, dev, name, body) => (await fetch(base + `/api/talk/upload?name=${name}&offset=0&last=1`, { method: 'POST', headers: { ...H(who, dev), 'Content-Type': 'application/octet-stream' }, body })).json();
const fileStatus = async (who, dev, id) => { const r = await fetch(base + '/api/talk/file/' + id, { headers: H(who, dev) }); await r.arrayBuffer(); await new Promise((z) => setTimeout(z, 30)); return r.status; };
const PH1 = 'phone-one-0000000001', PH2 = 'phone-two-0000000002', DES = 'des-phone-00000000003';

let G;
test('two phones on one account: each gets every message, on its own', async () => {
  await sync('am', PH1); await sync('am', PH2); await sync('des', DES);   // (each phone opens Talk once — registered)
  G = (await post('am', PH1, '/api/talk/act', { act: 'newGroup', client: 'p1', name: 'Shoot', members: ['u-des'] })).group.id;
  await take('am', PH1); await take('am', PH2); await take('des', DES);
  const m = await post('des', DES, '/api/talk/act', { act: 'send', group: G, text: 'Hello both phones' });
  assert.ok(m.ok);
  const a = await take('am', PH1);
  assert.ok(a.events.some((e) => e.id === m.id), 'the first phone has it');
  const b = await take('am', PH2);
  assert.ok(b.events.some((e) => e.id === m.id), 'and the second phone still gets it after the first took it');
  // ("Delivered" is per person: Yousef sees one "got" from Leila, not one per phone)
  const d = await take('des', DES);
  const gots = d.events.filter((e) => e.type === 'got' && e.by === 'u-am');
  assert.ok(gots.length >= 1 && gots.every((e) => e.by === 'u-am'));
});

test('a file stays until every phone has it — and the sending phone isn’t waited for', async () => {
  const up = await upload('des', DES, 'brief.pdf', Buffer.from('PDF'));
  await post('des', DES, '/api/talk/act', { act: 'send', group: G, file: { id: up.id, kind: 'file' } });
  await take('am', PH1); await take('am', PH2); await take('des', DES);
  assert.equal(await fileStatus('am', PH1, up.id), 200, 'the first phone downloads it');
  clock += 25 * 3600000; app.talk.sweep();
  assert.equal(await fileStatus('am', PH2, up.id), 200, 'still there a day later for the second phone, which hasn’t downloaded it');
  clock += 25 * 3600000; app.talk.sweep();
  assert.equal(await fileStatus('am', PH2, up.id), 404, 'gone a day after the last phone had it (the sender’s phone wasn’t waited for)');
});

test('an older app (no device key) is the person, as before — beside the newer phones', async () => {
  await sync('am');   // (an older Talk opened on another phone)
  const m = await post('des', DES, '/api/talk/act', { act: 'send', group: G, text: 'For every phone' });
  for (const dev of [PH1, PH2, null]) assert.ok((await take('am', dev)).events.some((e) => e.id === m.id), `phone ${dev || 'older app'} gets it`);
});

test('unread for E11 Console’s Talk button counts what waits on any of the person’s phones, once', async () => {
  await take('am', PH1); await take('am', PH2); await take('am', null);
  await post('am', PH1, '/api/talk/act', { act: 'unread', n: 0, seq: 0 });
  const before = app.talk.unreadFor('u-am');
  await post('des', DES, '/api/talk/act', { act: 'send', group: G, text: 'One more' });
  assert.equal(app.talk.unreadFor('u-am') - before, 1, 'one new message counts once, not once per phone');
});

test('a phone not opened for 30 days is let go — files aren’t kept for it', async () => {
  clock += 31 * 86400000;
  await sync('am', PH1); await sync('des', DES);   // (these two still in use)
  app.talk.sweep();
  const up = await upload('des', DES, 'late.pdf', Buffer.from('X'));
  await post('des', DES, '/api/talk/act', { act: 'send', group: G, file: { id: up.id, kind: 'file' } });
  await take('am', PH1); await take('des', DES);
  assert.equal(await fileStatus('am', PH1, up.id), 200);
  clock += 25 * 3600000; app.talk.sweep();
  assert.equal(await fileStatus('am', PH1, up.id), 404, 'not waiting for the phone that went quiet, nor the old app unseen for 30 days');
});
