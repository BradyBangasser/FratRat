//
//  ChatInvite.swift
//  FratRat
//
//  Created by Brady Bangasser on 6/13/26.
//


//
//  InviteModels.swift
//  FratRat
//

import Foundation

// MARK: - Invite payload
// Encoded into the QR code / shareable string.
// Format: "fratrat://invite/<conversationId>/<inviterPeerId>/<inviterName>"
struct ChatInvite: Equatable {
    let conversationId: String
    let inviterPeerId: String
    let inviterName: String

    /// The mesh topic both sides will use for this conversation.
    /// Distinct from the peer-derived `dm/<min><max>` topic used for
    /// existing matches — invite-based chats use a shared random ID
    /// so the topic is identical for both the inviter and the joiner
    /// without either side needing to know the other's peer ID upfront.
    var topic: String {
        "fratrat/v1/invite/\(conversationId)"
    }

    /// Encode as a URL string for the QR code / share sheet.
    var encoded: String {
        let safeName = inviterName
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? inviterName
        return "fratrat://invite/\(conversationId)/\(inviterPeerId)/\(safeName)"
    }

    /// Parse from a scanned QR string or pasted invite code.
    static func parse(_ raw: String) -> ChatInvite? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Accept either the full "fratrat://invite/..." URL or just the
        // path portion "<conversationId>/<peerId>/<name>"
        if s.hasPrefix("fratrat://invite/") {
            s = String(s.dropFirst("fratrat://invite/".count))
        }

        let parts = s.split(separator: "/", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        let conversationId = parts[0]
        let inviterPeerId = parts[1]
        let inviterName = parts.count > 2
            ? (parts[2].removingPercentEncoding ?? parts[2])
            : "Someone"

        guard !conversationId.isEmpty, !inviterPeerId.isEmpty else { return nil }

        return ChatInvite(
            conversationId: conversationId,
            inviterPeerId: inviterPeerId,
            inviterName: inviterName
        )
    }

    /// Generate a new invite with a fresh random conversation ID.
    static func create(inviterPeerId: String, inviterName: String) -> ChatInvite {
        ChatInvite(
            conversationId: UUID().uuidString.lowercased(),
            inviterPeerId: inviterPeerId,
            inviterName: inviterName
        )
    }
}