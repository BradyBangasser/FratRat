//
//  PendingRequestsView.swift
//  FratRat
//
//  Shows all pending incoming likes and direct invites.
//  Presented as a sheet from MatchesView when the badge count > 0.
//

import SwiftUI

struct PendingRequestsView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()

                if mesh.pendingLikes.isEmpty && mesh.pendingInvites.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundColor(.fratGray)
                        Text("No pending requests")
                            .font(.fratBold(18))
                            .foregroundColor(.fratDark)
                        Text("Likes and invites from others will appear here.")
                            .font(.fratBody(14))
                            .foregroundColor(.fratGray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {

                            // ── Incoming likes ────────────────────────────
                            if !mesh.pendingLikes.isEmpty {
                                SectionHeader("LIKES")

                                let likeKeys = Array(mesh.pendingLikes.keys).sorted()
                                VStack(spacing: 0) {
                                    ForEach(likeKeys, id: \.self) { peerId in
                                        if let like = mesh.pendingLikes[peerId] {
                                            LikeRequestRow(
                                                peerId: peerId,
                                                profile: mesh.peerProfiles[peerId]
                                            ) {
                                                // MeshManager handles decrypt → re-encrypt internally
                                                Task { await mesh.sendLikeBack(to: peerId, like: like) }
                                            } onDecline: {
                                                Task { await mesh.declineLike(from: peerId) }
                                            }
                                            if peerId != likeKeys.last {
                                                Divider()
                                                    .padding(.leading, 78)
                                                    .padding(.horizontal, 24)
                                            }
                                        }
                                    }
                                }
                                .background(Color.fratCard)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .padding(.horizontal, 24)
                            }

                            // ── Incoming invites ──────────────────────────
                            if !mesh.pendingInvites.isEmpty {
                                SectionHeader("INVITES")

                                let inviteKeys = Array(mesh.pendingInvites.keys).sorted()
                                VStack(spacing: 0) {
                                    ForEach(inviteKeys, id: \.self) { peerId in
                                        if let invite = mesh.pendingInvites[peerId] {
                                            InviteRequestRow(
                                                invite: invite,
                                                profile: mesh.peerProfiles[peerId]
                                            ) {
                                                let convId = invite.conversationId
                                                Task {
                                                    await mesh.acceptInvite(
                                                        from: peerId,
                                                        conversationId: convId
                                                    )
                                                }
                                            } onDecline: {
                                                Task { await mesh.declineInvite(from: peerId) }
                                            }
                                            if peerId != inviteKeys.last {
                                                Divider()
                                                    .padding(.leading, 78)
                                                    .padding(.horizontal, 24)
                                            }
                                        }
                                    }
                                }
                                .background(Color.fratCard)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .padding(.horizontal, 24)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Requests")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.fratPink)
                }
            }
        }
    }
}

// MARK: - Like request row
private struct LikeRequestRow: View {
    let peerId: String
    let profile: PeerProfile?
    let onAccept: () -> Void
    let onDecline: () -> Void

    private var displayName: String {
        profile?.displayName ?? "Peer \(String(peerId.prefix(6)))"
    }

    private var initials: String {
        profile?.avatarInitials ?? String(peerId.prefix(2)).uppercased()
    }

    var body: some View {
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
                    .frame(width: 50, height: 50)
                Text(initials)
                    .font(.fratBold(16))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.fratBold(15))
                    .foregroundColor(.fratDark)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.fratPink)
                    Text("Liked you")
                        .font(.fratBody(13))
                        .foregroundColor(.fratGray)
                }
                if let profile, !profile.college.isEmpty {
                    Text(profile.college)
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.fratGray)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.fratBg))
                }

                Button(action: onAccept) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.fratPink))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Invite request row
private struct InviteRequestRow: View {
    let invite: InvitePayload
    let profile: PeerProfile?
    let onAccept: () -> Void
    let onDecline: () -> Void

    private var displayName: String {
        profile?.displayName ?? invite.senderName
    }

    private var initials: String {
        profile?.avatarInitials ?? String(invite.senderName.prefix(2)).uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.3, green: 0.1, blue: 0.5),
                                     Color(red: 0.3, green: 0.1, blue: 0.5).opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                Text(initials)
                    .font(.fratBold(16))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.fratBold(15))
                    .foregroundColor(.fratDark)
                HStack(spacing: 4) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.3, green: 0.1, blue: 0.5))
                    Text("Invited you to chat")
                        .font(.fratBody(13))
                        .foregroundColor(.fratGray)
                }
                if let profile, !profile.college.isEmpty {
                    Text(profile.college)
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.fratGray)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.fratBg))
                }

                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(red: 0.3, green: 0.1, blue: 0.5)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Section header
private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack {
            Text(text)
                .font(.fratSemi(12))
                .foregroundColor(.fratGray)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }
}

#Preview {
    PendingRequestsView()
        .environmentObject(MeshManager())
}
