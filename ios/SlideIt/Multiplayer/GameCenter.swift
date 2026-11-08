import GameKit
import UIKit

/// Game Center sign-in, matchmaking and invites. Apple runs all the online
/// infrastructure, so Slide It needs no server of its own.
@MainActor
final class GameCenter: NSObject, ObservableObject {
    static let shared = GameCenter()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var lastError: String?
    /// Set when a match is ready to play; the app picks it up and clears it.
    @Published var readyMatch: GKMatch?

    private var listenerRegistered = false

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    UIApplication.topViewController?.present(viewController, animated: true)
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if let error { self.lastError = error.localizedDescription }
                if self.isAuthenticated, !self.listenerRegistered {
                    GKLocalPlayer.local.register(self)
                    self.listenerRegistered = true
                }
            }
        }
    }

    /// Show Apple's matchmaking screen: invite friends (via Messages or Game
    /// Center) or get matched with anyone.
    func presentMatchmaker() {
        guard isAuthenticated else {
            lastError = "Sign in to Game Center in the Settings app to play online."
            return
        }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 4
        request.inviteMessage = "Race me in Slide It!"
        guard let vc = GKMatchmakerViewController(matchRequest: request) else { return }
        vc.matchmakerDelegate = self
        UIApplication.topViewController?.present(vc, animated: true)
    }

    fileprivate func presentInvite(_ invite: GKInvite) {
        guard let vc = GKMatchmakerViewController(invite: invite) else { return }
        vc.matchmakerDelegate = self
        UIApplication.topViewController?.present(vc, animated: true)
    }

    func clearError() { lastError = nil }
}

extension GameCenter: GKMatchmakerViewControllerDelegate {
    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        Task { @MainActor in viewController.dismiss(animated: true) }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            viewController.dismiss(animated: true)
            self.lastError = message
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        Task { @MainActor in
            viewController.dismiss(animated: true)
            self.readyMatch = match
        }
    }
}

extension GameCenter: GKLocalPlayerListener {
    /// A friend's invite was accepted (e.g. tapped in Messages).
    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        Task { @MainActor in self.presentInvite(invite) }
    }
}

/// Plays over a Game Center real-time match. Data is relayed by Apple.
@MainActor
final class GameCenterTransport: NSObject, GameTransport {
    let kind = TransportKind.gameCenter
    let localPlayer: PlayerInfo
    private(set) var remotePlayers: [PlayerInfo] = []
    var onReceive: ((Data, String) -> Void)?
    var onPlayersChanged: (() -> Void)?
    private let match: GKMatch

    /// Everyone independently picks the same host: the lowest player id.
    var hostID: String { ([localPlayer.id] + remotePlayers.map(\.id)).min() ?? localPlayer.id }

    init(match: GKMatch) {
        self.match = match
        localPlayer = PlayerInfo(id: GKLocalPlayer.local.gamePlayerID, name: GKLocalPlayer.local.displayName)
        super.init()
        match.delegate = self
        refreshPlayers()
    }

    private func refreshPlayers() {
        remotePlayers = match.players.map { PlayerInfo(id: $0.gamePlayerID, name: $0.displayName) }
    }

    func send(_ data: Data) {
        guard !match.players.isEmpty else { return }
        try? match.sendData(toAllPlayers: data, with: .reliable)
    }

    func setLobbyOpen(_ open: Bool) {}

    func disconnect() {
        match.delegate = nil
        match.disconnect()
    }
}

extension GameCenterTransport: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let id = player.gamePlayerID
        Task { @MainActor in self.onReceive?(data, id) }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in
            self.refreshPlayers()
            self.onPlayersChanged?()
        }
    }
}

extension UIApplication {
    /// The view controller currently on screen, for presenting Game Center UI.
    static var topViewController: UIViewController? {
        let scene = shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
