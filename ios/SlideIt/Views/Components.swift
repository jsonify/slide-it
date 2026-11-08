import SwiftUI

/// Small labelled number in the top bar.
struct StatPill: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(Theme.display(19))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .frame(minWidth: 60)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    }
}

/// Live race timer: counts up from `start`, or shows a frozen final time.
struct TimerText: View {
    let start: Date?
    let finalMs: Int?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            StatPill(label: "Time", value: formatTime(milliseconds(at: context.date)))
        }
    }

    private func milliseconds(at date: Date) -> Int {
        if let finalMs { return finalMs }
        guard let start else { return 0 }
        return Int(date.timeIntervalSince(start) * 1000)
    }
}

/// Top bar shared by every game screen.
struct GameBar<Stats: View>: View {
    let onClose: () -> Void
    @ViewBuilder var stats: Stats
    @AppStorage(Feedback.soundKey) private var soundOn = true

    var body: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "xmark", action: onClose)
            Spacer(minLength: 0)
            HStack(spacing: 6) { stats }
            Spacer(minLength: 0)
            IconButton(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill") { soundOn.toggle() }
        }
    }
}

/// Big 3-2-1 over the screen while a round is about to start.
struct CountdownOverlay: View {
    let endsAt: Date
    var label: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let left = Int(ceil(endsAt.timeIntervalSince(context.date)))
            ZStack {
                Theme.bg.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 0) {
                    if let label {
                        Text(label).font(Theme.display(26)).foregroundStyle(Theme.text)
                    }
                    Text(left > 0 ? "\(left)" : "GO!")
                        .font(Theme.display(160))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: .black.opacity(0.3), radius: 0, y: 10)
                        .id(left)
                        .transition(.asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.3), value: left)
            .onChange(of: left, initial: true) { _, newValue in
                if newValue > 0 { Feedback.shared.play(.beep); Feedback.shared.tap() }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The row of emoji reaction buttons.
struct ReactionBar: View {
    let onReact: (String) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(MatchClient.allowedReactions, id: \.self) { emoji in
                Button { onReact(emoji) } label: {
                    Text(emoji)
                        .font(.system(size: 22))
                        .frame(width: 46, height: 42)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Emoji reactions drifting up the screen.
struct FloatingReactions: View {
    let reactions: [OnlineSession.FloatingReaction]
    var body: some View {
        GeometryReader { geo in
            ForEach(reactions) { r in
                FloatingReactionView(reaction: r)
                    .position(x: geo.size.width * r.x, y: geo.size.height - 90)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FloatingReactionView: View {
    let reaction: OnlineSession.FloatingReaction
    @State private var up = false
    var body: some View {
        VStack(spacing: 2) {
            Text(reaction.emoji).font(.system(size: 44))
            Text(reaction.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(reaction.color, in: Capsule())
        }
        .offset(y: up ? -260 : 20)
        .opacity(up ? 0 : 1)
        .scaleEffect(up ? 1 : 0.5)
        .onAppear { withAnimation(.easeOut(duration: 2.2)) { up = true } }
    }
}

/// Confetti burst, drawn with Canvas. Positions are computed from elapsed time
/// so there's no per-particle state to update.
struct ConfettiView: View {
    let count: Int
    @State private var start = Date()
    @State private var particles: [Particle] = []

    struct Particle {
        let vx, vy, size, spin, rot0: Double
        let color: Color
    }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSince(start)
                guard t < 3.5 else { return }
                for p in particles {
                    let x = size.width / 2 + p.vx * t * 60
                    let y = size.height * 0.45 + (p.vy * t + 0.5 * 27 * t * t) * 60
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.rot0 + p.spin * t))
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 3, width: p.size, height: p.size * 0.66)), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            start = Date()
            let colors = TileColor.allCases.map(\.color)
            particles = (0..<count).map { _ in
                Particle(
                    vx: .random(in: -8...8), vy: .random(in: -16 ... -6), size: .random(in: 6...13),
                    spin: .random(in: -12...12), rot0: .random(in: 0...6), color: colors.randomElement()!
                )
            }
        }
    }
}

/// One line of a results scoreboard.
struct ScoreRow: Identifiable {
    let id: String
    let name: String
    let color: Color
    let score: Int
    let highlight: Bool
}

/// Modal card for round / match results.
struct ResultCard<Actions: View>: View {
    let emoji: String
    let title: String
    let subtitle: String
    var rows: [ScoreRow] = []
    var winsNeeded = 0
    var hint: String?
    var hintUntil: Date?
    @ViewBuilder var actions: Actions

    var body: some View {
        ZStack {
            Color(hex: 0x0A0819, opacity: 0.66).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(emoji).font(.system(size: 64))
                Text(title)
                    .font(Theme.display(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if !rows.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(rows) { row in
                            HStack(spacing: 10) {
                                Avatar(name: row.name, color: row.color)
                                Text(row.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                                Spacer()
                                Pips(total: winsNeeded, filled: row.score)
                                Text("\(row.score)").font(Theme.display(22)).foregroundStyle(Theme.text)
                            }
                            .padding(10)
                            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(row.highlight ? Theme.accent : .clear, lineWidth: 2))
                        }
                    }
                }
                VStack(spacing: 10) { actions }
                if let hintUntil {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let left = Int(ceil(hintUntil.timeIntervalSince(context.date)))
                        Text(left > 0 ? "Next round in \(left)…" : "Get ready…")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                } else if let hint {
                    Text(hint)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
            .padding(20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

/// Lays out a game screen: board-left/panel-right when wide (iPad landscape),
/// stacked when tall (iPhone, iPad portrait).
struct GameLayout<Bar: View, Side: View, Tray: View, Bottom: View>: View {
    @ViewBuilder var bar: Bar
    @ViewBuilder var side: Side
    @ViewBuilder var tray: Tray
    @ViewBuilder var bottom: Bottom

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.15
            VStack(spacing: 12) {
                bar
                if wide {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 12) {
                            tray.frame(maxWidth: .infinity, maxHeight: .infinity)
                            bottom
                        }
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 12) { side }
                        }
                        .frame(width: min(320, geo.size.width * 0.32))
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) { side }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    tray.frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottom
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .environment(\.isWideLayout, wide)
        }
    }
}

private struct WideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isWideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }
}
