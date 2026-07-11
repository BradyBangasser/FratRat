//
//  MatchesView.swift
//  FratRat
//

import SwiftUI

// MARK: - Match model
struct Match: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let peerId: String
    var lastMessage: String
    var timestamp: Date
    var unread: Int

    var avatarInitials: String {
        let clean = peerId.replacingOccurrences(of: "12D3KooW", with: "")
        return String(clean.prefix(2)).uppercased()
    }

    init(peerId: String, connectedAt: Date = Date()) {
        self.id = UUID()
        self.peerId = peerId
        let short = peerId.replacingOccurrences(of: "12D3KooW", with: "")
        self.name = "Peer \(short.prefix(6))"
        self.lastMessage = "Connected"
        self.timestamp = connectedAt
        self.unread = 0
    }

    init(id: UUID = UUID(), name: String, peerId: String,
         lastMessage: String, timestamp: Date, unread: Int) {
        self.id = id; self.name = name; self.peerId = peerId
        self.lastMessage = lastMessage; self.timestamp = timestamp; self.unread = unread
    }
}

// MARK: - MatchesView
struct MatchesView: View {
    @EnvironmentObject var mesh: MeshManager
    @State private var activeChat: Match? = nil
    @State private var showInviteByName = false
    @State private var showQRInvite = false
    @State private var showJoin = false
    @State private var showRequests = false

    private var matches: [Match] {
        var seen = Set<String>()
        var result: [Match] = []

        // ── 1. Conversations with message history ─────────────────────
        for (convId, msgs) in mesh.conversationMessages {
            guard !msgs.isEmpty else { continue }
            seen.insert(convId)
            // convId is either a peer ID (DM) or a conversation UUID (invite/match)
            // Find the profile — check peerProfiles by convId directly,
            // or find a peer whose matched conversation_id equals convId
            let profile = mesh.peerProfiles[convId] ?? profileForConversation(convId)
            let last = msgs.sorted { $0.timestamp > $1.timestamp }.first
            result.append(Match(
                id: stableId(for: convId),
                name: profile?.displayName ?? "Chat \(String(convId.prefix(6)))",
                peerId: convId,
                lastMessage: last?.text ?? "",
                timestamp: last?.timestamp ?? Date(),
                unread: mesh.unreadCounts[convId] ?? 0
            ))
        }

        // ── 2. Matched conversations without messages yet ─────────────
        // Matches and accepted invites should appear in the list immediately
        // after the match is made, before any messages are exchanged.
        for (peerId, state) in mesh.relationships {
            let convId: String
            switch state {
            case .matched(let cid):         convId = cid
            case .inviteAccepted(let cid):  convId = cid
            default: continue
            }
            guard !seen.contains(convId), !seen.contains(peerId) else { continue }
            seen.insert(convId)
            seen.insert(peerId)
            let profile = mesh.peerProfiles[peerId]
            result.append(Match(
                id: stableId(for: convId),
                name: profile?.displayName ?? "New match",
                peerId: convId,
                lastMessage: "You matched! Say hello 👋",
                timestamp: Date(),
                unread: 0
            ))
        }

        return result.sorted { $0.timestamp > $1.timestamp }
    }

    /// Derives a deterministic UUID from a conversation ID string so
    /// SwiftUI's ForEach identity stays stable across recomputes of
    /// `matches` (which fires on every relationships/messages change,
    /// not just changes relevant to this particular row).
    private func stableId(for convId: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(convId)
        let hash = hasher.finalize()
        let bytes = withUnsafeBytes(of: hash) { Array($0) }
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { uuidBytes[i] = bytes[i % bytes.count] }
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    /// Find a profile for a conversation UUID by checking relationships.
    private func profileForConversation(_ conversationId: String) -> PeerProfile? {
        for (peerId, state) in mesh.relationships {
            switch state {
            case .matched(let cid) where cid == conversationId:
                return mesh.peerProfiles[peerId]
            case .inviteAccepted(let cid) where cid == conversationId:
                return mesh.peerProfiles[peerId]
            case .inviteSent(let cid) where cid == conversationId:
                return mesh.peerProfiles[peerId]
            default: continue
            }
        }
        return nil
    }

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Messages")
                            .font(.system(size: 34, weight: .black))
                            .foregroundColor(.fratDark)
                        Text("\(matches.count) conversation\(matches.count == 1 ? "" : "s")")
                            .font(.fratBody(15))
                            .foregroundColor(.fratGray)
                    }
                    Spacer()

                    HStack(spacing: 8) {
                        // Requests badge
                        Button {
                            showRequests = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.fratDark)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(Color.fratCard))
                                if mesh.pendingRequestCount > 0 {
                                    Text("\(mesh.pendingRequestCount)")
                                        .font(.fratBold(10))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .padding(.horizontal, 3)
                                        .background(Capsule().fill(Color.fratPink))
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }

                        // Scan QR to join
                        Button { showJoin = true } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.fratDark)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.fratCard))
                        }

                        // Invite menu
                        Menu {
                            Button {
                                showInviteByName = true
                            } label: {
                                Label("Invite by name", systemImage: "person.badge.plus")
                            }
                            Button {
                                showQRInvite = true
                            } label: {
                                Label("Show QR code", systemImage: "qrcode")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.fratPink))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 20)

                // ── Connection banner ─────────────────────────────────────
                if !mesh.connectionState.isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 13))
                            .foregroundColor(.fratGray)
                        Text(mesh.connectionState.label)
                            .font(.fratBody(13))
                            .foregroundColor(.fratGray)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }

                // ── Content ───────────────────────────────────────────────
                Text("MESSAGES")
                    .font(.fratSemi(12))
                    .foregroundColor(.fratGray)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                if matches.isEmpty {
                    EmptyMatchesCard(isConnected: mesh.connectionState.isConnected) {
                        showInviteByName = true
                    }
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(matches) { match in
                                MatchRow(match: match) {
                                    activeChat = match
                                }
                                if match.id != matches.last?.id {
                                    Divider()
                                        .padding(.leading, 78)
                                        .padding(.horizontal, 24)
                                }
                            }
                        }
                        .background(Color.fratCard)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 100)
                    }
                }

                Spacer()
            }
        }
        .fullScreenCover(item: $activeChat) { match in
            ChatView(match: match)
                .environmentObject(mesh)
        }
        .sheet(isPresented: $showRequests) {
            PendingRequestsView()
                .environmentObject(mesh)
        }
        .sheet(isPresented: $showInviteByName) {
            InviteByNameView()
                .environmentObject(mesh)
        }
        .sheet(isPresented: $showQRInvite) {
            // QR invite flow — existing InviteView
            InviteView()
                .environmentObject(mesh)
        }
        .sheet(isPresented: $showJoin) {
            JoinChatView()
                .environmentObject(mesh)
        }
    }
}

// MARK: - Empty state
private struct EmptyMatchesCard: View {
    let isConnected: Bool
    let onInvite: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.fratPinkLight)
                    .frame(width: 72, height: 72)
                Image(systemName: isConnected ? "message.fill" : "wifi.slash")
                    .font(.system(size: 28))
                    .foregroundColor(.fratPink)
            }
            Text(isConnected ? "No messages yet" : "Not connected")
                .font(.fratBold(20))
                .foregroundColor(.fratDark)
            Text(isConnected
                 ? "Start swiping to make connections, or invite someone directly."
                 : "Connect to a relay on the Discover tab to find people nearby.")
                .font(.fratBody(15))
                .foregroundColor(.fratGray)
                .multilineTextAlignment(.center)

            if isConnected {
                Button(action: onInvite) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                        Text("Invite someone")
                            .font(.fratSemi(14))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.fratPink))
                }
                .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.fratCard))
    }
}

// MARK: - Match row
private struct MatchRow: View {
    let match: Match
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.fratPink, Color.fratPink.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                    Text(match.avatarInitials)
                        .font(.fratBold(18))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(match.name)
                            .font(.fratBold(16))
                            .foregroundColor(.fratDark)
                        Spacer()
                        Text(match.timestamp.relativeString)
                            .font(.fratBody(12))
                            .foregroundColor(.fratGray)
                    }
                    HStack {
                        Text(match.lastMessage)
                            .font(.fratBody(14))
                            .foregroundColor(match.unread > 0 ? .fratDark : .fratGray)
                            .lineLimit(1)
                        Spacer()
                        if match.unread > 0 {
                            Text("\(match.unread)")
                                .font(.fratBold(11))
                                .foregroundColor(.white)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Circle().fill(Color.fratPink))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MatchesView()
        .environmentObject(MeshManager())
}
