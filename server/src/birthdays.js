// Birthdays: on a team member's birthday (day and month from their profile; 29 Feb is celebrated on 28 Feb in
// other years), from 9:00 Dubai the rest of the staff get an Inbox update and a phone notification
// "Today is <name>'s birthday". Freelancers neither get nor send them. Each birthday goes out once.
// The birthday person sees "Happy birthday" with confetti in their own app (web/app.js); the date itself is
// never sent to anyone else's app (access.shape).
import crypto from 'node:crypto';
import { dubaiNow } from './digest.js';

const START = 9 * 60;
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const staff = (u) => !!u && u.active !== false && u.role !== 'freelancer';
// is "MM-DD" today (a leap-day birthday falls on 28 Feb when there's no 29th)
export function isBirthday(bday, day) {
  const md = String(bday || '');
  if (!/^\d{2}-\d{2}$/.test(md)) return false;
  if (md === day.slice(5)) return true;
  const y = Number(day.slice(0, 4)), leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  return md === '02-29' && !leap && day.slice(5) === '02-28';
}
const first = (u) => String(u.name || String(u.email || '').split('@')[0]).trim().split(/\s+/)[0];

export function createBirthdays({ store, webPush, notifMessage, deliver, now = () => Date.now(), log = console }) {
  let timer = null;
  const load = () => { try { return JSON.parse(store.kv.get('bday-sent') || '{}'); } catch { return {}; } };
  async function tick() {
    const t = dubaiNow(now());
    if (t.minutes < START) return 0;
    const users = store.list('users');
    const sent = load();
    let made = 0;
    for (const b of users.filter((u) => staff(u) && isBirthday(u.bday, t.day))) {
      const key = `${t.day}:${b.id}`;
      if (sent[key]) continue;
      sent[key] = new Date(now()).toISOString();
      // (only the last few weeks are kept)
      for (const k of Object.keys(sent)) if (k.slice(0, 10) < new Date(now() - 40 * 86400000).toISOString().slice(0, 10)) delete sent[k];
      store.kv.set('bday-sent', JSON.stringify(sent));   // marked first: a crash never sends twice
      const at = new Date(now()).toISOString();
      const ops = users.filter((u) => staff(u) && u.id !== b.id).map((u) => {
        const id = 'n-bd' + crypto.randomBytes(6).toString('hex');
        return { kind: 'notifications', id, data: { id, to: u.id, from: b.id, kind: 'birthday', text: `Today is <b>${esc(first(b))}</b>’s birthday`, snippet: '', at, read: false } };
      });
      if (!ops.length) continue;
      const out = store.apply(ops, 'birthdays');
      if (deliver) deliver(out);
      made += ops.length;
      for (const r of out.results) {
        if (r.refused || !r.data) continue;
        try { await webPush.sendTo(r.data.to, notifMessage(store, r.data), { ttl: Math.max(60, Math.floor((t.endOfDay - now()) / 1000)) }); } catch { /* phone offline */ }
      }
    }
    return made;
  }
  return {
    tick,
    start() { if (!timer) { timer = setInterval(() => { tick().catch((e) => log.error('birthdays:', e.message)); }, 60_000); if (timer.unref) timer.unref(); tick().catch(() => {}); } },
    stop() { if (timer) { clearInterval(timer); timer = null; } },
  };
}
