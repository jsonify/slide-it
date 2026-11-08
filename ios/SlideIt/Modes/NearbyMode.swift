import SwiftUI

/// Host or join a game with people in the same room (no internet needed).
struct NearbyView: View {
    let playerName: String
    let onSession: (OnlineSession) -> Void
    let onBack: () -> Void
    @State private var guest: NearbyTransport?

    var body: some View {
        ZStack {
            AppBackground()
            if let guest {
                NearbyJoinList(transport: guest, onSession: onSession) {
                    guest.disconnect()
                    self.guest = nil
                }
            } else {
                VStack(spacing: 18) {
                    HStack {
                        IconButton(systemName: "chevron.left", action: onBack)
                        Spacer()
                    }
                    Spacer()
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("Play nearby").font(Theme.display(34)).foregroundStyle(Theme.text)
                    Text("For friends in the same room. Phones connect directly over Wi-Fi and Bluetooth, no internet needed.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    VStack(spacing: 12) {
                        Button("Host a game") {
                            onSession(OnlineSession(transport: NearbyTransport(name: playerName, hosting: true)))
                        }
                        .buttonStyle(GameButtonStyle(kind: .primary, big: true))
                        Button("Join a game") {
                            guest = NearbyTransport(name: playerName, hosting: false)
                        }
                        .buttonStyle(GameButtonStyle(kind: .secondary, big: true))
                    }
                    .padding(.top, 8)
                    Spacer()
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: 440)
            }
        }
    }
}

private struct NearbyJoinList: View {
    @ObservedObject var transport: NearbyTransport
    let onSession: (OnlineSession) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                IconButton(systemName: "chevron.left", action: onBack)
                Spacer()
                Text("Join a game").font(Theme.display(20)).foregroundStyle(Theme.text)
                Spacer()
                Color.clear.frame(width: 42, height: 42)
            }

            if transport.hosts.isEmpty {
                Spacer()
                ProgressView().tint(Theme.accent).scaleEffect(1.4)
                Text("Looking for games nearby…")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Ask a friend to tap Play Nearby → Host a game.")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(transport.hosts) { host in
                            Button {
                                transport.join(host)
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(name: host.name, color: Theme.avatars[host.name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Theme.avatars.count])
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(host.name)'s game").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
                                        Text(transport.joiningHost == host ? "Joining…" : "Tap to join")
                                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    if transport.joiningHost == host { ProgressView().tint(Theme.muted) }
                                    else { Image(systemName: "chevron.right").foregroundStyle(Theme.muted) }
                                }
                                .padding(14)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
                            }
                            .buttonStyle(.plain)
                            .disabled(transport.joiningHost != nil)
                        }
                    }
                }
            }
            if let error = transport.joinError {
                Text(error).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent2)
            }
        }
        .padding(16)
        .frame(maxWidth: 520)
        .onChange(of: transport.joined) { _, joined in
            if joined { onSession(OnlineSession(transport: transport)) }
        }
    }
}
