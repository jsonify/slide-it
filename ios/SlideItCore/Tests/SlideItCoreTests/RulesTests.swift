import XCTest
@testable import SlideItCore

final class RulesTests: XCTestCase {
    private func board(_ s: String) -> Board {
        let map: [Character: TileColor] = ["R": .red, "O": .orange, "Y": .yellow, "G": .green, "B": .blue, "W": .white]
        return Board(colors: s.map { map[$0] })
    }

    func testTargetsUseAtMostFourOfEachColour() {
        var rng = SeededRandom(seed: 1)
        for _ in 0..<500 {
            let t = Rules.makeTarget(using: &rng)
            XCTAssertEqual(t.count, 9)
            for c in TileColor.allCases { XCTAssertLessThanOrEqual(t.filter { $0 == c }.count, 4) }
        }
    }

    func testScrambledBoardsAreValidAndNotGifts() {
        var rng = SeededRandom(seed: 2)
        for _ in 0..<300 {
            let t = Rules.makeTarget(using: &rng)
            let b = Board.scrambled(for: t, using: &rng)
            XCTAssertNotNil(Board(wire: b.wire))
            XCTAssertLessThanOrEqual(b.matches(t), 2)
            XCTAssertEqual(Set(b.cells.compactMap { $0?.id }).count, 24, "tile ids are unique")
        }
    }

    func testSlideSingleTile() {
        var b = board("RRRROOOOYYYYGGGGBBBBWWWW.")
        let moved = b.cells[23]!.id
        XCTAssertTrue(b.slide(23))
        XCTAssertEqual(b.gap, 23)
        XCTAssertEqual(b.cells[24]?.id, moved, "the same tile moved, so it animates")
    }

    func testSlidePushesWholeRowAndColumn() {
        var b = board("RRRROOOOYYYYGGGGBBBBWWWW.")
        XCTAssertTrue(b.slide(20))
        XCTAssertEqual(b.gap, 20)
        XCTAssertEqual(b.colors[21...24].map { $0 }, [.white, .white, .white, .white])

        var c = board(".RRROOOOYYYYGGGGBBBBWWWWR")
        XCTAssertTrue(c.slide(20))
        XCTAssertEqual(c.gap, 20)
        XCTAssertEqual(c.colors[0], .orange)
        XCTAssertNotNil(Board(wire: c.wire))
    }

    func testIllegalMoves() {
        var b = board("RRRROOOOYYYYGGGGBBBBWWWW.")
        let before = b
        XCTAssertFalse(b.slide(0))
        XCTAssertFalse(b.slide(24))
        XCTAssertFalse(b.slide(99))
        XCTAssertEqual(b, before)
        XCTAssertTrue(b.canSlide(4))
        XCTAssertFalse(b.canSlide(6))
    }

    func testSwipeDirections() {
        let b = board("RRRROOOOYYYY.GGGGBBBBWWWW") // gap at 12 (centre)
        XCTAssertEqual(b.tileMoving(.right), 11)
        XCTAssertEqual(b.tileMoving(.left), 13)
        XCTAssertEqual(b.tileMoving(.down), 7)
        XCTAssertEqual(b.tileMoving(.up), 17)
        let corner = board("RRRROOOOYYYYGGGGBBBBWWWW.")
        XCTAssertNil(corner.tileMoving(.left))
        XCTAssertNil(corner.tileMoving(.up))
    }

    func testSolvedLooksOnlyAtCentre() {
        let b = board("RRRROOOOYYYYGGGGBBBBWWWW.")
        let target = Rules.center.map { b.colors[$0]! }
        XCTAssertTrue(b.isSolved(target))
        var other = target
        other[0] = other[0] == .white ? .red : .white
        XCTAssertFalse(b.isSolved(other))
        XCTAssertEqual(b.matches(other), 8)
    }

    func testWireRoundTripAndValidation() {
        var rng = SeededRandom(seed: 3)
        let b = Board.scrambled(for: nil, using: &rng)
        XCTAssertEqual(Board(wire: b.wire)?.colors, b.colors)
        XCTAssertNil(Board(wire: Array(repeating: 0, count: 25)))
        XCTAssertNil(Board(wire: [1, 2, 3]))
        XCTAssertNil(Rules.target(fromWire: [9, 9, 9, 9, 9, 9, 9, 9, 9]))
    }
}
