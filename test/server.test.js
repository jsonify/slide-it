import test from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';

process.env.COUNTDOWN_MS = '50';
process.env.NEXT_ROUND_MS = '100';
const { createServer } = await import('../server.js');
const { slide, isSolved, EMPTY } = await import('../public/game.js');

function client(port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  const inbox = [];
  const waiters = [];
  ws.on('message', (d) => {
    const m = JSON.parse(d);
    inbox.push(m);
    for (const w of [...waiters]) if (w.pred(m)) (waiters.splice(waiters.indexOf(w), 1), w.res(m));
  });
  return {
    ws,
    inbox,
    ready: new Promise((r) => ws.on('open', r)),
    send: (m) => ws.send(JSON.stringify(m)),
    next(pred, ms = 2000) {
      const hit = inbox.find(pred);
      if (hit) {
        inbox.splice(inbox.indexOf(hit), 1);
        return Promise.resolve(hit);
      }
      return new Promise((res, rej) => {
        const w = { pred, res };
        waiters.push(w);
        setTimeout(() => rej(new Error('timeout waiting for message')), ms);
      });
    },
  };
}

// A deterministic deal: the tray is solved except the gap sits in the centre
// window. Tapping 14 pushes the two Gs left, which solves it.
//   R R R R O
//   O O O Y Y
//   Y Y . G G   <- gap at 12; target wants 'G' at 12
//   G G B B B
//   B W W W W
const BOARD = 'RRRROOOOYYYY.GGGGBBBBWWWW'.split('');
const TARGET = ['O', 'O', 'Y', 'Y', 'G', 'G', 'G', 'B', 'B'];
test('two players can create, join, race and finish a match', async () => {
  assert.ok(!isSolved(BOARD, TARGET));
  const path = [13, 12, 14]; // wiggle a tile, then push the row across
  let check = BOARD;
  for (const i of path) check = slide(check, i).board;
  assert.ok(isSolved(check, TARGET), 'fixture path solves the board');

  const server = createServer({ deal: () => ({ target: TARGET.slice(), board: BOARD.slice() }) });
  await new Promise((r) => server.listen(0, r));
  const { port } = server.address();

  const a = client(port);
  const b = client(port);
  await Promise.all([a.ready, b.ready]);

  a.send({ t: 'create', name: 'Alice' });
  const wa = await a.next((m) => m.t === 'welcome');
  assert.match(wa.code, /^[A-Z]{4}$/);

  b.send({ t: 'join', code: wa.code, name: 'Bob' });
  const wb = await b.next((m) => m.t === 'welcome');
  assert.equal(wb.code, wa.code);

  // Non-host can't start; host can change settings and start.
  b.send({ t: 'start' });
  a.send({ t: 'settings', rounds: 1 });
  await a.next((m) => m.t === 'room' && m.rounds === 1 && m.players.length === 2);
  a.send({ t: 'start' });

  const cd = await a.next((m) => m.t === 'room' && m.state === 'countdown');
  assert.equal(cd.goal, null, 'goal hidden during countdown');
  assert.equal(cd.challenge, 'classic', 'challenge type announced during countdown');
  const aBoard = cd.players.find((p) => p.id === wa.you).board;
  const bBoard = cd.players.find((p) => p.id === wb.you).board;
  assert.equal(aBoard, bBoard, 'everyone gets the same starting tray');

  // Moves before GO are rejected.
  const early = aBoard.split('');
  const legal = [...Array(25).keys()].find((i) => slide(early, i));
  a.send({ t: 'move', i: legal });
  await a.next((m) => m.t === 'sync');

  const play = await a.next((m) => m.t === 'room' && m.state === 'playing');
  const target = play.goal.want;

  // Illegal move -> server resyncs.
  const gap = early.indexOf(EMPTY);
  const illegal = [...Array(25).keys()].find((i) => i !== gap && !slide(early, i));
  a.send({ t: 'move', i: illegal });
  await a.next((m) => m.t === 'sync');

  // Bob sees Alice's moves live.
  assert.deepEqual(target, TARGET);
  a.send({ t: 'move', i: path[0] });
  const seen = await b.next((m) => m.t === 'board' && m.id === wa.you);
  assert.equal(seen.m, 1);
  for (const i of path.slice(1)) {
    a.send({ t: 'move', i });
    await new Promise((r) => setTimeout(r, 15));
  }

  const over = await b.next((m) => m.t === 'room' && m.state === 'matchover', 5000);
  assert.equal(over.result.winnerId, wa.you);
  assert.equal(over.result.moves, path.length);
  assert.equal(over.players.find((p) => p.id === wa.you).score, 1);

  // Reconnect with token keeps the seat and score.
  b.ws.close();
  const b2 = client(port);
  await b2.ready;
  b2.send({ t: 'join', code: wa.code, playerId: wb.you, token: wb.token });
  const back = await b2.next((m) => m.t === 'welcome');
  assert.equal(back.you, wb.you);
  const snap = await b2.next((m) => m.t === 'room');
  assert.equal(snap.players.length, 2);

  // Wrong token can't hijack a seat.
  const c = client(port);
  await c.ready;
  c.send({ t: 'join', code: wa.code, playerId: wb.you, token: 'nope', name: 'Mallory' });
  const wc = await c.next((m) => m.t === 'welcome');
  assert.notEqual(wc.you, wb.you);

  // Bad code
  const d = client(port);
  await d.ready;
  d.send({ t: 'join', code: 'ZZZZ', name: 'x' });
  const err = await d.next((m) => m.t === 'error');
  assert.equal(err.code, 'no-room');

  for (const x of [a, b2, c, d]) x.ws.close();
  await new Promise((r) => server.close(r));
});

test('host picks challenges; rounds rotate through them', async () => {
  const server = createServer();
  await new Promise((r) => server.listen(0, r));
  const { port } = server.address();
  const a = client(port);
  const b = client(port);
  await Promise.all([a.ready, b.ready]);
  a.send({ t: 'create', name: 'Ann' });
  const wa = await a.next((m) => m.t === 'welcome');
  b.send({ t: 'join', code: wa.code, name: 'Ben' });
  await b.next((m) => m.t === 'welcome');

  // Non-host settings are ignored; unknown ids are dropped.
  b.send({ t: 'settings', challenges: ['ring'] });
  a.send({ t: 'settings', challenges: ['mirror', 'ring', 'bogus'], order: 'climb', rounds: 3 });
  const lobby = await a.next((m) => m.t === 'room' && m.order === 'climb' && m.players.length === 2);
  assert.deepEqual(lobby.challenges, ['mirror', 'ring']);

  // Empty selections are refused.
  a.send({ t: 'settings', challenges: [] });
  a.send({ t: 'start' });
  const cd = await a.next((m) => m.t === 'room' && m.state === 'countdown');
  assert.equal(cd.challenge, 'mirror', '"get harder" starts with the easier challenge');
  const play = await a.next((m) => m.t === 'room' && m.state === 'playing');
  assert.equal(play.goal.id, 'mirror');
  assert.equal(play.goal.want.length, 9);

  for (const x of [a, b]) x.ws.close();
  await new Promise((r) => server.close(r));
});
