// The iPhone app's Home straight from the server (iPhone app 25+): GET /api/home → the same model the app used to get
// from the page behind it (NativeHome in phone.js), worked out here with the same shared rules file (web/rules.js), from
// what this person may see (the same data their own app downloads). Read only.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export function createHomeView({ webDir, now = () => Date.now() }) {
  const file = path.join(webDir || path.resolve(here, '../../web'), 'rules.js');
  let rules = null, loadedAt = 0;
  // (read again when the file changes — a new version installed)
  function load() {
    const m = fs.statSync(file).mtimeMs;
    if (!rules || m !== loadedAt) {
      const src = fs.readFileSync(file, 'utf8');
      rules = vm.runInNewContext(`${src}; E11Rules`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN });
      loadedAt = m;
    }
    return rules;
  }
  const fileUrl = (p) => '/__file/' + String(p).split('/').map(encodeURIComponent).join('/');
  // data: what this person's own app downloads (visibleSnapshot in server.js)
  function home(u, data) {
    const R = load();
    const today = R.dubaiDay(now());
    const m = R.home({ users: data.users || [], projects: data.projects || [], tasks: data.tasks || [], statuses: data.statuses || [], plans: data.plans || [], meta: data.meta || {} }, u.id, today);
    if (!m) return null;
    // photos: the app fetches them itself (a small copy), signed in as it is
    for (const p of Object.values(m.people || {})) { if (p.photo) p.photo = fileUrl(p.photo) + '?view=1'; }
    return { ...m, today };
  }
  return { home };
}
