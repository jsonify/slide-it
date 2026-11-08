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

// ================================================================ challenges
// Every round is a "challenge": a goal saying which tray cells must hold which
// colours. The classic game is just one of them (the middle 3x3).
//
// A goal is plain JSON so the server can send it as-is:
//   id        challenge id (see CHALLENGES)
//   cells     tray indices that must match, or null for "anywhere" goals
//   want      the colour each of those cells needs ('*' = any tile)
//   show      what the target card pictures: { w, h, tiles } ('.' = not part of it)
//   peek      (memory) ms the picture stays visible after GO
export const WILD = '*';
const idx = (r, c) => r * SIZE + c;
const RING = [0, 1, 2, 3, 4, 9, 14, 19, 24, 23, 22, 21, 20, 15, 10, 5].sort((a, b) => a - b);
const CROSS = [2, 7, 10, 11, 12, 13, 14, 17, 22];
const XMARK = [0, 4, 6, 8, 12, 16, 18, 20, 24];
const CORNERS = [0, 1, 5, 6, 3, 4, 8, 9, 15, 16, 20, 21, 18, 19, 23, 24].sort((a, b) => a - b);

/** Challenge catalogue: name, star rating (1 easy … 3 brutal) and the one-line rule. */
export const CHALLENGES = {
  classic: { name: 'Classic', stars: 1, icon: '🎯', rule: 'Match the middle 3×3.' },
  wild: { name: 'Wildcards', stars: 1, icon: '✨', rule: 'Middle 3×3 — star squares take any colour.' },
  anywhere: { name: 'Anywhere', stars: 1, icon: '🧭', rule: 'Build the 3×3 pattern anywhere on your tray.' },
  mirror: { name: 'Mirror', stars: 2, icon: '🪞', rule: 'Build the picture flipped left ↔ right.' },
  cross: { name: 'Big Cross', stars: 2, icon: '➕', rule: 'Match the full middle row and column.' },
  xmarks: { name: 'X Marks', stars: 2, icon: '❌', rule: 'Match both long diagonals.' },
  twist: { name: 'Twist', stars: 3, icon: '🌀', rule: 'Build the picture turned 90° clockwise ↻.' },
  memory: { name: 'Memory', stars: 3, icon: '🧠', rule: 'The target vanishes after 5s. Peeking freezes your tray.' },
  corners: { name: 'Four Corners', stars: 3, icon: '🔲', rule: 'Match all four 2×2 corner blocks.' },
  ring: { name: 'The Ring', stars: 3, icon: '💍', rule: 'Match the whole outer ring — 16 tiles.' },
};
export const CHALLENGE_IDS = Object.keys(CHALLENGES);
export const PRESETS = {
  classic: ['classic'],
  party: ['classic', 'wild', 'anywhere', 'mirror', 'cross', 'xmarks'],
  brain: ['mirror', 'cross', 'xmarks', 'twist', 'memory', 'corners', 'ring'],
  all: CHALLENGE_IDS.slice(),
};

const grid3 = (tiles) => ({ w: 3, h: 3, tiles });
/** Picture a set of tray cells on a 5x5 map, leaving the rest blank. */
const map5 = (cells, want) => {
  const tiles = Array(SIZE * SIZE).fill('.');
  cells.forEach((c, i) => (tiles[c] = want[i]));
  return { w: SIZE, h: SIZE, tiles };
};
const mirror3 = (t) => t.map((_, i) => t[Math.floor(i / 3) * 3 + (2 - (i % 3))]);
// Rotating 90° clockwise: new[r][c] = old[2 - c][r].
const twist3 = (t) => t.map((_, i) => t[(2 - (i % 3)) * 3 + Math.floor(i / 3)]);
const same = (a, b) => a.every((x, i) => x === b[i]);

/** Deal a goal for challenge `id`. Colours come from the real tile pool, so it's always achievable. */
export function makeGoal(id = 'classic', rng = Math.random) {
  if (!CHALLENGES[id]) id = 'classic';
  const draw = (n) => shuffle(pool(), rng).slice(0, n);
  switch (id) {
    case 'wild': {
      const want = draw(9);
      const spots = shuffle([...want.keys()], rng).slice(0, 3);
      for (const s of spots) want[s] = WILD;
      return { id, cells: CENTER.slice(), want, show: grid3(want.slice()) };
    }
    case 'anywhere': {
      const want = draw(9);
      return { id, cells: null, want, show: grid3(want.slice()) };
    }
    case 'mirror':
    case 'twist': {
      const flip = id === 'mirror' ? mirror3 : twist3;
      let pic = draw(9);
      // A symmetric picture would make the twist pointless.
      for (let i = 0; i < 50 && same(pic, flip(pic)); i++) pic = draw(9);
      return { id, cells: CENTER.slice(), want: flip(pic), show: grid3(pic) };
    }
    case 'memory': {
      const want = draw(9);
      return { id, cells: CENTER.slice(), want, show: grid3(want.slice()), peek: 5000 };
    }
    case 'cross':
    case 'xmarks':
    case 'corners':
    case 'ring': {
      const cells = { cross: CROSS, xmarks: XMARK, corners: CORNERS, ring: RING }[id].slice();
      const want = draw(cells.length);
      return { id, cells, want, show: map5(cells, want) };
    }
    default: {
      const want = draw(9);
      return { id: 'classic', cells: CENTER.slice(), want, show: grid3(want.slice()) };
    }
  }
}

/** Wrap a legacy 9-colour target as a classic goal. */
export const classicGoal = (target) => ({ id: 'classic', cells: CENTER.slice(), want: target.slice(), show: grid3(target.slice()) });

const ok = (tile, want) => tile !== EMPTY && (want === WILD || tile === want);

/** Tray cells currently counted as correct (for "anywhere", the best placement). */
export function matchedCells(board, goal) {
  if (!goal) return [];
  if (goal.cells) return goal.cells.filter((c, i) => ok(board[c], goal.want[i]));
  let best = [];
  for (let r = 0; r <= SIZE - 3; r++)
    for (let c = 0; c <= SIZE - 3; c++) {
      const hit = [];
      for (let k = 0; k < 9; k++) {
        const cell = idx(r + Math.floor(k / 3), c + (k % 3));
        if (ok(board[cell], goal.want[k])) hit.push(cell);
      }
      if (hit.length > best.length) best = hit;
    }
  return best;
}

/** { n, total }: how close a tray is to completing the goal. */
export function progress(board, goal) {
  if (!goal) return { n: 0, total: 9 };
  return { n: matchedCells(board, goal).length, total: goal.want.length };
}

export const goalSolved = (board, goal) => {
  const { n, total } = progress(board, goal);
  return n === total;
};

/** A scrambled tray that isn't already close to the goal. */
export function makeBoardFor(goal, rng = Math.random) {
  const wilds = goal.want.filter((w) => w === WILD).length;
  const real = goal.want.length - wilds;
  const allowed = wilds + Math.max(1, Math.floor(real * 0.25));
  let board;
  for (let attempt = 0; attempt < 400; attempt++) {
    board = shuffle([...pool(), EMPTY], rng);
    if (progress(board, goal).n <= allowed) return board;
  }
  return board;
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
