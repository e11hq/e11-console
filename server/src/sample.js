// Sample data for the test copy: E11 people, projects, tasks, comments with replies and Inbox
// updates, moved so they happen around today. The person who asks becomes "Haris" in the story.
import fs from 'node:fs';

const REF_DAY = Date.UTC(2026, 9, 20); // the day the sample story was written
const DAY = 86400000;

export function sampleData(store, me) {
  const raw = fs.readFileSync(new URL('./sample-data.json', import.meta.url), 'utf8');
  const d = JSON.parse(raw.split('"u-haris"').join(JSON.stringify(me)));
  const now = new Date();
  const shift = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) - REF_DAY;
  const move = (v) => {
    if (typeof v === 'string') {
      if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return new Date(Date.parse(v + 'T00:00:00Z') + shift).toISOString().slice(0, 10);
      if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v)) return new Date(Date.parse(v) + shift).toISOString();
      return v;
    }
    if (Array.isArray(v)) return v.map(move);
    if (v && typeof v === 'object') { const o = {}; for (const [k, x] of Object.entries(v)) o[k] = move(x); return o; }
    return v;
  };
  const out = move(d);

  // people: skip anyone already on the team (same email), and the asker
  const have = new Set(store.list('users').map((u) => String(u.email || '').toLowerCase()));
  out.users = out.users.filter((u) => u.id !== me && u.name && !have.has(String(u.email || '').toLowerCase()))
    .map((u) => ({ ...u, setup: true, office: u.office || 'Dubai — Business Bay office' }));
  const known = new Set([me, ...store.list('users').map((u) => u.id), ...out.users.map((u) => u.id)]);

  // no files in the sample (they'd point at files that aren't on this server)
  out.tasks.forEach((t) => { t.attachments = []; (t.comments || []).forEach((c) => { c.attachments = []; }); (t.reviews || []).length = 0; });

  // a few threads with replies, some mentioning you
  const others = out.users.map((u) => u.id);
  const pick = (i) => others[i % others.length];
  const mention = (id, name) => `<span class="mention" data-user="${id}" contenteditable="false">@${name}</span>`;
  const meName = (store.get('users', me) || {}).name || 'you';
  let n = 0;
  out.tasks.filter((t) => !t.parentId && !t.done).slice(0, 6).forEach((t, i) => {
    let top = (t.comments || []).find((c) => !c.parentId);
    const at = (h) => new Date(Date.now() - h * 3600000).toISOString();
    if (!top) {
      top = { id: `smp-c${i}`, text: 'Kick-off notes are in the brief. Shout if anything is unclear.', html: 'Kick-off notes are in the brief. Shout if anything is unclear.', at: at(30 - i), attachments: [], parentId: null, reactions: {}, authorId: pick(i) };
      t.comments = (t.comments || []).concat(top);
    }
    const a = pick(i + 1), b = pick(i + 2);
    t.comments.push(
      { id: `smp-r${i}a`, text: 'On it — first draft by this afternoon.', html: 'On it — first draft by this afternoon.', at: at(20 - i), attachments: [], parentId: top.id, reactions: { '👍': 1 }, authorId: a },
      { id: `smp-r${i}b`, text: `@${meName} can you check the copy before it goes to the client?`, html: `${mention(me, meName)} can you check the copy before it goes to the client?`, at: at(6 - i / 2), attachments: [], parentId: top.id, reactions: {}, authorId: b },
    );
    out.notifications.push({ id: `smp-n${i}`, to: me, from: b, taskId: t.id, kind: 'mention', text: 'mentioned you in a reply on', snippet: `@${meName} can you check the copy before it goes to the client?`, commentId: `smp-r${i}b`, at: at(6 - i / 2), read: false });
    n++;
  });

  // Creative Director for the review flow, unless one is already set
  const meta = store.get('meta', 'main') || {};
  out.meta = { ...meta, cdUserId: meta.cdUserId || (known.has('u-karim') ? 'u-karim' : null) };
  out.notifications = out.notifications.filter((x) => x.to === me || known.has(x.to));
  return out;
}
