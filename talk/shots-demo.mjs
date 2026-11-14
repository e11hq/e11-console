// E11 Talk's App Store screenshots' data (talk/shots.py, Haris 2026-11-14): after E11 Console's demo is in the data folder
// (ios/shots-demo.mjs), the App Review copy's made-up chats for the reviewer — as the review copy makes them every night
// (server.js loadDemo → talk.reviewDemo). Nothing real in it.
// node talk/shots-demo.mjs <data folder> <reviewer email>
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openStore } from '../server/src/store.js';
import { createAccess } from '../server/src/access.js';
import { createTalk } from '../server/src/talk.js';

const [dataDir, email] = process.argv.slice(2);
const store = openStore(path.join(dataDir, 'db', 'e11.sqlite'));
const access = createAccess(store, { ownerEmail: email, plans: true });
const talk = createTalk({ dataDir, store, access });
const demoDir = fileURLToPath(new URL('../server/src/demo/', import.meta.url));
const r = talk.reviewDemo('u-review', demoDir);
console.log(JSON.stringify({ talk: r }));
