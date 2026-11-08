# Slide It for iPhone & iPad

A native SwiftUI version of Slide It. **No server needed**: online play runs
on Apple's Game Center, and nearby play connects phones directly.

## Ways to play

| Mode | What it is | Needs |
|---|---|---|
| **Play online** | Invite friends anywhere through Messages / Game Center, 2–4 players | Internet + Game Center |
| **Play nearby** | Friends in the same room, phones connect directly (Wi-Fi/Bluetooth), up to 6 players | Nothing |
| **Face-off** | Two players race on one iPad, sitting opposite each other | Nothing |
| **Solo practice** | Beat your best time | Nothing |

All the web version's extras are here too: live opponent trays, best-of-N
matches, emoji reactions, sounds, haptics, colour-blind shapes, and layouts for
iPhone, iPad portrait and iPad landscape.

## Run it on your own iPhone / iPad

You need a Mac with **Xcode 16 or newer**.

1. Open `ios/SlideIt.xcodeproj` in Xcode.
2. Click the **SlideIt** project → **Signing & Capabilities** → choose your **Team**
   (sign in with your Apple ID under Xcode → Settings → Accounts if needed).
3. If Xcode complains the bundle ID is taken, change **Bundle Identifier** to
   something unique, e.g. `com.yourname.slideit`.
4. Plug in your iPhone/iPad, pick it at the top of the window, press **▶ Run**.

**Free Apple ID?** Personal (free) teams can't use Game Center. Remove the
**Game Center** capability in Signing & Capabilities and everything else
(Nearby, Face-off, Solo) still works. Free-account builds expire after 7 days.

## Getting it onto your friends' phones (TestFlight)

This needs the Apple Developer Program ($99/year).

1. In [App Store Connect](https://appstoreconnect.apple.com) → **Apps → +**,
   create an app with the same bundle identifier.
2. In the app's page, turn on **Game Center** (Features → Game Center). Online
   matchmaking only works once this is on.
3. In Xcode: **Product → Archive**, then **Distribute App → TestFlight & App Store**.
4. In App Store Connect → **TestFlight**, add your friends' emails as testers.
   They install Apple's **TestFlight** app and tap your invite. Builds last 90 days;
   upload a new one to keep playing.

From there you're one review away from the App Store if you want it.

## How multiplayer works (no server)

- One device in each match is the **host** (the lowest Game Center player ID,
  or whoever tapped *Host* in Nearby). It deals the rounds and acts as referee.
- When someone solves the puzzle, their device sends every move they made. The
  host replays them from the shared starting tray to check the claim is real.
- To be fair despite lag, the host waits 0.35s after the first claim and awards
  the round to the **fastest time**, measured on each player's own device from
  the moment their target appeared.
- If the host leaves mid-match, the remaining players pick a new host and the
  round is re-dealt. Scores are kept.

## Code layout

```
ios/
  SlideIt.xcodeproj         Xcode project (folders are synced, so new files are picked up automatically)
  SlideItCore/              Platform-independent game logic, compiled into the app
    Sources/SlideItCore/
      Rules.swift           Tiles, board, sliding, win check
      Protocol.swift        Network messages
      MatchEngine.swift     Host-side referee
      MatchClient.swift     Each device's match state machine (pure, fully unit-tested)
    Tests/                  25 tests, including simulated multi-device matches
  SlideIt/
    App/                    App entry, theme, sound synth + haptics
    Multiplayer/            Game Center + Nearby transports, OnlineSession glue
    Views/                  Tray, lobby, race screen, home, shared components
    Modes/                  Solo, Face-off, Nearby join
```

Run the logic tests on a Mac (or any machine with Swift):

```bash
cd ios/SlideItCore && swift test
```
