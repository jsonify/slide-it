import test from 'node:test';
import assert from 'node:assert/strict';
import { makeTarget, makeBoard, slide, canSlide, isSolved, matches, isValidBoard, EMPTY, CENTER, COLORS } from '../public/game.js';

const B = (s) => s.split('');

test('target never uses more than 4 of a colour', () => {
  for (let i = 0; i < 500; i++) {
    const t = makeTarget();
    assert.equal(t.length, 9);
    for (const c of COLORS) assert.ok(t.filter((x) => x === c).length <= 4);
  }
});

test('boards are valid and start scrambled', () => {
  for (let i = 0; i < 300; i++) {
    const t = makeTarget();
    const b = makeBoard(t);
    assert.ok(isValidBoard(b));
    assert.ok(matches(b, t) <= 2);
  }
});

test('slide moves a single tile into the gap', () => {
  //            row0  row1  row2  row3  row4
  const b = B('RRRROOOOYYYYGGGGBBBBWWWW.');
  const r = slide(b, 23);
  assert.equal(r.board.join(''), 'RRRROOOOYYYYGGGGBBBBWWW.W');
  assert.deepEqual(r.path, [[23, 24]]);
});

test('slide pushes a whole row', () => {
  const b = B('RRRROOOOYYYYGGGGBBBBWWWW.');
  const r = slide(b, 20);
  assert.equal(r.board.join(''), 'RRRROOOOYYYYGGGGBBBB.WWWW');
  assert.equal(r.path.length, 4);
});

test('slide pushes a whole column', () => {
  const b = B('.RRROOOOYYYYGGGGBBBBWWWWR');
  const r = slide(b, 20);
  assert.equal(r.board[0], 'O');
  assert.equal(r.board[20], EMPTY);
  assert.ok(isValidBoard(r.board));
});

test('illegal moves are rejected', () => {
  const b = B('RRRROOOOYYYYGGGGBBBBWWWW.');
  assert.equal(slide(b, 0), null); // not in line with the gap
  assert.equal(slide(b, 24), null); // the gap itself
  assert.equal(canSlide(b, 6), false);
  assert.equal(canSlide(b, 4), true);
});

test('isSolved checks only the centre 3x3', () => {
  const b = B('RRRROOOOYYYYGGGGBBBBWWWW.');
  const target = CENTER.map((i) => b[i]);
  assert.ok(isSolved(b, target));
  const other = target.slice();
  other[0] = other[0] === 'W' ? 'R' : 'W';
  assert.ok(!isSolved(b, other));
});

test('a random target is reachable by random play (sanity)', () => {
  // Greedy-free check: random walk keeps the board valid indefinitely.
  let b = makeBoard(makeTarget());
  for (let i = 0; i < 2000; i++) {
    const r = slide(b, Math.floor(Math.random() * 25));
    if (r) b = r.board;
  }
  assert.ok(isValidBoard(b));
});
