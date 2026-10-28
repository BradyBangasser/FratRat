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
// Format: "fratrat://invite/<conversationId>/<inviterPeerId>/<keyHex>/<inviterName>"
//
// The QR code is the private channel: it carries the conversation key, so
// whoever scans it can read and write the chat, and nobody else can.
struct ChatInvite: Equatable {
    let conversationId: String
    let inviterPeerId: String
    let key: Data
    let inviterName: String

    /// Encode as a URL string for the QR code / share sheet.
    var encoded: String {
        let safeName = inviterName
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? inviterName
        return "fratrat://invite/\(conversationId)/\(inviterPeerId)/\(key.hexString)/\(safeName)"
    }

    /// Parse from a scanned QR string or pasted invite code.
    static func parse(_ raw: String) -> ChatInvite? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Accept either the full "fratrat://invite/..." URL or just the
        // path portion "<conversationId>/<peerId>/<name>"
        if s.hasPrefix("fratrat://invite/") {
            s = String(s.dropFirst("fratrat://invite/".count))
        }

        let parts = s.split(separator: "/", maxSplits: 3).map(String.init)
        guard parts.count >= 3 else { return nil }

        let conversationId = parts[0]
        let inviterPeerId = parts[1]
        guard let key = Data(hexString: parts[2]), key.count == 32 else { return nil }
        let inviterName = parts.count > 3
            ? (parts[3].removingPercentEncoding ?? parts[3])
            : "Someone"

        guard !conversationId.isEmpty, !inviterPeerId.isEmpty else { return nil }

        return ChatInvite(
            conversationId: conversationId,
            inviterPeerId: inviterPeerId,
            key: key,
            inviterName: inviterName
        )
    }

    /// Generate a new invite with a fresh conversation ID and key.
    static func create(inviterPeerId: String, inviterName: String) -> ChatInvite {
        ChatInvite(
            conversationId: UUID().uuidString.lowercased(),
            inviterPeerId: inviterPeerId,
            key: generateConversationKey(),
            inviterName: inviterName
        )
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
