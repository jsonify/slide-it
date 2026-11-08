// Shared, dependency-free game rules. Imported by both the browser and the server
// so that both sides agree exactly on what a legal move and a win look like.

export const SIZE = 5;
export const EMPTY = '.';
// Six tile colours, four of each = 24 tiles + 1 gap on a 5x5 tray.
export const COLORS = ['R', 'O', 'Y', 'G', 'B', 'W'];
export const PER_COLOR = 4;
// Indices of the centre 3x3 window on the 5x5 tray.
export const CENTER = [6, 7, 8, 11, 12, 13, 16, 17, 18];

const rand = (rng, n) => Math.floor(rng() * n);

function shuffle(arr, rng = Math.random) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = rand(rng, i + 1);
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function pool() {
  const tiles = [];
  for (const c of COLORS) for (let i = 0; i < PER_COLOR; i++) tiles.push(c);
  return tiles;
}

/** A random 3x3 target. Drawn from the real tile pool, so it is always achievable. */
export function makeTarget(rng = Math.random) {
  return shuffle(pool(), rng).slice(0, 9);
}

/** Count how many of the centre 9 cells already match the target. */
export function matches(board, target) {
  let n = 0;
  for (let i = 0; i < 9; i++) if (board[CENTER[i]] === target[i]) n++;
  return n;
}

/**
 * A scrambled starting tray. We re-roll until it's genuinely scrambled relative
 * to the target (no more than 2 cells already correct) so nobody gets a gift.
 */
export function makeBoard(target, rng = Math.random) {
  for (let attempt = 0; attempt < 200; attempt++) {
    const board = shuffle([...pool(), EMPTY], rng);
    if (!target || matches(board, target) <= 2) return board;
  }
  return shuffle([...pool(), EMPTY], rng);
}

export function isSolved(board, target) {
  return matches(board, target) === 9;
}

/** True if tapping `index` would slide something (same row/column as the gap). */
export function canSlide(board, index) {
  const e = board.indexOf(EMPTY);
  if (index < 0 || index >= SIZE * SIZE || index === e) return false;
  return Math.floor(index / SIZE) === Math.floor(e / SIZE) || index % SIZE === e % SIZE;
}

/**
 * Tap a tile in line with the gap: every tile between it and the gap shifts one
 * step towards the gap (so you can push a whole row/column in one go).
 * Returns { board, path } where path lists [from, to] for each tile that moved,
 * or null if the move is illegal. Does not mutate the input.
 */
export function slide(board, index) {
  if (!canSlide(board, index)) return null;
  const next = board.slice();
  const e = board.indexOf(EMPTY);
  const sameRow = Math.floor(index / SIZE) === Math.floor(e / SIZE);
  const step = (sameRow ? 1 : SIZE) * (index < e ? -1 : 1); // from gap towards tapped tile
  const path = [];
  let p = e;
  while (p !== index) {
    next[p] = next[p + step];
    path.push([p + step, p]);
    p += step;
  }
  next[index] = EMPTY;
  return { board: next, path };
}

/** Basic structural validation for boards coming over the wire. */
export function isValidBoard(board) {
  if (!Array.isArray(board) || board.length !== SIZE * SIZE) return false;
  const counts = {};
  for (const c of board) counts[c] = (counts[c] || 0) + 1;
  if (counts[EMPTY] !== 1) return false;
  return COLORS.every((c) => counts[c] === PER_COLOR);
}
