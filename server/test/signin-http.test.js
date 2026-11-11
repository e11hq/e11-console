// Our own sign-in through the server: the page Cloudflare sends people to, an admin's code, the owner code, the token
// Cloudflare gets, the other admins told, and every older sign-in ended
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';
import { hashSecret } from '../src/signin.js';

let app, base, dir;
const CB = 'https://team.cloudflareaccess.com/cdn-cgi/access/callback';
const REQ = { client_id: 'cf', redirect_uri: CB, state: 'st1', nonce: 'nn1' };
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11si-'));
  app = createServer({ dataDir: dir, dev: true, adminEmail: 'owner@e11.test', signinIssuer: 'https://signin-test.e11.test', ownerCodeHash: hashSecret('2468'),
    signinClients: [{ id: 'cf', secret: 'shh', redirects: [CB] }] });
  app.cfSync = null;
  const port = await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${port}`;
  app.store.importAll({ users: [
    { id: 'u-own', email: 'owner@e11.test', name: 'Owner One', role: 'admin', active: true },
    { id: 'u-adm', email: 'omar@e11.test', name: 'Omar Saleh', role: 'office_admin', active: true },
    { id: 'u-adm2', email: 'lina@e11.test', name: 'Lina Haddad', role: 'admin', active: true },
    { id: 'u-sara', email: 'sara@e11.test', name: 'Sara Khan', role: 'production', active: true },
  ] });
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

const post = (p, body, h = {}) => fetch(base + p, { method: 'POST', headers: { 'Content-Type': 'application/json', ...h }, body: JSON.stringify(body) }).then((r) => r.json());
const api = (what, body) => post('/oidc/api/' + what, { req: REQ, ...body });

test('Cloudflare finds us: discovery, keys, and the page for a known client only', async () => {
  const d = await fetch(base + '/.well-known/openid-configuration').then((r) => r.json());
  assert.equal(d.authorization_endpoint, 'https://signin-test.e11.test/oidc/authorize');
  assert.equal((await fetch(base + '/oidc/jwks').then((r) => r.json())).keys.length, 1);
  const q = new URLSearchParams({ ...REQ, response_type: 'code', scope: 'openid email' });
  const ok = await fetch(base + '/oidc/authorize?' + q);
  assert.equal(ok.status, 200);
  assert.match(await ok.text(), /Sign in · E11 Console/);
  const bad = await fetch(base + '/oidc/authorize?' + new URLSearchParams({ ...REQ, redirect_uri: 'https://evil.test/cb', response_type: 'code' }));
  assert.equal(bad.status, 400);
});

test("an admin's code → a new password → Cloudflare's token; the other admins told, not the maker or the person", async () => {
  assert.equal((await post('/api/signin/code', { userId: 'u-sara' }, { 'X-Dev-Email': 'sara@e11.test' })).ok, false, 'not an admin');
  const made = await post('/api/signin/code', { userId: 'u-sara' }, { 'X-Dev-Email': 'omar@e11.test' });
  assert.ok(made.ok); assert.match(made.code, /^\d{4}$/); assert.equal(made.newUser, true);
  const s = await api('start', { email: 'sara@e11.test' });
  assert.deepEqual([s.ok, s.password, s.owner], [true, false, false]);
  const c = await api('code', { email: 'sara@e11.test', code: made.code });
  assert.ok(c.ok && c.ticket);
  const done = await api('setpw', { ticket: c.ticket, password: 'sara long password' });
  assert.ok(done.ok);
  const back = new URL(done.redirect);
  assert.equal(back.origin + back.pathname, CB); assert.equal(back.searchParams.get('state'), 'st1');
  const tok = await fetch(base + '/oidc/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Authorization: 'Basic ' + Buffer.from('cf:shh').toString('base64') },
    body: new URLSearchParams({ grant_type: 'authorization_code', code: back.searchParams.get('code'), redirect_uri: CB }) }).then((r) => r.json());
  assert.ok(tok.id_token);
  assert.equal(JSON.parse(Buffer.from(tok.id_token.split('.')[1], 'base64url')).email, 'sara@e11.test');
  const notes = app.store.list('notifications').filter((n) => n.kind === 'signin');
  assert.deepEqual(notes.map((n) => n.to).sort(), ['u-adm2', 'u-own']);
  assert.match(notes[0].text, /Omar Saleh made a sign-in code for Sara Khan, and Sara’s password was changed/);
  // next time: the password
  assert.equal((await api('start', { email: 'sara@e11.test' })).password, true);
  assert.ok((await api('password', { email: 'sara@e11.test', password: 'sara long password' })).redirect);
  assert.equal((await api('password', { email: 'sara@e11.test', password: 'wrong one' })).ok, false);
});

test('the owner code: the owner only, then a password, and nobody told', async () => {
  const before = app.store.list('notifications').length;
  assert.equal((await api('start', { email: 'owner@e11.test' })).owner, true);
  assert.equal((await api('owner', { email: 'sara@e11.test', code: '2468' })).ok, false);
  const o = await api('owner', { email: 'owner@e11.test', code: '2468' });
  assert.ok(o.ok);
  assert.ok((await api('setpw', { ticket: o.ticket, password: 'owner long password' })).redirect);
  assert.equal(app.store.list('notifications').length, before);
});

test("the owner's own codes for others: out of the admins' record, telling no one", async () => {
  const before = app.store.list('notifications').length;
  const made = await post('/api/signin/code', { userId: 'u-adm' }, { 'X-Dev-Email': 'owner@e11.test' });
  assert.ok(made.ok);
  const c = await api('code', { email: 'omar@e11.test', code: made.code });
  await api('setpw', { ticket: c.ticket, password: 'omar long password' });
  assert.equal(app.store.list('notifications').length, before);
  const adminSees = await fetch(base + '/api/signin/codes', { headers: { 'X-Dev-Email': 'lina@e11.test' } }).then((r) => r.json());
  assert.ok(adminSees.codes.every((x) => !x.byOwner));
  const ownerSees = await fetch(base + '/api/signin/codes', { headers: { 'X-Dev-Email': 'owner@e11.test' } }).then((r) => r.json());
  assert.ok(ownerSees.codes.some((x) => x.byOwner));
});

test('the page draws its first step in a browser (its data read back whole)', async () => {
  const { chromium } = await import('playwright').catch(() => ({}));
  if (!chromium) return;
  const b = await chromium.launch();
  try {
    const p = await b.newPage();
    const errs = []; p.on('pageerror', (e) => errs.push(e.message));
    await p.goto(base + '/oidc/authorize?' + new URLSearchParams({ ...REQ, response_type: 'code' }));
    await p.fill('#em', 'sara@e11.test');
    await p.click('button.go');
    await p.waitForSelector('#pw');
    assert.deepEqual(errs, []);
  } finally { await b.close(); }
});
