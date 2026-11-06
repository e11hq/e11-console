// E11 Talk's server (talk.js, stage 1): groups under clients, who may do what, messages passed on and gone once every
// member's phone has them, files the same, pins (5), mute, edit within 15 minutes, delete for everyone within 2 days.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

let clock = Date.parse('2026-11-06T08:00:00Z');
let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11talk-'));
  app = createServer({ dataDir: dir, dev: true, now: () => clock, digest: false, occRemind: false, birthdays: false, daily: false, scheduled: false, views: false, holidays: false, pruneInbox: false });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
  app.store.importAll({
    users: [
      { id: 'u-adm', email: 'adm@x.com', role: 'admin', active: true, name: 'Haris' },
      { id: 'u-off', email: 'off@x.com', role: 'office_admin', active: true, name: 'Arsal' },
      { id: 'u-am', email: 'am@x.com', role: 'am', active: true, name: 'Leila' },
      { id: 'u-des', email: 'des@x.com', role: 'production', active: true, name: 'Yousef' },
      { id: 'u-fr', email: 'fr@x.com', role: 'freelancer', active: true, name: 'Free', projectIds: ['p1'] },
      { id: 'u-sm', email: 'sm@x.com', role: 'social', active: true, name: 'Sara' },
      { id: 'u-6', email: 'u6@x.com', role: 'social', active: true, name: 'Six' },
    ],
    clients: [{ id: 'c1', name: 'Northline', logo: 'Clients/c1/logo.png', folders: [] }],
    projects: [
      { id: 'p1', name: 'Northline', color: '#3a7bd5', clientId: 'c1', order: 1, ams: [{ id: 'u-am' }] },
      { id: 'p2', name: 'Southgate', color: '#e5484d', order: 2, ams: [] },
      { id: 'p3', name: 'Old Co', color: '#888', order: 3, inactive: true },
    ],
  }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const H = (who) => ({ 'X-Dev-Email': who + '@x.com', 'Content-Type': 'application/json' });
const state = async (who) => (await fetch(base + '/api/talk/state', { headers: H(who) })).json();
const act = async (who, b) => (await fetch(base + '/api/talk/act', { method: 'POST', headers: H(who), body: JSON.stringify(b) })).json();
const sync = async (who, after = 0) => (await fetch(base + '/api/talk/sync?after=' + after, { headers: H(who) })).json();
const ack = async (who, upto) => (await fetch(base + '/api/talk/ack', { method: 'POST', headers: H(who), body: JSON.stringify({ upto }) })).json();

let G;
test('a group under a client: made by staff, with its members; freelancers can’t make one', async () => {
  const s = await state('am');
  assert.ok(s.clients.some((c) => c.id === 'p1' && c.logo === 'Clients/c1/logo.png'));
  assert.ok(!s.clients.some((c) => c.id === 'p3'), 'inactive clients aren’t offered');
  assert.equal((await act('fr', { act: 'newGroup', client: 'p1', name: 'X' })).ok, false);
  const r = await act('am', { act: 'newGroup', client: 'p1', name: 'Winter campaign', members: ['u-des', 'u-sm'] });
  assert.ok(r.ok); G = r.group.id;
  assert.deepEqual(r.group.members.sort(), ['u-am', 'u-des', 'u-sm']);
  assert.deepEqual(r.group.admins, ['u-am']);
  // only the people in it see it — not the Admin who isn't in it
  assert.ok((await state('des')).groups.some((g) => g.id === G));
  assert.ok(!(await state('adm')).groups.some((g) => g.id === G));
});

test('messages are passed on: each member gets them, and they go once every phone has them', async () => {
  const m = await act('am', { act: 'send', group: G, text: 'Hello team', cid: 'c-1' });
  assert.ok(m.ok);
  const d = await sync('des');
  const msg = d.events.find((e) => e.type === 'msg' && e.id === m.id);
  assert.equal(msg.text, 'Hello team'); assert.equal(msg.by, 'u-am'); assert.equal(msg.cid, 'c-1');
  assert.ok(!(await sync('adm')).events.some((e) => e.id === m.id), 'not for people outside the group');
  // everyone but Sara has it: still held for her
  await ack('am', d.last); await ack('des', d.last);
  assert.ok((await sync('sm')).events.some((e) => e.id === m.id));
  const s2 = await sync('sm'); await ack('sm', s2.last);
  assert.equal((await sync('sm', 0)).events.length, 0, 'once everyone has it, it’s gone from the server');
});

test('only the group’s admins add people; Super / Office Admins can make themselves admin', async () => {
  assert.equal((await act('des', { act: 'addPeople', group: G, ids: ['u-6'] })).ok, false);
  assert.ok((await act('am', { act: 'addPeople', group: G, ids: ['u-6'] })).ok);
  assert.ok((await act('am', { act: 'setSecond', group: G, id: 'u-des' })).ok);
  assert.ok((await act('des', { act: 'addPeople', group: G, ids: ['u-fr'] })).ok, 'the second admin adds people');
  // the second admin can't take the creator's admin away; an Office Admin can
  assert.equal((await act('des', { act: 'dropAdmin', group: G, id: 'u-am' })).ok, false);
  const mm = await act('off', { act: 'makeMeAdmin', group: G });
  assert.ok(mm.ok && mm.group.members.includes('u-off') && mm.group.admins.includes('u-off'));
  const dr = await act('off', { act: 'dropAdmin', group: G, id: 'u-am' });
  assert.ok(dr.ok && !dr.group.admins.includes('u-am') && dr.group.creator === 'u-am');
  assert.equal((await act('am', { act: 'addPeople', group: G, ids: ['u-adm'] })).ok, false, 'the creator without admin can’t add people');
});

test('a freelancer sees only the groups they’re in', async () => {
  const s = await state('fr');
  assert.deepEqual(s.groups.map((g) => g.id), [G]);
  assert.equal(s.me.canMake, false);
});

test('edit within 15 minutes, delete for everyone within 2 days, reactions, read', async () => {
  const m = await act('des', { act: 'send', group: G, text: 'Draft is up' });
  assert.equal((await act('am', { act: 'edit', msg: m.id, text: 'mine now' })).ok, false, 'only your own');
  assert.ok((await act('des', { act: 'edit', msg: m.id, text: 'Draft v2 is up' })).ok);
  clock += 16 * 60000;
  assert.equal((await act('des', { act: 'edit', msg: m.id, text: 'late' })).ok, false);
  assert.ok((await act('sm', { act: 'react', msg: m.id, emoji: '👍' })).ok);
  assert.ok((await act('sm', { act: 'read', group: G, upto: m.id })).ok);
  assert.ok((await act('des', { act: 'del', msg: m.id })).ok);
  const ev = (await sync('am')).events.filter((e) => e.id === m.id || e.upto === m.id).map((e) => e.type);
  assert.deepEqual(ev, ['msg', 'edit', 'react', 'read', 'del']);
  const m2 = await act('des', { act: 'send', group: G, text: 'old one' });
  clock += 3 * 86400000;
  assert.equal((await act('des', { act: 'del', msg: m2.id })).ok, false, 'too late for everyone');
});

test('pins: up to 5 groups — a 6th says Pinned is full; clients pinned apart; mute', async () => {
  const ids = [G];
  for (let i = 0; i < 5; i++) ids.push((await act('am', { act: 'newGroup', client: i % 2 ? 'p1' : 'p2', name: 'G' + i })).group.id);
  for (const id of ids.slice(0, 5)) assert.ok((await act('am', { act: 'pin', id, on: true })).ok);
  const full = await act('am', { act: 'pin', id: ids[5], on: true });
  assert.equal(full.full, true); assert.equal(full.pins.length, 5);
  assert.ok((await act('am', { act: 'pinClient', id: 'p2', on: true })).ok);
  assert.deepEqual((await state('am')).pins.clients, ['p2']);
  const mu = await act('am', { act: 'mute', group: G, until: 'always' });
  assert.ok(mu.ok && mu.mutedUntil > clock);
});

test('files: uploaded in pieces, sent in a message, read by the group only, gone once everyone has it', async () => {
  const up = await (await fetch(base + '/api/talk/upload?name=brief.pdf&offset=0&last=1', { method: 'POST', headers: { 'X-Dev-Email': 'am@x.com', 'Content-Type': 'application/octet-stream' }, body: Buffer.from('PDFDATA') })).json();
  assert.ok(up.ok && up.done);
  const m = await act('am', { act: 'send', group: G, file: { id: up.id, kind: 'file' } });
  assert.ok(m.ok);
  const got = await fetch(base + '/api/talk/file/' + up.id, { headers: H('des') });
  assert.equal(got.status, 200); assert.equal(await got.text(), 'PDFDATA');
  assert.equal((await fetch(base + '/api/talk/file/' + up.id, { headers: H('adm') })).status, 404, 'not for people outside the group');
  for (const w of ['am', 'des', 'sm', 'u6', 'fr', 'off']) { const s = await sync(w); if (s.last) await ack(w, s.last); }
  assert.equal(fs.existsSync(path.join(dir, 'talk-relay', up.id)), false, 'the file is gone from the server');
});

test('leaving, removing, deleting a group', async () => {
  assert.ok((await act('sm', { act: 'leave', group: G })).ok);
  assert.ok(!(await state('sm')).groups.some((g) => g.id === G));
  assert.equal((await act('des', { act: 'removePerson', group: G, id: 'u-am' })).ok, false, 'only Super / Office Admins remove the creator');
  assert.ok((await act('off', { act: 'deleteGroup', group: G })).ok);
  assert.ok(!(await state('des')).groups.some((g) => g.id === G));
  assert.ok((await sync('des')).events.some((e) => e.type === 'gone' && e.group === G));
});

test('a group with no new messages for 90 days is deleted, its people told', async () => {
  const g = (await act('am', { act: 'newGroup', client: 'p2', name: 'Quiet one', members: ['u-des'] })).group.id;
  await act('am', { act: 'send', group: g, text: 'last words' });
  clock += 91 * 86400000;
  app.talk.sweep();
  assert.ok(!(await state('des')).groups.some((x) => x.id === g));
  assert.ok((await sync('des')).events.some((e) => e.type === 'gone' && e.group === g && e.why === 'inactive'));
});

test('sample groups (test site, the owner): three groups with a conversation, each marked (sample)', async () => {
  const r = app.talk.sample(app.store.get('users', 'u-adm'));
  assert.ok(r.ok); assert.equal(r.made.length, 3);
  const s = await state('adm');
  const mine = s.groups.filter((g) => g.name.endsWith('(sample)'));
  assert.equal(mine.length, 3);
  const ev = (await sync('adm')).events.filter((e) => mine.some((g) => g.id === e.group));
  assert.ok(ev.filter((e) => e.type === 'msg').length >= 13);
  assert.ok(ev.some((e) => e.type === 'msg' && (e.mentions || []).includes('u-adm')));
  assert.ok(ev.some((e) => e.type === 'msg' && e.reply && e.reply.id));
  assert.ok(ev.some((e) => e.type === 'react'));
  assert.equal((await (await fetch(base + '/api/talk/sample', { method: 'POST', headers: H('adm'), body: '{}' })).json()).ok, false, 'not on the live site');
});

test('client contacts: added by Super / Office Admins only; E11 Talk only; their own client’s groups; never "Seen by"', async () => {
  assert.equal((await act('am', { act: 'addContact', name: 'Ahmed Karim', email: 'ahmed@harbor.ae', client: 'p1' })).ok, false, 'not an Account Manager');
  assert.equal((await act('off', { act: 'addContact', name: 'X', email: 'am@x.com', client: 'p1' })).ok, false, 'not a team email');
  const k = (await act('off', { act: 'addContact', name: 'Ahmed Karim', email: 'ahmed@harbor.ae', client: 'p1' })).contact;
  assert.ok(k && k.id.startsWith('k-'));
  const KH = { 'X-Dev-Email': 'ahmed@harbor.ae', 'Content-Type': 'application/json' };
  // E11 Console refuses them; E11 Talk lets them in, with nothing but their own client
  assert.equal((await fetch(base + '/api/me', { headers: KH })).status, 403);
  let ks = await (await fetch(base + '/api/talk/state', { headers: KH })).json();
  assert.ok(ks.ok && ks.me.contact && ks.groups.length === 0 && ks.clients.length === 1 && ks.clients[0].id === 'p1' && !ks.contacts);
  // only admins put contacts in groups, and only their own client's
  assert.equal((await act('am', { act: 'newGroup', client: 'p1', name: 'Approvals', members: ['u-des', k.id] })).ok, false);
  assert.equal((await act('adm', { act: 'newGroup', client: 'p2', name: 'Wrong client', members: [k.id] })).ok, false);
  const g = (await act('adm', { act: 'newGroup', client: 'p1', name: 'Approvals', members: ['u-des', k.id] })).group;
  assert.ok(g.withClient);
  const kact = async (b) => (await fetch(base + '/api/talk/act', { method: 'POST', headers: KH, body: JSON.stringify(b) })).json();
  ks = await (await fetch(base + '/api/talk/state', { headers: KH })).json();
  assert.deepEqual(ks.groups.map((x) => x.id), [g.id]);
  assert.ok(ks.people.every((p) => g.members.includes(p.id)), 'a contact sees only the people of their groups');
  // they write and read, but can't make or change groups
  const m = await kact({ act: 'send', group: g.id, text: 'Looks great, go ahead with v3' });
  assert.ok(m.ok);
  assert.equal((await kact({ act: 'newGroup', client: 'p1', name: 'Mine' })).ok, false);
  assert.equal((await kact({ act: 'addPeople', group: g.id, ids: ['u-am'] })).ok, false);
  // "Seen by": staff see the client's; the client never gets anyone's
  await act('des', { act: 'read', group: g.id, upto: m.id });
  await kact({ act: 'read', group: g.id, upto: m.id });
  const kev = await (await fetch(base + '/api/talk/sync?after=0', { headers: KH })).json();
  assert.ok(!kev.events.some((e) => e.type === 'read'), 'no read receipts for clients');
  assert.ok((await sync('des')).events.some((e) => e.type === 'read' && e.by === k.id), 'staff see the client has seen it');
  // the boss's list; removed: out of every group, and E11 Talk refuses them at once
  assert.ok((await state('off')).contacts.some((c) => c.id === k.id && c.groups === 1));
  assert.ok((await act('adm', { act: 'removeContact', id: k.id })).ok);
  assert.equal((await fetch(base + '/api/talk/state', { headers: KH })).status, 403);
  assert.ok(!(await state('adm')).groups.find((x) => x.id === g.id).members.includes(k.id));
});

test('a linked Mac: code from the Mac, scanned by the same person’s phone; gets what they get; history; unlink', async () => {
  const req = async (who, p, b, mac) => (await fetch(base + p, { method: b ? 'POST' : 'GET', headers: { ...H(who), ...(mac ? { 'X-Talk-Mac': mac } : {}) }, body: b ? JSON.stringify(b) : undefined })).json();
  const g = (await act('am', { act: 'newGroup', client: 'p1', name: 'Mac group', members: ['u-des'] })).group.id;
  // the Mac (signed in as Leila) shows a code; Yousef's phone can't use it, Leila's can
  const c = await req('am', '/api/talk/link/code', { name: 'Leila’s MacBook' });
  assert.ok(c.ok && c.code);
  assert.equal((await req('am', '/api/talk/link/status?code=' + c.code)).mac, undefined);
  const wrong = await act('des', { act: 'linkMac', code: c.code });
  assert.equal(wrong.ok, false); assert.match(wrong.error, /someone else/);
  const l = await act('am', { act: 'linkMac', code: c.code });
  assert.ok(l.ok); const mac = l.mac.id;
  assert.equal((await req('am', '/api/talk/link/status?code=' + c.code)).mac, mac);
  assert.equal((await act('am', { act: 'linkMac', code: c.code })).ok, false, 'one use');
  assert.equal((await state('am')).macs[0].name, 'Leila’s MacBook');
  // the phone hands over its chats; the Mac picks them up as its own
  const h = await req('am', '/api/talk/link/history', { mac, groups: [{ group: g, msgs: [{ id: 'm-old', text: 'before' }] }, { group: 'not-mine', msgs: [] }], files: [] });
  assert.ok(h.ok); assert.equal(h.groups, 1);
  // a message to the group: Yousef's phone, Leila's phone and Leila's Mac — each kept until that device has it
  const m = await act('des', { act: 'send', group: g, text: 'For the Mac too' });
  const ms = await req('am', '/api/talk/sync?after=0', null, mac);
  assert.ok(ms.events.some((e) => e.type === 'history' && e.groups[0].msgs[0].id === 'm-old'));
  assert.ok(ms.events.some((e) => e.id === m.id));
  await req('am', '/api/talk/ack', { upto: ms.last }, mac);
  assert.ok((await sync('am')).events.some((e) => e.id === m.id), 'Leila’s phone still gets it');
  // what Leila sends from her phone shows on her Mac too
  const mine = await act('am', { act: 'send', group: g, text: 'From my phone' });
  const s2 = await req('am', '/api/talk/sync?after=' + ms.last, null, mac); assert.ok(s2.events, JSON.stringify(s2)); assert.ok(s2.events.some((e) => e.id === mine.id));
  // someone else signed in on that Mac: the link is gone
  assert.equal((await fetch(base + '/api/talk/sync?after=0', { headers: { ...H('des'), 'X-Talk-Mac': mac } })).status, 410);
  assert.equal((await state('am')).macs.length, 0);
  // link again, then unlink from the phone
  const c2 = await req('am', '/api/talk/link/code', { name: 'Mac' });
  const l2 = await act('am', { act: 'linkMac', code: c2.code });
  assert.ok((await act('am', { act: 'unlinkMac', id: l2.mac.id })).ok);
  assert.equal((await fetch(base + '/api/talk/sync?after=0', { headers: { ...H('am'), 'X-Talk-Mac': l2.mac.id } })).status, 410);
  // a code runs out after 2 minutes; a client contact can't link
  const c3 = await req('am', '/api/talk/link/code', { name: 'Mac' });
  clock += 3 * 60000;
  assert.equal((await act('am', { act: 'linkMac', code: c3.code })).ok, false);
  // the phone not opening E11 Talk for 30 days: the Mac is unlinked
  const c4 = await req('am', '/api/talk/link/code', { name: 'Mac' });
  const l4 = await act('am', { act: 'linkMac', code: c4.code });
  await sync('am');
  clock += 31 * 86400000;
  app.talk.sweep();
  assert.equal((await state('am')).macs.length, 0);
});
