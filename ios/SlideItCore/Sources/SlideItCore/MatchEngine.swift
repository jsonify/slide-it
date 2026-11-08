/// The referee, run only on the host device. It deals rounds, verifies
/// "I solved it!" claims by replaying the claimed moves, and keeps score.
///
/// There's no server: one player's device is the host. To stay fair despite
/// network lag, the host doesn't simply take the first claim it hears. It
/// waits a short window after the first claim and then awards the round to
/// the fastest time, measured on each player's own device from the moment
/// their target appeared.
public struct MatchEngine: Sendable {
    public enum Phase: Equatable, Sendable {
        case lobby, playing, adjudicating, roundOver, matchOver
    }

    public enum ClaimResult: Equatable, Sendable {
        /// Invalid, late, or for a different round: ignored.
        case rejected
        /// First valid claim: the caller should call `finalize()` after `claimWindow`.
        case first
        /// Valid claim during an open adjudication window.
        case accepted
    }

    public static let countdown: Double = 3
    public static let nextRoundDelay: Double = 4.5
    public static let claimWindow: Double = 0.35

    public private(set) var players: [String]
    public private(set) var scores: [String: Int]
    public private(set) var bestOf: Int
    public private(set) var round: Int
    public private(set) var roundId: Int
    public private(set) var phase: Phase = .lobby
    public private(set) var target: [TileColor] = []
    public private(set) var startBoard: Board?
    private var claims: [(player: String, moves: Int, ms: Int)] = []
    /// Tests only: deal this position every round instead of a random one.
    var fixedDeal: (target: [TileColor], board: Board)?

    public var winsNeeded: Int { bestOf / 2 + 1 }

    /// `roundId` lets a new host (after the old one drops out) continue numbering
    /// so stale messages from the previous round are ignored.
    public init(players: [String], bestOf: Int = 3, scores: [String: Int] = [:], round: Int = 0, roundId: Int = 0) {
        self.players = players
        self.bestOf = bestOf
        self.round = round
        self.roundId = roundId
        self.scores = Dictionary(uniqueKeysWithValues: players.map { ($0, scores[$0] ?? 0) })
    }

    public mutating func startMatch(bestOf: Int, using rng: inout some RandomNumberGenerator) -> RoundStart {
        self.bestOf = max(1, bestOf)
        scores = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
        round = 0
        return nextRound(using: &rng)
    }

    public mutating func nextRound(using rng: inout some RandomNumberGenerator) -> RoundStart {
        round += 1
        return deal(using: &rng)
    }

    /// Re-deal the current round (used when the host changes mid-round).
    public mutating func restartRound(using rng: inout some RandomNumberGenerator) -> RoundStart {
        if round == 0 { round = 1 }
        return deal(using: &rng)
    }

    private mutating func deal(using rng: inout some RandomNumberGenerator) -> RoundStart {
        if let fixedDeal { return deal(target: fixedDeal.target, board: fixedDeal.board) }
        let target = Rules.makeTarget(using: &rng)
        return deal(target: target, board: Board.scrambled(for: target, using: &rng))
    }

    /// Deal a specific round (internal so tests can use known positions).
    mutating func deal(target: [TileColor], board: Board) -> RoundStart {
        if round == 0 { round = 1 }
        roundId += 1
        self.target = target
        startBoard = board
        claims = []
        phase = .playing
        return RoundStart(
            roundId: roundId, round: round, bestOf: bestOf,
            target: target.map(\.rawValue), board: board.wire,
            scores: scores, countdown: Self.countdown
        )
    }

    public mutating func claim(from player: String, roundId: Int, moves: [Int], ms: Int) -> ClaimResult {
        guard phase == .playing || phase == .adjudicating,
              roundId == self.roundId,
              players.contains(player),
              !claims.contains(where: { $0.player == player }),
              var board = startBoard
        else { return .rejected }
        // Replay every move from the shared starting tray: each must be legal and
        // the result must actually match the target.
        for index in moves where !board.slide(index) { return .rejected }
        guard board.isSolved(target) else { return .rejected }

        claims.append((player, moves.count, max(0, ms)))
        if phase == .playing {
            phase = .adjudicating
            return .first
        }
        return .accepted
    }

    /// Close the adjudication window and award the round to the fastest valid claim.
    public mutating func finalize() -> RoundOver? {
        guard phase == .adjudicating, !claims.isEmpty else { return nil }
        // min(by:) keeps the earliest-arriving claim on an exact tie.
        let best = claims.enumerated().min { a, b in
            a.element.ms != b.element.ms ? a.element.ms < b.element.ms : a.offset < b.offset
        }!.element
        scores[best.player, default: 0] += 1
        let matchOver = scores[best.player, default: 0] >= winsNeeded
        phase = matchOver ? .matchOver : .roundOver
        return RoundOver(
            roundId: roundId, winnerID: best.player, ms: best.ms, moves: best.moves,
            scores: scores, matchOver: matchOver, nextIn: matchOver ? 0 : Self.nextRoundDelay
        )
    }

    public mutating func removePlayer(_ id: String) {
        players.removeAll { $0 == id }
        scores[id] = nil
        claims.removeAll { $0.player == id }
        if phase == .adjudicating && claims.isEmpty { phase = .playing }
    }

    public mutating func toLobby() {
        phase = .lobby
        claims = []
    }
}
