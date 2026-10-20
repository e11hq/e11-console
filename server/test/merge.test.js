import { test } from 'node:test';
import assert from 'node:assert/strict';
import { merge3 } from '../src/merge.js';

const task = () => ({ id: 't1', title: 'EDM', tags: ['ford'], assignees: ['a'], comments: [{ id: 'c1', text: 'hi' }], checklist: [{ id: 'k1', text: 'x', done: false }] });

test('two people comment on the same task at the same time: both comments kept', () => {
  const base = task();
  const mine = { ...task(), comments: [...base.comments, { id: 'c2', text: 'mine' }] };
  const theirs = { ...task(), comments: [...base.comments, { id: 'c3', text: 'theirs' }] };
  const out = merge3(base, mine, theirs);
  assert.deepEqual(out.comments.map((c) => c.id), ['c1', 'c3', 'c2']);
});

test('different fields edited by two people: both kept', () => {
  const base = task();
  const out = merge3(base, { ...base, title: 'EDM v2' }, { ...base, due: '2026-10-21' });
  assert.equal(out.title, 'EDM v2');
  assert.equal(out.due, '2026-10-21');
});

test('deleting a comment is not undone by someone else adding one', () => {
  const base = task();
  const mine = { ...base, comments: [] };
  const theirs = { ...base, comments: [...base.comments, { id: 'c3', text: 'new' }] };
  assert.deepEqual(merge3(base, mine, theirs).comments.map((c) => c.id), ['c3']);
});

test('assignees and tags merge as sets', () => {
  const base = task();
  const out = merge3(base, { ...base, assignees: ['a', 'b'], tags: [] }, { ...base, assignees: ['a', 'c'], tags: ['ford', 'edm'] });
  assert.deepEqual(out.assignees, ['a', 'c', 'b']);
  assert.deepEqual(out.tags, ['edm']);
});

test('same checklist item ticked by one and renamed by another', () => {
  const base = task();
  const mine = { ...base, checklist: [{ id: 'k1', text: 'x', done: true }] };
  const theirs = { ...base, checklist: [{ id: 'k1', text: 'renamed', done: false }] };
  assert.deepEqual(merge3(base, mine, theirs).checklist, [{ id: 'k1', text: 'renamed', done: true }]);
});

test('unchanged save keeps the server version', () => {
  const base = task();
  const theirs = { ...base, title: 'server' };
  assert.equal(merge3(base, task(), theirs).title, 'server');
});

test('true conflict on one field: latest save wins', () => {
  const base = task();
  assert.equal(merge3(base, { ...base, title: 'A' }, { ...base, title: 'B' }).title, 'A');
});

test('reordering sections is kept when the server only renamed one', () => {
  const base = { id: 'p', sections: [{ id: 's1', name: 'To do' }, { id: 's2', name: 'Doing' }, { id: 's3', name: 'Done' }] };
  const mine = { id: 'p', sections: [base.sections[2], base.sections[0], base.sections[1]] };
  const theirs = { id: 'p', sections: [{ id: 's1', name: 'Backlog' }, base.sections[1], base.sections[2]] };
  const out = merge3(base, mine, theirs);
  assert.deepEqual(out.sections.map((s) => s.id + ':' + s.name), ['s3:Done', 's1:Backlog', 's2:Doing']);
});

test('removed key on one side', () => {
  const base = { id: 1, a: 1, b: 2 };
  assert.deepEqual(merge3(base, { id: 1, a: 1 }, { id: 1, a: 5, b: 2 }), { id: 1, a: 5 });
});
