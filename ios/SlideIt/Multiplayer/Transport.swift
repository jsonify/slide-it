import Foundation

/// A way of exchanging game messages with other devices. Game Center (internet
/// play with friends anywhere) and Nearby (peer-to-peer in the same room) both
/// implement this, so the game itself doesn't care which one is in use.
@MainActor
protocol GameTransport: AnyObject {
    var kind: TransportKind { get }
    var localPlayer: PlayerInfo { get }
    var remotePlayers: [PlayerInfo] { get }
    /// The device acting as referee. Every device must agree on this.
    var hostID: String { get }
    var onReceive: ((Data, String) -> Void)? { get set }
    var onPlayersChanged: (() -> Void)? { get set }
    func send(_ data: Data)
    /// Called when a match starts / returns to the lobby (Nearby uses this to stop/resume advertising).
    func setLobbyOpen(_ open: Bool)
    func disconnect()
}

enum TransportKind {
    case gameCenter, nearby

    var label: String {
        switch self {
        case .gameCenter: "Game Center"
        case .nearby: "Nearby"
        }
    }
}
