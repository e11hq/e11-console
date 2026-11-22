import { test } from 'node:test';
import assert from 'node:assert/strict';
import { presign, bindingR2, PART } from '../src/r2.js';
import { presign as officePresign } from '../../server/src/r2.js';

// the relay's signing (Web Crypto) gives exactly the office's (node:crypto) — the one that worked up to 2026-11-21
test('R2 upload addresses signed exactly as the office signs them', async () => {
  const a = { method: 'PUT', host: 'acc.r2.cloudflarestorage.com', path: '/e11-talk-files/msg/f-1', query: { partNumber: '2', uploadId: 'u x' }, keyId: 'KEYID', secret: 'SECRET/+=', expires: 3600, now: Date.UTC(2026, 10, 22, 18, 0, 0) };
  assert.equal(await presign(a), officePresign(a));
});

test('with the R2 key: uploads go straight to R2 (one address, or parts), and are put together there', async () => {
  const calls = [];
  const go = async (u, o) => { calls.push([o.method, u]); return { ok: true, status: 200, text: async () => (/uploads=/.test(u) ? '<UploadId>UP1</UploadId>' : '<CompleteMultipartUploadResult/>') }; };
  const r2 = bindingR2({ bucket: {}, secret: 's', base: 'https://talkline.test', s3: { account: 'acc', keyId: 'K', secret: 'S', name: 'e11-talk-files' }, go });
  const one = await r2.start('msg/f-1', 1000);
  assert.ok(one.put.startsWith('https://acc.r2.cloudflarestorage.com/e11-talk-files/msg/f-1?'), one.put);
  const big = await r2.start('msg/f-2', PART * 2 + 1);
  assert.equal(big.upload, 'UP1'); assert.equal(big.urls.length, 3);
  assert.ok(big.urls.every((u) => u.startsWith('https://acc.r2.cloudflarestorage.com/e11-talk-files/msg/f-2?') && /uploadId=UP1/.test(u)));
  await r2.complete('msg/f-2', 'UP1', ['"a"', '"b"', '"c"']);
  assert.equal(calls.filter((c) => c[0] === 'POST').length, 2);
  // without the key: through the relay as before
  const old = bindingR2({ bucket: {}, secret: 's', base: 'https://talkline.test' });
  assert.ok((await old.start('msg/f-3', 10)).put.startsWith('https://talkline.test/r2/put/'));
});
