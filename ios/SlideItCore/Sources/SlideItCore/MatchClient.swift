/// Everything one device knows about a multiplayer match, as a pure state
/// machine. The app feeds it inputs (taps, network messages, timers firing,
/// players joining/leaving) and carries out the effects it returns (send this
/// message, start that timer, play this sound).
///
/// Keeping this free of GameKit/UIKit means whole matches — including the host
/// dropping out mid-round — can be simulated in unit tests.
public struct MatchClient: Sendable {
    public enum Phase: Equatable, Sendable {
        case lobby, countdown, playing, roundOver, matchOver
        /// The match can't continue (e.g. everyone else left).
        case ended(String)
    }

    public struct Opponent: Equatable, Sendable {
        public var board: Board?
        public var moves: Int
    }

    public enum Timer: Equatable, Sendable {
        case reveal(roundId: Int)
        case finalize(roundId: Int)
        case nextRound(roundId: Int)
    }

    /// Moments the UI should react to with sound / haptics / animation.
    public enum Cue: Equatable, Sendable {
        case roundStarted(countdown: Double)
        case revealed
        case slid
        case bumped
        case matchUp
        case matchDown
        case solved
        case roundWon, roundLost, matchWon, matchLost
        case roundOver(nextIn: Double)
        case reaction(from: String, emoji: String)
    }

    public enum Effect: Equatable, Sendable {
        /// Send to every other device.
        case send(Message)
        /// Call `timerFired` after this many seconds.
        case schedule(Timer, after: Double)
        case cue(Cue)
    }

    public static let allowedReactions = ["👏", "🔥", "😱", "😂", "😤", "🐢"]

    public let me: PlayerInfo
    public private(set) var others: [PlayerInfo]
    public private(set) var hostID: String
    public private(set) var phase: Phase = .lobby
    public private(set) var bestOf = 3
    public private(set) var round = 0
    public private(set) var roundId = 0
    /// nil until the countdown finishes.
    public private(set) var target: [TileColor]?
    public private(set) var board: Board?
    public private(set) var moves: [Int] = []
    public private(set) var opponents: [String: Opponent] = [:]
    public private(set) var scores: [String: Int] = [:]
    public private(set) var result: RoundOver?
    public private(set) var claimSent = false
    private var hiddenTarget: [TileColor] = []
    /// Host-only messages that arrived from someone who isn't (yet) our host.
    /// When the host drops out, the new host's first message can arrive before
    /// we've noticed the old one left; we replay these once the roster updates.
    private var deferred: [(message: Message, from: String)] = []
    private var engine: MatchEngine?
    /// Tests only: deal this position every round instead of a random one.
    var fixedDeal: (target: [TileColor], board: Board)?

    public init(me: PlayerInfo, others: [PlayerInfo], hostID: String) {
        self.me = me
        self.others = others
        self.hostID = hostID
    }

    // MARK: Derived

    public var isHost: Bool { hostID == me.id }
    public var winsNeeded: Int { bestOf / 2 + 1 }
    public var players: [PlayerInfo] { [me] + others }
    public var canMove: Bool { phase == .playing && board != nil && !claimSent }
    public var canStart: Bool { isHost && !others.isEmpty && (phase == .lobby || phase == .matchOver) }
    public func name(of id: String) -> String { players.first { $0.id == id }?.name ?? "Someone" }

    // MARK: Host actions

    public mutating func setBestOf(_ n: Int) -> [Effect] {
        guard isHost, phase == .lobby, [1, 3, 5, 7].contains(n) else { return [] }
        return broadcast(.lobby(bestOf: n))
    }

    public mutating func start(using rng: inout some RandomNumberGenerator) -> [Effect] {
        guard canStart else { return [] }
        var engine = MatchEngine(players: players.map(\.id), bestOf: bestOf, roundId: roundId)
        engine.fixedDeal = fixedDeal
        let rs = engine.startMatch(bestOf: bestOf, using: &rng)
        self.engine = engine
        return broadcast(.roundStart(rs))
    }

    public mutating func backToLobby() -> [Effect] {
        guard isHost, phase == .matchOver else { return [] }
        engine = nil
        return broadcast(.lobby(bestOf: bestOf))
    }

    // MARK: Player actions

    /// Tap tray cell `index`. `elapsedMs` = time since this device revealed the target.
    public mutating func tap(_ index: Int, elapsedMs: Int) -> [Effect] {
        guard canMove, var b = board, let target else { return [] }
        let before = b.matches(target)
        guard b.slide(index) else { return [.cue(.bumped)] }
        board = b
        moves.append(index)
        var fx: [Effect] = [.cue(.slid), .send(.progress(roundId: roundId, board: b.wire, moves: moves.count))]
        let after = b.matches(target)
        if after > before { fx.append(.cue(.matchUp)) }
        if after < before { fx.append(.cue(.matchDown)) }
        if b.isSolved(target) {
            claimSent = true
            fx.append(.cue(.solved))
            fx += broadcast(.solved(roundId: roundId, moves: moves, ms: elapsedMs))
        }
        return fx
    }

    public mutating func swipe(_ direction: Direction, elapsedMs: Int) -> [Effect] {
        guard canMove, let b = board else { return [] }
        guard let index = b.tileMoving(direction) else { return [.cue(.bumped)] }
        return tap(index, elapsedMs: elapsedMs)
    }

    public mutating func react(_ emoji: String) -> [Effect] {
        guard Self.allowedReactions.contains(emoji) else { return [] }
        return broadcast(.reaction(emoji))
    }

    // MARK: Network

    public mutating func receive(_ message: Message, from sender: String, using rng: inout some RandomNumberGenerator) -> [Effect] {
        switch message {
        case .roundStart(let rs):
            if sender != hostID { return deferUntilHostChanges(message, from: sender) }
            guard rs.roundId > roundId || phase == .lobby || phase == .matchOver,
                  let target = Rules.target(fromWire: rs.target), let board = Board(wire: rs.board)
            else { return [] }
            roundId = rs.roundId
            round = rs.round
            bestOf = rs.bestOf
            scores = rs.scores
            hiddenTarget = target
            self.target = nil
            self.board = board
            moves = []
            claimSent = false
            result = nil
            opponents = Dictionary(uniqueKeysWithValues: others.map { ($0.id, Opponent(board: board, moves: 0)) })
            phase = .countdown
            return [.cue(.roundStarted(countdown: rs.countdown)), .schedule(.reveal(roundId: rs.roundId), after: rs.countdown)]

        case .progress(let rid, let wire, let count):
            guard sender != me.id, rid == roundId, let b = Board(wire: wire) else { return [] }
            opponents[sender] = Opponent(board: b, moves: count)
            return []

        case .solved(let rid, let claimed, let ms):
            guard isHost, var engine else { return [] }
            let res = engine.claim(from: sender, roundId: rid, moves: claimed, ms: ms)
            self.engine = engine
            return res == .first ? [.schedule(.finalize(roundId: rid), after: MatchEngine.claimWindow)] : []

        case .roundOver(let ro):
            if sender != hostID { return deferUntilHostChanges(message, from: sender) }
            guard ro.roundId == roundId, phase == .playing || phase == .countdown else { return [] }
            result = ro
            scores = ro.scores
            phase = ro.matchOver ? .matchOver : .roundOver
            let won = ro.winnerID == me.id
            let cue: Cue = ro.matchOver ? (won ? .matchWon : .matchLost) : (won ? .roundWon : .roundLost)
            return [.cue(cue), .cue(.roundOver(nextIn: ro.nextIn))]

        case .lobby(let n):
            if sender != hostID { return deferUntilHostChanges(message, from: sender) }
            bestOf = n
            if phase != .lobby {
                phase = .lobby
                target = nil
                board = nil
                result = nil
                opponents = [:]
            }
            return []

        case .reaction(let emoji):
            guard Self.allowedReactions.contains(emoji) else { return [] }
            return [.cue(.reaction(from: sender, emoji: emoji))]
        }
    }

    // MARK: Timers

    public mutating func timerFired(_ timer: Timer, using rng: inout some RandomNumberGenerator) -> [Effect] {
        switch timer {
        case .reveal(let rid):
            guard rid == roundId, phase == .countdown else { return [] }
            phase = .playing
            target = hiddenTarget
            return [.cue(.revealed)]

        case .finalize(let rid):
            guard isHost, var engine, engine.roundId == rid, let ro = engine.finalize() else { return [] }
            self.engine = engine
            var fx = broadcast(.roundOver(ro))
            if !ro.matchOver { fx.append(.schedule(.nextRound(roundId: rid), after: ro.nextIn)) }
            return fx

        case .nextRound(let rid):
            guard isHost, var engine, engine.roundId == rid, engine.phase == .roundOver else { return [] }
            let rs = engine.nextRound(using: &rng)
            self.engine = engine
            return broadcast(.roundStart(rs))
        }
    }

    // MARK: Players joining / leaving

    public mutating func playersChanged(others newOthers: [PlayerInfo], hostID newHost: String, using rng: inout some RandomNumberGenerator) -> [Effect] {
        let departed = Set(others.map(\.id)).subtracting(newOthers.map(\.id))
        others = newOthers
        hostID = newHost
        for id in departed {
            opponents[id] = nil
            scores[id] = nil
            engine?.removePlayer(id)
        }
        let replay = deferred.filter { $0.from == newHost && newHost != me.id }
        deferred = []

        if newOthers.isEmpty {
            if phase != .lobby { phase = .ended("Everyone else left the game.") }
            engine = nil
            return []
        }
        if case .ended = phase { return [] }
        guard isHost else {
            var fx: [Effect] = []
            for d in replay { fx += receive(d.message, from: d.from, using: &rng) }
            return fx
        }

        switch phase {
        case .lobby:
            // Tell anyone new what match length we're on.
            return broadcast(.lobby(bestOf: bestOf))
        case .countdown, .playing, .roundOver:
            if engine == nil {
                // The host left mid-match and we've taken over: re-deal this round.
                var e = MatchEngine(players: players.map(\.id), bestOf: bestOf, scores: scores, round: round, roundId: roundId)
                e.fixedDeal = fixedDeal
                // Mid-round: replay this round. Between rounds: deal the next one.
                let rs = phase == .roundOver ? e.nextRound(using: &rng) : e.restartRound(using: &rng)
                engine = e
                return broadcast(.roundStart(rs))
            }
            return []
        case .matchOver:
            if engine == nil {
                engine = MatchEngine(players: players.map(\.id), bestOf: bestOf, scores: scores, round: round, roundId: roundId)
                engine?.fixedDeal = fixedDeal
            }
            return []
        case .ended:
            return []
        }
    }

    // MARK: Helpers

    private mutating func deferUntilHostChanges(_ message: Message, from sender: String) -> [Effect] {
        guard sender != me.id, others.contains(where: { $0.id == sender }) else { return [] }
        deferred.append((message, sender))
        if deferred.count > 8 { deferred.removeFirst() }
        return []
    }

    /// Send to everyone else AND apply locally, so the host's own messages go
    /// through exactly the same path as everyone else's.
    private mutating func broadcast(_ message: Message) -> [Effect] {
        var never = SeededRandom(seed: 0) // local delivery of these messages never deals
        return [.send(message)] + receive(message, from: me.id, using: &never)
    }
}
