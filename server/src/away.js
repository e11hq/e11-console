// Out of Office (Haris 2026-11-13, mock-up "Out of Office" approved): each person sets their own — the day they're back
// (user.away, 'YYYY-MM-DD'). Until 9:00 AM Dubai time that day every notification of theirs pauses (E11 Console's phone
// and browser notifications, the morning summary, reminders, E11 Talk's); the Inbox and the chats still collect everything.
// At 9:00 AM on the day it's over by itself — nothing needs clearing; the apps work it out the same way.
export const AWAY_RE = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
// the moment it ends: 9:00 AM in Dubai (UTC+4, no daylight saving) = 05:00 UTC that day
export const awayEnds = (day) => (AWAY_RE.test(String(day || '')) ? Date.parse(`${day}T05:00:00Z`) : 0);
export const isAway = (u, now = Date.now()) => !!u && now < awayEnds(u.away);
// tags that still come while away: the test notifications you send yourself (My profile)
export const AWAY_PASS = new Set(['test', 'digest-test']);
