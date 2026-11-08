import Foundation

/// Messages exchanged between devices during a multiplayer match. The same
/// messages travel over Game Center and over Nearby (peer-to-peer) play.
public struct PlayerInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Sent by the host to begin a round. Everyone gets the identical tray.
public struct RoundStart: Codable, Equatable, Sendable {
    public var roundId: Int
    public var round: Int
    public var bestOf: Int
    public var target: [Int]
    public var board: [Int]
    public var scores: [String: Int]
    /// Seconds of 3-2-1 countdown before the target is revealed.
    public var countdown: Double

    public init(roundId: Int, round: Int, bestOf: Int, target: [Int], board: [Int], scores: [String: Int], countdown: Double) {
        self.roundId = roundId
        self.round = round
        self.bestOf = bestOf
        self.target = target
        self.board = board
        self.scores = scores
        self.countdown = countdown
    }
}

/// Sent by the host when it has decided who won the round.
public struct RoundOver: Codable, Equatable, Sendable {
    public var roundId: Int
    public var winnerID: String
    public var ms: Int
    public var moves: Int
    public var scores: [String: Int]
    public var matchOver: Bool
    /// Seconds until the host deals the next round (0 when the match is over).
    public var nextIn: Double

    public init(roundId: Int, winnerID: String, ms: Int, moves: Int, scores: [String: Int], matchOver: Bool, nextIn: Double) {
        self.roundId = roundId
        self.winnerID = winnerID
        self.ms = ms
        self.moves = moves
        self.scores = scores
        self.matchOver = matchOver
        self.nextIn = nextIn
    }
}

public enum Message: Codable, Equatable, Sendable {
    /// Host -> all: start a round.
    case roundStart(RoundStart)
    /// Player -> all: my tray after a move (drives opponents' live mini boards).
    case progress(roundId: Int, board: [Int], moves: Int)
    /// Player -> host: I solved it. Includes every move so the host can replay and verify.
    case solved(roundId: Int, moves: [Int], ms: Int)
    /// Host -> all: round result.
    case roundOver(RoundOver)
    /// Host -> all: we're in the lobby (also carries the chosen match length).
    case lobby(bestOf: Int)
    /// Anyone -> all: an emoji reaction.
    case reaction(String)

    public func encoded() -> Data {
        // Encoding these plain value types cannot fail.
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public static func decode(_ data: Data) -> Message? {
        try? JSONDecoder().decode(Message.self, from: data)
    }
}
