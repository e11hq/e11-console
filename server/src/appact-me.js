// Part B step 4: the iPhone app's My profile, done on the server — the same record the page's saveMe saved (web/phone.js
// NativeMe pfName / pfCountry / pfCity / pfBday / pfSound / pfNotif / pfPhoto / pfPhotoOff, web/app.js 'toggle-digest',
// 'toggle-notif-type'), the same messages. One handler, pfSet(u, body), on body.field:
//   'name'    body.value          your name ('Please enter your name' when empty)
//   'country' body.value          '' = not set; a new country clears the city (as pickPlace)
//   'city'    body.value          '' = not set
//   'bday'    body.value          'MM-DD', or null / '' = none
//   'sound'   body.value          true / false
//   'notif'   body.k, body.on     a notification type on / off (prefs.notifOff)
//   'digest'  body.on             the morning summary on / off (prefs.digestOff)
//   'avatar'  body.value          the new photo's path (from the upload), or null = no photo; the old photo's file goes
//                                 to the server's trash folder (filesGone) when nothing else uses it
// It only ever edits the acting person's own record (u.id) — someone else's can't be named. Answers as the other acts:
//   { ok: true, changes: [{ kind: 'users', id, base, data }], messages, answer: {}, filesGone? } | { ok: false, status, error }
const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
// (web/appme-people.js NOTIF_TYPES: the keys My profile shows)
const NOTIF_KEYS = ['assign', 'mention', 'comment', 'status', 'update', 'cd', 'client', 'due', 'priority', 'attach', 'part', 'result', 'review', 'review-wd', 'daily'];
const MD = /^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
// (where the photo upload puts a profile photo — files.js processImage)
const AVATAR_DIR = 'attachments/_avatars/';

export function createMeActs({ store } = {}) {
  const fail = (status, error, extra = {}) => ({ ok: false, status, error, ...extra });
  const done = (changes, messages = [], answer = {}, more = {}) => ({ ok: true, changes, messages, answer, ...more });
  const text = (v, max = 120) => (typeof v === 'string' && v.length <= max ? v.trim() : null);
  // a file nothing else holds any more (as the server's own trashPath: checked against every record), once x is saved
  function unused(p, x) {
    const hay = ['users', 'projects', 'tasks', 'clients', 'meta', 'finance', 'claims', 'plans', 'scheduled']
      .map((k) => JSON.stringify(k === 'users' ? store.list('users').map((y) => (y.id === x.id ? x : y)) : store.list(k))).join('\n');
    const forms = [p, JSON.stringify(p).slice(1, -1), p.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/</g, '&lt;').replace(/>/g, '&gt;')];
    return !forms.some((f) => hay.includes(f));
  }

  function pfSet(u, body) {
    body = body || {};
    // (the record as stored — never the signed-in copy, which Owner view dresses up with Admin rights)
    const x0 = store.get('users', String(u && u.id));
    if (!x0) return fail(404, 'Your account is no longer here');
    const x = clone(x0);
    const prefs = () => (x.prefs = x.prefs || {});
    const field = String(body.field || '');
    const msgs = [];
    let gone = null;
    if (field === 'name') {
      const v = text(body.value, 200);
      if (!v) return fail(400, 'Please enter your name');
      x.name = v; msgs.push('Name saved');
    } else if (field === 'country') {
      const v = text(body.value == null ? '' : body.value);
      if (v == null) return fail(400, 'Choose a country');
      if (v !== (x.country || '')) x.city = '';
      x.country = v;
    } else if (field === 'city') {
      const v = text(body.value == null ? '' : body.value);
      if (v == null) return fail(400, 'Type the name of your city');
      x.city = v;
    } else if (field === 'bday') {
      const v = body.value == null || body.value === '' ? null : String(body.value);
      if (v != null && !MD.test(v)) return fail(400, 'Choose a day and month');
      if (v === (x.bday || null)) return done([], []);   // (the page saves only a different day)
      x.bday = v;
    } else if (field === 'sound') {
      if (typeof body.value !== 'boolean') return fail(400, 'Not available');
      prefs().sound = body.value;
    } else if (field === 'notif') {
      const k = String(body.k || '');
      if (!NOTIF_KEYS.includes(k) || typeof body.on !== 'boolean') return fail(400, 'Not available');
      const p = prefs(); p.notifOff = p.notifOff || {};
      if (body.on) delete p.notifOff[k]; else p.notifOff[k] = true;
    } else if (field === 'digest') {
      if (typeof body.on !== 'boolean') return fail(400, 'Not available');
      if (!!prefs().digestOff === !body.on) return done([], []);
      x.prefs.digestOff = !body.on;
      msgs.push(x.prefs.digestOff ? 'Morning summary off' : 'Morning summary on — 10:30 am, Monday to Friday');
    } else if (field === 'avatar') {
      const v = body.value == null ? null : String(body.value);
      // (only a photo the upload made — never another file of the office's passed off as a picture)
      if (v != null && (!v.startsWith(AVATAR_DIR) || v.split('/').includes('..') || v.length > 300)) return fail(400, 'Couldn’t use that photo');
      if (x.avatar && x.avatar !== v) gone = x.avatar;
      x.avatar = v;
    } else return fail(400, 'Not available');
    if (same(x0, x)) return done([], []);
    const filesGone = gone && unused(gone, x) ? [gone] : [];
    return done([{ kind: 'users', id: String(x.id), base: clone(x0), data: x }], msgs, {}, filesGone.length ? { filesGone } : {});
  }

  return { pfSet };
}
