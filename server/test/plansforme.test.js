// The content skeletons waiting for someone's approval, every month (E11AppMe.plansForMe) — the CD's Review Requests show
// them as their own group "Content plans" on top of Waiting (Haris 2026-11-10, the mock-up "Review Requests — fully Apple", A2)
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const src = ['rules.js', 'appview.js', 'appme-plans.js'].map((f) => fs.readFileSync(new URL('../../web/' + f, import.meta.url), 'utf8')).join(';\n');
const engine = () => vm.runInNewContext(`${src}; ({ E11Rules, E11AppView, E11AppMe })`, { Date, Math, Number, String, Object, Array, JSON, Map, Set, parseInt, isNaN, encodeURIComponent, RegExp });
const hours = (n) => new Date(Date.now() - n * 36e5).toISOString();
const data = {
  users: [
    { id: 'u-cd', name: 'Carine Saab', email: 'cd@x.test', role: 'am', active: true },
    { id: 'u-se', name: 'Lina Fares', email: 'se@x.test', role: 'social', active: true },
    { id: 'u-sm', name: 'Mona Manager', email: 'sm@x.test', role: 'social', active: true },
    { id: 'u-p', name: 'Ali Designer', email: 'p@x.test', role: 'production', active: true },
  ],
  projects: [
    { id: 'p1', name: 'Blue Bay', color: '#2f7f9e', socials: ['u-se'], sections: [] },
    { id: 'p2', name: 'Cedar Foods', color: '#3f7d6a', socials: ['u-se'], sections: [] },
    { id: 'p3', name: 'Old Client', color: '#888888', socials: ['u-se'], inactive: true, sections: [] },
  ],
  statuses: [], meta: { cdUserId: 'u-cd', socialMgrIds: ['u-sm'] },
  plans: [
    { id: 'pl1', projectId: 'p1', month: '2026-12', status: 'review', review: { by: 'u-se', at: hours(2), to: 'both' }, posts: [] },
    { id: 'pl2', projectId: 'p2', month: '2027-01', status: 'review', review: { by: 'u-se', at: hours(5), to: 'cd' }, posts: [] },
    { id: 'pl3', projectId: 'p2', month: '2026-12', status: 'review', review: { by: 'u-se', at: hours(1), to: 'sm' }, posts: [] },   // the Social Manager's only
    { id: 'pl4', projectId: 'p1', month: '2027-01', status: 'approved', posts: [] },
    { id: 'pl5', projectId: 'p3', month: '2026-12', status: 'review', review: { by: 'u-se', at: hours(3), to: 'cd' }, posts: [] },   // an inactive client's
  ],
  tasks: [], notifications: [],
};
const forMe = (me) => { const { E11Rules: R, E11AppMe: M } = engine(); return M.plansForMe(R, data, me, Date.now()).rows; };

test('the CD: every skeleton sent to them, any month, oldest sent first — not one sent only to the Social Manager', () => {
  const rows = forMe('u-cd');
  assert.deepEqual(rows.map((r) => r.id), ['pl2', 'pl1']);
  assert.equal(rows[0].title, 'Cedar Foods · January 2027');
  assert.match(rows[1].sub, /^Content skeleton · Lina sent it · /);
  assert.equal(rows[1].pid, 'p1'); assert.equal(rows[1].month, '2026-12');
});

test('the Social Manager: theirs; someone else: none', () => {
  assert.deepEqual(forMe('u-sm').map((r) => r.id), ['pl1', 'pl3']);
  assert.equal(forMe('u-p').length, 0);
});
