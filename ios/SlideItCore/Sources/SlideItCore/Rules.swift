// Game rules for Slide It. Mirrors public/game.js in the web version so both
// play identically.

/// The six tile colours. Four of each = 24 tiles on a 5x5 tray with one gap.
public enum TileColor: Int, CaseIterable, Codable, Sendable, Hashable {
    case red, orange, yellow, green, blue, white
}

/// A physical tile. The id is stable for the life of a board so the UI can
/// animate each tile as it slides.
public struct Tile: Identifiable, Hashable, Sendable {
    public let id: Int
    public let color: TileColor
}

/// Which way a tile moves when the player swipes.
public enum Direction: Sendable, CaseIterable {
    case up, down, left, right
}

public enum Rules {
    public static let size = 5
    public static let cellCount = size * size
    public static let perColor = 4
    /// Indices of the centre 3x3 window, row by row.
    public static let center = [6, 7, 8, 11, 12, 13, 16, 17, 18]

    /// The full set of 24 tiles.
    public static func pool() -> [TileColor] {
        TileColor.allCases.flatMap { Array(repeating: $0, count: perColor) }
    }

    /// A random 3x3 target, drawn from the real tile pool so it's always achievable.
    public static func makeTarget(using rng: inout some RandomNumberGenerator) -> [TileColor] {
        Array(pool().shuffled(using: &rng).prefix(9))
    }

    public static func makeTarget() -> [TileColor] {
        var rng = SystemRandomNumberGenerator()
        return makeTarget(using: &rng)
    }

    /// Wire format helpers: colours travel as their raw Int values.
    public static func target(fromWire wire: [Int]) -> [TileColor]? {
        let colors = wire.compactMap(TileColor.init(rawValue:))
        return colors.count == 9 && wire.count == 9 ? colors : nil
    }
}

public struct Board: Equatable, Sendable {
    public private(set) var cells: [Tile?]

    /// Build a board from colours (nil = the gap). Tiles get ids 0...23 in reading order.
    public init(colors: [TileColor?]) {
        var nextID = 0
        cells = colors.map { color in
            guard let color else { return nil }
            defer { nextID += 1 }
            return Tile(id: nextID, color: color)
        }
    }

    /// A scrambled tray where at most 2 of the centre cells already match the
    /// target, so nobody starts with a gift.
    public static func scrambled(for target: [TileColor]?, using rng: inout some RandomNumberGenerator) -> Board {
        let all: [TileColor?] = Rules.pool().map { Optional($0) } + [nil]
        for _ in 0..<200 {
            let board = Board(colors: all.shuffled(using: &rng))
            if let target, board.matches(target) > 2 { continue }
            return board
        }
        return Board(colors: all.shuffled(using: &rng))
    }

    public static func scrambled(for target: [TileColor]?) -> Board {
        var rng = SystemRandomNumberGenerator()
        return scrambled(for: target, using: &rng)
    }

    public var colors: [TileColor?] { cells.map { $0?.color } }

    public var gap: Int { cells.firstIndex(where: { $0 == nil }) ?? 0 }

    /// True if tapping `index` slides something: it's in the gap's row or column.
    public func canSlide(_ index: Int) -> Bool {
        guard (0..<Rules.cellCount).contains(index), index != gap else { return false }
        return index / Rules.size == gap / Rules.size || index % Rules.size == gap % Rules.size
    }

    /// Tap a tile in line with the gap: it and every tile between it and the gap
    /// shift one step towards the gap. Returns false (and changes nothing) if illegal.
    @discardableResult
    public mutating func slide(_ index: Int) -> Bool {
        guard canSlide(index) else { return false }
        let g = gap
        let sameRow = index / Rules.size == g / Rules.size
        let step = (sameRow ? 1 : Rules.size) * (index < g ? -1 : 1) // from the gap towards the tapped tile
        var p = g
        while p != index {
            cells[p] = cells[p + step]
            p += step
        }
        cells[index] = nil
        return true
    }

    /// The tile that a swipe in `direction` would move into the gap, if any.
    public func tileMoving(_ direction: Direction) -> Int? {
        let g = gap
        let col = g % Rules.size
        let row = g / Rules.size
        switch direction {
        case .right: return col > 0 ? g - 1 : nil
        case .left: return col < Rules.size - 1 ? g + 1 : nil
        case .down: return row > 0 ? g - Rules.size : nil
        case .up: return row < Rules.size - 1 ? g + Rules.size : nil
        }
    }

    /// Indices (on the 5x5 tray) of centre cells that currently match the target.
    public func matchedCells(_ target: [TileColor]) -> Set<Int> {
        var set = Set<Int>()
        for (k, i) in Rules.center.enumerated() where k < target.count && cells[i]?.color == target[k] {
            set.insert(i)
        }
        return set
    }

    public func matches(_ target: [TileColor]) -> Int { matchedCells(target).count }

    public func isSolved(_ target: [TileColor]) -> Bool { matches(target) == 9 }

    // MARK: Wire format

    /// 25 ints: colour raw values, -1 for the gap.
    public var wire: [Int] { cells.map { $0?.color.rawValue ?? -1 } }

    /// Decode and validate a board from the wire. Returns nil if malformed.
    public init?(wire: [Int]) {
        guard wire.count == Rules.cellCount, wire.filter({ $0 == -1 }).count == 1 else { return nil }
        var colors: [TileColor?] = []
        for value in wire {
            if value == -1 { colors.append(nil); continue }
            guard let c = TileColor(rawValue: value) else { return nil }
            colors.append(c)
        }
        for c in TileColor.allCases where colors.filter({ $0 == c }).count != Rules.perColor { return nil }
        self.init(colors: colors)
    }
}

/// Small deterministic RNG (SplitMix64) for tests and reproducible deals.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
