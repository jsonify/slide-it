// Slide It — tiny game server.
// Serves the web app from ./public and runs real-time rooms over WebSocket (/ws).
// The server is authoritative: it deals the boards, validates every move and
// decides who won, so a modified client can't cheat.

import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { makeGoal, makeBoardFor, classicGoal, slide, goalSolved, progress, CHALLENGES, CHALLENGE_IDS } from './public/game.js';

const PORT = Number(process.env.PORT) || 3000;
const ROOT = join(dirname(fileURLToPath(import.meta.url)), 'public');

export const MAX_PLAYERS = 6;
const COUNTDOWN_MS = Number(process.env.COUNTDOWN_MS ?? 3000);
const NEXT_ROUND_MS = Number(process.env.NEXT_ROUND_MS ?? 6000);
const ROOM_IDLE_MS = 10 * 60 * 1000;
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ'; // no I, L, O — easy to read aloud
const AVATARS = ['#ff5d73', '#3fa7ff', '#ffb52e', '#2ed39a', '#b46bff', '#ff8a3d'];
const REACTIONS = new Set(['👏', '🔥', '😱', '😂', '😤', '🐢']);

// ---------------------------------------------------------------- static files

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

async function serveStatic(req, res) {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, rooms: rooms.size }));
  }
  let path = decodeURIComponent(url.pathname);
  if (path.endsWith('/')) path += 'index.html';
  const file = normalize(join(ROOT, path));
  if (!file.startsWith(ROOT)) {
    res.writeHead(403);
    return res.end();
  }
  try {
    const info = await stat(file);
    if (!info.isFile()) throw new Error('not a file');
    const body = await readFile(file);
    res.writeHead(200, {
      'content-type': MIME[extname(file)] || 'application/octet-stream',
      // Short cache so updates reach phones quickly; html always revalidates.
      'cache-control': extname(file) === '.html' ? 'no-cache' : 'public, max-age=300',
    });
    res.end(body);
  } catch {
    // Unknown paths fall back to the app (so /ABCD style links still load it).
    if (!extname(path)) {
      const body = await readFile(join(ROOT, 'index.html'));
      res.writeHead(200, { 'content-type': MIME['.html'], 'cache-control': 'no-cache' });
      return res.end(body);
    }
    res.writeHead(404);
    res.end('Not found');
  }
}

// ----------------------------------------------------------------------- rooms

/** @type {Map<string, Room>} */
const rooms = new Map();

function newCode() {
  for (;;) {
    let code = '';
    const bytes = randomBytes(4);
    for (const b of bytes) code += CODE_ALPHABET[b % CODE_ALPHABET.length];
    if (!rooms.has(code)) return code;
  }
}

const cleanName = (s) =>
  String(s ?? '')
    .replace(/[\u0000-\u001f<>]/g, '')
    .trim()
    .slice(0, 16) || 'Player';

// How a round's goal + starting tray are dealt for a challenge. Tests can swap
// this out (returning { goal, board }, or a legacy { target, board }).
const randomDeal = (challenge) => {
  const goal = makeGoal(challenge);
  return { goal, board: makeBoardFor(goal) };
};

const shuffled = (arr) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

class Room {
  constructor(code, deal = randomDeal) {
    this.code = code;
    this.deal = deal;
    this.players = new Map(); // id -> player
    this.hostId = null;
    this.state = 'lobby'; // lobby | countdown | playing | roundover | matchover
    this.rounds = 3; // best of N
    this.round = 0;
    this.roundId = 0; // unique per round, never reused
    this.challenges = ['classic']; // which challenges are in rotation
    this.order = 'shuffle'; // shuffle | climb (rounds get harder)
    this.deck = [];
    this.challenge = null; // this round's challenge id
    this.goal = null;
    this.startBoard = null;
    this.goAt = 0;
    this.result = null; // last round result
    this.timer = null;
    this.idleSince = Date.now();
  }

  get winsNeeded() {
    return Math.ceil(this.rounds / 2);
  }

  addPlayer(name) {
    const used = new Set([...this.players.values()].map((p) => p.color));
    const player = {
      id: randomUUID(),
      token: randomBytes(16).toString('hex'),
      name: cleanName(name),
      color: AVATARS.find((c) => !used.has(c)) || AVATARS[this.players.size % AVATARS.length],
      score: 0,
      board: null,
      moves: 0,
      solvedAt: 0,
      socket: null,
      moveTimes: [],
    };
    this.players.set(player.id, player);
    if (!this.hostId) this.hostId = player.id;
    return player;
  }

  removePlayer(id) {
    this.players.delete(id);
    if (this.hostId === id) this.pickNewHost();
    // If someone leaves mid-round and only one active player remains, end it.
    if (this.state === 'playing' && this.activePlayers().length === 0) this.toLobby();
  }

  pickNewHost() {
    const next = [...this.players.values()].find((p) => p.socket) || [...this.players.values()][0];
    this.hostId = next ? next.id : null;
  }

  activePlayers() {
    return [...this.players.values()].filter((p) => p.board);
  }

  connected() {
    return [...this.players.values()].filter((p) => p.socket);
  }

  clearTimer() {
    clearTimeout(this.timer);
    this.timer = null;
  }

  startMatch() {
    for (const p of this.players.values()) p.score = 0;
    this.round = 0;
    this.result = null;
    this.deck = [];
    this.startRound();
  }

  /** Next challenge: work through the selected set without repeats, then go again. */
  nextChallenge() {
    if (!this.deck.length) {
      const fresh = shuffled(this.challenges);
      if (this.order === 'climb') fresh.sort((a, b) => CHALLENGES[a].stars - CHALLENGES[b].stars);
      // Don't play the same challenge twice in a row across a reshuffle.
      if (fresh.length > 1 && fresh[0] === this.challenge) fresh.push(fresh.shift());
      this.deck = fresh;
    }
    return this.deck.shift();
  }

  startRound() {
    this.clearTimer();
    this.round += 1;
    this.roundId += 1;
    this.challenge = this.nextChallenge();
    const dealt = this.deal(this.challenge);
    this.goal = dealt.goal || classicGoal(dealt.target);
    this.challenge = this.goal.id;
    this.startBoard = dealt.board;
    this.result = null;
    // Everyone gets the identical scrambled tray, so it's pure skill.
    for (const p of this.players.values()) {
      p.board = p.socket ? this.startBoard.slice() : null;
      p.moves = 0;
      p.solvedAt = 0;
    }
    this.state = 'countdown';
    this.goAt = Date.now() + COUNTDOWN_MS;
    this.broadcastRoom();
    this.timer = setTimeout(() => {
      this.state = 'playing';
      this.broadcastRoom();
    }, COUNTDOWN_MS);
  }

  move(player, index) {
    if (this.state !== 'playing' || !player.board) return false;
    // Light flood protection: humans don't do 30+ taps a second.
    const now = Date.now();
    player.moveTimes = player.moveTimes.filter((t) => now - t < 1000);
    if (player.moveTimes.length > 30) return false;
    const res = slide(player.board, index);
    if (!res) return false;
    player.moveTimes.push(now);
    player.board = res.board;
    player.moves += 1;
    this.broadcast({ t: 'board', id: player.id, b: player.board.join(''), m: player.moves });
    if (goalSolved(player.board, this.goal)) this.finishRound(player);
    return true;
  }

  finishRound(winner) {
    this.clearTimer();
    winner.score += 1;
    winner.solvedAt = Date.now();
    this.result = {
      winnerId: winner.id,
      ms: winner.solvedAt - this.goAt,
      moves: winner.moves,
    };
    const matchOver = winner.score >= this.winsNeeded;
    this.state = matchOver ? 'matchover' : 'roundover';
    if (!matchOver) {
      this.goAt = Date.now() + NEXT_ROUND_MS; // reused as "next round at"
      this.timer = setTimeout(() => this.startRound(), NEXT_ROUND_MS);
    }
    this.broadcastRoom();
  }

  toLobby() {
    this.clearTimer();
    this.state = 'lobby';
    this.goal = null;
    this.challenge = null;
    for (const p of this.players.values()) p.board = null;
    this.broadcastRoom();
  }

  snapshot() {
    return {
      t: 'room',
      code: this.code,
      host: this.hostId,
      state: this.state,
      round: this.round,
      roundId: this.roundId,
      rounds: this.rounds,
      winsNeeded: this.winsNeeded,
      goAt: this.goAt,
      now: Date.now(),
      challenges: this.challenges,
      order: this.order,
      // The challenge type is announced during the countdown, but the goal
      // itself stays hidden so nobody gets a head start.
      challenge: this.state === 'lobby' ? null : this.challenge,
      goal: this.state === 'countdown' || !this.goal ? null : this.goal,
      result: this.result,
      players: [...this.players.values()].map((p) => ({
        id: p.id,
        name: p.name,
        color: p.color,
        score: p.score,
        connected: !!p.socket,
        board: p.board ? p.board.join('') : null,
        moves: p.moves,
        matches: p.board && this.goal ? progress(p.board, this.goal).n : 0,
      })),
    };
  }

  broadcastRoom() {
    this.broadcast(this.snapshot());
  }

  broadcast(msg) {
    const data = JSON.stringify(msg);
    for (const p of this.players.values()) if (p.socket?.readyState === 1) p.socket.send(data);
  }
}

// ------------------------------------------------------------------- sockets

function send(ws, msg) {
  if (ws.readyState === 1) ws.send(JSON.stringify(msg));
}

function attach(ws, room, player) {
  // A newer connection for the same player replaces any older one.
  if (player.socket && player.socket !== ws) {
    send(player.socket, { t: 'replaced' });
    player.socket.close();
  }
  player.socket = ws;
  ws.room = room;
  ws.player = player;
  room.idleSince = Date.now();
  if (!room.hostId || !room.players.get(room.hostId)?.socket) room.hostId = player.id;
  send(ws, { t: 'welcome', code: room.code, you: player.id, token: player.token });
  room.broadcastRoom();
}

function handle(ws, msg, opts) {
  const { room, player } = ws;
  switch (msg.t) {
    case 'create': {
      if (room) return;
      const r = new Room(newCode(), opts.deal);
      rooms.set(r.code, r);
      attach(ws, r, r.addPlayer(msg.name));
      return;
    }
    case 'join': {
      if (room) return;
      const code = String(msg.code || '').toUpperCase().trim();
      const r = rooms.get(code);
      if (!r) return send(ws, { t: 'error', code: 'no-room', msg: `No game with code ${code}.` });
      // Rejoining (refresh, phone locked, network blip) keeps your seat and score.
      const existing = msg.playerId && r.players.get(msg.playerId);
      if (existing && existing.token === msg.token) {
        if (msg.name) existing.name = cleanName(msg.name);
        return attach(ws, r, existing);
      }
      if (r.players.size >= MAX_PLAYERS)
        return send(ws, { t: 'error', code: 'full', msg: 'That game is full.' });
      attach(ws, r, r.addPlayer(msg.name));
      return;
    }
  }

  if (!room || !player) return;
  const isHost = room.hostId === player.id;

  switch (msg.t) {
    case 'settings': {
      if (!isHost || room.state !== 'lobby') break;
      if ([1, 3, 5, 7].includes(msg.rounds)) room.rounds = msg.rounds;
      if (Array.isArray(msg.challenges)) {
        const picked = CHALLENGE_IDS.filter((id) => msg.challenges.includes(id));
        if (picked.length) room.challenges = picked;
      }
      if (msg.order === 'shuffle' || msg.order === 'climb') room.order = msg.order;
      room.broadcastRoom();
      break;
    }
    case 'start':
      if (isHost && (room.state === 'lobby' || room.state === 'matchover')) room.startMatch();
      break;
    case 'lobby':
      if (isHost && room.state === 'matchover') room.toLobby();
      break;
    case 'move':
      if (!room.move(player, Number(msg.i)) && player.board) {
        // Client got out of step (lag, round ended) — give it the truth.
        send(ws, { t: 'sync', b: player.board.join(''), m: player.moves });
      }
      break;
    case 'react':
      if (REACTIONS.has(msg.e)) room.broadcast({ t: 'react', id: player.id, e: msg.e });
      break;
    case 'rename':
      player.name = cleanName(msg.name);
      room.broadcastRoom();
      break;
    case 'leave':
      ws.room = ws.player = null;
      player.socket = null;
      room.removePlayer(player.id);
      if (room.players.size === 0) {
        room.clearTimer();
        rooms.delete(room.code);
      } else room.broadcastRoom();
      send(ws, { t: 'left' });
      break;
  }
}

export function createServer(opts = {}) {
  const server = http.createServer((req, res) => {
    serveStatic(req, res).catch(() => {
      res.writeHead(500);
      res.end();
    });
  });
  const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 4096 });

  wss.on('connection', (ws) => {
    ws.alive = true;
    ws.on('pong', () => (ws.alive = true));
    ws.on('message', (data) => {
      let msg;
      try {
        msg = JSON.parse(data);
      } catch {
        return;
      }
      if (msg && typeof msg.t === 'string') handle(ws, msg, opts);
    });
    ws.on('close', () => {
      const { room, player } = ws;
      if (!room || !player || player.socket !== ws) return;
      player.socket = null;
      if (room.state === 'lobby') {
        // In the lobby a closed tab just means they left. Give a short grace
        // period for reloads / app switching before freeing the seat.
        setTimeout(() => {
          if (!player.socket && room.players.has(player.id) && room.state === 'lobby') {
            room.removePlayer(player.id);
            room.broadcastRoom();
          }
        }, 45_000);
      }
      if (room.hostId === player.id) room.pickNewHost();
      if (room.connected().length === 0) room.idleSince = Date.now();
      room.broadcastRoom();
    });
  });

  // Heartbeat: drop dead sockets (phones that went to sleep) and idle rooms.
  const interval = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) {
        ws.terminate();
        continue;
      }
      ws.alive = false;
      ws.ping();
    }
    for (const [code, room] of rooms) {
      if (room.connected().length === 0 && Date.now() - room.idleSince > ROOM_IDLE_MS) {
        room.clearTimer();
        rooms.delete(code);
      }
    }
  }, 15_000);
  server.on('close', () => clearInterval(interval));

  return server;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  createServer().listen(PORT, () => {
    console.log(`Slide It running → http://localhost:${PORT}`);
  });
}
