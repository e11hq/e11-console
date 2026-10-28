// Made-up data for the App Review copy (review.js) and the App Store screenshots: the same running agency as the test
// copy's sample (sample-fresh.js), told with a made-up story, made-up clients and made-up people, and drawn pictures
// (server/src/demo/, built by scripts/make-demo.py). The sample builder still knows the team by their internal keys,
// so everything it produces goes through scrub() — every real name and brand is swapped for its made-up one — and
// the files are moved to the swapped paths. server/test/demo.test.js checks that nothing real is left.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { freshSample } from './sample-fresh.js';

const DIR = new URL('./demo/', import.meta.url);

export const DEMO_REVIEWER = {
  id: 'u-review', name: 'Alex Morgan', role: 'admin', fin: 'admin', designation: 'Managing Director', active: true, setup: true, avatar: null,
  prefs: { profileAsked: true }, office: 'Dubai — Business Bay office', bday: '03-14', city: 'Dubai', country: 'United Arab Emirates',
};

// real → made up (longest first, whole words, case as written)
const SWAP = [
  // people
  ['Muhammad Haris Sharif', 'Alex Morgan'], ['Mohammad Haris', 'Alex Morgan'], ['Muhammad Arsal', 'Daniel Reyes'], ['Nadia Khashem', 'Leila Aziz'], ['Nadia_khashem', 'Leila'],
  ['Areej Masri', 'Lena Farouk'], ['Lana Al Ramli', 'Maya Rahman'], ['Lana E11', 'Maya Rahman'], ['Carine Abou Jaoude', 'Claire Dubois'], ['Ali Raza', 'Tariq Mansour'],
  ['Moon-Ray Jabra', 'Kai Turner'], ['Moon Jabra', 'Kai Turner'], ['Maab Osama', 'Nadine Fares'], ['Zaahir Hamid', 'Ravi Menon'], ['Zahir Hameed', 'Ravi Menon'],
  ['Aishwarya Sanjay', 'Priya Nair'], ['Amelia Aouidat', 'Sofia Marin'], ['Joe Hajj', 'Marco Silva'], ['Yousef Al Hwij', 'Omar Nasser'], ['Omar Saleh', 'Yusuf Karim'],
  ['Nadia', 'Leila'], ['Areej', 'Lena'], ['Lana', 'Maya'], ['Carine', 'Claire'], ['Aishwarya', 'Priya'], ['Amelia', 'Sofia'], ['Maab', 'Nadine'], ['Zaahir', 'Ravi'], ['Zahir', 'Ravi'],
  ['Yousef', 'Omar'], ['Arsal', 'Daniel'], ['Haris', 'Alex'], ['Maria', 'Elena Petrova'], ['Joe', 'Marco'],
  // clients and places
  ['Ford & Lincoln', 'Northline Motors'], ['Ford Bronco', 'Northline Summit'], ['AL TAYER MOTORS', 'Crescent Motors'], ['Al Tayer', 'Crescent'], ['KOREA 360', 'Seoul Street Market'],
  ['Korea 360', 'Seoul Street Market'], ['korea360', 'seoul-street'], ['Gebriel Motors', 'Granite Auto Parts'], ['Palm Jebel Ali', 'Palmvale Marina'], ['Nakheel Mall', 'Palmvale Mall'],
  ['Dragon City', 'Lantern Market'], ['Nakheel', 'Palmvale'], ['Ford', 'Northline'], ['ford', 'northline'], ['Lincoln', 'Northline'], ['Bronco', 'Summit'], ['KIA', 'Kestrel Auto'],
  ['DEEPAL', 'Voltra EV'], ['ALAIN', 'Azure Bay'], ['Alain', 'Azure Bay'], ['alain', 'azure-bay'], ['HRE', 'Halden Hotels'], ['CPT', 'Coastline Pantry'], ['ASV', 'Aster Health'],
  ['Automechanika', 'Trade Show 2026'], ['automechanika', 'tradeshow'], ['Bizreh', 'Bloom Café'], ['FORTA', 'Fortis Fitness'], ['KOREA', 'SEOUL STREET'], ['Korea', 'Seoul Street'],
  // email addresses
  ['e11-digital.com', 'example.com'], ['gmail.com', 'example.com'], ['sam.rivera.design', 'sam.rivera'],
];
// internal keys that show up in file paths and folder names
const KEYS = [['u-nadia', 'u-d01'], ['u-lina', 'u-d02'], ['u-lana', 'u-d03'], ['u-karim', 'u-d04'], ['u-ali', 'u-d05'], ['u-moon', 'u-d06'], ['u-maab', 'u-d07'],
  ['u-omar', 'u-d08'], ['u-aish', 'u-d09'], ['u-new', 'u-d10'], ['u-maya', 'u-d11'], ['u-joe', 'u-d12'], ['u-sara', 'u-d13'], ['u-arsal', 'u-d14'],
  ['p-ford', 'p-d01'], ['p-kia', 'p-d02'], ['p-deepal', 'p-d03'], ['p-atm', 'p-d04'], ['p-alain', 'p-d05'], ['p-hre', 'p-d06'], ['p-korea', 'p-d07'], ['p-cpt', 'p-d08'],
  ['p-asv', 'p-d09'], ['p-gm', 'p-d10'], ['p-bizreh', 'p-d11'], ['p-forta', 'p-d12'], ['p-nakheel', 'p-d13']];
const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const RE = new RegExp(SWAP.map(([a]) => `(?<![\\w])${reEsc(a)}(?![\\w])`).join('|'), 'g');
const TO = new Map(SWAP);
const KRE = new RegExp(KEYS.map(([a]) => `(?<![\\w])${reEsc(a)}(?![\\w])`).join('|'), 'g');
const KTO = new Map(KEYS);
// (underscores count as separators too, so file names like Ford_Offroad are caught)
const RE2 = new RegExp(SWAP.map(([a]) => `(?<=_|^)${reEsc(a)}(?=_|$)`).join('|'), 'g');
// (drawn logos write the name in capitals, with & as &amp;)
const UP = SWAP.map(([a, b]) => [a.toUpperCase().replace(/&/g, '&amp;'), b.toUpperCase().replace(/&/g, '&amp;')]);
const RE_UP = new RegExp(UP.map(([a]) => `(?<![\\w])${reEsc(a)}(?![\\w])`).join('|'), 'g');
const TO_UP = new Map(UP);
const scrubUpper = (s) => scrub(s).replace(RE_UP, (m) => TO_UP.get(m));
export const scrub = (s) => String(s).replace(KRE, (m) => KTO.get(m)).replace(RE, (m) => TO.get(m)).replace(RE2, (m) => TO.get(m));

// who the internal keys stand for, for the drawn portraits
const FACE = (id) => new URL(`face-${id}.jpg`, DIR);
const hasFace = (id) => fs.existsSync(FACE(id));

export function demoData(store, me, filesRoot) {
  const story = JSON.parse(fs.readFileSync(new URL('demo-story.json', DIR), 'utf8'));
  const stage = filesRoot ? fs.mkdtempSync(path.join(os.tmpdir(), 'e11-demo-')) : null;
  try {
    const out = freshSample(store, me, stage, { story, media: DIR, src: DIR, photo: (id) => (hasFace(id) ? FACE(id) : null) });
    // finance people and the freelancer get portraits too; the reviewer as well
    for (const u of out.users) if (!u.avatar && stage && hasFace(u.id)) { const rel = `attachments/_avatars/smp-${u.id}.jpg`; put(stage, rel, FACE(u.id)); u.avatar = rel; }
    const meUser = store.get('users', me);
    if (meUser && stage) { const rel = `attachments/_avatars/smp-${me}.jpg`; put(stage, rel, FACE('u-review')); out.users.push({ ...meUser, avatar: rel }); }
    out.plans = [];   // (content plans are a trial on the test copy only)
    const data = JSON.parse(scrub(JSON.stringify(out)));
    // everyone's email made from their made-up name (the reviewer keeps the sign-in address)
    for (const u of data.users) { delete u.salt; delete u.hash; u.prefs = { ...(u.prefs || {}), profileAsked: true }; } // (old local sign-in fields; no "add your birthday" card in a demo)
    // every client shows its drawn logo
    for (const c of data.clients || []) { const lf = (c.folders || []).find((f) => f.name === 'Logos'); const svg = lf && lf.files.find((f) => /\.svg$/i.test(f.name)); if (svg && !c.logo) c.logo = svg.path; }
    for (const u of data.users) if (u.id !== me && u.name) u.email = `${u.name.toLowerCase().normalize('NFD').replace(/[^a-z ]/g, '').trim().replace(/\s+/g, '.')}@example.com`;
    if (stage) moveAll(stage, filesRoot);
    return data;
  } finally {
    if (stage) fs.rmSync(stage, { recursive: true, force: true });
  }
}

function put(root, rel, src) {
  const dest = path.join(root, ...rel.split('/'));
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}
// every file to its swapped path; drawn logos (SVG text) get their names swapped inside too
function moveAll(from, to) {
  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]));
  for (const f of walk(from)) {
    const rel = path.relative(from, f).split(path.sep).join('/');
    const dest = path.join(to, ...scrub(rel).split('/'));
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    if (/\.svg$/i.test(f)) fs.writeFileSync(dest, scrubUpper(fs.readFileSync(f, 'utf8')));
    else fs.copyFileSync(f, dest);
  }
}
