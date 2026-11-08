import GameKit
import SwiftUI

@main
struct SlideItApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var gameCenter = GameCenter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(gameCenter)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear { gameCenter.authenticate() }
                .onReceive(gameCenter.$readyMatch) { match in
                    guard let match else { return }
                    gameCenter.readyMatch = nil
                    app.startOnline(GameCenterTransport(match: match))
                }
        }
    }
}

/// Which screen is showing.
@MainActor
final class AppModel: ObservableObject {
    enum Screen {
        case home, solo, faceOff
        case nearby(name: String)
        case online(OnlineSession)

        var key: String {
            switch self {
            case .home: "home"
            case .solo: "solo"
            case .faceOff: "faceOff"
            case .nearby: "nearby"
            case .online(let s): "online-\(s.id)"
            }
        }
    }

    @Published var screen: Screen = .home {
        didSet { UIApplication.shared.isIdleTimerDisabled = screen.key != "home" }
    }

    func startOnline(_ transport: GameTransport) {
        if case .online(let old) = screen { old.leave() }
        screen = .online(OnlineSession(transport: transport))
    }

    func goHome() {
        if case .online(let session) = screen { session.leave() }
        screen = .home
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            switch app.screen {
            case .home:
                HomeView()
            case .solo:
                SoloView(onExit: app.goHome)
            case .faceOff:
                FaceOffView(onExit: app.goHome)
            case .nearby(let name):
                NearbyView(playerName: name, onSession: { app.screen = .online($0) }, onBack: app.goHome)
            case .online(let session):
                OnlineMatchView(session: session, onExit: app.goHome)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: app.screen.key)
    }
}
