// E11 Talk's App Store screenshots' data (talk/shots.py, Haris 2026-11-14): after E11 Console's demo is in the data folder
// (ios/shots-demo.mjs), the App Review copy's made-up chats for the reviewer — as the review copy makes them every night
// (server.js loadDemo → talk.reviewDemo). Nothing real in it.
// node talk/shots-demo.mjs <data folder> <reviewer email>
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openStore } from '../server/src/store.js';
import { createAccess } from '../server/src/access.js';
import { createTalk } from '../server/src/talk.js';
import { DatabaseSync } from 'node:sqlite';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';

const [dataDir, email] = process.argv.slice(2);
const store = openStore(path.join(dataDir, 'db', 'e11.sqlite'));
const access = createAccess(store, { ownerEmail: email, plans: true });
const talk = createTalk({ dataDir, store, access });
const demoDir = fileURLToPath(new URL('../server/src/demo/', import.meta.url));
const r = talk.reviewDemo('u-review', demoDir);

// the boards' extras (screenshots only): a voice note with reactions in a Social group, your reply, and a linked Mac
const users = store.list('users'), byId = (id) => users.find((x) => x.id === id);
const me = byId('u-review');
const g = talk.state(me).groups.find((x) => /Social$/.test(x.name)) || talk.state(me).groups[0];
const others = g.members.filter((id) => id !== me.id).map(byId).filter(Boolean);
let voice = Buffer.alloc(8192);
try {
  const f = path.join(os.tmpdir(), 'talk-voice.m4a');
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'sine=frequency=220:duration=42', '-c:a', 'aac', '-b:a', '32k', f]);
  voice = fs.readFileSync(f);
} catch { /* no ffmpeg: the bytes don't matter for a picture */ }
const extra = {};
if (others.length) {
  const a = others[0];
  const up = talk.upload(a, null, 'Voice message.m4a', 0, voice, true);
  const wave = Buffer.from([10,18,30,46,34,20,40,62,52,30,18,34,56,74,48,26,14,30,52,42,26,14,30,22,36,26,44,60,38,22,12,26,40,58,44,28,18,32,50,36,22,12,24,18,30,20,14,10].map((v) => Math.min(255, v * 3.4))).toString('base64');
  const sent = talk.act(a, { act: 'send', group: g.id, text: '', file: { id: up.id, kind: 'voice', secs: 42, wave } });
  extra.voice = sent;
  for (const [x, e] of [[others[1], '👏'], [others[2], '🔥'], [me, '👏']]) if (x && sent.id) talk.act(x, { act: 'react', msg: sent.id, emoji: e });
  extra.reply = talk.act(me, { act: 'send', group: g.id, text: 'Got it — thanks! 🙌' });
}
const db = new DatabaseSync(path.join(dataDir, 'db', 'talk.sqlite'));
const first = String(me.name || 'Alex').split(' ')[0];
db.prepare('INSERT INTO macs (id, uid, name, linked_at, seen_at) VALUES (?, ?, ?, ?, ?)').run('mac-demo', me.id, `${first}’s MacBook Pro`, Date.now() - 12 * 86400_000, Date.now() - 4 * 60_000);
db.close();
console.log(JSON.stringify({ talk: r, group: g.name, extra }));
