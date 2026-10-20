// Three-way merge used when someone saves an item that changed on the server since they loaded it.
//   base   = the version the person's app last saw
//   mine   = what the person is saving now
//   theirs = what the server has now (someone else may have changed it)
// Only the parts the person actually changed are applied on top of the server's version, so two
// people commenting on (or editing different fields of) the same task never overwrite each other.

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const hasId = (v) => isObj(v) && (typeof v.id === 'string' || typeof v.id === 'number');
const isIdArray = (a) => Array.isArray(a) && a.every(hasId);
const isPrimArray = (a) => Array.isArray(a) && a.every((x) => x === null || typeof x !== 'object');

export function deepEqual(a, b) {
  if (a === b) return true;
  if (typeof a !== typeof b || a === null || b === null || typeof a !== 'object') return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a)) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (!deepEqual(a[i], b[i])) return false;
    return true;
  }
  const ka = Object.keys(a), kb = Object.keys(b);
  if (ka.length !== kb.length) return false;
  for (const k of ka) if (!Object.prototype.hasOwnProperty.call(b, k) || !deepEqual(a[k], b[k])) return false;
  return true;
}

export function merge3(base, mine, theirs) {
  if (deepEqual(mine, base)) return theirs;     // I didn't touch it: keep the server's
  if (deepEqual(theirs, base)) return mine;     // nobody else touched it: take mine
  if (deepEqual(mine, theirs)) return mine;     // we both made the same change
  if (isObj(mine) && isObj(theirs)) return mergeObjects(isObj(base) ? base : {}, mine, theirs);
  const arrays = [base, mine, theirs].filter((x) => x !== undefined);
  if (Array.isArray(mine) && Array.isArray(theirs)) {
    if (arrays.every(isIdArray)) return mergeIdArrays(Array.isArray(base) ? base : [], mine, theirs);
    if (arrays.every(isPrimArray)) return mergeSets(Array.isArray(base) ? base : [], mine, theirs);
  }
  return mine;                                   // true conflict on a single value: latest save wins
}

function mergeObjects(base, mine, theirs) {
  const out = {};
  const keys = new Set([...Object.keys(theirs), ...Object.keys(mine), ...Object.keys(base)]);
  for (const k of keys) {
    const inMine = Object.prototype.hasOwnProperty.call(mine, k);
    const inTheirs = Object.prototype.hasOwnProperty.call(theirs, k);
    const inBase = Object.prototype.hasOwnProperty.call(base, k);
    if (!inMine && inBase && deepEqual(base[k], theirs[k])) continue;        // I deleted it, they didn't change it
    if (!inTheirs && inBase && deepEqual(base[k], mine[k])) continue;        // they deleted it, I didn't change it
    const v = merge3(base[k], mine[k], theirs[k]);
    if (v !== undefined) out[k] = v;
  }
  return out;
}

// Lists of things with ids (comments, activity, attachments, checklist, sections, folders…)
function mergeIdArrays(base, mine, theirs) {
  const byId = (a) => new Map(a.map((x) => [String(x.id), x]));
  const b = byId(base), m = byId(mine), t = byId(theirs);
  const out = [];
  // Use my order if I reordered things, otherwise the server's order
  const common = (a) => a.map((x) => String(x.id)).filter((id) => b.has(id));
  const reordered = !deepEqual(common(mine), common(base).filter((id) => m.has(id)));
  const order = reordered ? [...mine, ...theirs.filter((x) => !m.has(String(x.id)))] : [...theirs, ...mine.filter((x) => !t.has(String(x.id)))];
  const seen = new Set();
  for (const item of order) {
    const id = String(item.id);
    if (seen.has(id)) continue;
    seen.add(id);
    const inB = b.has(id), inM = m.has(id), inT = t.has(id);
    if (inB && !inM) continue;                  // I removed it
    if (inB && !inT) continue;                  // someone else removed it
    if (inM && inT) out.push(merge3(b.get(id), m.get(id), t.get(id)));
    else if (inM) out.push(m.get(id));          // I added it
    else out.push(t.get(id));                   // someone else added it
  }
  return out;
}

// Lists of plain values (tags, assignees): apply my additions and removals to the server's list
function mergeSets(base, mine, theirs) {
  const key = (x) => JSON.stringify(x);
  const bk = new Set(base.map(key)), mk = new Set(mine.map(key));
  const removed = new Set(base.filter((x) => !mk.has(key(x))).map(key));
  const added = mine.filter((x) => !bk.has(key(x)));
  const out = theirs.filter((x) => !removed.has(key(x)));
  const have = new Set(out.map(key));
  added.forEach((x) => { if (!have.has(key(x))) { out.push(x); have.add(key(x)); } });
  return out;
}
