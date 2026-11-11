// Our own sign-in (signin.js): passwords, admins' sign-in codes, the owner's standing code, signing out everywhere,
// and the OpenID Connect answers Cloudflare asks for
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { createSignin, hashSecret, checkSecret } from '../src/signin.js';

const users = {
  'owner@e11.test': { email: 'owner@e11.test', name: 'Owner', role: 'admin' },
  'sara@e11.test': { email: 'sara@e11.test', name: 'Sara Khan', role: 'production' },
  'gone@e11.test': { email: 'gone@e11.test', name: 'Gone', role: 'production', removed: true },
};
const OWNER_CODE = '1357';
function make(t0 = 1_800_000_000_000) {
  let clock = t0;
  const used = [];
  const s = createSignin({
    db: new DatabaseSync(':memory:'), now: () => clock, ownerEmail: 'owner@e11.test', ownerCodeHash: hashSecret(OWNER_CODE),
    findUser: (e) => users[e] || null, issuer: 'https://signin-test.e11.test',
    clients: [{ id: 'cf', secret: 'shh-secret', redirects: ['https://team.cloudflareaccess.com/cdn-cgi/access/callback'] }],
    onCodeUsed: (x) => used.push(x),
  });
  return { s, used, tick: (ms) => { clock += ms; }, now: () => clock };
}

test('hashes: a secret checks against its own hash only', () => {
  const h = hashSecret('correct horse');
  assert.ok(checkSecret('correct horse', h));
  assert.ok(!checkSecret('wrong horse', h));
  assert.ok(!checkSecret('x', 'nonsense'));
});

test('the first screen: on the team or not, password or code', () => {
  const { s } = make();
  assert.equal(s.start('nobody@e11.test').ok, false);
  assert.equal(s.start('gone@e11.test').ok, false);
  assert.deepEqual(s.start(' Sara@E11.test '), { ok: true, email: 'sara@e11.test', password: false, owner: false });
  assert.equal(s.start('owner@e11.test').owner, true);
});

test('a code: one use, that email, 24 hours, a new one cancels the old, then the password', () => {
  const { s, used, tick } = make();
  const a = s.makeCode('sara@e11.test', 'admin@e11.test');
  assert.match(a.code, /^\d{4}$/);
  const b = s.makeCode('sara@e11.test', 'admin@e11.test');
  if (a.code !== b.code) assert.equal(s.useCode('sara@e11.test', a.code).ok, false, 'the old code is cancelled');
  const r = s.useCode('sara@e11.test', b.code);
  assert.ok(r.ok && r.ticket);
  assert.equal(s.setPassword(r.ticket, 'short').ok, false);
  assert.equal(s.setPassword(r.ticket, 'a good long password').ok, true);
  assert.deepEqual(used, [{ email: 'sara@e11.test', madeBy: 'admin@e11.test' }]);
  assert.equal(s.setPassword(r.ticket, 'another long password').ok, false, 'the code is used up');
  assert.equal(s.signInPassword('sara@e11.test', 'a good long password').ok, true);
  assert.equal(s.start('sara@e11.test').password, true);
  // a code runs out after 24 hours
  const c = s.makeCode('sara@e11.test', 'admin@e11.test');
  tick(24 * 3600_000 + 1);
  assert.equal(s.useCode('sara@e11.test', c.code).ok, false);
});

test('a code stops after 5 wrong tries', () => {
  const { s } = make();
  const c = s.makeCode('sara@e11.test', 'admin@e11.test');
  const wrong = c.code === '0000' ? '1111' : '0000';
  for (let i = 0; i < 5; i++) assert.equal(s.useCode('sara@e11.test', wrong).ok, false);
  assert.equal(s.useCode('sara@e11.test', c.code).ok, false);
});

test('a password set with a code ends every sign-in made before it; the owner code ends nothing', () => {
  const { s, tick } = make();
  assert.equal(s.revokedBefore('sara@e11.test'), 0);
  const c = s.makeCode('sara@e11.test', 'admin@e11.test');
  tick(1000);
  s.setPassword(s.useCode('sara@e11.test', c.code).ticket, 'a good long password');
  assert.ok(s.revokedBefore('sara@e11.test') > 0);
  const o = s.useOwnerCode('owner@e11.test', OWNER_CODE);
  assert.ok(o.ok);
  assert.equal(s.setPassword(o.ticket, 'owner long password').ok, true);
  assert.equal(s.revokedBefore('owner@e11.test'), 0);
});

test("the owner's codes: no one told, and kept out of the admins' record", () => {
  const { s, used } = make();
  const c = s.makeCode('sara@e11.test', 'owner@e11.test', { byOwner: true });
  s.setPassword(s.useCode('sara@e11.test', c.code).ticket, 'a good long password');
  assert.deepEqual(used, []);
  assert.equal(s.codesRecord().length, 0);
  assert.equal(s.codesRecord({ owner: true }).length, 1);
});

test('the owner code: owner only, locked an hour after 5 wrong tries, never for good', () => {
  const { s, tick } = make();
  assert.equal(s.useOwnerCode('sara@e11.test', OWNER_CODE).ok, false);
  for (let i = 0; i < 5; i++) assert.equal(s.useOwnerCode('owner@e11.test', '0000').ok, false);
  assert.equal(s.useOwnerCode('owner@e11.test', OWNER_CODE).ok, false, 'locked');
  tick(3600_000 + 1);
  assert.equal(s.useOwnerCode('owner@e11.test', OWNER_CODE).ok, true);
});

test('passwords: 5 wrong tries lock it for a while', () => {
  const { s, tick } = make();
  s.setPassword(s.useCode('sara@e11.test', s.makeCode('sara@e11.test', 'a@e11.test').code).ticket, 'a good long password');
  for (let i = 0; i < 5; i++) assert.equal(s.signInPassword('sara@e11.test', 'nope nope').ok, false);
  assert.equal(s.signInPassword('sara@e11.test', 'a good long password').ok, false);
  tick(15 * 60_000 + 1);
  assert.equal(s.signInPassword('sara@e11.test', 'a good long password').ok, true);
});

test("OpenID Connect: Cloudflare's code for a signed token with the email", () => {
  const { s } = make();
  const redirectUri = 'https://team.cloudflareaccess.com/cdn-cgi/access/callback';
  assert.equal(s.redirectOk(s.client('cf'), 'https://evil.test/cb'), false);
  const code = s.authCode('sara@e11.test', { clientId: 'cf', redirectUri, nonce: 'n1' });
  assert.equal(s.exchange({ code, clientId: 'cf', clientSecret: 'wrong', redirectUri }).error, 'invalid_client');
  const code2 = s.authCode('sara@e11.test', { clientId: 'cf', redirectUri, nonce: 'n1' });
  const r = s.exchange({ code: code2, clientId: 'cf', clientSecret: 'shh-secret', redirectUri });
  assert.ok(r.id_token);
  const [h, b, sig] = r.id_token.split('.');
  const claims = JSON.parse(Buffer.from(b, 'base64url').toString());
  assert.equal(claims.email, 'sara@e11.test'); assert.equal(claims.aud, 'cf'); assert.equal(claims.nonce, 'n1');
  const jwk = s.jwks().keys[0];
  assert.ok(crypto.verify('RSA-SHA256', Buffer.from(`${h}.${b}`), crypto.createPublicKey({ key: jwk, format: 'jwk' }), Buffer.from(sig, 'base64url')));
  assert.equal(s.exchange({ code: code2, clientId: 'cf', clientSecret: 'shh-secret', redirectUri }).error, 'invalid_grant', 'one use');
  assert.equal(s.userinfo(r.access_token).email, 'sara@e11.test');
});

test('device keys: kept while good, a new one otherwise; stop when the password is set with a code, or the person leaves', () => {
  const { s, tick } = make();
  const a = s.deviceKey('sara@e11.test', null, 'iPhone');
  assert.ok(a.ok && a.key && !a.kept);
  assert.equal(s.deviceKey('sara@e11.test', a.key).kept, true);
  assert.equal(s.useDevice(a.key).email, 'sara@e11.test');
  assert.equal(s.useDevice(a.key.split('.')[0] + '.wrong').ok, false);
  assert.equal(s.deviceKey('owner@e11.test', a.key).kept, undefined, "someone else's key isn't kept for them");
  tick(1000);
  s.setPassword(s.useCode('sara@e11.test', s.makeCode('sara@e11.test', 'admin@e11.test').code).ticket, 'a good long password');
  assert.equal(s.useDevice(a.key).ok, false, 'the password set with a code ends it');
  const b = s.deviceKey('sara@e11.test', a.key);
  assert.ok(b.ok && b.key !== a.key);
  assert.equal(s.useDevice(b.key).ok, true);
  s.dropDevice(b.key);
  assert.equal(s.useDevice(b.key).ok, false, 'signed out: dropped');
  const c = s.deviceKey('sara@e11.test', null);
  users['sara@e11.test'].removed = true;
  assert.equal(s.useDevice(c.key).ok, false, 'left the team');
  delete users['sara@e11.test'].removed;
});
