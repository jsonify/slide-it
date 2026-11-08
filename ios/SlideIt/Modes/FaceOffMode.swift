import SwiftUI

/// Two players, one device, sitting opposite each other. Each gets their own
/// tray (the top one is upside down) and races the other on the same scramble.
@MainActor
final class FaceOffGame: ObservableObject {
    enum Phase: Equatable { case countdown, playing, done(winner: Int) }

    @Published private(set) var phase: Phase = .countdown
    @Published private(set) var target: [TileColor] = []
    @Published private(set) var boards: [Board] = []
    @Published private(set) var moves = [0, 0]
    @Published private(set) var scores = [0, 0]
    @Published private(set) var countdownEndsAt = Date()
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishMs = 0
    private var roundToken = UUID()

    init() { newRound() }

    func newRound() {
        target = Rules.makeTarget()
        let board = Board.scrambled(for: target)
        boards = [board, board]
        moves = [0, 0]
        startedAt = nil
        phase = .countdown
        countdownEndsAt = Date().addingTimeInterval(MatchEngine.countdown)
        let token = UUID()
        roundToken = token
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(MatchEngine.countdown * 1_000_000_000))
            guard let self, self.roundToken == token else { return }
            self.phase = .playing
            self.startedAt = Date()
            Feedback.shared.play(.go)
            Feedback.shared.tap()
        }
    }

    func resetScores() {
        scores = [0, 0]
        newRound()
    }

    func tap(_ player: Int, _ index: Int) {
        guard phase == .playing else { return }
        let before = boards[player].matches(target)
        guard boards[player].slide(index) else { return }
        moves[player] += 1
        Feedback.shared.play(.slide)
        Feedback.shared.tap()
        if boards[player].matches(target) > before { Feedback.shared.play(.match) }
        if boards[player].isSolved(target) {
            scores[player] += 1
            finishMs = Int(Date().timeIntervalSince(startedAt ?? Date()) * 1000)
            phase = .done(winner: player)
            Feedback.shared.play(.win)
            Feedback.shared.success()
        }
    }

    func swipe(_ player: Int, _ direction: Direction) {
        guard phase == .playing, let i = boards[player].tileMoving(direction) else { return }
        tap(player, i)
    }
}

struct FaceOffView: View {
    @StateObject private var game = FaceOffGame()
    let onExit: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                half(1).rotationEffect(.degrees(180))
                middle
                half(0)
            }
            .padding(.horizontal, 12)

            if case .done(let winner) = game.phase {
                ConfettiView(count: 140)
                    .rotationEffect(.degrees(winner == 1 ? 180 : 0))
            }
        }
    }

    private var middle: some View {
        HStack(spacing: 12) {
            IconButton(systemName: "xmark", action: onExit)
            Spacer()
            switch game.phase {
            case .countdown:
                TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                    let left = max(1, Int(ceil(game.countdownEndsAt.timeIntervalSince(ctx.date))))
                    Text("\(left)").font(Theme.display(34)).foregroundStyle(Theme.accent)
                        .onChange(of: left, initial: true) { _, _ in Feedback.shared.play(.beep) }
                }
            case .playing:
                TimerText(start: game.startedAt, finalMs: nil)
            case .done:
                Button("Next round") { game.newRound() }
                    .buttonStyle(GameButtonStyle(kind: .primary))
                    .frame(maxWidth: 200)
            }
            Spacer()
            IconButton(systemName: "arrow.counterclockwise") { game.resetScores() }
        }
        .padding(.vertical, 8)
    }

    private func half(_ player: Int) -> some View {
        GeometryReader { geo in
            let sideWidth = min(130, geo.size.width * 0.28)
            let tray = min(geo.size.height - 8, geo.size.width - sideWidth - 12)
            let revealed = game.phase != .countdown
            HStack(spacing: 12) {
                VStack(spacing: 10) {
                    Text("Player \(player + 1)")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.avatars[player])
                    TargetView(target: revealed ? game.target : nil, tileSize: min(34, (sideWidth - 20) / 3.6))
                    Text("Wins: \(game.scores[player])")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("\(game.moves[player]) moves")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .frame(width: sideWidth)

                ZStack {
                    TrayView(
                        board: game.boards[player],
                        target: revealed ? game.target : nil,
                        enabled: game.phase == .playing,
                        solved: game.phase == .done(winner: player),
                        onTap: { game.tap(player, $0) },
                        onSwipe: { game.swipe(player, $0) }
                    )
                    if case .done(let winner) = game.phase {
                        Text(winner == player ? "You win! \(formatTime(game.finishMs))s" : "So close!")
                            .font(Theme.display(24))
                            .foregroundStyle(winner == player ? Color(hex: 0x2A1D00) : Theme.text)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(winner == player ? Theme.accent : Theme.panel, in: Capsule())
                            .shadow(radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: tray, height: tray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: game.phase)
    }
}
