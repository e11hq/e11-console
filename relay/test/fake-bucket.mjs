// A stand-in for an R2 bucket binding (put / head / get / delete / multipart), in memory.
export function fakeBucket() {
  const objs = new Map(), ups = new Map();
  // (a stream, as the Worker now hands over, read whole here)
  const bytes = async (b) => (b && typeof b.getReader === 'function' ? new Uint8Array(await new Response(b).arrayBuffer()) : new Uint8Array(b));
  const obj = (k) => { const b = objs.get(k); return b && { size: b.byteLength, httpEtag: '"e"', body: b }; };
  return {
    objs,
    async put(k, body) { objs.set(k, await bytes(body)); return { etag: 'e-' + k }; },
    async head(k) { return obj(k) || null; },
    async get(k, o = {}) { const b = objs.get(k); if (!b) return null; const r = o.range; if (!r) return obj(k);
      const off = r.offset ?? b.byteLength - r.suffix, len = r.length ?? b.byteLength - off; return { size: b.byteLength, httpEtag: '"e"', range: r, body: b.slice(off, off + len) }; },
    async delete(k) { objs.delete(k); },
    async createMultipartUpload(k) { const id = 'up' + (ups.size + 1); ups.set(id, { k, parts: new Map() }); return { uploadId: id }; },
    resumeMultipartUpload(k, id) { const u = ups.get(id); return {
      async uploadPart(n, body) { u.parts.set(n, await bytes(body)); return { partNumber: n, etag: 'p' + n }; },
      async complete(list) { const parts = list.map((x) => u.parts.get(x.partNumber)); const all = new Uint8Array(parts.reduce((a, p) => a + p.byteLength, 0)); let o = 0; for (const p of parts) { all.set(p, o); o += p.byteLength; } objs.set(k, all); ups.delete(id); } }; },
  };
}
