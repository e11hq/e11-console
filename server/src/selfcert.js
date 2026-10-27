// A self-signed certificate for the office-network port (office.js), made with Node's own crypto (no outside
// packages, no openssl needed in the container). The Mac app doesn't trust it by name: it checks the certificate's
// SHA-256 fingerprint, which it gets from the server through the normal signed-in (Cloudflare) connection.
import crypto from 'node:crypto';

const len = (n) => (n < 0x80 ? Buffer.from([n]) : n < 0x100 ? Buffer.from([0x81, n]) : n < 0x10000 ? Buffer.from([0x82, n >> 8, n & 0xff]) : Buffer.from([0x83, n >> 16, (n >> 8) & 0xff, n & 0xff]));
const tlv = (tag, body) => Buffer.concat([Buffer.from([tag]), len(body.length), body]);
const seq = (...items) => tlv(0x30, Buffer.concat(items));
const set = (...items) => tlv(0x31, Buffer.concat(items));
const int = (buf) => tlv(0x02, buf[0] & 0x80 ? Buffer.concat([Buffer.from([0]), buf]) : buf);
const explicit = (n, body) => tlv(0xa0 + n, body);
const utf8 = (s) => tlv(0x0c, Buffer.from(s, 'utf8'));
const bits = (buf) => tlv(0x03, Buffer.concat([Buffer.from([0]), buf]));
function oid(s) {
  const p = s.split('.').map(Number);
  const out = [p[0] * 40 + p[1]];
  for (const v of p.slice(2)) {
    const bytes = [v & 0x7f];
    let x = v >> 7;
    while (x) { bytes.unshift((x & 0x7f) | 0x80); x >>= 7; }
    out.push(...bytes);
  }
  return tlv(0x06, Buffer.from(out));
}
// UTCTime YYMMDDHHMMSSZ (good until 2049)
const utc = (d) => tlv(0x17, Buffer.from(d.toISOString().replace(/[-:T]/g, '').slice(2, 14) + 'Z'));
const ECDSA_SHA256 = '1.2.840.10045.4.3.2';

export function selfSignedCert({ cn = 'E11 Console office', years = 20, now = new Date() } = {}) {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const spki = publicKey.export({ type: 'spki', format: 'der' });
  const serial = crypto.randomBytes(16); serial[0] &= 0x7f;
  const name = seq(set(seq(oid('2.5.4.3'), utf8(cn))));
  const from = new Date(now.getTime() - 86400000), to = new Date(now.getTime() + years * 365 * 86400000);
  const tbs = seq(explicit(0, int(Buffer.from([2]))), int(serial), seq(oid(ECDSA_SHA256)), name, seq(utc(from), utc(to)), name, spki);
  const sig = crypto.sign('sha256', tbs, privateKey);   // (ECDSA: already DER)
  const der = seq(tbs, seq(oid(ECDSA_SHA256)), bits(sig));
  const pem = `-----BEGIN CERTIFICATE-----\n${der.toString('base64').match(/.{1,64}/g).join('\n')}\n-----END CERTIFICATE-----\n`;
  return { cert: pem, key: privateKey.export({ type: 'pkcs8', format: 'pem' }), sha256: crypto.createHash('sha256').update(der).digest('hex') };
}
