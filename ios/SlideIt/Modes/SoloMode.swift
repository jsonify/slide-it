import SwiftUI

/// Single-player practice against the clock.
@MainActor
final class SoloGame: ObservableObject {
    enum Phase: Equatable { case countdown, playing, done }

    @Published private(set) var phase: Phase = .countdown
    @Published private(set) var target: [TileColor] = []
    @Published private(set) var board = Board(colors: Array(repeating: nil, count: Rules.cellCount))
    @Published private(set) var moves = 0
    @Published private(set) var countdownEndsAt = Date()
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishMs: Int?
    @Published private(set) var isNewBest = false

    @AppStorage("soloBestMs") var bestMs = 0
    @AppStorage("soloBestMoves") var bestMoves = 0
    @AppStorage("soloSolved") var solvedCount = 0

    private var roundToken = UUID()

    init() { newRound() }

    func newRound() {
        target = Rules.makeTarget()
        board = Board.scrambled(for: target)
        moves = 0
        startedAt = nil
        finishMs = nil
        isNewBest = false
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

    func tap(_ index: Int) {
        guard phase == .playing else { return }
        let before = board.matches(target)
        guard board.slide(index) else { return bump() }
        moves += 1
        Feedback.shared.play(.slide)
        Feedback.shared.tap()
        let after = board.matches(target)
        if after > before { Feedback.shared.play(.match) }
        if after < before { Feedback.shared.play(.unmatch) }
        if board.isSolved(target) { finish() }
    }

    func swipe(_ direction: Direction) {
        guard phase == .playing else { return }
        guard let i = board.tileMoving(direction) else { return bump() }
        tap(i)
    }

    private func bump() {
        Feedback.shared.play(.bump)
        Feedback.shared.bump()
    }

    private func finish() {
        let ms = Int(Date().timeIntervalSince(startedAt ?? Date()) * 1000)
        finishMs = ms
        phase = .done
        isNewBest = bestMs == 0 || ms < bestMs
        if isNewBest {
            bestMs = ms
            bestMoves = moves
        }
        solvedCount += 1
        Feedback.shared.play(.win)
        Feedback.shared.success()
    }
}

struct SoloView: View {
    @StateObject private var game = SoloGame()
    let onExit: () -> Void
    @State private var showCard = false

    var body: some View {
        ZStack {
            AppBackground()
            GameLayout {
                GameBar(onClose: onExit) {
                    StatPill(label: "Best", value: game.bestMs > 0 ? formatTime(game.bestMs) : "—")
                    TimerText(start: game.startedAt, finalMs: game.finishMs)
                    StatPill(label: "Moves", value: "\(game.moves)")
                }
            } side: {
                TargetPanel(target: game.phase == .countdown ? nil : game.target)
                Panel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Solo practice").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                        Text(game.bestMs > 0 ? "Best \(formatTime(game.bestMs))s · \(game.bestMoves) moves" : "No best time yet")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text("\(game.solvedCount) solved").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .frame(minWidth: 150, alignment: .leading)
                }
            } tray: {
                TrayView(
                    board: game.board,
                    target: game.phase == .countdown ? nil : game.target,
                    enabled: game.phase == .playing,
                    solved: game.phase == .done,
                    onTap: game.tap,
                    onSwipe: game.swipe
                )
            } bottom: {
                EmptyView()
            }

            if game.phase == .countdown {
                CountdownOverlay(endsAt: game.countdownEndsAt, label: "Solo")
            }

            if game.phase == .done {
                ConfettiView(count: game.isNewBest ? 220 : 90)
                if showCard {
                    ResultCard(
                        emoji: game.isNewBest ? "🏆" : "🎉",
                        title: game.isNewBest ? "New personal best!" : "Solved!",
                        subtitle: "\(formatTime(game.finishMs ?? 0))s · \(game.moves) moves" + (game.isNewBest ? "" : " · best \(formatTime(game.bestMs))s")
                    ) {
                        Button("Play again") { game.newRound() }.buttonStyle(GameButtonStyle(kind: .primary, big: true))
                        Button("Menu", action: onExit).buttonStyle(GameButtonStyle(kind: .ghost))
                    }
                }
            }
        }
        .onChange(of: game.phase) { _, phase in
            showCard = false
            guard phase == .done else { return }
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { showCard = game.phase == .done }
            }
        }
    }
}
