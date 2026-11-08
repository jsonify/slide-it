import SwiftUI
import UIKit

/// One coloured tile with a chunky, bevelled look and a shape for accessibility.
struct TileView: View {
    let color: TileColor
    var matched = false

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            let shape = RoundedRectangle(cornerRadius: s * 0.2, style: .continuous)
            ZStack {
                shape.fill(
                    color.color
                        .shadow(.inner(color: .black.opacity(0.18), radius: 0, x: 0, y: -s * 0.07))
                        .shadow(.inner(color: .white.opacity(0.45), radius: 0, x: 0, y: s * 0.035))
                )
                Image(systemName: color.symbol)
                    .font(.system(size: s * 0.36, weight: .black))
                    .foregroundStyle(.black.opacity(0.3))
                    .offset(y: -s * 0.02)
            }
            .shadow(color: .black.opacity(0.35), radius: s * 0.03, x: 0, y: s * 0.03)
            .overlay {
                if matched {
                    shape.stroke(.white.opacity(0.9), lineWidth: max(2, s * 0.05))
                        .shadow(color: .white.opacity(0.5), radius: s * 0.08)
                        .transition(.scale(scale: 1.15).combined(with: .opacity))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The 5x5 tray. Tiles keep their identity, so every slide animates.
struct TrayView: View {
    let board: Board
    let target: [TileColor]?
    var enabled: Bool
    var solved = false
    var onTap: (Int) -> Void = { _ in }
    var onSwipe: (Direction) -> Void = { _ in }

    // Geometry as fractions of the tray side: 3.2% padding, 16.8% tiles, 2.4% gaps.
    private static let pad = 0.032, tile = 0.168, gap = 0.024, pitch = 0.192

    private struct Placed: Identifiable {
        let id: Int
        let index: Int
        let color: TileColor
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let matched = target.map { board.matchedCells($0) } ?? []
            let placed: [Placed] = board.cells.enumerated().compactMap { (i, t) -> Placed? in
                guard let t else { return nil }
                return Placed(id: t.id, index: i, color: t.color)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: side * 0.07, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2560), Color(hex: 0x1A163A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.07, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 18)

                // The centre 3x3 window that has to match the target.
                RoundedRectangle(cornerRadius: side * 0.05, style: .continuous)
                    .strokeBorder(
                        solved ? Theme.accent : Theme.accent.opacity(0.55),
                        style: StrokeStyle(lineWidth: max(2, side * 0.007), dash: solved ? [] : [side * 0.02, side * 0.014])
                    )
                    .frame(width: side * 0.576, height: side * 0.576)
                    .offset(x: side * 0.212, y: side * 0.212)
                    .shadow(color: solved ? Theme.accent.opacity(0.7) : .clear, radius: 20)

                ForEach(placed) { p in
                    TileView(color: p.color, matched: matched.contains(p.index))
                        .frame(width: side * Self.tile, height: side * Self.tile)
                        .offset(
                            x: side * (Self.pad + Double(p.index % Rules.size) * Self.pitch),
                            y: side * (Self.pad + Double(p.index / Rules.size) * Self.pitch)
                        )
                }

                TouchSurface(
                    enabled: enabled,
                    onBegin: { point in
                        let i = Self.cell(at: point, side: side)
                        guard board.canSlide(i) else { return false }
                        onTap(i)
                        return true
                    },
                    onSwipe: onSwipe
                )
                .frame(width: side, height: side)
            }
            .frame(width: side, height: side)
            .saturation(enabled || solved ? 1 : 0.85)
            .animation(.spring(response: 0.16, dampingFraction: 0.86), value: board)
            .animation(.easeOut(duration: 0.2), value: matched)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your tray")
    }

    static func cell(at point: CGPoint, side: CGFloat) -> Int {
        func idx(_ v: CGFloat) -> Int { min(4, max(0, Int(((v / side) - 0.02) / pitch))) }
        return idx(point.y) * Rules.size + idx(point.x)
    }
}

/// UIKit touch handling: reacts on touch-down (no tap delay), supports swipes,
/// and lets two players use two trays at the same time (Face-off mode).
struct TouchSurface: UIViewRepresentable {
    var enabled: Bool
    /// Return true if the touch was used as a tap; false starts swipe tracking.
    var onBegin: (CGPoint) -> Bool
    var onSwipe: (Direction) -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true
        return v
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.enabled = enabled
        view.onBegin = onBegin
        view.onSwipe = onSwipe
    }

    final class TouchView: UIView {
        var enabled = false
        var onBegin: (CGPoint) -> Bool = { _ in false }
        var onSwipe: (Direction) -> Void = { _ in }
        private var swipeStarts: [ObjectIdentifier: CGPoint] = [:]

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled else { return }
            for t in touches {
                let p = t.location(in: self)
                if !onBegin(p) { swipeStarts[ObjectIdentifier(t)] = p }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled else { return }
            let threshold = max(16, bounds.width * 0.05)
            for t in touches {
                let key = ObjectIdentifier(t)
                guard let start = swipeStarts[key] else { continue }
                let p = t.location(in: self)
                let dx = p.x - start.x, dy = p.y - start.y
                guard abs(dx) >= threshold || abs(dy) >= threshold else { continue }
                // Keep tracking from here so one long drag can push several tiles.
                swipeStarts[key] = p
                onSwipe(abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up))
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { swipeStarts[ObjectIdentifier(t)] = nil }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { swipeStarts[ObjectIdentifier(t)] = nil }
        }
    }
}

/// The 3x3 target pattern.
struct TargetView: View {
    let target: [TileColor]?
    var tileSize: CGFloat = 28

    var body: some View {
        let cols = Array(repeating: GridItem(.fixed(tileSize), spacing: tileSize * 0.16), count: 3)
        LazyVGrid(columns: cols, spacing: tileSize * 0.16) {
            ForEach(0..<9, id: \.self) { i in
                if let target {
                    TileView(color: target[i])
                        .frame(width: tileSize, height: tileSize)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: tileSize * 0.2, style: .continuous)
                        .fill(Theme.panel2)
                        .overlay(Text("?").font(Theme.display(tileSize * 0.5)).foregroundStyle(Theme.muted))
                        .frame(width: tileSize, height: tileSize)
                }
            }
        }
        .frame(width: tileSize * 3 + tileSize * 0.32)
        .padding(tileSize * 0.22)
        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: tileSize * 0.4, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: target)
    }
}

/// A small read-only 5x5 board for opponents.
struct MiniBoard: View {
    let wire: [Int]?
    let target: [TileColor]?
    var size: CGFloat = 50

    var body: some View {
        let cell = (size - 4 - 6) / 5
        let board = wire.flatMap { Board(wire: $0) }
        let matched = target.flatMap { t in board.map { $0.matchedCells(t) } } ?? []
        VStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { r in
                HStack(spacing: 1.5) {
                    ForEach(0..<5, id: \.self) { c in
                        let i = r * 5 + c
                        RoundedRectangle(cornerRadius: 2)
                            .fill(board?.cells[i]?.color.color ?? .clear)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white, lineWidth: matched.contains(i) ? 1 : 0))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .padding(2)
        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 6))
    }
}
