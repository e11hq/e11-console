// Birthdays: the rest of the staff get "Today is …'s birthday" once, from 9:00 Dubai; Freelancers neither get nor
// send them; nobody else's app ever receives the date itself
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { isBirthday } from '../src/birthdays.js';

const OWNER = 'haris@e11-digital.com';
let app, dir, base, clock = Date.parse('2026-10-27T04:30:00Z');   // 08:30 Dubai
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11-bday-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: OWNER, digest: false, holidays: false, occRemind: false, birthdays: false, now: () => clock });
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({ users: [
    { id: 'u-h', email: OWNER, name: 'Haris Sharif', role: 'admin', active: true },
    { id: 'u-a', email: 'areej@e11-digital.com', name: 'Areej Masri', role: 'am', active: true, bday: '10-27' },
    { id: 'u-p', email: 'ali@e11-digital.com', name: 'Ali Raza', role: 'production', active: true, bday: '02-29' },
    { id: 'u-f', email: 'sam@gmail.com', name: 'Sam Free', role: 'freelancer', active: true, bday: '10-27' },
    { id: 'u-x', email: 'old@e11-digital.com', name: 'Old Timer', role: 'production', active: false },
  ], projects: [], statuses: [] }, 'test');
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });
const call = (who, p) => fetch(base + p, { headers: { 'X-Dev-Email': who } }).then((r) => r.json());

test('a birthday on 29 February is celebrated on 28 February in other years', () => {
  assert.equal(isBirthday('02-29', '2027-02-28'), true);
  assert.equal(isBirthday('02-29', '2028-02-28'), false);
  assert.equal(isBirthday('02-29', '2028-02-29'), true);
  assert.equal(isBirthday('10-27', '2026-10-27'), true);
  assert.equal(isBirthday('', '2026-10-27'), false);
});

test('from 9:00 Dubai the rest of the staff are told once; not the birthday person, Freelancers or past members', async () => {
  assert.equal(await app.birthdays.tick(), 0, 'not before 9:00');
  clock = Date.parse('2026-10-27T05:05:00Z');   // 09:05 Dubai
  const made = await app.birthdays.tick();
  const n = app.store.list('notifications').filter((x) => x.kind === 'birthday');
  assert.deepEqual(n.map((x) => x.to).sort(), ['u-h', 'u-p'], 'Haris and Ali hear about Areej');
  assert.equal(made, 2);
  assert.ok(n.every((x) => x.from === 'u-a' && /Areej/.test(x.text)));
  assert.equal(await app.birthdays.tick(), 0, 'only once');
});

test('nobody else’s app gets the date; your own does', async () => {
  const me = await call(OWNER, '/api/me');
  assert.equal(me.user.bday, undefined);
  const snap = await call(OWNER, '/api/snapshot');
  const users = (snap.data || snap).users || [];
  const a = users.find((x) => x.id === 'u-a');
  assert.ok(a, 'Areej is listed');
  assert.equal(a.bday, undefined, 'her birthday is not sent to Haris');
  const own = await call('areej@e11-digital.com', '/api/me');
  assert.equal(own.user.bday, '10-27');
});
