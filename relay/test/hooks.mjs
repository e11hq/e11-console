// Tests outside Cloudflare: Talk's own code gets the hub's stand-ins for node:sqlite and node:fs, as wrangler's alias gives it.
const SHIM = { 'node:sqlite': new URL('../src/shims/sqlite.js', import.meta.url).href, 'node:fs': new URL('../src/shims/fs.js', import.meta.url).href };
export async function resolve(spec, ctx, next) {
  if (spec === 'cloudflare:workers') return { url: new URL('./stub-workers.mjs', import.meta.url).href, shortCircuit: true };
  if (SHIM[spec] && ctx.parentURL && ctx.parentURL.endsWith('/server/src/talk.js')) return { url: SHIM[spec], shortCircuit: true };
  return next(spec, ctx);
}
