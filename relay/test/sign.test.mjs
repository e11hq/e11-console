import { test } from 'node:test';
import assert from 'node:assert/strict';
import { newKey, signHeaders, verify, fingerprint } from '../src/sign.js';

test('the office’s signature: right body passes, anything changed or old fails', async () => {
  const k = await newKey(), body = '{"a":1}';
  const h = new Headers(await signHeaders(k.priv, 'POST', '/office/dir', body));
  assert.equal(await verify(k.pub, 'POST', '/office/dir', body, h), true);
  assert.equal(await verify(k.pub, 'POST', '/office/dir', '{"a":2}', h), false);
  assert.equal(await verify(k.pub, 'POST', '/office/load', body, h), false);
  const other = await newKey();
  assert.equal(await verify(other.pub, 'POST', '/office/dir', body, h), false);
  const old = new Headers(await signHeaders(k.priv, 'POST', '/office/dir', body, Date.now() - 10 * 60_000));
  assert.equal(await verify(k.pub, 'POST', '/office/dir', body, old), false);
});
test('a sign-in’s fingerprint: the same for the same, different otherwise', async () => {
  const a = await fingerprint(new Headers({ cookie: 's=1' })), b = await fingerprint(new Headers({ cookie: 's=1' })), c = await fingerprint(new Headers({ cookie: 's=2' }));
  assert.equal(a, b); assert.notEqual(a, c);
});
