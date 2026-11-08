import XCTest
@testable import SlideItCore

/// A fake network of devices, each running its own MatchClient. Messages are
/// delivered instantly; timers run when the simulated clock is advanced.
private final class Network {
    var clients: [String: MatchClient] = [:]
    var connected: [String] = []
    var cues: [String: [MatchClient.Cue]] = [:]
    var sent: [(from: String, message: Message)] = []
    private var timers: [(owner: String, timer: MatchClient.Timer, at: Double)] = []
    private var now = 0.0
    private var rng = SeededRandom(seed: 99)

    init(players ids: [String], deal: (target: [TileColor], board: Board)? = MatchEngineTests.fixture) {
        connected = ids
        for id in ids {
            var c = MatchClient(me: PlayerInfo(id: id, name: id.uppercased()), others: ids.filter { $0 != id }.map { PlayerInfo(id: $0, name: $0.uppercased()) }, hostID: ids.min()!)
            c.fixedDeal = deal
            clients[id] = c
            cues[id] = []
        }
    }

    subscript(id: String) -> MatchClient { clients[id]! }

    func act(_ id: String, _ body: (inout MatchClient, inout SeededRandom) -> [MatchClient.Effect]) {
        var c = clients[id]!
        let fx = body(&c, &rng)
        clients[id] = c
        apply(id, fx)
    }

    private func apply(_ id: String, _ effects: [MatchClient.Effect]) {
        for e in effects {
            switch e {
            case .send(let m):
                sent.append((id, m))
                for other in connected where other != id {
                    act(other) { c, rng in c.receive(m, from: id, using: &rng) }
                }
            case .schedule(let t, let after):
                timers.append((id, t, now + after))
            case .cue(let cue):
                cues[id, default: []].append(cue)
            }
        }
    }

    func advance(_ seconds: Double) {
        let end = now + seconds
        while let next = timers.enumerated().filter({ $0.element.at <= end }).min(by: { $0.element.at < $1.element.at }) {
            timers.remove(at: next.offset)
            now = next.element.at
            guard connected.contains(next.element.owner) else { continue }
            act(next.element.owner) { c, rng in c.timerFired(next.element.timer, using: &rng) }
        }
        now = end
    }

    /// Simulate a device dropping out: everyone else sees the new roster and
    /// re-elects the host (lowest id, same rule as the Game Center transport).
    func disconnect(_ id: String) {
        connected.removeAll { $0 == id }
        for other in connected {
            let others = connected.filter { $0 != other }.map { PlayerInfo(id: $0, name: $0.uppercased()) }
            act(other) { c, rng in c.playersChanged(others: others, hostID: connected.min()!, using: &rng) }
        }
    }

    func solve(_ id: String, path: [Int] = MatchEngineTests.fixturePath, elapsedMs: Int) {
        for i in path { act(id) { c, _ in c.tap(i, elapsedMs: elapsedMs) } }
    }
}

extension MatchEngineTests {
    static var fixture: (target: [TileColor], board: Board) { (fixtureTarget, fixtureBoard) }
}

final class MatchClientTests: XCTestCase {
    func testLobbySettingsReachEveryone() {
        let net = Network(players: ["a", "b", "c"])
        XCTAssertTrue(net["a"].isHost)
        XCTAssertFalse(net["b"].canStart)
        net.act("b") { c, _ in c.setBestOf(5) } // not the host: ignored
        XCTAssertEqual(net["c"].bestOf, 3)
        net.act("a") { c, _ in c.setBestOf(5) }
        XCTAssertEqual(net["b"].bestOf, 5)
        XCTAssertEqual(net["c"].bestOf, 5)
    }

    func testCountdownHidesTargetThenEveryoneGetsSameRound() {
        let net = Network(players: ["a", "b"], deal: nil) // random deal
        net.act("a") { c, rng in c.start(using: &rng) }
        for id in ["a", "b"] {
            XCTAssertEqual(net[id].phase, .countdown)
            XCTAssertNil(net[id].target, "target hidden during countdown")
            XCTAssertFalse(net[id].canMove)
        }
        XCTAssertEqual(net["a"].board?.wire, net["b"].board?.wire, "identical starting trays")
        net.act("b") { c, _ in c.tap(0, elapsedMs: 0) }
        XCTAssertTrue(net["b"].moves.isEmpty, "can't move before GO")

        net.advance(MatchEngine.countdown)
        XCTAssertEqual(net["a"].phase, .playing)
        XCTAssertEqual(net["b"].phase, .playing)
        XCTAssertNotNil(net["a"].target)
        XCTAssertEqual(net["a"].target, net["b"].target)
        XCTAssertTrue(net.cues["b"]!.contains(.revealed))
    }

    func testOpponentsSeeLiveProgress() {
        let net = Network(players: ["a", "b"])
        net.act("a") { c, rng in c.start(using: &rng) }
        net.advance(3)
        net.act("b") { c, _ in c.tap(13, elapsedMs: 500) }
        XCTAssertEqual(net["a"].opponents["b"]?.moves, 1)
        XCTAssertEqual(net["a"].opponents["b"]?.board?.wire, net["b"].board?.wire)
        XCTAssertTrue(net.cues["b"]!.contains(.slid))
    }

    func testFullBestOfThreeMatch() throws {
        let net = Network(players: ["a", "b", "c"])
        net.act("a") { c, rng in c.start(using: &rng) }

        // Round 1: guest b wins.
        net.advance(3)
        net.solve("b", elapsedMs: 4000)
        XCTAssertFalse(net["b"].canMove, "locked after solving, waiting for the referee")
        net.advance(MatchEngine.claimWindow)
        for id in ["a", "b", "c"] {
            XCTAssertEqual(net[id].phase, .roundOver)
            XCTAssertEqual(net[id].result?.winnerID, "b")
            XCTAssertEqual(net[id].scores["b"], 1)
        }
        XCTAssertTrue(net.cues["b"]!.contains(.roundWon))
        XCTAssertTrue(net.cues["c"]!.contains(.roundLost))

        // Next round deals automatically.
        net.advance(MatchEngine.nextRoundDelay)
        XCTAssertEqual(net["c"].phase, .countdown)
        XCTAssertEqual(net["c"].round, 2)

        // Round 2: host a wins.
        net.advance(3)
        net.solve("a", elapsedMs: 3000)
        net.advance(MatchEngine.claimWindow)
        XCTAssertEqual(net["b"].scores, ["a": 1, "b": 1, "c": 0])

        // Round 3: b wins the match.
        net.advance(MatchEngine.nextRoundDelay + 3)
        net.solve("b", elapsedMs: 2500)
        net.advance(MatchEngine.claimWindow)
        for id in ["a", "b", "c"] { XCTAssertEqual(net[id].phase, .matchOver) }
        XCTAssertTrue(net.cues["b"]!.contains(.matchWon))
        XCTAssertTrue(net.cues["a"]!.contains(.matchLost))

        // Nothing else gets dealt until the host chooses.
        net.advance(30)
        XCTAssertEqual(net["c"].phase, .matchOver)

        // Rematch resets the scores.
        XCTAssertTrue(net["a"].canStart)
        net.act("a") { c, rng in c.start(using: &rng) }
        XCTAssertEqual(net["c"].phase, .countdown)
        XCTAssertEqual(net["c"].round, 1)
        XCTAssertEqual(net["c"].scores.values.reduce(0, +), 0)
    }

    func testFastestTimeBeatsFirstToArrive() {
        let net = Network(players: ["a", "b"])
        net.act("a") { c, rng in c.start(using: &rng) }
        net.advance(3)
        // The host's claim arrives first (no network delay) but b was faster on its own clock.
        net.solve("a", elapsedMs: 6000)
        net.solve("b", elapsedMs: 5800)
        net.advance(MatchEngine.claimWindow)
        XCTAssertEqual(net["a"].result?.winnerID, "b")
        XCTAssertEqual(net["b"].result?.ms, 5800)
    }

    func testBackToLobby() {
        let net = Network(players: ["a", "b"])
        net.act("a") { c, rng in c.setBestOf(1) + c.start(using: &rng) }
        net.advance(3)
        net.solve("b", elapsedMs: 1000)
        net.advance(1)
        XCTAssertEqual(net["b"].phase, .matchOver)
        net.act("b") { c, _ in c.backToLobby() } // only the host can
        XCTAssertEqual(net["b"].phase, .matchOver)
        net.act("a") { c, _ in c.backToLobby() }
        XCTAssertEqual(net["b"].phase, .lobby)
        XCTAssertNil(net["b"].board)
    }

    func testHostLeavingMidRoundHandsOverAndKeepsScores() {
        let net = Network(players: ["a", "b", "c"])
        net.act("a") { c, rng in c.start(using: &rng) }
        net.advance(3)
        net.solve("c", elapsedMs: 1000)
        net.advance(MatchEngine.claimWindow) // c: 1 point
        net.advance(MatchEngine.nextRoundDelay + 1) // round 2 under way (in countdown)
        let oldRoundId = net["b"].roundId

        net.disconnect("a")
        XCTAssertTrue(net["b"].isHost, "lowest remaining id takes over")
        XCTAssertGreaterThan(net["b"].roundId, oldRoundId, "new host re-deals")
        XCTAssertEqual(net["c"].phase, .countdown)
        XCTAssertEqual(net["c"].round, 2)
        XCTAssertEqual(net["c"].scores, ["b": 0, "c": 1])
        XCTAssertEqual(net["c"].players.count, 2)

        // And the new host referees correctly.
        net.advance(3)
        net.solve("c", elapsedMs: 900)
        net.advance(MatchEngine.claimWindow)
        XCTAssertEqual(net["b"].phase, .matchOver)
        XCTAssertEqual(net["b"].result?.winnerID, "c")
    }

    func testHostLeavingBetweenRoundsDealsNextRound() {
        let net = Network(players: ["a", "b", "c"])
        net.act("a") { c, rng in c.start(using: &rng) }
        net.advance(3)
        net.solve("b", elapsedMs: 1000)
        net.advance(MatchEngine.claimWindow)
        XCTAssertEqual(net["b"].phase, .roundOver)
        net.disconnect("a")
        XCTAssertEqual(net["c"].phase, .countdown)
        XCTAssertEqual(net["c"].round, 2)
    }

    func testEveryoneElseLeaving() {
        let net = Network(players: ["a", "b"])
        net.act("a") { c, rng in c.start(using: &rng) }
        net.disconnect("b")
        XCTAssertEqual(net["a"].phase, .ended("Everyone else left the game."))
        XCTAssertFalse(net["a"].canMove)
    }

    func testOnlyTheHostCanRunTheGame() {
        let net = Network(players: ["a", "b"])
        var rng = SeededRandom(seed: 1)
        // b pretends to be host.
        var b = net["b"]
        let fake = RoundStart(roundId: 50, round: 1, bestOf: 1, target: MatchEngineTests.fixtureTarget.map(\.rawValue), board: MatchEngineTests.fixtureBoard.wire, scores: [:], countdown: 3)
        net.act("a") { c, rng in c.receive(.roundStart(fake), from: "b", using: &rng) }
        XCTAssertEqual(net["a"].phase, .lobby)
        // b can't start either.
        XCTAssertTrue(b.start(using: &rng).isEmpty)
        // Junk reactions are dropped.
        net.act("a") { c, _ in c.react("💩") }
        XCTAssertTrue(net.sent.isEmpty)
        net.act("a") { c, _ in c.react("🔥") }
        XCTAssertTrue(net.cues["b"]!.contains(.reaction(from: "a", emoji: "🔥")))
    }

    func testFalseClaimFromCheaterIgnored() {
        let net = Network(players: ["a", "b"])
        net.act("a") { c, rng in c.start(using: &rng) }
        net.advance(3)
        let rid = net["a"].roundId
        net.act("a") { c, rng in c.receive(.solved(roundId: rid, moves: [], ms: 1), from: "b", using: &rng) }
        net.advance(1)
        XCTAssertEqual(net["a"].phase, .playing)
    }
}
