import Foundation
import SwiftUI

/// Runs one multiplayer match. All the game logic lives in `MatchClient`; this
/// class connects it to a transport, real timers, sounds and haptics.
@MainActor
final class OnlineSession: ObservableObject, Identifiable {
    struct FloatingReaction: Identifiable, Equatable {
        let id = UUID()
        let emoji: String
        let name: String
        let color: Color
        let x: CGFloat
    }

    let id = UUID()
    let transport: GameTransport

    @Published private(set) var client: MatchClient
    @Published private(set) var countdownEndsAt: Date?
    @Published private(set) var revealedAt: Date?
    @Published private(set) var nextRoundAt: Date?
    @Published private(set) var reactions: [FloatingReaction] = []
    @Published private(set) var solvedFlash = false

    private var timers: [Task<Void, Never>] = []
    private var lastReaction = Date.distantPast

    init(transport: GameTransport) {
        self.transport = transport
        client = MatchClient(me: transport.localPlayer, others: transport.remotePlayers, hostID: transport.hostID)
        transport.onReceive = { [weak self] data, sender in self?.received(data, from: sender) }
        transport.onPlayersChanged = { [weak self] in self?.playersChanged() }
        playersChanged()
    }

    // MARK: Derived helpers for the UI

    var players: [PlayerInfo] { client.players }

    func color(for id: String) -> Color {
        // Stable colours: everyone sorts the roster the same way.
        let ids = client.players.map(\.id).sorted()
        let i = ids.firstIndex(of: id) ?? 0
        return Theme.avatars[i % Theme.avatars.count]
    }

    var elapsedMs: Int {
        guard let revealedAt else { return 0 }
        return Int(Date().timeIntervalSince(revealedAt) * 1000)
    }

    // MARK: Inputs

    func setBestOf(_ n: Int) { run { c, _ in c.setBestOf(n) } }

    func start() {
        run { c, rng in c.start(using: &rng) }
        transport.setLobbyOpen(false)
    }

    func backToLobby() {
        run { c, _ in c.backToLobby() }
        transport.setLobbyOpen(true)
    }

    func tap(_ index: Int) {
        let ms = elapsedMs
        run { c, _ in c.tap(index, elapsedMs: ms) }
    }

    func swipe(_ direction: Direction) {
        let ms = elapsedMs
        run { c, _ in c.swipe(direction, elapsedMs: ms) }
    }

    func react(_ emoji: String) {
        guard Date().timeIntervalSince(lastReaction) > 0.7 else { return }
        lastReaction = Date()
        run { c, _ in c.react(emoji) }
    }

    func leave() {
        timers.forEach { $0.cancel() }
        timers = []
        transport.onReceive = nil
        transport.onPlayersChanged = nil
        transport.disconnect()
    }

    // MARK: Plumbing

    private func received(_ data: Data, from sender: String) {
        guard let message = Message.decode(data) else { return }
        run { c, rng in c.receive(message, from: sender, using: &rng) }
    }

    private func playersChanged() {
        let before = client.others.count
        run { c, rng in c.playersChanged(others: transport.remotePlayers, hostID: transport.hostID, using: &rng) }
        if client.others.count > before, client.phase == .lobby { Feedback.shared.play(.join) }
        if client.phase == .lobby { transport.setLobbyOpen(true) }
    }

    private func run(_ body: (inout MatchClient, inout SystemRandomNumberGenerator) -> [MatchClient.Effect]) {
        var c = client
        var rng = SystemRandomNumberGenerator()
        let effects = body(&c, &rng)
        client = c
        perform(effects)
    }

    private func perform(_ effects: [MatchClient.Effect]) {
        for effect in effects {
            switch effect {
            case .send(let message):
                transport.send(message.encoded())
            case .schedule(let timer, let seconds):
                let task = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    guard !Task.isCancelled, let self else { return }
                    self.run { c, rng in c.timerFired(timer, using: &rng) }
                }
                timers.append(task)
                timers.removeAll { $0.isCancelled }
            case .cue(let cue):
                handle(cue)
            }
        }
    }

    private func handle(_ cue: MatchClient.Cue) {
        let fx = Feedback.shared
        switch cue {
        case .roundStarted(let countdown):
            countdownEndsAt = Date().addingTimeInterval(countdown)
            revealedAt = nil
            nextRoundAt = nil
            solvedFlash = false
        case .revealed:
            revealedAt = Date()
            fx.play(.go)
            fx.tap()
        case .slid:
            fx.play(.slide)
            fx.tap()
        case .bumped:
            fx.play(.bump)
            fx.bump()
        case .matchUp: fx.play(.match)
        case .matchDown: fx.play(.unmatch)
        case .solved:
            solvedFlash = true
            fx.success()
        case .roundWon, .matchWon:
            fx.play(.win)
            fx.success()
        case .roundLost, .matchLost:
            fx.play(.lose)
            fx.warning()
        case .roundOver(let nextIn):
            nextRoundAt = nextIn > 0 ? Date().addingTimeInterval(nextIn) : nil
        case .reaction(let from, let emoji):
            fx.play(.pop)
            let r = FloatingReaction(
                emoji: emoji,
                name: from == client.me.id ? "You" : client.name(of: from),
                color: color(for: from),
                x: CGFloat.random(in: 0.12...0.88)
            )
            reactions.append(r)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                self?.reactions.removeAll { $0.id == r.id }
            }
        }
    }
}
