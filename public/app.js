import {
  EMPTY, CENTER, SIZE, WILD, slide, canSlide,
  makeGoal, makeBoardFor, progress, matchedCells, goalSolved, CHALLENGES, CHALLENGE_IDS, PRESETS,
} from './game.js';

// ======================================================================= utils
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const store = {
  get(k, d) {
    try {
      const v = localStorage.getItem('slideit:' + k);
      return v == null ? d : JSON.parse(v);
    } catch {
      return d;
    }
  },
  set(k, v) {
    try {
      localStorage.setItem('slideit:' + k, JSON.stringify(v));
    } catch {}
  },
};
const fmtTime = (ms) => (Math.max(0, ms) / 1000).toFixed(1);
const isIOS = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone;

let toastTimer;
function toast(msg, ms = 2400) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), ms);
}

// ======================================================================= sound
let soundOn = store.get('sound', true);
let actx;
function ac() {
  if (!actx) {
    const C = window.AudioContext || window.webkitAudioContext;
    if (!C) return null;
    actx = new C();
  }
  if (actx.state === 'suspended') actx.resume();
  return actx;
}
['pointerup', 'touchend', 'keydown'].forEach((ev) => document.addEventListener(ev, () => ac(), { once: true }));

function tone(f, d = 0.08, type = 'sine', v = 0.15, t0 = 0, to) {
  if (!soundOn) return;
  const a = ac();
  if (!a) return;
  const t = a.currentTime + t0;
  const o = a.createOscillator();
  const g = a.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f, t);
  if (to) o.frequency.exponentialRampToValueAtTime(to, t + d);
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(v, t + 0.005);
  g.gain.exponentialRampToValueAtTime(0.0001, t + d);
  o.connect(g).connect(a.destination);
  o.start(t);
  o.stop(t + d + 0.03);
}
const sfx = {
  slide: () => tone(480 + Math.random() * 90, 0.05, 'triangle', 0.09, 0, 340),
  match: () => (tone(880, 0.09, 'sine', 0.12), tone(1320, 0.14, 'sine', 0.1, 0.06)),
  unmatch: () => tone(300, 0.08, 'sine', 0.06, 0, 220),
  beep: () => tone(620, 0.12, 'square', 0.05),
  go: () => tone(990, 0.3, 'square', 0.06),
  win: () => [523, 659, 784, 1047, 1319].forEach((f, i) => tone(f, 0.2, 'triangle', 0.13, i * 0.09)),
  lose: () => [392, 330, 262].forEach((f, i) => tone(f, 0.22, 'sawtooth', 0.045, i * 0.13)),
  pop: () => tone(650, 0.07, 'sine', 0.1, 0, 1200),
  bump: () => tone(130, 0.06, 'square', 0.04),
  join: () => (tone(660, 0.08, 'sine', 0.1), tone(990, 0.1, 'sine', 0.1, 0.07)),
};
function setSound(on) {
  soundOn = on;
  store.set('sound', on);
  $('#btn-sound').textContent = on ? '🔊' : '🔇';
  $('#btn-sound-home').textContent = `Sound: ${on ? 'on' : 'off'}`;
}

// iOS Safari has no vibrate API, but toggling a native <input switch> gives a
// system haptic tick (iOS 18+). Android uses navigator.vibrate.
const hapticEl = $('#haptic');
function haptic() {
  if (navigator.vibrate) navigator.vibrate(8);
  else if (isIOS) hapticEl.click();
}

// Keep the screen awake during a match where supported.
let wakeLock = null;
async function keepAwake(on) {
  try {
    if (on && !wakeLock && 'wakeLock' in navigator) {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => (wakeLock = null));
    } else if (!on && wakeLock) {
      await wakeLock.release();
      wakeLock = null;
    }
  } catch {}
}

// ======================================================================= tiles
const SHAPES = {
  R: '<circle cx="12" cy="12" r="9"/>',
  O: '<path d="M12 2.5 22 20.5H2z"/>',
  Y: '<path d="m12 2 3 6.3 6.8.8-5 4.7 1.3 6.7L12 17.2l-6.1 3.3 1.3-6.7-5-4.7 6.8-.8z"/>',
  G: '<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/>',
  B: '<path d="M12 1.5 22.5 12 12 22.5 1.5 12z"/>',
  W: '<path d="M8.5 2.5h7v6h6v7h-6v6h-7v-6h-6v-7h6z"/>',
};
function tileEl(c) {
  const d = document.createElement('div');
  d.className = 'tile';
  d.dataset.c = c;
  if (SHAPES[c]) d.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${SHAPES[c]}</svg>`;
  else if (c === '?') d.textContent = '?';
  else if (c === WILD) {
    d.dataset.c = 'wild';
    d.textContent = '★';
  } else if (c === EMPTY) d.dataset.c = 'blank';
  return d;
}

/** Which tray cells a challenge is about. Fixed per challenge, so it's safe to show early. */
const regionFor = (id) => (id ? makeGoal(id).cells : CENTER);
const starsOf = (id) => '★'.repeat(CHALLENGES[id]?.stars || 1);

// ======================================================================= tray
// The player's 5x5 board. Tiles are persistent DOM nodes that slide with CSS
// transforms, so every move animates smoothly.
class Tray {
  constructor(el, onMove) {
    this.el = el;
    this.onMove = onMove;
    this.board = null;
    this.slots = [];
    this.goal = null; // revealed goal (null until GO)
    this.region = null; // cells that matter this round (known from the challenge type)
    this.enabled = false;
    this.swipe = null;
    el.addEventListener('pointerdown', (e) => this.down(e));
    el.addEventListener('pointermove', (e) => this.drag(e));
    for (const ev of ['pointerup', 'pointercancel', 'lostpointercapture']) el.addEventListener(ev, () => (this.swipe = null));
  }

  /** Mark which tray cells this round is about (the dashed window / slots). */
  setRegion(cells) {
    this.region = cells;
    for (const m of this.el.querySelectorAll('.window, .slot')) m.remove();
    const center = cells && cells.length === 9 && cells.every((c, i) => c === CENTER[i]);
    if (center) this.el.insertAdjacentHTML('afterbegin', '<div class="window"></div>');
    else if (cells)
      this.el.insertAdjacentHTML(
        'afterbegin',
        cells.map((c) => `<div class="slot" style="--x:${c % SIZE};--y:${Math.floor(c / SIZE)}"></div>`).join(''),
      );
    this.el.classList.toggle('anywhere', !cells);
    this.highlight();
  }

  reset(board) {
    this.el.innerHTML = '';
    this.el.classList.remove('solved');
    this.board = board.slice();
    this.slots = board.map((c) => (c === EMPTY ? null : { c, el: tileEl(c) }));
    this.slots.forEach((t, i) => {
      if (!t) return;
      t.el.style.transition = 'none';
      this.place(t, i);
      this.el.appendChild(t.el);
    });
    // Re-enable transitions after first paint.
    requestAnimationFrame(() => requestAnimationFrame(() => this.slots.forEach((t) => t && (t.el.style.transition = ''))));
    this.setRegion(this.region);
  }

  place(t, i) {
    t.el.style.setProperty('--x', i % SIZE);
    t.el.style.setProperty('--y', Math.floor(i / SIZE));
  }

  /** Server says the board is something else: re-assign tiles by colour and slide them there. */
  setBoard(board) {
    if (!this.board) return this.reset(board);
    if (board.join('') === this.board.join('')) return;
    const pools = {};
    this.slots.forEach((t, i) => t && (pools[t.c] ||= []).push({ t, i }));
    const next = new Array(board.length).fill(null);
    // Tiles already in a correct spot stay put.
    board.forEach((c, i) => {
      if (c === EMPTY) return;
      const pool = pools[c];
      const k = pool?.findIndex((p) => p.i === i);
      if (k >= 0) next[i] = pool.splice(k, 1)[0].t;
    });
    board.forEach((c, i) => {
      if (c !== EMPTY && !next[i]) next[i] = pools[c].shift().t;
    });
    this.slots = next;
    this.board = board.slice();
    this.slots.forEach((t, i) => t && this.place(t, i));
    this.highlight();
  }

  apply(index) {
    const res = slide(this.board, index);
    if (!res) return false;
    const next = this.slots.slice();
    for (const [from, to] of res.path) next[to] = this.slots[from];
    next[index] = null;
    this.slots = next;
    this.board = res.board;
    for (const [, to] of res.path) this.place(this.slots[to], to);
    this.highlight();
    return true;
  }

  highlight() {
    const region = this.region ? new Set(this.region) : null;
    const hit = new Set(this.board ? matchedCells(this.board, this.goal) : []);
    this.slots.forEach((t, i) => {
      if (!t) return;
      t.el.classList.toggle('match', hit.has(i));
      // Tiles that can't matter this round fade back a little.
      t.el.classList.toggle('off', !!region && !region.has(i));
    });
  }

  cellAt(e) {
    const r = this.el.getBoundingClientRect();
    const fx = (e.clientX - r.left) / r.width;
    const fy = (e.clientY - r.top) / r.height;
    const col = Math.min(4, Math.max(0, Math.floor((fx - 0.02) / 0.192)));
    const row = Math.min(4, Math.max(0, Math.floor((fy - 0.02) / 0.192)));
    return row * SIZE + col;
  }

  down(e) {
    if (!this.enabled) return;
    e.preventDefault();
    const i = this.cellAt(e);
    if (canSlide(this.board, i)) this.tryMove(i);
    else this.swipe = { x: e.clientX, y: e.clientY };
    try {
      this.el.setPointerCapture(e.pointerId);
    } catch {}
  }

  // Swipe anywhere: the tile next to the gap moves in the swipe direction.
  drag(e) {
    if (!this.enabled || !this.swipe) return;
    const dx = e.clientX - this.swipe.x;
    const dy = e.clientY - this.swipe.y;
    const th = Math.max(16, this.el.clientWidth * 0.05);
    if (Math.abs(dx) < th && Math.abs(dy) < th) return;
    this.swipe = { x: e.clientX, y: e.clientY };
    this.push(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : dy > 0 ? 'down' : 'up');
  }

  push(dir) {
    const g = this.board.indexOf(EMPTY);
    const col = g % SIZE;
    const row = Math.floor(g / SIZE);
    const from = { right: col > 0 && g - 1, left: col < 4 && g + 1, down: row > 0 && g - SIZE, up: row < 4 && g + SIZE }[dir];
    if (from === false) return this.bump();
    this.tryMove(from);
  }

  tryMove(i) {
    if (this.apply(i)) this.onMove(i);
    else this.bump();
  }

  bump() {
    sfx.bump();
    this.el.classList.remove('nudge');
    void this.el.offsetWidth;
    this.el.classList.add('nudge');
  }
}

// ======================================================================= state
const S = {
  mode: null, // 'online' | 'solo'
  me: null,
  room: null,
  clockOffset: 0,
  roundId: null,
  revealed: null,
  myMoves: 0,
  locked: false,
  lastCountdown: null,
  resultShownFor: null,
  solo: null,
};
const now = () => Date.now() + S.clockOffset;
let lastMatchCount = 0;

const tray = new Tray($('#board'), onMyMove);

function show(name) {
  for (const s of document.querySelectorAll('.screen')) s.classList.toggle('active', s.id === 'screen-' + name);
  keepAwake(name === 'game');
}

// ======================================================================= network
// Where the game server lives. Empty = same site (Render, local dev). When the
// page is hosted somewhere static like Vercel, config.js points this at the
// real server, e.g. https://slide-it.onrender.com.
const SERVER = String(window.SLIDEIT_SERVER || '').replace(/\/+$/, '');
const wsURL = () => {
  if (!SERVER) return `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`;
  return `${SERVER.replace(/^http/, 'ws')}/ws`;
};
let everConnected = false;
const net = {
  ws: null,
  want: false,
  retry: 0,
  hello: null, // message to (re)send every time the socket opens
  timer: null,
  open(hello) {
    this.hello = hello;
    this.want = true;
    this.connect();
  },
  connect() {
    clearTimeout(this.timer);
    if (this.ws && this.ws.readyState <= 1) return;
    const ws = new WebSocket(wsURL());
    this.ws = ws;
    const slow = setTimeout(() => this.want && showConn(), 1500);
    ws.onopen = () => {
      clearTimeout(slow);
      everConnected = true;
      this.retry = 0;
      $('#conn').classList.add('hidden');
      if (this.hello) this.send(this.hello);
    };
    ws.onmessage = (e) => {
      let m;
      try {
        m = JSON.parse(e.data);
      } catch {
        return;
      }
      onMessage(m);
    };
    ws.onclose = () => {
      clearTimeout(slow);
      if (this.ws !== ws || !this.want) return;
      showConn();
      this.timer = setTimeout(() => this.connect(), Math.min(4000, 250 * 2 ** this.retry++));
    };
  },
  send(m) {
    if (this.ws?.readyState === 1) this.ws.send(JSON.stringify(m));
  },
  close() {
    this.want = false;
    this.hello = null;
    clearTimeout(this.timer);
    $('#conn').classList.add('hidden');
    try {
      this.ws?.close();
    } catch {}
    this.ws = null;
  },
};
// A free server that was asleep can take ~30s to wake up on the first visit.
function showConn() {
  const c = $('#conn');
  c.textContent = everConnected ? 'Reconnecting…' : 'Waking up the game server… (can take up to 30s)';
  c.classList.remove('hidden');
}
// Nudge a sleeping server awake as soon as the page opens, so it's ready by
// the time someone taps Create or Join.
if (SERVER) fetch(`${SERVER}/health`, { mode: 'no-cors', cache: 'no-store' }).catch(() => {});

// Phones suspend sockets in the background — reconnect the moment we're back.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && net.want) {
    net.retry = 0;
    net.connect();
    if (S.mode) keepAwake(true);
  }
});

function onMessage(m) {
  switch (m.t) {
    case 'welcome':
      S.me = m.you;
      store.set('session', { code: m.code, playerId: m.you, token: m.token, at: Date.now() });
      net.hello = { t: 'join', code: m.code, playerId: m.you, token: m.token, name: myName() };
      history.replaceState(null, '', `/?g=${m.code}`);
      break;
    case 'room':
      S.clockOffset = m.now - Date.now();
      S.room = m;
      renderRoom();
      break;
    case 'board': {
      const p = S.room?.players.find((x) => x.id === m.id);
      if (!p) return;
      p.board = m.b;
      p.moves = m.m;
      p.matches = S.room.goal ? progress(m.b.split(''), S.room.goal).n : 0;
      if (m.id === S.me) {
        if (m.m >= S.myMoves) reconcile(m.b, m.m);
      } else {
        renderOpponents();
        if (watchId() === m.id) tray.setBoard(m.b.split(''));
      }
      break;
    }
    case 'sync':
      reconcile(m.b, m.m, true);
      break;
    case 'react':
      floatReaction(m.id, m.e);
      break;
    case 'error':
      toast(m.msg);
      if (m.code === 'no-room' || m.code === 'full') {
        store.set('session', null);
        goHome();
      }
      break;
    case 'replaced':
      toast('This game was opened somewhere else.');
      goHome(false);
      break;
  }
}

function reconcile(b, m, force = false) {
  if (force || m >= S.myMoves) {
    S.myMoves = m;
    tray.setBoard(b.split(''));
    renderStats();
  }
}

// ======================================================================= home
const myName = () => $('#name').value.trim() || 'Player';

function goHome(leave = true) {
  if (leave && S.mode === 'online') net.send({ t: 'leave' });
  net.close();
  if (S.mode === 'online') store.set('session', null);
  S.mode = null;
  S.room = null;
  S.roundId = null;
  S.solo = null;
  hideOverlays();
  $('#countdown').classList.add('hidden');
  history.replaceState(null, '', '/');
  show('home');
  renderRejoin();
}

function startOnline(hello) {
  store.set('name', myName());
  S.mode = 'online';
  S.roundId = null;
  S.resultShownFor = null;
  net.open(hello);
}

$('#btn-create').onclick = () => {
  sfx.pop();
  startOnline({ t: 'create', name: myName() });
};
$('#btn-join').onclick = () => {
  const code = $('#join-code').value.trim().toUpperCase();
  if (code.length !== 4) {
    toast('Enter the 4-letter game code');
    $('#join-code').focus();
    return;
  }
  sfx.pop();
  const sess = store.get('session');
  startOnline(
    sess?.code === code
      ? { t: 'join', code, playerId: sess.playerId, token: sess.token, name: myName() }
      : { t: 'join', code, name: myName() },
  );
};
$('#join-code').addEventListener('input', (e) => {
  e.target.value = e.target.value.toUpperCase().replace(/[^A-Z]/g, '');
});
$('#join-code').addEventListener('keydown', (e) => e.key === 'Enter' && $('#btn-join').click());
$('#btn-solo').onclick = () => {
  sfx.pop();
  store.set('name', myName());
  openSoloPicker();
};
$('#btn-howto').onclick = () => $('#overlay-howto').classList.remove('hidden');
$('#overlay-howto [data-close]').onclick = () => $('#overlay-howto').classList.add('hidden');
$('#btn-sound-home').onclick = () => setSound(!soundOn);
$('#btn-sound').onclick = () => setSound(!soundOn);

// Offer to jump back into a game you were in recently (e.g. the app was closed).
function renderRejoin() {
  const old = document.getElementById('btn-rejoin');
  old?.remove();
  const sess = store.get('session');
  if (!sess || Date.now() - sess.at > 30 * 60 * 1000) return;
  const b = document.createElement('button');
  b.id = 'btn-rejoin';
  b.className = 'btn secondary';
  b.textContent = `Rejoin game ${sess.code}`;
  b.onclick = () => startOnline({ t: 'join', code: sess.code, playerId: sess.playerId, token: sess.token, name: myName() });
  $('.stack').prepend(b);
}

// Animated logo
function initLogo() {
  const g = $('#logo-grid');
  const colors = 'ROYGBW';
  const tiles = [];
  for (let i = 0; i < 9; i++) {
    const t = tileEl(colors[Math.floor(Math.random() * 6)]);
    g.appendChild(t);
    tiles.push(t);
  }
  setInterval(() => {
    if (!$('#screen-home').classList.contains('active')) return;
    const t = tiles[Math.floor(Math.random() * 9)];
    const c = colors[Math.floor(Math.random() * 6)];
    t.style.transform = 'scale(0.6) rotate(90deg)';
    setTimeout(() => {
      const n = tileEl(c);
      t.dataset.c = c;
      t.innerHTML = n.innerHTML;
      t.style.transform = '';
    }, 180);
  }, 900);
}

// ======================================================================= lobby
function renderLobby() {
  const r = S.room;
  const isHost = r.host === S.me;
  const code = $('#lobby-code');
  if (code.dataset.code !== r.code) {
    code.dataset.code = r.code;
    const tints = ['var(--Y)', 'var(--G)', 'var(--B)', 'var(--O)'];
    code.innerHTML = [...r.code].map((ch, i) => `<span style="background:${tints[i]}">${ch}</span>`).join('');
  }
  const prevCount = $('#lobby-players').children.length;
  $('#lobby-players').innerHTML = r.players
    .map(
      (p) => `<li>
        <span class="avatar" style="background:${p.color}">${esc(p.name[0].toUpperCase())}</span>
        <span class="pname">${esc(p.name)}</span>
        ${p.id === S.me ? '<span class="you">(you)</span>' : ''}
        ${!p.connected ? '<span class="tag off">away</span>' : p.id === r.host ? '<span class="tag">host</span>' : ''}
      </li>`,
    )
    .join('');
  if (prevCount && r.players.length > prevCount) sfx.join();
  $('#player-count').textContent = `${r.players.length} / 6`;

  const seg = $('#rounds-seg');
  seg.classList.toggle('readonly', !isHost);
  for (const b of seg.children) b.classList.toggle('on', Number(b.dataset.r) === r.rounds);

  renderChallengePicker(r, isHost);

  const ready = r.players.filter((p) => p.connected).length;
  $('#btn-start').classList.toggle('hidden', !isHost);
  $('#btn-start').disabled = ready < 2;
  const host = r.players.find((p) => p.id === r.host);
  $('#lobby-hint').textContent = isHost
    ? ready < 2
      ? 'Waiting for friends to join… share the code!'
      : `${ready} players ready. Start when everyone's in.`
    : `Waiting for ${host ? host.name : 'the host'} to start…`;
}

$('#rounds-seg').onclick = (e) => {
  const r = Number(e.target.dataset?.r);
  if (r) net.send({ t: 'settings', rounds: r });
};
$('#btn-start').onclick = () => net.send({ t: 'start' });

// ----- challenge picker (host chooses which puzzle types are in the match)
const PRESET_LABELS = { classic: 'Classic', party: 'Party mix', brain: 'Brain burners', all: 'Everything' };
$('#preset-seg').innerHTML = Object.entries(PRESET_LABELS).map(([k, v]) => `<button data-p="${k}">${v}</button>`).join('');
$('#challenge-list').innerHTML = CHALLENGE_IDS.map(
  (id) => `<button class="chip" data-id="${id}"><span class="ci">${CHALLENGES[id].icon}</span><span class="cn">${CHALLENGES[id].name}</span><span class="stars">${starsOf(id)}</span></button>`,
).join('');

function renderChallengePicker(r, isHost) {
  const sel = new Set(r.challenges || ['classic']);
  const card = $('#challenge-card');
  card.classList.toggle('readonly', !isHost);
  for (const b of $('#preset-seg').children) {
    const set = PRESETS[b.dataset.p];
    b.classList.toggle('on', set.length === sel.size && set.every((id) => sel.has(id)));
  }
  for (const b of $('#challenge-list').children) b.classList.toggle('on', sel.has(b.dataset.id));
  for (const b of $('#order-seg').children) b.classList.toggle('on', b.dataset.o === (r.order || 'shuffle'));
  $('#order-row').classList.toggle('hidden', sel.size < 2);
  $('#challenge-summary').textContent =
    sel.size === 1
      ? CHALLENGES[[...sel][0]].rule
      : `${sel.size} challenges, ${r.order === 'climb' ? 'easiest first, getting harder each round' : 'in a random order'}.`;
}
$('#preset-seg').onclick = (e) => {
  const p = e.target.closest('button')?.dataset.p;
  if (p) net.send({ t: 'settings', challenges: PRESETS[p] });
};
$('#challenge-list').onclick = (e) => {
  const id = e.target.closest('button')?.dataset.id;
  if (!id || !S.room) return;
  const sel = new Set(S.room.challenges);
  if (sel.has(id)) {
    if (sel.size === 1) return toast('Pick at least one challenge');
    sel.delete(id);
  } else sel.add(id);
  net.send({ t: 'settings', challenges: CHALLENGE_IDS.filter((x) => sel.has(x)) });
};
$('#order-seg').onclick = (e) => {
  const o = e.target.closest('button')?.dataset.o;
  if (o) net.send({ t: 'settings', order: o });
};
$('#btn-leave-lobby').onclick = () => goHome();
$('#btn-share').onclick = async () => {
  const code = S.room?.code;
  if (!code) return;
  const url = `${location.origin}/?g=${code}`;
  const text = `Race me in Slide It! Game code: ${code}`;
  try {
    if (navigator.share) return await navigator.share({ title: 'Slide It', text, url });
  } catch (e) {
    if (e.name === 'AbortError') return;
  }
  try {
    await navigator.clipboard.writeText(`${text} ${url}`);
    toast('Invite link copied!');
  } catch {
    toast(`Code: ${code}`);
  }
};

// ======================================================================= game (online)
const meP = () => S.room?.players.find((p) => p.id === S.me);
// Spectators watch the player who's closest to solving.
function watchId() {
  const me = meP();
  if (me?.board) return S.me;
  const act = S.room?.players.filter((p) => p.board) || [];
  act.sort((a, b) => b.matches - a.matches);
  return act[0]?.id;
}

function renderRoom() {
  const r = S.room;
  const me = meP();
  if (!me) return;
  if (r.state === 'lobby') {
    S.roundId = null;
    hideOverlays();
    $('#countdown').classList.add('hidden');
    show('lobby');
    renderLobby();
    return;
  }
  show('game');
  $('#reactions').classList.remove('solo');

  if (S.roundId !== r.roundId) {
    // A brand-new round.
    S.roundId = r.roundId;
    S.revealed = null;
    S.myMoves = me.moves;
    S.locked = false;
    S.lastCountdown = null;
    hideOverlays();
    tray.goal = null;
    tray.region = regionFor(r.challenge);
    S.peekUntil = 0;
    const w = r.players.find((p) => p.id === watchId());
    tray.reset((w?.board || '.'.repeat(25)).split(''));
    renderTarget(null, false, r.challenge);
    renderBriefing(r.challenge, `Round ${r.round}`);
  } else if (me.board && me.moves >= S.myMoves && (r.state === 'playing' || r.state === 'countdown')) {
    reconcile(me.board, me.moves);
  }

  const playing = r.state === 'playing';
  if (r.goal && S.revealed !== r.roundId) {
    S.revealed = r.roundId;
    tray.goal = r.goal;
    renderTarget(r.goal, true);
    tray.highlight();
    lastMatchCount = progress(tray.board, tray.goal).n;
    if (playing) {
      sfx.go();
      showGo();
    }
  }

  $('#spectate').classList.toggle('hidden', !!me.board || r.state === 'roundover' || r.state === 'matchover');
  tray.enabled = playing && !!me.board && !S.locked && !peeking();
  $('#board').classList.toggle('locked', !tray.enabled);
  $('#countdown').classList.toggle('hidden', r.state !== 'countdown');

  if ((r.state === 'roundover' || r.state === 'matchover') && S.resultShownFor !== `${r.roundId}:${r.state}`) {
    S.resultShownFor = `${r.roundId}:${r.state}`;
    showResult();
  } else if (r.state === 'matchover') {
    renderResultActions(); // host may have changed
  }

  renderOpponents();
  renderStats();
}


/** The "Match this" card: the challenge name, its picture and a reminder of any twist. */
function renderTarget(goal, reveal = false, id = goal?.id) {
  const ch = CHALLENGES[id] || CHALLENGES.classic;
  $('#target-name').textContent = `${ch.icon} ${ch.name}`;
  const how = { mirror: 'Build it flipped ↔', twist: 'Build it turned ↻ 90°', anywhere: 'Anywhere on your tray', wild: '★ = any colour' }[id];
  $('#target-how').textContent = how || '';
  $('#target-how').classList.toggle('hidden', !how);
  const el = $('#target');
  const show = goal?.show || (makeGoal(id).show.w === 5 ? { w: 5, h: 5, tiles: Array(25).fill('?') } : { w: 3, h: 3, tiles: Array(9).fill('?') });
  el.classList.toggle('reveal', reveal);
  el.classList.toggle('map', show.w === 5);
  el.classList.remove('veiled');
  el.innerHTML = '';
  // In map view the blank cells of a hidden goal still show the shape.
  const cells = show.w === 5 && !goal ? new Set(regionFor(id)) : null;
  show.tiles.forEach((c, i) => {
    const t = tileEl(cells && !cells.has(i) ? EMPTY : c);
    if (reveal) t.style.animationDelay = `${i * (show.w === 5 ? 12 : 35)}ms`;
    el.appendChild(t);
  });
  $('#btn-peek').classList.add('hidden');
}

/** Countdown overlay: tell everyone what kind of challenge is coming. */
function renderBriefing(id, label) {
  const ch = CHALLENGES[id] || CHALLENGES.classic;
  $('#countdown-label').textContent = label;
  $('#countdown-challenge').innerHTML = `<b>${ch.icon} ${esc(ch.name)}</b> <span class="stars">${starsOf(id)}</span>`;
  $('#countdown-rule').textContent = ch.rule;
}

// ----- memory challenge: the target hides after a few seconds; peeking freezes you.
const peeking = () => Date.now() < (S.peekUntil || 0);
function currentGoal() {
  return S.mode === 'solo' ? S.solo?.goal : S.room?.goal;
}
function updateVeil(t, goAt, playing) {
  const goal = currentGoal();
  const el = $('#target');
  const veiled = !!goal?.peek && playing && t - goAt > goal.peek && !peeking();
  if (el.classList.contains('veiled') !== veiled) {
    el.classList.toggle('veiled', veiled);
    if (veiled && !S.peekUntil) toast('Target hidden! Tap Peek if you need it.', 1600);
  }
  $('#btn-peek').classList.toggle('hidden', !(goal?.peek && playing && t - goAt > goal.peek) || peeking());
  // Unfreeze after a peek.
  if (S.peekFrozen && !peeking()) {
    S.peekFrozen = false;
    if (S.mode === 'solo' ? S.solo?.state === 'playing' : S.room?.state === 'playing' && meP()?.board && !S.locked) {
      tray.enabled = true;
      $('#board').classList.remove('locked');
    }
  }
}
$('#btn-peek').onclick = () => {
  if (!tray.enabled) return;
  S.peekUntil = Date.now() + 1500;
  S.peekFrozen = true;
  tray.enabled = false;
  $('#board').classList.add('locked');
  $('#target').classList.remove('veiled');
  $('#btn-peek').classList.add('hidden');
  sfx.pop();
};

function onMyMove(i) {
  sfx.slide();
  haptic();
  const goal = tray.goal;
  if (S.mode === 'solo') return soloMove();
  S.myMoves += 1;
  net.send({ t: 'move', i });
  const me = meP();
  if (me) {
    me.board = tray.board.join('');
    me.moves = S.myMoves;
  }
  matchSound(goal);
  if (goal && goalSolved(tray.board, goal)) {
    // Freeze until the server confirms (it decides ties).
    S.locked = true;
    tray.enabled = false;
    $('#board').classList.add('solved');
  }
  renderStats();
}

function matchSound(goal) {
  if (!goal) return;
  const n = progress(tray.board, goal).n;
  if (n > lastMatchCount) sfx.match();
  else if (n < lastMatchCount) sfx.unmatch();
  lastMatchCount = n;
}

function renderStats() {
  if (S.mode === 'solo') {
    const best = S.solo ? getBest(S.solo.id) : null;
    $('#stat-a-k').textContent = 'Best';
    $('#stat-a').textContent = best ? fmtTime(best.ms) : '—';
    $('#stat-moves').textContent = S.solo?.moves ?? 0;
    return;
  }
  const r = S.room;
  const me = meP();
  if (!r || !me) return;
  $('#stat-a-k').textContent = 'Wins';
  $('#stat-a').textContent = `${me.score}/${r.winsNeeded}`;
  $('#stat-moves').textContent = me.board ? S.myMoves : '—';
}

const oppEls = new Map();
function renderOpponents() {
  const box = $('#opponents');
  if (S.mode === 'solo') return;
  const r = S.room;
  const others = r.players.filter((p) => p.id !== S.me);
  for (const [id, el] of oppEls) if (!others.find((p) => p.id === id)) (el.remove(), oppEls.delete(id));
  for (const p of others) {
    let el = oppEls.get(p.id);
    if (!el) {
      el = document.createElement('div');
      el.className = 'opp';
      el.innerHTML = `<div class="opp-head"><span class="avatar"></span><span class="opp-name"></span><span class="pips"></span></div>
        <div class="opp-body"><div class="mini"></div><div class="opp-meter"><span class="num"></span><div class="meter"><b></b></div><span class="opp-moves"></span></div></div>`;
      el.querySelector('.mini').innerHTML = '<i></i>'.repeat(25);
      oppEls.set(p.id, el);
      box.appendChild(el);
    }
    el.classList.toggle('offline', !p.connected);
    const total = r.goal ? r.goal.want.length : 9;
    el.classList.toggle('hot', !!p.board && !!r.goal && p.matches >= total - 2 && r.state === 'playing');
    const av = el.querySelector('.avatar');
    av.style.background = p.color;
    av.textContent = p.name[0].toUpperCase();
    el.querySelector('.opp-name').textContent = p.name;
    el.querySelector('.pips').innerHTML = Array.from({ length: r.winsNeeded }, (_, i) => `<i class="pip${i < p.score ? ' on' : ''}"></i>`).join('');
    const goal = r.goal;
    const cells = el.querySelectorAll('.mini i');
    const b = p.board || '';
    const hit = new Set(goal && b ? matchedCells(b.split(''), goal) : []);
    cells.forEach((cell, i) => {
      const c = b[i];
      cell.style.background = c && c !== EMPTY ? `var(--${c})` : 'transparent';
      cell.classList.toggle('m', hit.has(i));
    });
    el.querySelector('.num').innerHTML = p.board ? `${goal ? p.matches : 0}<small>/${total}</small>` : '<small>watching</small>';
    el.querySelector('.meter b').style.width = `${p.board && goal ? (p.matches / total) * 100 : 0}%`;
    el.querySelector('.opp-moves').textContent = p.board ? `${p.moves} moves` : p.connected ? '' : 'away';
  }
}

// ======================================================================= results
function hideOverlays() {
  $('#overlay-result').classList.add('hidden');
  $('#overlay-solo').classList.add('hidden');
}

function scoreboardHTML(winnerId) {
  const r = S.room;
  return [...r.players]
    .sort((a, b) => b.score - a.score)
    .map(
      (p) => `<li class="${p.id === winnerId ? 'win' : ''}">
        <span class="avatar" style="background:${p.color}">${esc(p.name[0].toUpperCase())}</span>
        <span class="pname">${esc(p.name)}${p.id === S.me ? ' (you)' : ''}</span>
        <span class="pips">${Array.from({ length: r.winsNeeded }, (_, i) => `<i class="pip${i < p.score ? ' on' : ''}"></i>`).join('')}</span>
        <span class="score">${p.score}</span>
      </li>`,
    )
    .join('');
}

let nextRoundTimer;
function showResult() {
  const r = S.room;
  const res = r.result;
  const winner = r.players.find((p) => p.id === res.winnerId);
  const iWon = res.winnerId === S.me;
  const match = r.state === 'matchover';
  tray.enabled = false;
  if (iWon) $('#board').classList.add('solved');
  // Show the winning tray to everyone else for a moment.
  if (!iWon && winner?.board) tray.setBoard(winner.board.split(''));

  $('#result-emoji').textContent = iWon ? (match ? '🏆' : '⚡') : match ? '🥈' : '😵';
  $('#result-title').textContent = iWon
    ? match ? 'You win the match!' : 'You got it!'
    : `${winner?.name || 'Someone'} ${match ? 'wins the match!' : 'got it first'}`;
  $('#result-sub').textContent = `${CHALLENGES[r.challenge]?.name || 'Classic'} · ${fmtTime(res.ms)}s · ${res.moves} moves`;
  $('#scoreboard').innerHTML = scoreboardHTML(res.winnerId);
  renderResultActions();
  iWon ? sfx.win() : sfx.lose();
  if (iWon) confetti(match ? 260 : 120);

  clearInterval(nextRoundTimer);
  const hint = $('#result-hint');
  hint.textContent = '';
  // Short delay so people see the final board before the sheet covers it.
  setTimeout(() => {
    if (S.resultShownFor === `${r.roundId}:${r.state}` && S.room.state === r.state) $('#overlay-result').classList.remove('hidden');
  }, 700);
  if (!match) {
    const tick = () => {
      const left = Math.ceil((S.room.goAt - now()) / 1000);
      hint.textContent = left > 0 ? `Next round in ${left}…` : 'Get ready…';
    };
    tick();
    nextRoundTimer = setInterval(tick, 250);
  }
}

function renderResultActions() {
  const r = S.room;
  const box = $('#result-actions');
  box.innerHTML = '';
  if (r.state !== 'matchover') return;
  clearInterval(nextRoundTimer);
  const isHost = r.host === S.me;
  if (isHost) {
    box.append(button('Play again', 'btn primary big', () => net.send({ t: 'start' })));
    box.append(button('Back to lobby', 'btn ghost', () => net.send({ t: 'lobby' })));
  } else {
    const host = r.players.find((p) => p.id === r.host);
    $('#result-hint').textContent = `Waiting for ${host?.name || 'the host'} to start a rematch…`;
  }
  box.append(button('Leave game', 'btn ghost', () => goHome()));
}

function button(label, cls, fn) {
  const b = document.createElement('button');
  b.className = cls;
  b.textContent = label;
  b.onclick = fn;
  return b;
}

// ======================================================================= countdown + timer loop
function showGo() {
  const c = $('#countdown');
  const n = $('#countdown-n');
  c.classList.remove('hidden');
  n.textContent = 'GO!';
  n.classList.remove('tick');
  void n.offsetWidth;
  n.classList.add('tick');
  $('#countdown-label').textContent = '';
  $('#countdown-challenge').innerHTML = '';
  $('#countdown-rule').textContent = '';
  setTimeout(() => c.classList.add('hidden'), 450);
}

function loop() {
  requestAnimationFrame(loop);
  if (!$('#screen-game').classList.contains('active')) return;
  let state, goAt, endMs;
  if (S.mode === 'solo') {
    if (!S.solo) return;
    state = S.solo.state;
    goAt = S.solo.goAt;
    endMs = S.solo.ms;
  } else if (S.room) {
    state = S.room.state;
    goAt = S.room.goAt;
    endMs = S.room.result?.ms;
  } else return;

  const t = S.mode === 'solo' ? Date.now() : now();
  if (state === 'countdown') {
    const left = Math.ceil((goAt - t) / 1000);
    if (left !== S.lastCountdown && left > 0) {
      S.lastCountdown = left;
      const n = $('#countdown-n');
      n.textContent = left;
      n.classList.remove('tick');
      void n.offsetWidth;
      n.classList.add('tick');
      sfx.beep();
    }
    $('#stat-time').textContent = '0.0';
  } else if (state === 'playing') {
    $('#stat-time').textContent = fmtTime(t - goAt);
    updateVeil(t, goAt, true);
  } else if (endMs != null) {
    $('#stat-time').textContent = fmtTime(endMs);
  }
}

// ======================================================================= reactions
const REACTIONS = ['👏', '🔥', '😱', '😂', '😤', '🐢'];
let lastReact = 0;
$('#reactions').innerHTML = REACTIONS.map((e) => `<button data-e="${e}" aria-label="React ${e}">${e}</button>`).join('');
$('#reactions').onclick = (e) => {
  const em = e.target.closest('button')?.dataset.e;
  if (!em || Date.now() - lastReact < 700) return;
  lastReact = Date.now();
  net.send({ t: 'react', e: em });
};
function floatReaction(id, e) {
  const p = S.room?.players.find((x) => x.id === id);
  if (!p) return;
  const f = document.createElement('div');
  f.className = 'floater';
  f.style.left = `${10 + Math.random() * 75}%`;
  f.innerHTML = `<span class="e">${esc(e)}</span><span class="n" style="background:${p.color}">${esc(p.id === S.me ? 'You' : p.name)}</span>`;
  $('#floaters').appendChild(f);
  sfx.pop();
  setTimeout(() => f.remove(), 2300);
}

$('#btn-leave-game').onclick = () => {
  if (S.mode === 'solo' || confirm('Leave this game?')) goHome();
};

// ======================================================================= solo practice
// Best times are kept per challenge. (Older versions stored a single 'best' for classic.)
const bestKey = (id) => `best:${id}`;
const getBest = (id) => store.get(bestKey(id), id === 'classic' ? store.get('best', null) : null);

function openSoloPicker() {
  const list = $('#solo-list');
  list.innerHTML =
    `<button class="chip wide" data-id="random"><span class="ci">🎲</span><span class="cn">Surprise me</span><span class="stars"></span></button>` +
    CHALLENGE_IDS.map((id) => {
      const best = getBest(id);
      return `<button class="chip wide" data-id="${id}"><span class="ci">${CHALLENGES[id].icon}</span>
        <span class="cn">${CHALLENGES[id].name}<small>${best ? `best ${fmtTime(best.ms)}s` : CHALLENGES[id].rule}</small></span>
        <span class="stars">${starsOf(id)}</span></button>`;
    }).join('');
  $('#overlay-solo').classList.remove('hidden');
}
$('#solo-list').onclick = (e) => {
  let id = e.target.closest('button')?.dataset.id;
  if (!id) return;
  if (id === 'random') id = CHALLENGE_IDS[Math.floor(Math.random() * CHALLENGE_IDS.length)];
  $('#overlay-solo').classList.add('hidden');
  sfx.pop();
  startSolo(id);
};
$('#overlay-solo [data-close]').onclick = () => $('#overlay-solo').classList.add('hidden');

function startSolo(id = S.solo?.id || 'classic') {
  S.mode = 'solo';
  hideOverlays();
  for (const el of oppEls.values()) el.remove();
  oppEls.clear();
  const goal = makeGoal(id);
  const board = makeBoardFor(goal);
  S.solo = { id, goal, moves: 0, state: 'countdown', goAt: Date.now() + 3000, ms: null };
  S.lastCountdown = null;
  S.peekUntil = 0;
  S.peekFrozen = false;
  lastMatchCount = 0;
  tray.goal = null;
  tray.region = goal.cells;
  tray.reset(board);
  tray.enabled = false;
  renderTarget(null, false, id);
  renderSoloCard();
  $('#reactions').classList.add('solo');
  $('#spectate').classList.add('hidden');
  renderBriefing(id, 'Solo');
  $('#countdown').classList.remove('hidden');
  $('#board').classList.add('locked');
  show('game');
  renderStats();
  const solo = S.solo;
  setTimeout(() => {
    if (S.solo !== solo) return;
    solo.state = 'playing';
    solo.goAt = Date.now();
    tray.goal = goal;
    renderTarget(goal, true);
    tray.highlight();
    lastMatchCount = progress(tray.board, goal).n;
    tray.enabled = true;
    $('#board').classList.remove('locked');
    sfx.go();
    showGo();
  }, 3000);
}

function renderSoloCard() {
  const id = S.solo.id;
  const best = getBest(id);
  const played = store.get('played', 0);
  $('#opponents').innerHTML = `<div class="opp"><div class="opp-head"><span class="opp-name">Solo · ${esc(CHALLENGES[id].name)}</span></div>
    <div class="opp-meter"><span class="num">${best ? `${fmtTime(best.ms)}<small>s best</small>` : '<small>No best time yet</small>'}</span>
    <span class="opp-moves">${best ? `${best.moves} moves · ` : ''}${played} solved</span></div></div>`;
}

function soloMove() {
  const s = S.solo;
  s.moves += 1;
  matchSound(s.goal);
  renderStats();
  if (!goalSolved(tray.board, s.goal)) return;
  s.state = 'done';
  s.ms = Date.now() - s.goAt;
  tray.enabled = false;
  $('#board').classList.add('solved');
  $('#target').classList.remove('veiled');
  $('#btn-peek').classList.add('hidden');
  const best = getBest(s.id);
  const isBest = !best || s.ms < best.ms;
  if (isBest) store.set(bestKey(s.id), { ms: s.ms, moves: s.moves });
  store.set('played', store.get('played', 0) + 1);
  sfx.win();
  confetti(isBest ? 220 : 90);
  $('#result-emoji').textContent = isBest ? '🏆' : '🎉';
  $('#result-title').textContent = isBest ? 'New personal best!' : 'Solved!';
  $('#result-sub').textContent = `${CHALLENGES[s.id].name} · ${fmtTime(s.ms)}s · ${s.moves} moves${!isBest ? ` · best ${fmtTime(best.ms)}s` : ''}`;
  $('#scoreboard').innerHTML = '';
  $('#result-hint').textContent = '';
  const box = $('#result-actions');
  box.innerHTML = '';
  box.append(button('Play again', 'btn primary big', () => startSolo(s.id)));
  box.append(button('Try another challenge', 'btn ghost', openSoloPicker));
  box.append(button('Home', 'btn ghost', () => goHome()));
  setTimeout(() => S.solo === s && $('#overlay-result').classList.remove('hidden'), 800);
  renderSoloCard();
  renderStats();
}

// ======================================================================= keyboard (desktop testing)
document.addEventListener('keydown', (e) => {
  const dir = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' }[e.key];
  if (dir && tray.enabled && $('#screen-game').classList.contains('active')) {
    e.preventDefault();
    tray.push(dir);
  }
});

// ======================================================================= confetti
function confetti(n) {
  const cv = $('#confetti');
  const ctx = cv.getContext('2d');
  const dpr = devicePixelRatio || 1;
  cv.width = innerWidth * dpr;
  cv.height = innerHeight * dpr;
  const colors = ['#ff4d5e', '#ff9a2e', '#ffd93d', '#2fd27a', '#3d8bff', '#ffffff'];
  const parts = Array.from({ length: n }, () => ({
    x: innerWidth / 2 + (Math.random() - 0.5) * 120,
    y: innerHeight * 0.45,
    vx: (Math.random() - 0.5) * 16,
    vy: -Math.random() * 16 - 6,
    s: 6 + Math.random() * 7,
    r: Math.random() * 6,
    vr: (Math.random() - 0.5) * 0.4,
    c: colors[Math.floor(Math.random() * colors.length)],
  }));
  const start = performance.now();
  (function frame(t) {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    for (const p of parts) {
      p.vy += 0.45;
      p.vx *= 0.99;
      p.x += p.vx;
      p.y += p.vy;
      p.r += p.vr;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.r);
      ctx.fillStyle = p.c;
      ctx.fillRect(-p.s / 2, -p.s / 3, p.s, p.s * 0.66);
      ctx.restore();
    }
    if (t - start < 3500) requestAnimationFrame(frame);
    else ctx.clearRect(0, 0, innerWidth, innerHeight);
  })(start);
}

// ======================================================================= boot
$('#howto-challenges').innerHTML = CHALLENGE_IDS.map(
  (id) => `<li><span>${CHALLENGES[id].icon}</span><div><b>${CHALLENGES[id].name}</b> <span class="stars">${starsOf(id)}</span><br>${esc(CHALLENGES[id].rule)}</div></li>`,
).join('');
setSound(soundOn);
$('#name').value = store.get('name', '');
initLogo();
loop();
if (isIOS && !standalone) $('#install-tip').classList.remove('hidden');

// Invite links look like /?g=ABCD
const linkCode = new URLSearchParams(location.search).get('g')?.toUpperCase();
if (linkCode && /^[A-Z]{4}$/.test(linkCode)) {
  $('#join-code').value = linkCode;
  const sess = store.get('session');
  if (sess?.code === linkCode) {
    startOnline({ t: 'join', code: linkCode, playerId: sess.playerId, token: sess.token, name: myName() });
  } else if (store.get('name', '')) {
    startOnline({ t: 'join', code: linkCode, name: myName() });
  } else {
    toast('Enter your name, then tap Join');
    $('#name').focus();
  }
} else {
  renderRejoin();
}
