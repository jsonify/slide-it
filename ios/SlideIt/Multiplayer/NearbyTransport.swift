import Foundation
import MultipeerConnectivity

/// Play with people in the same room over Wi-Fi / Bluetooth, peer to peer.
/// No internet, no Game Center, no accounts needed.
///
/// Topology is a star: the host advertises, guests connect to the host, and the
/// host relays every guest's messages to the other guests. That keeps things
/// simple and works even if guests can't see each other directly.
@MainActor
final class NearbyTransport: NSObject, GameTransport, ObservableObject {
    static let serviceType = "slideit" // must match NSBonjourServices in Info.plist

    struct Host: Identifiable, Hashable {
        let peer: MCPeerID
        let playerID: String
        let name: String
        var id: String { playerID }
    }

    /// Transport-level envelope: who a payload came from, plus roster updates.
    private struct Envelope: Codable {
        var from: String
        var hello: PlayerInfo?
        var roster: [PlayerInfo]?
        var payload: Data?
    }

    let kind = TransportKind.nearby
    let localPlayer: PlayerInfo
    let isHosting: Bool
    var onReceive: ((Data, String) -> Void)?
    var onPlayersChanged: (() -> Void)?

    // Guest-side discovery state
    @Published private(set) var hosts: [Host] = []
    @Published private(set) var joiningHost: Host?
    @Published private(set) var joined = false
    @Published private(set) var joinError: String?

    private let peer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var playersByPeer: [MCPeerID: PlayerInfo] = [:] // host: connected guests
    private var roster: [PlayerInfo] = [] // guest: everyone, as sent by the host
    private var hostPeer: MCPeerID?
    private var hostPlayerID: String?
    private var lobbyOpen = true

    static let maxGuests = 5

    init(name: String, hosting: Bool) {
        localPlayer = PlayerInfo(id: UUID().uuidString, name: name)
        isHosting = hosting
        peer = MCPeerID(displayName: String(name.prefix(40)))
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
        if hosting {
            startAdvertising()
        } else {
            let b = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
            b.delegate = self
            b.startBrowsingForPeers()
            browser = b
        }
    }

    // MARK: GameTransport

    var remotePlayers: [PlayerInfo] {
        if isHosting {
            return playersByPeer.values.sorted { $0.name < $1.name }
        }
        return roster.filter { $0.id != localPlayer.id }
    }

    var hostID: String { isHosting ? localPlayer.id : (hostPlayerID ?? "") }

    func send(_ data: Data) {
        let env = Envelope(from: localPlayer.id, payload: data)
        if isHosting {
            sendEnvelope(env, to: session.connectedPeers)
        } else if let hostPeer {
            sendEnvelope(env, to: [hostPeer])
        }
    }

    func setLobbyOpen(_ open: Bool) {
        guard isHosting, open != lobbyOpen else { return }
        lobbyOpen = open
        if open { startAdvertising() } else { stopAdvertising() }
    }

    func disconnect() {
        stopAdvertising()
        browser?.stopBrowsingForPeers()
        browser = nil
        session.disconnect()
    }

    // MARK: Guest

    func join(_ host: Host) {
        guard let browser, joiningHost == nil else { return }
        joinError = nil
        joiningHost = host
        hostPeer = host.peer
        hostPlayerID = host.playerID
        browser.invitePeer(host.peer, to: session, withContext: nil, timeout: 20)
    }

    // MARK: Internals

    private func startAdvertising() {
        let a = MCNearbyServiceAdvertiser(
            peer: peer,
            discoveryInfo: ["id": localPlayer.id, "name": String(localPlayer.name.prefix(40))],
            serviceType: Self.serviceType
        )
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
    }

    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    private func sendEnvelope(_ env: Envelope, to peers: [MCPeerID]) {
        guard !peers.isEmpty, let data = try? JSONEncoder().encode(env) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    private func broadcastRoster() {
        let everyone = [localPlayer] + remotePlayers
        sendEnvelope(Envelope(from: localPlayer.id, roster: everyone), to: session.connectedPeers)
    }

    private func handle(_ data: Data, from peerID: MCPeerID) {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        if isHosting {
            if let hello = env.hello {
                playersByPeer[peerID] = hello
                broadcastRoster()
                onPlayersChanged?()
            } else if let payload = env.payload, let sender = playersByPeer[peerID] {
                onReceive?(payload, sender.id)
                // Relay to every other guest.
                let others = session.connectedPeers.filter { $0 != peerID }
                sendEnvelope(Envelope(from: sender.id, payload: payload), to: others)
            }
        } else {
            if let roster = env.roster {
                self.roster = roster
                if !joined {
                    joined = true
                    browser?.stopBrowsingForPeers()
                }
                onPlayersChanged?()
            } else if let payload = env.payload {
                onReceive?(payload, env.from)
            }
        }
    }

    private func peerChanged(_ peerID: MCPeerID, _ state: MCSessionState) {
        switch state {
        case .connected:
            if !isHosting, peerID == hostPeer {
                sendEnvelope(Envelope(from: localPlayer.id, hello: localPlayer), to: [peerID])
            }
        case .notConnected:
            if isHosting {
                if playersByPeer.removeValue(forKey: peerID) != nil {
                    broadcastRoster()
                    onPlayersChanged?()
                }
            } else if peerID == hostPeer {
                if joined {
                    roster = []
                    onPlayersChanged?()
                } else {
                    joinError = "Couldn't join that game. Try again."
                    joiningHost = nil
                    hostPeer = nil
                }
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }
}

extension NearbyTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.peerChanged(peerID, state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.handle(data, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension NearbyTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            let accept = self.lobbyOpen && self.session.connectedPeers.count < Self.maxGuests
            invitationHandler(accept, accept ? self.session : nil)
        }
    }
}

extension NearbyTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let id = info?["id"] else { return }
        let name = info?["name"] ?? peerID.displayName
        Task { @MainActor in
            self.hosts.removeAll { $0.playerID == id }
            self.hosts.append(Host(peer: peerID, playerID: id, name: name))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.hosts.removeAll { $0.peer == peerID } }
    }
}
