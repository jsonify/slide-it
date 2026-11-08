import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var gameCenter: GameCenter
    @AppStorage("playerName") private var name = ""
    @AppStorage(Feedback.soundKey) private var soundOn = true
    @State private var showHowTo = false
    @FocusState private var nameFocused: Bool

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? UIDevice.current.name : String(trimmed.prefix(16))
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 22) {
                    LogoView()
                        .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your name").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                        TextField("", text: $name, prompt: Text("e.g. Sam").foregroundColor(Theme.muted))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .padding(15)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(nameFocused ? Theme.accent : Theme.line, lineWidth: nameFocused ? 2 : 1))
                            .onChange(of: name) { _, v in if v.count > 16 { name = String(v.prefix(16)) } }
                    }

                    VStack(spacing: 12) {
                        ModeButton(
                            title: "Play online",
                            subtitle: gameCenter.isAuthenticated ? "Invite friends anywhere with Game Center" : "Sign in to Game Center to play online",
                            icon: "globe",
                            kind: .primary
                        ) {
                            Feedback.shared.play(.pop)
                            gameCenter.presentMatchmaker()
                        }
                        ModeButton(title: "Play nearby", subtitle: "Same room, no internet needed", icon: "dot.radiowaves.left.and.right", kind: .secondary) {
                            Feedback.shared.play(.pop)
                            app.screen = .nearby(name: displayName)
                        }
                        ModeButton(title: "Face-off", subtitle: "Two players, one iPad", icon: "person.2.fill", kind: .ghost) {
                            Feedback.shared.play(.pop)
                            app.screen = .faceOff
                        }
                        ModeButton(title: "Solo practice", subtitle: "Beat your best time", icon: "stopwatch.fill", kind: .ghost) {
                            Feedback.shared.play(.pop)
                            app.screen = .solo
                        }
                    }

                    HStack(spacing: 6) {
                        Button("How to play") { showHowTo = true }
                        Text("·").foregroundStyle(Theme.muted)
                        Button(soundOn ? "Sound: on" : "Sound: off") { soundOn.toggle() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .buttonStyle(.plain)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
        .alert("Game Center", isPresented: Binding(get: { gameCenter.lastError != nil }, set: { if !$0 { gameCenter.clearError() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(gameCenter.lastError ?? "")
        }
    }
}

private struct ModeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let kind: GameButtonStyle.Kind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.display(20))
                    Text(subtitle).font(.system(size: 13, weight: .semibold)).opacity(0.75)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).opacity(0.6)
            }
        }
        .buttonStyle(GameButtonStyle(kind: kind))
    }
}

/// A little 3x3 of tiles that keeps flipping colours.
private struct LogoView: View {
    @State private var tiles: [TileColor] = (0..<9).map { _ in TileColor.allCases.randomElement()! }
    @State private var flipping: Int?
    private let timer = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 5), count: 3), spacing: 5) {
                ForEach(0..<9, id: \.self) { i in
                    TileView(color: tiles[i])
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(flipping == i ? 90 : 0))
                        .scaleEffect(flipping == i ? 0.6 : 1)
                }
            }
            .frame(width: 118)
            .padding(8)
            .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 18)

            HStack(spacing: 8) {
                Text("Slide").foregroundStyle(Theme.text)
                Text("It").foregroundStyle(Theme.accent)
            }
            .font(Theme.display(54))
            Text("Match the pattern. Beat your friends.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .onReceive(timer) { _ in
            let i = Int.random(in: 0..<9)
            withAnimation(.easeIn(duration: 0.18)) { flipping = i }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                tiles[i] = TileColor.allCases.randomElement()!
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { flipping = nil }
            }
        }
    }
}

struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("square.grid.3x3.fill", "Everyone gets the **same scrambled tray**: 24 coloured tiles and one gap."),
        ("eye.fill", "When the countdown ends, a **target pattern** appears."),
        ("hand.tap.fill", "**Tap any tile** in the gap's row or column to slide it. The tiles in between move too. You can also **swipe**."),
        ("checkmark.seal.fill", "First to make the **middle 3×3** match the target wins the round. The outer ring doesn't matter."),
        ("trophy.fill", "Win enough rounds to take the match. Watch your friends' trays update live!"),
    ]

    var body: some View {
        ZStack {
            Theme.panel.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("How to play").font(Theme.display(30)).foregroundStyle(Theme.text)
                ForEach(steps, id: \.1) { icon, text in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 26)
                        Text(.init(text))
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: 0xDDD9FF))
                    }
                }
                Spacer()
                Button("Got it") { dismiss() }.buttonStyle(GameButtonStyle(kind: .primary, big: true))
            }
            .padding(24)
        }
        .presentationDetents([.large])
    }
}
