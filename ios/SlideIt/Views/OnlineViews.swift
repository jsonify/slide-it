import SwiftUI

/// Top-level view for a multiplayer match: lobby, then the race.
struct OnlineMatchView: View {
    @ObservedObject var session: OnlineSession
    let onExit: () -> Void
    @State private var confirmLeave = false

    var body: some View {
        ZStack {
            AppBackground()
            switch session.client.phase {
            case .lobby:
                LobbyView(session: session, onExit: onExit)
            case .ended(let reason):
                ResultCard(emoji: "👋", title: "Game over", subtitle: reason, rows: scoreRows, winsNeeded: session.client.winsNeeded) {
                    Button("Back to menu", action: onExit).buttonStyle(GameButtonStyle(kind: .primary, big: true))
                }
            default:
                RaceView(session: session, onClose: { confirmLeave = true })
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.client.phase)
        .confirmationDialog("Leave this game?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave game", role: .destructive, action: onExit)
        }
    }

    private var scoreRows: [ScoreRow] {
        session.players.map {
            .init(id: $0.id, name: $0.name, color: session.color(for: $0.id), score: session.client.scores[$0.id] ?? 0, highlight: false)
        }
    }
}

struct LobbyView: View {
    @ObservedObject var session: OnlineSession
    let onExit: () -> Void

    private var client: MatchClient { session.client }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    IconButton(systemName: "xmark", action: onExit)
                    Spacer()
                    Text("Game lobby").font(Theme.display(20)).foregroundStyle(Theme.text)
                    Spacer()
                    Color.clear.frame(width: 42, height: 42)
                }

                Panel {
                    VStack(spacing: 8) {
                        Image(systemName: session.transport.kind == .nearby ? "dot.radiowaves.left.and.right" : "gamecontroller.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        Text(session.transport.kind == .nearby ? "Nearby game" : "Game Center match")
                            .font(Theme.display(20)).foregroundStyle(Theme.text)
                        Text(session.transport.kind == .nearby
                             ? (client.isHost ? "Friends nearby can find this game under Play Nearby → Join." : "Connected to the host.")
                             : "Everyone's connected through Game Center.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Players").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                            Spacer()
                            Text("\(client.players.count)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                        ForEach(client.players) { p in
                            HStack(spacing: 12) {
                                Avatar(name: p.name, color: session.color(for: p.id))
                                Text(p.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                                if p.id == client.me.id {
                                    Text("(you)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if p.id == client.hostID {
                                    Text("HOST")
                                        .font(.system(size: 11, weight: .heavy)).tracking(1)
                                        .foregroundStyle(Theme.accent)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(10)
                            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                        if client.others.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView().tint(Theme.muted)
                                Text("Waiting for players to join…").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: client.players)
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Match length")
                        Picker("Match length", selection: Binding(get: { client.bestOf }, set: { session.setBestOf($0) })) {
                            Text("1 round").tag(1)
                            Text("Best of 3").tag(3)
                            Text("Best of 5").tag(5)
                            Text("Best of 7").tag(7)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!client.isHost)
                    }
                }

                if client.isHost {
                    Button("Start game") { session.start() }
                        .buttonStyle(GameButtonStyle(kind: .primary, big: true))
                        .disabled(!client.canStart)
                        .opacity(client.canStart ? 1 : 0.5)
                } else {
                    Text("Waiting for \(client.name(of: client.hostID)) to start…")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}

struct RaceView: View {
    @ObservedObject var session: OnlineSession
    let onClose: () -> Void

    private var client: MatchClient { session.client }

    var body: some View {
        ZStack {
            GameLayout {
                GameBar(onClose: onClose) {
                    StatPill(label: "Wins", value: "\(client.scores[client.me.id] ?? 0)/\(client.winsNeeded)")
                    TimerText(start: session.revealedAt, finalMs: finalMs)
                    StatPill(label: "Moves", value: "\(client.moves.count)")
                }
            } side: {
                TargetPanel(target: client.target)
                ForEach(client.others) { p in
                    OpponentCard(
                        player: p,
                        color: session.color(for: p.id),
                        opponent: client.opponents[p.id],
                        target: client.target,
                        score: client.scores[p.id] ?? 0,
                        winsNeeded: client.winsNeeded,
                        live: client.phase == .playing
                    )
                }
            } tray: {
                if let board = displayedBoard {
                    TrayView(
                        board: board,
                        target: client.target,
                        enabled: client.canMove,
                        solved: session.solvedFlash || client.result?.winnerID == client.me.id,
                        onTap: session.tap,
                        onSwipe: session.swipe
                    )
                }
            } bottom: {
                ReactionBar(onReact: session.react)
            }

            FloatingReactions(reactions: session.reactions)

            if client.phase == .countdown, let endsAt = session.countdownEndsAt {
                CountdownOverlay(endsAt: endsAt, label: "Round \(client.round)")
            }

            if let result = client.result, client.phase == .roundOver || client.phase == .matchOver {
                ResultOverlay(session: session, result: result)
            }
        }
    }

    private var finalMs: Int? {
        guard let r = client.result, client.phase == .roundOver || client.phase == .matchOver else { return nil }
        return r.ms
    }

    /// After someone else wins, show their winning tray for a moment.
    private var displayedBoard: Board? {
        if let r = client.result, r.winnerID != client.me.id, let b = client.opponents[r.winnerID]?.board {
            return b
        }
        return client.board
    }
}

struct TargetPanel: View {
    let target: [TileColor]?
    @Environment(\.isWideLayout) private var wide
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Panel(padding: wide ? 16 : 10) {
            VStack(spacing: 6) {
                SectionLabel("Match this")
                TargetView(target: target, tileSize: wide ? 48 : (sizeClass == .regular ? 40 : 28))
            }
        }
    }
}

struct OpponentCard: View {
    let player: PlayerInfo
    let color: Color
    let opponent: MatchClient.Opponent?
    let target: [TileColor]?
    let score: Int
    let winsNeeded: Int
    let live: Bool
    @Environment(\.isWideLayout) private var wide

    var body: some View {
        let matches = (target.flatMap { t in opponent?.board.map { $0.matches(t) } }) ?? 0
        let hot = live && matches >= 7
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Avatar(name: player.name, color: color, size: 20)
                Text(player.name).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 4)
                Pips(total: winsNeeded, filled: score)
            }
            HStack(spacing: 8) {
                MiniBoard(wire: opponent?.board?.wire, target: target, size: wide ? 64 : 50)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(matches)").font(Theme.display(20)).foregroundStyle(Theme.text)
                        Text("/9").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.good, Theme.accent], startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * Double(matches) / 9)
                        }
                    }
                    .frame(height: 6)
                    Text("\(opponent?.moves ?? 0) moves").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: wide ? nil : 170)
        .frame(maxWidth: wide ? .infinity : nil)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(hot ? Theme.accent2 : Theme.line, lineWidth: hot ? 2 : 1))
        .animation(.easeOut(duration: 0.25), value: matches)
    }
}

private struct ResultOverlay: View {
    @ObservedObject var session: OnlineSession
    let result: RoundOver
    @State private var visible = false

    private var client: MatchClient { session.client }

    var body: some View {
        let iWon = result.winnerID == client.me.id
        let match = result.matchOver
        let winner = client.name(of: result.winnerID)
        ZStack {
            if iWon { ConfettiView(count: match ? 260 : 120) }
            if visible {
                ResultCard(
                    emoji: iWon ? (match ? "🏆" : "⚡") : (match ? "🥈" : "😵"),
                    title: iWon ? (match ? "You win the match!" : "You got it!") : "\(winner) \(match ? "wins the match!" : "got it first")",
                    subtitle: "\(formatTime(result.ms))s · \(result.moves) moves",
                    rows: rows,
                    winsNeeded: client.winsNeeded,
                    hint: match && !client.isHost ? "Waiting for \(client.name(of: client.hostID)) to start a rematch…" : nil,
                    hintUntil: match ? nil : session.nextRoundAt
                ) {
                    if match {
                        if client.isHost {
                            Button("Play again") { session.start() }.buttonStyle(GameButtonStyle(kind: .primary, big: true))
                            Button("Back to lobby") { session.backToLobby() }.buttonStyle(GameButtonStyle(kind: .ghost))
                        }
                    }
                }
            }
        }
        .task(id: result.roundId) {
            // Let everyone see the final tray before the card covers it.
            visible = false
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { visible = true }
        }
    }

    private var rows: [ScoreRow] {
        client.players
            .map { ScoreRow(id: $0.id, name: $0.id == client.me.id ? "\($0.name) (you)" : $0.name, color: session.color(for: $0.id), score: client.scores[$0.id] ?? 0, highlight: $0.id == result.winnerID) }
            .sorted { $0.score > $1.score }
    }
}
