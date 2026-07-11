//
//  InviteByNameView.swift
//  FratRat
//
//  Search known peer profiles and send a direct invite to a specific
//  person. Guards: cannot re-invite or invite someone you've already
//  liked (unless it's a group chat — handled separately).
//

import SwiftUI

struct InviteByNameView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var sentTo: Set<String> = []   // peer IDs invited this session
    @State private var activeAlert: InviteAlert?

    enum InviteAlert: Identifiable {
        case confirmSend(peerId: String, name: String)
        case alreadySent(name: String)
        var id: String {
            switch self {
            case .confirmSend(let p, _): return "confirm_\(p)"
            case .alreadySent(let n): return "sent_\(n)"
            }
        }
    }

    // Peers we can show — excludes self, excludes relay
    private var candidates: [PeerProfile] {
        mesh.peerProfiles.values
            .filter { $0.peerId != mesh.myPeerId }
            .filter { $0.peerId != mesh.selectedRelay?.peerId }
            .filter {
                guard !searchText.isEmpty else { return true }
                let q = searchText.lowercased()
                return $0.name.lowercased().contains(q)
                    || $0.college.lowercased().contains(q)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Search bar ────────────────────────────────────────
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.fratGray)
                            .font(.system(size: 15))
                        TextField("Search by name or college…", text: $searchText)
                            .font(.fratBody(15))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.fratGray)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                    if candidates.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: searchText.isEmpty ? "person.2.slash" : "magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundColor(.fratGray)
                            Text(searchText.isEmpty ? "No peers nearby" : "No results for \"\(searchText)\"")
                                .font(.fratBold(17))
                                .foregroundColor(.fratDark)
                            Text(searchText.isEmpty
                                 ? "Peers appear here once they connect to the mesh."
                                 : "Try a different name or college.")
                                .font(.fratBody(14))
                                .foregroundColor(.fratGray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(candidates, id: \.peerId) { profile in
                                    InvitePeerRow(
                                        profile: profile,
                                        state: inviteState(for: profile.peerId)
                                    ) {
                                        handleInviteTap(profile: profile)
                                    }
                                    if profile.peerId != candidates.last?.peerId {
                                        Divider()
                                            .padding(.leading, 78)
                                            .padding(.horizontal, 24)
                                    }
                                }
                            }
                            .background(Color.fratCard)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("Invite someone")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.fratPink)
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmSend(let peerId, let name):
                return Alert(
                    title: Text("Invite \(name)?"),
                    message: Text("They'll receive a notification and can accept or decline."),
                    primaryButton: .default(Text("Send invite")) {
                        Task { await sendInvite(to: peerId, name: name) }
                    },
                    secondaryButton: .cancel()
                )
            case .alreadySent(let name):
                return Alert(
                    title: Text("Already invited"),
                    message: Text("You've already sent \(name) an invite. Wait for them to respond."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func inviteState(for peerId: String) -> InvitePeerRowState {
        if sentTo.contains(peerId) { return .sent }
        let rel = loadRelationship(peerId: peerId)
        switch rel {
        case .liked, .matched, .inviteSent, .inviteAccepted:
            return .unavailable
        case .likedBy, .declined, .none:
            return mesh.canInvite(peerId) ? .canInvite : .unavailable
        case .inviteReceived:
            return .pendingTheirResponse
        }
    }

    private func handleInviteTap(profile: PeerProfile) {
        let state = inviteState(for: profile.peerId)
        switch state {
        case .sent:
            activeAlert = .alreadySent(name: profile.displayName)
        case .unavailable:
            break // button disabled, shouldn't reach here
        case .pendingTheirResponse:
            break // already waiting, button disabled
        case .canInvite:
            activeAlert = .confirmSend(peerId: profile.peerId, name: profile.displayName)
        }
    }

    private func sendInvite(to peerId: String, name: String) async {
        let conversationId = UUID().uuidString.lowercased()
        // MeshManager generates the conversation key and encrypts it
        // to the recipient's pubkey internally via NodeIdentity.encryptForPeer()
        await mesh.sendInvite(to: peerId, conversationId: conversationId)
        sentTo.insert(peerId)
    }
}

// MARK: - Row state
enum InvitePeerRowState {
    case canInvite
    case sent
    case unavailable            // liked, matched, already invited
    case pendingTheirResponse   // they invited us
}

// MARK: - Peer row
private struct InvitePeerRow: View {
    let profile: PeerProfile
    let state: InvitePeerRowState
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.fratPinkLight)
                    .frame(width: 50, height: 50)
                Text(profile.avatarInitials)
                    .font(.fratBold(16))
                    .foregroundColor(.fratPink)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.fratBold(15))
                    .foregroundColor(.fratDark)
                if !profile.college.isEmpty || !profile.year.isEmpty {
                    Text([profile.college, profile.year]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.fratBody(13))
                        .foregroundColor(.fratGray)
                }
            }

            Spacer()

            // Action button
            switch state {
            case .canInvite:
                Button(action: onTap) {
                    Text("Invite")
                        .font(.fratSemi(13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.fratPink))
                }
            case .sent:
                Text("Sent")
                    .font(.fratSemi(13))
                    .foregroundColor(.fratGray)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.fratGray.opacity(0.15)))
            case .unavailable:
                Text("Unavailable")
                    .font(.fratSemi(12))
                    .foregroundColor(.fratGray.opacity(0.6))
            case .pendingTheirResponse:
                Text("Invited you")
                    .font(.fratSemi(12))
                    .foregroundColor(.fratPink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(state == .unavailable ? 0.5 : 1)
        .allowsHitTesting(state == .canInvite || state == .sent)
    }
}

#Preview {
    InviteByNameView()
        .environmentObject(MeshManager())
}
