// The App Store screenshots' data (ios/shots.py, Haris 2026-11-11): the App Review copy's made-up demo data (server/src/demo.js),
// loaded into a fresh local data folder before the server starts — as the review copy loads it (server.js loadDemo), with
// the reviewer signing in by the given email, and one person's birthday today (the birthday screenshot). Nothing real in it.
// node ios/shots-demo.mjs <data folder> <reviewer email> → prints {"reviewer", "birthday"} as JSON
import fs from 'node:fs';
import path from 'node:path';
import { openStore } from '../server/src/store.js';
import { demoData, DEMO_REVIEWER } from '../server/src/demo.js';

const [dataDir, email] = process.argv.slice(2);
fs.mkdirSync(path.join(dataDir, 'db'), { recursive: true });
const store = openStore(path.join(dataDir, 'db', 'e11.sqlite'));
const now = new Date().toISOString();
store.apply([{ kind: 'meta', id: 'main', data: { createdAt: now } }], 'shots');
store.apply([{ kind: 'users', id: 'u-review', data: { ...DEMO_REVIEWER, email, createdAt: new Date(Date.now() - 400 * 86400000).toISOString() } }], 'shots');
const filesRoot = path.join(dataDir, 'files');
fs.mkdirSync(filesRoot, { recursive: true });
const data = demoData(store, 'u-review', filesRoot);
// (today in Dubai, MM-DD: one active team member — not the reviewer — has their birthday today)
const md = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Dubai', month: '2-digit', day: '2-digit' }).format(new Date()).replace('/', '-');
const bday = data.users.find((u) => u.id !== 'u-review' && u.active !== false && ['am', 'production'].includes(u.role) && u.avatar);
if (bday) bday.bday = md;
store.importAll(data, 'u-review');
console.log(JSON.stringify({ reviewer: email, birthday: bday ? { id: bday.id, email: bday.email, name: bday.name } : null, tasks: data.tasks.length, plans: (data.plans || []).length }));
