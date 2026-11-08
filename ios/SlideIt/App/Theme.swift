import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {
    static let bg = Color(hex: 0x14112B)
    static let bgTop = Color(hex: 0x2A2366)
    static let bg2 = Color(hex: 0x1D1940)
    static let panel = Color(hex: 0x241F4D)
    static let panel2 = Color(hex: 0x2E2860)
    static let line = Color.white.opacity(0.09)
    static let text = Color(hex: 0xF4F2FF)
    static let muted = Color(hex: 0xA49FCC)
    static let accent = Color(hex: 0xFFD23D)
    static let accent2 = Color(hex: 0xFF5D73)
    static let good = Color(hex: 0x2ED39A)
    static let avatars: [Color] = [0xFF5D73, 0x3FA7FF, 0xFFB52E, 0x2ED39A, 0xB46BFF, 0xFF8A3D].map { Color(hex: $0) }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension TileColor {
    var color: Color {
        switch self {
        case .red: Color(hex: 0xFF4D5E)
        case .orange: Color(hex: 0xFF9A2E)
        case .yellow: Color(hex: 0xFFD93D)
        case .green: Color(hex: 0x2FD27A)
        case .blue: Color(hex: 0x3D8BFF)
        case .white: Color(hex: 0xEEF0F7)
        }
    }

    /// Every colour also has a shape, so the game works for colour-blind players.
    var symbol: String {
        switch self {
        case .red: "circle.fill"
        case .orange: "triangle.fill"
        case .yellow: "star.fill"
        case .green: "square.fill"
        case .blue: "diamond.fill"
        case .white: "plus"
        }
    }
}

/// The app's dark background, used behind every screen.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.bgTop, Theme.bg.opacity(0)], center: .top, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

/// Rounded "card" panel used throughout.
struct Panel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}

/// Chunky game button with a pressed-down effect.
struct GameButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .primary
    var big = false

    private var fill: AnyShapeStyle {
        switch kind {
        case .primary: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFE066), Color(hex: 0xFFBF1F)], startPoint: .top, endPoint: .bottom))
        case .secondary: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF7D8F), Color(hex: 0xFF4D64)], startPoint: .top, endPoint: .bottom))
        case .ghost: AnyShapeStyle(Theme.panel)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Color(hex: 0x2A1D00)
        case .secondary: .white
        case .ghost: Theme.text
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(big ? Theme.display(20) : .system(size: 17, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, big ? 18 : 14)
            .padding(.horizontal, 16)
            .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(kind == .ghost ? Theme.line : .clear))
            .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 42, height: 42)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
        }
        .buttonStyle(.plain)
    }
}

struct Avatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 34
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(Theme.display(size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct Pips: View {
    let total: Int
    let filled: Int
    var size: CGFloat = 7
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                Circle()
                    .fill(i < filled ? Theme.accent : Color.white.opacity(0.14))
                    .frame(width: size, height: size)
                    .shadow(color: i < filled ? Theme.accent : .clear, radius: 3)
            }
        }
    }
}

func formatTime(_ ms: Int) -> String {
    String(format: "%.1f", Double(max(0, ms)) / 1000)
}
