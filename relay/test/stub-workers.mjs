// Cloudflare's own module, as far as the hub uses it — so the hub itself can be started in a test (Haris 2026-11-22 12:22:
// a start-up error reached the live hub; every deploy now starts it here first)
export class DurableObject { constructor(ctx, env) { this.ctx = ctx; this.env = env; } }
