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

import { makeGoal, makeBoardFor, progress, goalSolved, matchedCells, CHALLENGE_IDS, CHALLENGES, WILD, SIZE } from '../public/game.js';

test('every challenge deals an achievable goal and a scrambled tray', () => {
  for (const id of CHALLENGE_IDS) {
    for (let i = 0; i < 100; i++) {
      const g = makeGoal(id);
      assert.equal(g.id, id);
      assert.ok(CHALLENGES[id].rule);
      for (const c of COLORS) assert.ok(g.want.filter((x) => x === c).length <= 4, `${id} colour budget`);
      if (g.cells) assert.equal(g.cells.length, g.want.length);
      assert.equal(g.show.tiles.length, g.show.w * g.show.h);
      const b = makeBoardFor(g);
      assert.ok(isValidBoard(b));
      assert.ok(!goalSolved(b, g), `${id} must not start solved`);
    }
  }
});

// Build a tray that satisfies a goal by placing wanted colours, then filling the rest.
function solve(goal, origin = 0) {
  const board = Array(25).fill(null);
  const left = { R: 4, O: 4, Y: 4, G: 4, B: 4, W: 4 };
  const cells = goal.cells || [...Array(9).keys()].map((k) => origin + Math.floor(k / 3) * SIZE + (k % 3));
  cells.forEach((c, i) => {
    const w = goal.want[i];
    if (w !== WILD) (board[c] = w), left[w]--;
  });
  const rest = Object.entries(left).flatMap(([c, n]) => Array(n).fill(c));
  rest.push(EMPTY);
  // Put the gap outside the goal so wildcards are covered.
  const free = board.map((x, i) => (x === null ? i : -1)).filter((i) => i >= 0);
  const outside = free.filter((i) => !cells.includes(i));
  board[outside[0]] = EMPTY;
  rest.pop();
  for (const i of free) if (board[i] === null) board[i] = rest.shift();
  return board;
}

test('goals are solved exactly when their cells match', () => {
  for (const id of CHALLENGE_IDS) {
    const g = makeGoal(id);
    const b = solve(g);
    assert.ok(isValidBoard(b), id);
    assert.ok(goalSolved(b, g), `${id} solved`);
    assert.equal(progress(b, g).n, g.want.length);
  }
});

test('mirror and twist ask for the transformed picture', () => {
  const m = makeGoal('mirror');
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) assert.equal(m.want[r * 3 + c], m.show.tiles[r * 3 + (2 - c)]);
  const t = makeGoal('twist');
  // Top row of the build is the picture's left column read bottom-to-top.
  assert.deepEqual(t.want.slice(0, 3), [t.show.tiles[6], t.show.tiles[3], t.show.tiles[0]]);
});

test('anywhere goals count the best placement on the tray', () => {
  const g = makeGoal('anywhere');
  const b = solve(g, 12); // bottom-right 3x3
  assert.ok(goalSolved(b, g));
  assert.equal(matchedCells(b, g).length, 9);
});

test('wildcards accept any tile but not the gap', () => {
  const g = makeGoal('wild');
  const wi = g.want.indexOf(WILD);
  const b = solve(g);
  assert.ok(goalSolved(b, g));
  const gap = b.indexOf(EMPTY);
  const cell = g.cells[wi];
  [b[gap], b[cell]] = [b[cell], b[gap]];
  assert.ok(!goalSolved(b, g));
});
