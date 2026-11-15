// Sign out — this browser / this Mac only (Haris 2026-11-15): never Cloudflare's /cdn-cgi/access/logout (it signs the person
// out on every device); /sign-out clears only this browser's Cloudflare sign-in for the site and goes on to sign in again
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer } from '../src/server.js';

let app, base, dir;
before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'e11so-'));
  app = createServer({ dataDir: dir, dev: true, digest: false, occRemind: false });
  base = `http://127.0.0.1:${await app.listen(0, '127.0.0.1')}`;
});
after(async () => { await app.close(); fs.rmSync(dir, { recursive: true, force: true }); });

test('/sign-out clears this browser\'s Cloudflare sign-in and goes back to the start', async () => {
  const r = await fetch(base + '/sign-out', { redirect: 'manual', headers: { Cookie: 'CF_Authorization=abc' } });
  assert.equal(r.status, 303);
  assert.equal(r.headers.get('location'), '/');
  assert.equal(r.headers.get('cache-control'), 'no-store');
  const set = r.headers.getSetCookie();
  for (const n of ['CF_Authorization', 'CF_AppSession']) {
    const c = set.find((x) => x.startsWith(n + '='));
    assert.ok(c, n + ' cleared');
    assert.match(c, /^[^=]+=;/); assert.match(c, /Max-Age=0/); assert.match(c, /Path=\//);
  }
});

test('the page signs out through /sign-out, never Cloudflare\'s sign-out for everyone', () => {
  const web = (f) => fs.readFileSync(new URL('../../web/' + f, import.meta.url), 'utf8');
  assert.match(web('app.js'), /const signOutUrl = \(\) => \(window\.E11_REVIEW \? '\/review\/sign-out' : '\/sign-out'\)/);
  for (const f of ['app.js', 'phone.js']) assert.ok(!/location\.href\s*=\s*['"]\/cdn-cgi\/access\/logout/.test(web(f)), f);
  assert.ok(!/code from your email/.test(web('phone.js')), 'no email code any more');
});
