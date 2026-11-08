import XCTest
@testable import SlideItCore

final class MatchEngineTests: XCTestCase {
    // Known position: the gap sits in the centre window. Tapping 14 pushes the
    // two greens left and solves it; [13, 12, 14] wiggles a tile first.
    //   R R R R O
    //   O O O Y Y
    //   Y Y . G G
    //   G G B B B
    //   B W W W W
    static let fixtureBoard: Board = {
        let map: [Character: TileColor] = ["R": .red, "O": .orange, "Y": .yellow, "G": .green, "B": .blue, "W": .white]
        return Board(colors: "RRRROOOOYYYY.GGGGBBBBWWWW".map { map[$0] })
    }()
    static let fixtureTarget: [TileColor] = [.orange, .orange, .yellow, .yellow, .green, .green, .green, .blue, .blue]
    static let fixturePath = [13, 12, 14]

    /// Start (or continue) the match with the fixture round.
    private func dealSolvable(_ engine: inout MatchEngine, rng: inout SeededRandom, start: Bool) -> (RoundStart, [Int]) {
        if start {
            _ = engine.startMatch(bestOf: engine.bestOf, using: &rng) // resets scores
        } else {
            _ = engine.nextRound(using: &rng)
        }
        let rs = engine.deal(target: Self.fixtureTarget, board: Self.fixtureBoard)
        return (rs, Self.fixturePath)
    }

    func testFullRoundFastestValidClaimWins() throws {
        var rng = SeededRandom(seed: 42)
        var engine = MatchEngine(players: ["a", "b", "c"], bestOf: 3)
        let rs = engine.startMatch(bestOf: 3, using: &rng)
        XCTAssertEqual(rs.round, 1)
        XCTAssertEqual(rs.board, engine.startBoard!.wire)
        XCTAssertEqual(engine.phase, .playing)

        // Junk claims are rejected.
        XCTAssertEqual(engine.claim(from: "a", roundId: rs.roundId, moves: [], ms: 1000), .rejected, "not solved")
        XCTAssertEqual(engine.claim(from: "zz", roundId: rs.roundId, moves: [], ms: 1), .rejected, "unknown player")
        XCTAssertEqual(engine.claim(from: "a", roundId: rs.roundId + 7, moves: [], ms: 1), .rejected, "wrong round")
        XCTAssertEqual(engine.phase, .playing)
    }

    func testAdjudicationPicksFastestAndScoresMatch() throws {
        var rng = SeededRandom(seed: 7)
        var engine = MatchEngine(players: ["host", "guest"], bestOf: 3)
        var round = 0
        var winsForGuest = 0
        while engine.phase != .matchOver {
            let (rs, path) = dealSolvable(&engine, rng: &rng, start: round == 0)
            round += 1
            // Host claims first but slower; guest's claim arrives later with a faster time.
            XCTAssertEqual(engine.claim(from: "host", roundId: rs.roundId, moves: path, ms: 9000), .first)
            XCTAssertEqual(engine.claim(from: "guest", roundId: rs.roundId, moves: path, ms: 8000), .accepted)
            XCTAssertEqual(engine.claim(from: "guest", roundId: rs.roundId, moves: path, ms: 1), .rejected, "one claim each")
            let over = try XCTUnwrap(engine.finalize())
            XCTAssertEqual(over.winnerID, "guest")
            XCTAssertEqual(over.moves, path.count)
            winsForGuest += 1
            XCTAssertEqual(over.scores["guest"], winsForGuest)
            XCTAssertEqual(over.matchOver, winsForGuest == 2)
            XCTAssertEqual(engine.claim(from: "host", roundId: rs.roundId, moves: path, ms: 1), .rejected, "round closed")
        }
        XCTAssertEqual(winsForGuest, 2, "best of 3 ends at 2 wins")
    }

    func testCheatingClaimRejected() {
        var rng = SeededRandom(seed: 11)
        var engine = MatchEngine(players: ["a", "b"])
        let (rs, path) = dealSolvable(&engine, rng: &rng, start: true)
        var bogus = path
        bogus.insert(engine.startBoard!.gap, at: 0) // tapping the gap is illegal
        XCTAssertEqual(engine.claim(from: "a", roundId: rs.roundId, moves: bogus, ms: 1), .rejected)
        XCTAssertEqual(engine.claim(from: "a", roundId: rs.roundId, moves: path, ms: 100), .first)
    }

    func testHostMigrationContinuesRoundNumbering() {
        var rng = SeededRandom(seed: 5)
        var engine = MatchEngine(players: ["b", "c"], bestOf: 5, scores: ["b": 2, "c": 1, "gone": 1], round: 4, roundId: 9)
        XCTAssertEqual(engine.scores, ["b": 2, "c": 1])
        let rs = engine.restartRound(using: &rng)
        XCTAssertEqual(rs.round, 4)
        XCTAssertEqual(rs.roundId, 10)
        XCTAssertEqual(rs.scores, ["b": 2, "c": 1])
    }

    func testRemovingOnlyClaimantReopensRound() {
        var rng = SeededRandom(seed: 13)
        var engine = MatchEngine(players: ["a", "b"])
        let (rs, path) = dealSolvable(&engine, rng: &rng, start: true)
        XCTAssertEqual(engine.claim(from: "a", roundId: rs.roundId, moves: path, ms: 100), .first)
        engine.removePlayer("a")
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertNil(engine.finalize())
        XCTAssertEqual(engine.claim(from: "b", roundId: rs.roundId, moves: path, ms: 200), .first)
        XCTAssertEqual(engine.finalize()?.winnerID, "b")
    }

    func testMessagesRoundTripThroughJSON() {
        let msgs: [Message] = [
            .roundStart(RoundStart(roundId: 1, round: 1, bestOf: 3, target: [0, 1, 2, 3, 4, 5, 0, 1, 2], board: Array(0..<25), scores: ["x": 1], countdown: 3)),
            .progress(roundId: 2, board: [1, 2], moves: 5),
            .solved(roundId: 2, moves: [1, 2, 3], ms: 12345),
            .roundOver(RoundOver(roundId: 2, winnerID: "x", ms: 1, moves: 2, scores: ["x": 2], matchOver: true, nextIn: 0)),
            .lobby(bestOf: 5),
            .reaction("🔥"),
        ]
        for m in msgs { XCTAssertEqual(Message.decode(m.encoded()), m) }
        XCTAssertNil(Message.decode(Data("nonsense".utf8)))
    }
}
