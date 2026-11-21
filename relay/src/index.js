// E11 Talk on Cloudflare — not in use yet (claude/talk-cloudflare-relay-plan.md). The hub (a Durable Object holding the
// phones' lines, messages, groups and sign-in) comes next; until then this answers nothing useful.
export default {
  async fetch() { return new Response('E11 Talk relay — not in use yet', { status: 503 }); },
};
