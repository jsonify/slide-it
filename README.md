# Slide It 🟥🟨🟦

A real-time, head-to-head **sliding tile race** for iPhone, iPad, or any browser.
Everyone gets the same scrambled 5×5 tray. When the countdown ends, a random 3×3
target appears. First to make the middle of their tray match it wins the round.

It comes in two flavours:

- **Native iPhone & iPad app** (`ios/`): SwiftUI, with online play through Game
  Center and nearby play over Wi-Fi/Bluetooth. **No server to host.**
  See [ios/README.md](ios/README.md).
- **Web app** (this folder): runs in any browser via a link. Needs a small Node
  server online.

## Features

- **10 challenge types** from easy to brutal (see below). The host picks which are in the match, with presets and a "get harder" mode
- **Live multiplayer for 2–6 players**: 4-letter room codes, plus invite links through the iOS share sheet
- **Fair races**: every player starts from the identical scramble
- **Server-authoritative**: the server deals the boards, checks every move and decides the winner, so nobody can cheat
- **See your rivals**: opponents' trays update live, with a match meter that turns red when someone is close
- **Best of 1 / 3 / 5 / 7** matches, auto next round, rematch button
- **Tap or swipe**: tap any tile in line with the gap to push the whole row or column, or swipe
- Emoji reactions, sound effects, haptic ticks (iOS 18+), keeps the screen awake while you play
- **Reconnects automatically** if a phone locks or switches apps, and you keep your seat and score
- **Solo practice** for any challenge, with a personal-best time for each
- Colour-blind friendly: every colour also has its own shape
- Layouts for phone portrait, iPad portrait and iPad/desktop landscape

## Run it locally

```bash
npm install
npm start          # → http://localhost:3000
```

To play with phones on the same Wi-Fi, open `http://<your-computer's-IP>:3000`
on each device.

## Put it online so friends anywhere can play

It's a single small Node server (HTTP + WebSocket), so any Node host works.

**Render (free, easiest):** push this repo to GitHub, then on render.com choose
*New → Blueprint*, select the repo, and it uses `render.yaml`. You get a URL
like `https://slide-it.onrender.com`. Send that to your friends.
(Free instances go to sleep when idle, so the first visit can take ~30s to wake.)

**Fly.io / Railway / anywhere with Docker:** a `Dockerfile` is included.
The server listens on `$PORT`.

## How to play

1. One person taps **Create a game** and then **Invite friends** (or reads out the code).
2. Friends tap the link, or enter the code and tap **Join**.
3. The host picks the match length and taps **Start game**.
4. After 3‑2‑1, the target appears. Slide tiles until the **middle 3×3** (dashed box) matches it.
   The outer ring doesn't matter. Matching tiles get a white glow.
5. First to match wins the round. Win enough rounds to take the match.

## Challenges

Each round is one challenge. The countdown announces which one is coming, and
the target card shows its picture and reminds you of any twist.

| | Challenge | What you do |
|---|---|---|
| ★ | 🎯 Classic | Match the middle 3×3 |
| ★ | ✨ Wildcards | Middle 3×3, but three star squares take any colour |
| ★ | 🧭 Anywhere | Build the 3×3 pattern anywhere on the tray |
| ★★ | 🪞 Mirror | Build the picture flipped left ↔ right |
| ★★ | ➕ Big Cross | Match the full middle row and column (9 tiles, out to the edges) |
| ★★ | ❌ X Marks | Match both long diagonals |
| ★★★ | 🌀 Twist | Build the picture turned 90° clockwise |
| ★★★ | 🧠 Memory | The target vanishes 5s after GO. Peeking shows it again but freezes your tray for 1.5s |
| ★★★ | 🔲 Four Corners | Match all four 2×2 corner blocks (16 tiles) |
| ★★★ | 💍 The Ring | Match the whole outer ring (16 tiles) |

In the lobby the host picks a preset (**Classic**, **Party mix**, **Brain
burners**, **Everything**) or toggles challenges one by one, and chooses
**Shuffle** or **Get harder** (easiest first, building up to the hardest).
Rounds work through the chosen set without repeats.

Adding a challenge means adding an entry to `CHALLENGES` and a case in
`makeGoal()` in `public/game.js`. A goal is just a list of tray cells and the
colour each needs, so the server, win check and UI pick it up automatically.

## Project layout

```
server.js           HTTP static server + WebSocket rooms (authoritative game state)
public/game.js      Shared rules (deal, slide, win check), used by server AND browser
public/app.js       Client: screens, animated tray, networking, sound, haptics
public/style.css    Styles / responsive layouts
public/index.html   App shell + PWA metadata
test/               node:test unit tests + a full two-player match over WebSockets
```

```bash
npm test
```
