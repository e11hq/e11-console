// Comments: words can be edited for 10 minutes only (everyone, Admins too); read receipts for @mentions; link previews
// (public addresses only); and the AMs' / Super Admins' 9:00 morning round-up (Mon–Fri, not on UAE public holidays)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from '../src/server.js';
import { privateIp, publicUrl, readMeta } from '../src/links.js';
import { dailyText } from '../src/amdaily.js';

const OWNER = 'haris@e11-digital.com', AM = 'areej@e11-digital.com', PROD = 'ali@e11-digital.com';
const WEB = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'web');
let app, dir, base, clock = Date.parse('2026-10-27T04:30:00Z');   // Tue 08:30 Dubai
const pages = {
  'https://example.com/a': { type: 'text/html', body: '<html><head><title>Plain</title><meta property="og:title" content="Summer &amp; Sun"><meta property="og:description" content="The campaign"><meta property="og:image" content="/pic.jpg"><link rel="icon" href="/fav.png"></head></html>' },
  'https://example.com/pic.jpg': { type: 'image/jpeg', body: 'JPEGDATA' },
  'https://example.com/x.svg': { type: 'image/svg+xml', body: '<svg onload=alert(1)>' },
  'https://we.tl/t-abc': { redirect: 'https://wetransfer.com/downloads/0123456789abcdef0123456789abcdef/abcdef1234' },
  'https://wetransfer.com/downloads/0123456789abcdef0123456789abcdef/abcdef1234': { type: 'text/html', body: '<title>WeTransfer</title>' },
  'https://wetransfer.com/api/v4/transfers/0123456789abcdef0123456789abcdef/prepare-download': { type: 'application/json', body: JSON.stringify({ state: 'downloadable', expires_at: '2026-11-02T10:00:00Z', size: 2400000000, files: [{ name: 'KIA_final.mp4', size: 2000000000 }, { name: 'KIA_cutdown.mp4', size: 400000000 }] }) },
};
const asked = [];
async function fakeFetch(u, opts = {}) {
  asked.push(u);
  if (!publicUrl(u)) throw new Error('Not a public web address');
  let p = pages[u], hops = 0;
  while (p && p.redirect && hops++ < 5) { u = p.redirect; p = pages[u]; }
  if (!p) return { status: 404, url: u, type: 'text/html', body: Buffer.from('') };
  return { status: 200, url: u, type: p.type, body: Buffer.from(p.body) };
}
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-cm2-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, webDir: WEB, digest: false, holidays: false, occRemind: false, birthdays: false, scheduled: false, daily: false, now: () => clock, linkFetch: fakeFetch });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  const old = new Date(Date.now() - 30 * 60000).toISOString(), fresh = new Date(Date.now() - 2 * 60000).toISOString();
  const men = (id) => `<span class="mention" data-user="${id}">@x</span> look`;
  app.store.importAll({ users: [
    { id: 'u-h', email: OWNER, name: 'Haris Sharif', role: 'admin', active: true },
    { id: 'u-a', email: AM, name: 'Areej Masri', role: 'am', active: true },
    { id: 'u-b', email: 'bilal@e11-digital.com', name: 'Bilal Am', role: 'am', active: true, prefs: { notifOff: { daily: true } } },
    { id: 'u-p', email: PROD, name: 'Ali Raza', role: 'production', active: true },
    { id: 'u-o', email: 'office@e11-digital.com', name: 'Office Admin', role: 'office_admin', active: true },
  ], projects: [{ id: 'p1', name: 'KIA', sections: [{ id: 's1', name: 'To do' }], ams: [{ id: 'u-a' }] }, { id: 'p2', name: 'Ford', sections: [{ id: 's9', name: 'To do' }] }],
  tasks: [
    { id: 't1', title: 'Banner', projectId: 'p1', sectionId: 's1', assignees: ['u-p'], createdBy: 'u-a', attachments: [], tags: [], reviews: [], due: '2026-10-27',
      comments: [{ id: 'c-old', text: 'old words', html: 'old words', at: old, authorId: 'u-a' }, { id: 'c-new', text: 'new words', html: 'new words', at: fresh, authorId: 'u-a' },
        { id: 'c-men', text: '@Ali look', html: men('u-p'), at: old, authorId: 'u-a' }, { id: 'c-plain', text: 'no mention', html: 'no mention', at: old, authorId: 'u-a' }] },
    { id: 't2', title: 'Late post', projectId: 'p1', sectionId: 's1', assignees: ['u-p'], createdBy: 'u-h', comments: [], attachments: [], tags: [], due: '2026-10-20',
      needsCD: true, reviews: [{ id: 'r1', by: 'u-p', at: '2026-10-21T08:00:00Z', state: 'pending' }] },
    { id: 't3', title: 'Approved reel', projectId: 'p1', sectionId: 's1', assignees: ['u-p'], createdBy: 'u-a', comments: [], attachments: [], tags: [], needsCD: true,
      reviews: [{ id: 'r2', by: 'u-p', at: '2026-10-21T08:00:00Z', state: 'approved', decidedAt: '2026-10-22T08:00:00Z' }] },
    { id: 't4', title: 'Ford flyer', projectId: 'p2', sectionId: 's9', assignees: ['u-p'], createdBy: 'u-h', comments: [], attachments: [], tags: [], due: '2026-10-27' },
  ], statuses: [] }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
async function push(who, id, change) {
  const cur = app.store.get('tasks', id);
  const data = change(JSON.parse(JSON.stringify(cur)));
  const r = await fetch(base + '/api/push', { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify({ changes: [{ kind: 'tasks', id, base: cur, data }] }) }).then((x) => x.json());
  return !!r.results[0].refused;
}
const post = (who, p, body) => fetch(base + p, { method: 'POST', headers: { 'X-Dev-Email': who, 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) }).then((r) => r.json());
const get = (who, p) => fetch(base + p, { headers: { 'X-Dev-Email': who } });
const edit = (cid, words) => (t) => { const c = t.comments.find((x) => x.id === cid); c.text = words; c.html = words; return t; };

test('a comment’s words can be changed for 10 minutes after it was sent', async () => {
  assert.equal(await push(AM, 't1', edit('c-new', 'new words, fixed')), false, 'within 10 minutes');
  assert.equal(await push(AM, 't1', edit('c-old', 'changed later')), true, 'after 10 minutes');
  assert.equal(await push(OWNER, 't1', edit('c-old', 'changed by an admin')), true, 'Admins too');
});
test('after the 10 minutes it can still be deleted, reacted to, and new comments added', async () => {
  assert.equal(await push(AM, 't1', (t) => { t.comments.find((c) => c.id === 'c-old').reactions = { '👍': 1 }; return t; }), false, 'reaction');
  assert.equal(await push(AM, 't1', (t) => { t.comments.push({ id: 'c-x', text: 'hi', html: 'hi', at: new Date().toISOString(), authorId: 'u-a' }); return t; }), false, 'new comment');
  assert.equal(await push(AM, 't1', (t) => { t.comments = t.comments.filter((c) => c.id !== 'c-x'); return t; }), false, 'delete');
});

test('read receipts: a person @mentioned marks the comment seen; nobody else can', async () => {
  assert.equal((await post(OWNER, '/api/seen', { taskId: 't1', ids: ['c-men'] })).marked, 0, 'not mentioned');
  assert.equal((await post(PROD, '/api/seen', { taskId: 't1', ids: ['c-plain'] })).marked, 0, 'a comment without their mention');
  assert.equal((await post(PROD, '/api/seen', { taskId: 't1', ids: ['c-men'] })).marked, 1);
  const c = app.store.get('tasks', 't1').comments.find((x) => x.id === 'c-men');
  assert.ok(c.seen && c.seen['u-p'], 'saved on the comment');
  assert.equal((await post(PROD, '/api/seen', { taskId: 't1', ids: ['c-men'] })).marked, 0, 'only once');
  assert.equal(await push(AM, 't1', (t) => { t.comments.push({ id: 'c-y', text: 'ok', html: 'ok', at: new Date().toISOString(), authorId: 'u-a' }); return t; }), false);
  assert.ok(app.store.get('tasks', 't1').comments.find((x) => x.id === 'c-men').seen['u-p'], 'a later save from an app that hadn’t got it yet keeps it');
});

test('link previews: only public addresses', () => {
  for (const ip of ['127.0.0.1', '10.0.0.5', '192.168.1.20', '172.20.0.1', '169.254.169.254', '100.64.0.1', '::1', 'fd00::1', '::ffff:192.168.0.1', '0.0.0.0']) assert.equal(privateIp(ip), true, ip);
  for (const ip of ['8.8.8.8', '104.16.0.1', '2606:4700::1111']) assert.equal(privateIp(ip), false, ip);
  for (const u of ['http://localhost/x', 'http://nas.local/', 'http://192.168.1.2/', 'ftp://example.com/', 'https://example.com:8443/', 'https://user:pw@example.com/', 'javascript:alert(1)', 'http://intranet/']) assert.equal(publicUrl(u), null, u);
  assert.ok(publicUrl('https://wetransfer.com/downloads/x'));
});
test('link previews: the page’s title, description, picture and icon', async () => {
  const m = readMeta(pages['https://example.com/a'].body, 'https://example.com/a');
  assert.equal(m.title, 'Summer & Sun');
  assert.equal(m.image, 'https://example.com/pic.jpg');
  assert.equal(m.icon, 'https://example.com/fav.png');
  const r = await get(AM, '/api/link?u=' + encodeURIComponent('https://example.com/a')).then((x) => x.json());
  assert.equal(r.ok, true); assert.equal(r.title, 'Summer & Sun'); assert.equal(r.desc, 'The campaign'); assert.equal(r.site, 'example.com');
  const n = asked.length;
  await get(AM, '/api/link?u=' + encodeURIComponent('https://example.com/a')).then((x) => x.json());
  assert.equal(asked.length, n, 'kept, not read again');
  const img = await get(AM, '/api/link/img?u=' + encodeURIComponent('https://example.com/pic.jpg'));
  assert.equal(img.status, 200); assert.equal(img.headers.get('content-type'), 'image/jpeg');
  assert.match(img.headers.get('content-security-policy'), /sandbox/);
  assert.equal((await get(AM, '/api/link/img?u=' + encodeURIComponent('https://example.com/x.svg'))).status, 404, 'no SVG');
  const bad = await get(AM, '/api/link?u=' + encodeURIComponent('http://192.168.1.10/admin')).then((x) => x.json());
  assert.equal(bad.ok, false);
});
test('link previews: WeTransfer with its files, size and expiry', async () => {
  const r = await get(AM, '/api/link?u=' + encodeURIComponent('https://we.tl/t-abc')).then((x) => x.json());
  assert.equal(r.site, 'WeTransfer'); assert.equal(r.key, 'wetransfer');
  assert.equal(r.wt.files, 2); assert.equal(r.wt.size, 2400000000); assert.equal(r.wt.expires, '2026-11-02T10:00:00Z');
  assert.deepEqual(r.wt.names, ['KIA_final.mp4', 'KIA_cutdown.mp4']);
});

const daily = () => app.store.list('notifications').filter((n) => n.kind === 'daily');
test('morning round-up: not before 9:00, then once to each AM and Super Admin who wants it', async () => {
  assert.equal(await app.daily.tick(), 0, 'not before 9:00');
  clock = Date.parse('2026-10-27T05:02:00Z');   // Tue 09:02 Dubai
  assert.equal(await app.daily.tick(), 2);
  const list = daily();
  assert.deepEqual(list.map((n) => n.to).sort(), ['u-a', 'u-h'], 'the AM and the Super Admin; not the AM who switched it off, Production or the Office Admin');
  const a = list.find((n) => n.to === 'u-a'), h = list.find((n) => n.to === 'u-h');
  // Areej looks after KIA: t1 (due today), t2 (overdue, waiting for CD), t3 (approved, no client approval)
  assert.deepEqual({ ...a.counts, team: undefined }, { team: undefined, overdue: 1, today: 1, cd: 1, amend: 0, client: 1, sched: 0 });
  assert.equal(a.team, false);
  // Haris: the whole team (Areej's and his own created tasks: also Ford's t4)
  assert.equal(h.team, true); assert.equal(h.counts.today, 2);
  assert.match(a.text, /1 overdue · 1 due today · 1 waiting for CD · 1 need client approval/);
  assert.equal(await app.daily.tick(), 0, 'only once a day');
});
test('morning round-up: not on weekends or UAE public holidays', async () => {
  clock = Date.parse('2026-10-31T05:10:00Z');   // Saturday
  assert.equal(await app.daily.tick(), 0);
  clock = Date.parse('2026-12-02T05:10:00Z');   // Wed 2 Dec, UAE National Day
  assert.ok(app.daily.holidayOn('2026-12-02'));
  assert.equal(await app.daily.tick(), 0);
  assert.equal(app.daily.holidayOn('2026-12-07'), null);
  app.store.kv.set('holiday-sync', JSON.stringify({ publicDays: [{ date: '2026-12-07', name: 'Extra holiday' }] }));
  assert.equal(app.daily.holidayOn('2026-12-07'), 'Extra holiday', 'a public holiday from the UAE calendar');
  clock = Date.parse('2026-12-08T05:10:00Z');   // Tue 8 Dec
  assert.equal(await app.daily.tick(), 2);
});
test('morning round-up: wording, and a try-out for yourself', async () => {
  assert.equal(dailyText({ overdue: 0, today: 0, cd: 0, amend: 0, client: 0, sched: 0 }), 'All clear today — nothing overdue or due today.');
  assert.equal(dailyText({ overdue: 0, today: 2, cd: 0, amend: 1, client: 0, sched: 1 }), '2 due today · 1 with amendments · 1 scheduled comment today');
  const n0 = daily().length;
  assert.equal((await post(AM, '/api/daily/test')).ok, true);
  assert.equal(daily().length, n0 + 1);
  assert.equal((await fetch(base + '/api/daily/test', { method: 'POST', headers: { 'X-Dev-Email': PROD } })).status, 403);
});
