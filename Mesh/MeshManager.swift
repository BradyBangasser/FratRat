//
//  MeshManager.swift
//  FratRat
//

import Foundation
import SwiftUI
import Combine
import CryptoKit
import CoreLocation

// MARK: - Connection state

enum MeshConnectionState: Equatable {
    case disconnected
    case discoveringRelays
    case connecting(relay: String)
    case connected(relay: String)
    case failed(String)

    var label: String {
        switch self {
        case .disconnected:              return "Offline"
        case .discoveringRelays:         return "Finding relays…"
        case .connecting(let r):         return "Connecting to \(r)…"
        case .connected(let r):          return "Connected · \(r)"
        case .failed(let e):             return "Failed: \(e)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - PeerProfile display helpers

extension PeerProfile {
    var displayName: String {
        name.isEmpty ? "Peer \(String(peerId.prefix(6)))" : name
    }

    var avatarInitials: String {
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? String(peerId.prefix(2)).uppercased() : initials
    }
}

// MARK: - MeshManager

final class MeshManager: ObservableObject {

    @Published var connectionState: MeshConnectionState = .disconnected
    @Published var availableRelays: [RelayInfoViewModel] = []
    @Published var selectedRelay:   RelayInfoViewModel?
    @Published var peerCount:       Int = 0
    @Published var connectedPeers:  [String: Date] = [:]
    @Published var myPeerId:        String? = nil
    @Published var peerProfiles:    [String: PeerProfile] = [:]
    @Published var parties:         [UInt64: PartyProfile] = [:]
    @Published var alerts:          [UInt64: AlertProfile] = [:]
    @Published var conversationMessages: [String: [ChatMessage]] = [:]
    @Published var unreadCounts:    [String: Int] = [:]
    /// The other person in each conversation, by conversation id.
    @Published var conversationPeers: [String: String] = [:]
    @Published var relationships:   [String: RelationshipState] = [:]
    @Published var pendingLikes:    [String: LikePayload] = [:]
    @Published var pendingInvites:  [String: InvitePayload] = [:]
    @Published var pendingRequestCount: Int = 0
    @Published var banner: BannerEvent?    = nil
    @Published var userLocation: CLLocation? = nil
    @Published private(set) var blockedPeerIds: Set<String> = MeshManager.loadBlocked()
    /// Set once deleteAllData() finishes; the app returns to onboarding.
    @Published var dataDeleted = false

    private var node:     MeshNode?
    private var identity: NodeIdentity?
    /// The relay gRPC URL for blob and log calls. Learned from the network
    /// directory in findRelays(); starts at the first bootstrap relay.
    private var grpcAddr: String = ZkrpConfig.bootstrapRelays.first ?? ""
    /// Mailbox topic → conversation id, for every topic we watch.
    private var topicConversations: [String: String] = [:]
    /// Re-derives conversation mailboxes as they rotate.
    private var rotationTask: Task<Void, Never>?
    /// First message a QR-invite joiner sends, carrying their name.
    static let joinedPrefix = "JOINED:"

    init() {}

    // MARK: - Conversations
    //
    // Every conversation (a match, an accepted invite, a QR chat) has a key
    // only its two members hold. Messages are sealed with it and published on
    // a mailbox topic derived from it that rotates daily, so relays see
    // neither the text nor who is talking (see rust/ios/src/conversation.rs).

    func profile(forConversation id: String) -> PeerProfile? {
        conversationPeers[id].flatMap { peerProfiles[$0] }
    }

    /// Remember a conversation's key and start watching its mailbox.
    @MainActor
    func openConversation(_ id: String, key: Data, peerId: String?) async {
        guard saveConversationKey(conversationId: id, key: key) else {
            Swift.print("[chat] rejected a malformed conversation key")
            return
        }
        if let peerId { conversationPeers[id] = peerId }
        guard let node,
              let topics = try? conversationTopics(key: key),
              let topicKey = try? conversationTopicKey(key: key)
        else { return }
        for topic in topics where topicConversations[topic] == nil {
            topicConversations[topic] = id
            try? await node.subscribeSealed(topic: topic, key: topicKey)
        }
    }

    /// Watch the current mailbox window of every conversation, and the
    /// current campus topics, dropping topics that rotated out. Mailboxes and
    /// inboxes rotate daily; campus keys with each credential epoch.
    @MainActor
    func refreshConversationSubscriptions() async {
        guard let node else { return }
        var wanted: [String: String] = [:]
        var topicKeys: [String: Data] = [:]
        for id in loadAllConversationKeyIds() {
            guard let key = loadConversationKey(conversationId: id),
                  let topics = try? conversationTopics(key: key),
                  let topicKey = try? conversationTopicKey(key: key)
            else { continue }
            for topic in topics {
                wanted[topic] = id
                topicKeys[topic] = topicKey
            }
        }
        for topic in topicConversations.keys where wanted[topic] == nil {
            try? await node.unsubscribeSealed(topic: topic)
        }
        for (topic, topicKey) in topicKeys where topicConversations[topic] == nil {
            try? await node.subscribeSealed(topic: topic, key: topicKey)
        }
        topicConversations = wanted
        await node.refreshCampus()
    }

    // MARK: - Blocking
    //
    // On this device only: a blocked account's messages, likes and invites
    // are dropped, they leave Discover, and conversations with them are
    // deleted along with their keys.

    private static let blockedKey = "fratrat.blockedPeerIds"

    private static func loadBlocked() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? [])
    }

    private func saveBlocked() {
        UserDefaults.standard.set(Array(blockedPeerIds), forKey: Self.blockedKey)
    }

    @MainActor
    func block(_ peerId: String) async {
        blockedPeerIds.insert(peerId)
        saveBlocked()
        relationships[peerId] = .declined
        _ = saveRelationship(peerId: peerId, state: .declined)
        pendingLikes.removeValue(forKey: peerId)
        pendingInvites.removeValue(forKey: peerId)
        updateRequestCount()
        for (conversationId, member) in conversationPeers where member == peerId {
            deleteConversationKey(conversationId: conversationId)
            deleteConversation(conversationId: conversationId)
            conversationMessages[conversationId] = nil
            unreadCounts[conversationId] = nil
            conversationPeers[conversationId] = nil
        }
        await refreshConversationSubscriptions()
    }

    @MainActor
    func unblock(_ peerId: String) {
        blockedPeerIds.remove(peerId)
        saveBlocked()
        relationships[peerId] = RelationshipState.none
        _ = saveRelationship(peerId: peerId, state: .none)
    }

    // MARK: - Reporting

    enum ReportReason: String, CaseIterable, Identifiable {
        case harassment    = "Harassment or threats"
        case inappropriate = "Inappropriate photos or messages"
        case fake          = "Fake profile or spam"
        case underage      = "May be under 18"
        case other         = "Something else"

        var id: String { rawValue }
    }

    /// What a report carries. Nothing about the reporter: the relay sees an
    /// anonymous admission, and the moderator sees who was reported and why.
    private struct Report: Encodable {
        struct Profile: Encodable {
            let name, college, year, bio: String
            let photoUrls: [String]
            /// So a moderator can see the photos, which are encrypted.
            let photoKeys: [String]
        }
        struct Message: Encodable {
            let fromReported: Bool
            let text: String
            let timestamp: UInt64
        }
        let version = 1
        let reported: String
        let reason: String
        let details: String
        let profile: Profile?
        let messages: [Message]
    }

    /// Send a report through the anonymous upload path. The conversation's
    /// last messages go along only if the reporter chose to include them.
    /// Returns the report id to quote to support.
    @MainActor
    func report(
        _ peerId: String,
        reason: ReportReason,
        details: String,
        includeMessagesFrom conversationId: String?
    ) async throws -> String {
        let profile = peerProfiles[peerId].map {
            Report.Profile(
                name: $0.name, college: $0.college, year: $0.year, bio: $0.bio,
                photoUrls: $0.photoBlobIds,
                photoKeys: $0.photoBlobKeys.map { $0.base64EncodedString() }
            )
        }
        let recent = conversationId.map { self.messages(for: $0).suffix(20) } ?? []
        let report = Report(
            reported: peerId,
            reason:   reason.rawValue,
            details:  details,
            profile:  profile,
            messages: recent.map {
                Report.Message(
                    fromReported: !$0.isOwn,
                    text:         $0.text,
                    timestamp:    UInt64($0.timestamp.timeIntervalSince1970)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var payload = Data("==== FratRat report ====\n".utf8)
        payload.append(try encoder.encode(report))
        return try await uploadDebugLog(data: payload, grpcAddr: grpcAddr)
    }

    // MARK: - Deleting everything

    /// Erase this device's account: identity, credential, profile, photos,
    /// conversations and settings. Profiles and photos other people's phones
    /// already received stay with them until their caches expire.
    @MainActor
    func deleteAllData() async {
        await disconnect()
        identity = nil
        myPeerId = nil
        deleteAllLocalData()
        UserProfile.deleteLocal()
        UserDefaults.standard.removeObject(forKey: AppSettings.key)
        UserDefaults.standard.removeObject(forKey: Self.blockedKey)
        UserDefaults.standard.removeObject(forKey: DiscoverView.passedKey)
        blockedPeerIds = []
        LogCapture.shared.clear()
        dataDeleted = true
    }

    // MARK: - Relay discovery

    @MainActor
    func findRelays() async {
        connectionState = .discoveringRelays
        availableRelays = []

        // Bootstrap relays first, then relays cached from earlier runs.
        let network = await ZkrpNetwork.shared.refresh()
        if let url = ZkrpNetwork.shared.grpcURL { grpcAddr = url }
        let results = network?.relays ?? []
        Swift.print("[mesh] network directory: \(results.count) relays, stale=\(network?.stale ?? true)")

        if results.isEmpty {
            connectionState = .failed("Can't reach any relay. Check your connection.")
        } else {
            availableRelays = results.map {
                RelayInfoViewModel(
                    multiaddr: $0.multiaddr,
                    peerId:    $0.peerId,
                    region:    $0.region,
                    load:      Int($0.load),
                    meshes:    $0.meshes
                )
            }
            connectionState = .disconnected
        }
    }

    // MARK: - Connection

    @MainActor
    func connect(to relay: RelayInfoViewModel) async {
        if let existing = node {
            await existing.shutdown()
            node      = nil
            peerCount = 0
            connectedPeers = [:]
        }

        selectedRelay   = relay
        connectionState = .connecting(relay: relay.displayHost)

        do {
            let identity = NodeIdentity.loadOrGenerateDefault()
            let config   = TransportConfig(tcpPort: 0, quicPort: 0)
            let handler  = MeshEventBridge(manager: self)
            myPeerId     = identity.peerIdString()
            self.identity = identity

            node = try await MeshNode(
                identity:  identity,
                relayAddr: relay.multiaddr,
                config:    config,
                handler:   handler,
                profile:   loadCurrentProfile()
            )

            connectionState = .connected(relay: relay.displayHost)
            seedFromCache()

            topicConversations = [:]
            await refreshConversationSubscriptions()
            await fetchMissedMessages()
            rotationTask?.cancel()
            rotationTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                    await self?.refreshConversationSubscriptions()
                }
            }

            // Upload any photos that were saved during offline onboarding
            Task { await retryPendingPhotoUploads() }

        } catch {
            connectionState = .failed(error.localizedDescription)
            node = nil
        }
    }

    @MainActor
    func connectToBestRelay() async {
        // The network directory orders relays nearest first (measured from
        // this device), with load as the tie-breaker.
        guard let best = availableRelays.first else {
            connectionState = .failed("No relays available")
            return
        }
        await connect(to: best)
    }

    @MainActor
    func disconnect() async {
        rotationTask?.cancel()
        await node?.shutdown()
        node            = nil
        topicConversations = [:]
        connectionState = .disconnected
        peerCount       = 0
        connectedPeers  = [:]
        peerProfiles    = [:]
        parties         = [:]
        alerts          = [:]
        conversationMessages = [:]
        unreadCounts    = [:]
        conversationPeers = [:]
        relationships   = [:]
        pendingLikes    = [:]
        pendingInvites  = [:]
        pendingRequestCount = 0
    }

    // MARK: - Cache seeding

    @MainActor
    private func seedFromCache() {
        for profile in loadAllPeerProfiles() {
            peerProfiles[profile.peerId] = profile
        }
        let now = UInt64(Date().timeIntervalSince1970)
        for party in loadAllParties() where party.expires > now {
            parties[party.id] = party
        }
        for alert in loadAllAlerts() where alert.expires > now {
            alerts[alert.id] = alert
        }
        for conversationId in loadAllConversationIds() {
            let stored = loadMessages(conversationId: conversationId)
            if !stored.isEmpty {
                conversationMessages[conversationId] = stored.map { ChatMessage(stored: $0) }
            }
            // QR chats have no relationship record; their peer is whoever wrote.
            if let other = stored.first(where: { !$0.isOwn })?.senderPeerId {
                conversationPeers[conversationId] = other
            }
        }
        for rel in loadAllRelationships() {
            // A blocked account may have liked us again since; stay declined.
            guard !blockedPeerIds.contains(rel.peerId) else {
                relationships[rel.peerId] = .declined
                continue
            }
            relationships[rel.peerId] = rel.state
            switch rel.state {
            case .matched(let cid), .inviteSent(let cid), .inviteAccepted(let cid):
                conversationPeers[cid] = rel.peerId
            case .likedBy(let enc):
                pendingLikes[rel.peerId] = LikePayload(
                    conversationKeyEnc: enc,
                    senderPeerId:       rel.peerId,
                    timestamp:          0
                )
            case .inviteReceived(let convId, let fromName, let enc):
                pendingInvites[rel.peerId] = InvitePayload(
                    conversationId:     convId,
                    conversationKeyEnc: enc,
                    senderName:         fromName,
                    senderPeerId:       rel.peerId,
                    timestamp:          0
                )
            default: break
            }
        }
        pendingRequestCount = pendingLikes.count + pendingInvites.count
        Swift.print("[mesh] seeded: \(peerProfiles.count) profiles, \(parties.count) parties, \(alerts.count) alerts, \(conversationMessages.count) conversations, \(relationships.count) relationships")
    }

    // MARK: - Photo encryption helpers

    private func encryptPhoto(_ data: Data) throws -> (ciphertext: Data, key: Data) {
        let symmetricKey = SymmetricKey(size: .bits256)
        let sealed       = try ChaChaPoly.seal(data, using: symmetricKey)
        let keyBytes     = symmetricKey.withUnsafeBytes { Data($0) }
        return (sealed.combined, keyBytes)
    }

    private func decryptPhoto(_ ciphertext: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let box          = try ChaChaPoly.SealedBox(combined: ciphertext)
        return try ChaChaPoly.open(box, using: symmetricKey)
    }

    // MARK: - Blob / photo storage

    /// Encrypt and upload a photo. Returns the CloudFront URL and the
    /// symmetric key needed to decrypt it. The key is stored in the
    /// user's PeerProfile so mesh peers can decrypt the photo.
    @MainActor
    func uploadPhoto(_ data: Data) async throws -> (url: String, key: Data) {
        let (ciphertext, key) = try encryptPhoto(data)
        let url = try await uploadPhotoBlob(
            data:     ciphertext,
            grpcAddr: grpcAddr,
        )
        return (url, key)
    }

    /// Download and decrypt a photo from CloudFront.
    @MainActor
    func retrievePhoto(url: String, key: Data) async throws -> Data {
        guard let cfUrl = URL(string: url) else { throw MeshUploadError.notConnected }
        let (ciphertext, resp) = try await URLSession.shared.data(from: cfUrl)
        guard let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MeshUploadError.notConnected
        }
        return try decryptPhoto(ciphertext, key: key)
    }

    /// Fetch an unencrypted blob from the legacy mesh P2P blob store.
    /// Used for profiles uploaded before the S3/CloudFront migration.
    @MainActor
    func retrievePhotoLegacy(blobId: String) async throws -> Data {
        guard let node else { throw MeshUploadError.notConnected }
        return try await node.retrievePhoto(blobId: blobId)
    }

    /// Upload captured client logs to the relay via the dedicated Logging
    /// gRPC service (streaming UploadDebugLog). Returns the log_id.
    @MainActor
    func uploadLogs(_ data: Data) async throws -> String {
        // Nothing that identifies the account or the time: the log id the
        // user reads back to us is the only link.
        let header = """
        ==== FratRat client log ====
        bytes: \(data.count)
        ============================

        """
        var payload = Data(header.utf8)
        payload.append(data)

        // Calls the Logging.UploadDebugLog streaming RPC through the FFI.
        do {
            let logId = try await uploadDebugLog(
                data:     payload,
                grpcAddr: grpcAddr
            )
            LogCapture.shared.log("[upload] success id=\(logId)")
            return logId
        } catch {
            // `error` is bound implicitly in a Swift catch block
            LogCapture.shared.log("[upload] FAILED: \(error)")
            LogCapture.shared.log("[upload] localizedDescription: \(error.localizedDescription)")
            throw error   // or return nil / handle, depending on the signature
        }
    }

    /// Upload any photos that were saved locally but not yet uploaded
    /// (e.g. the user completed onboarding without an internet connection).
    /// Called automatically after a successful relay connection.
    private func retryPendingPhotoUploads() async {
        var profile = UserProfile.load()
        guard profile.hasPendingUploads else { return }

        var cfUrls = profile.photoURLs
        var keys   = profile.photoKeys

        for filename in profile.localPhotoFilenames.dropFirst(cfUrls.count) {
            guard let data = ImageStore.data(for: filename) else { continue }
            if let result = try? await uploadPhoto(data) {
                cfUrls.append(result.url)
                keys.append(result.key)
            }
        }

        guard cfUrls.count > profile.photoURLs.count else { return }

        await MainActor.run {
            profile.photoURLs = cfUrls
            profile.photoKeys = keys
            profile.save()
        }
        await announceProfile()
        Swift.print("[mesh] retried photo uploads: \(cfUrls.count) total")
    }

    // MARK: - Messaging

    /// Encrypt and publish a chat message. Returns false if it couldn't be sent.
    @MainActor
    @discardableResult
    func send(_ text: String, conversationId: String) async -> Bool {
        guard let myPeerId,
              let msg = await publish(text, conversationId: conversationId, from: myPeerId)
        else { return false }
        _ = saveMessage(message: msg.toStored())
        appendIfNew(msg, to: conversationId)
        return true
    }

    /// Tell a QR-invite's creator who just joined. Not shown as a message.
    @MainActor
    func announceJoined(conversationId: String, name: String) async {
        guard let myPeerId else { return }
        _ = await publish(Self.joinedPrefix + name, conversationId: conversationId, from: myPeerId)
    }

    @MainActor
    private func publish(_ text: String, conversationId: String, from myPeerId: String) async -> ChatMessage? {
        guard let node, let key = loadConversationKey(conversationId: conversationId) else { return nil }
        let msg = ChatMessage(text: text, isOwn: true, conversationId: conversationId, senderPeerId: myPeerId)
        do {
            let wire   = try JSONEncoder().encode(WireMessage(msg))
            let sealed = try sealForConversation(key: key, conversationId: conversationId, plaintext: wire)
            let topic  = try conversationSendTopic(key: key)
            try await node.sendRaw(topic: topic, payload: sealed)
            // Also leave it on the relay for when they're offline. The live
            // copy is already out, so a failed deposit doesn't fail the send.
            let grpcAddr = self.grpcAddr
            Task.detached {
                do {
                    try await depositForConversation(grpcAddr: grpcAddr, key: key, sealed: sealed)
                } catch {
                    Swift.print("[chat] deposit failed: \(error)")
                }
            }
            return msg
        } catch {
            Swift.print("[chat] send failed: \(error)")
            return nil
        }
    }

    /// What travels, sealed, in a conversation. Live messages are attributed
    /// to the account that signed them. Messages fetched from a relay mailbox
    /// carry no signature, so `from` (sealed, so only a key holder can set it)
    /// stands in, and only where the conversation's member is already known
    /// or this is how we learn it.
    private struct WireMessage: Codable {
        let messageId: String
        let text:      String
        let timestamp: UInt64
        let from:      String?

        init(_ msg: ChatMessage) {
            messageId = msg.id
            text      = msg.text
            timestamp = UInt64(msg.timestamp.timeIntervalSince1970)
            from      = msg.senderPeerId
        }
    }

    // MARK: - Profile helpers

    @MainActor
    func announceProfile() async {
        try? await node?.announceProfile(profile: loadCurrentProfile())
    }

    @MainActor
    func replyWithProfile(to peerId: String) async {
        try? await node?.replyWithProfile(profile: loadCurrentProfile(), toPeerId: peerId)
    }

    private func loadCurrentProfile() -> PeerProfile {
        if let saved = loadUserProfile() { return saved }
        return PeerProfile(
            peerId:        NodeIdentity.loadOrGenerateDefault().peerIdString(),
            name:          "",
            college:       "",
            year:          "",
            bio:           "",
            photoBlobIds:  [],
            photoBlobKeys: [],
            timestamp:     UInt64(Date().timeIntervalSince1970)
        )
    }

    // MARK: - Relationship guards

    func canLike(_ peerId: String) -> Bool {
        FratRat.canLike(peerId: peerId)
    }

    func canInvite(_ peerId: String) -> Bool {
        FratRat.canInvite(peerId: peerId)
    }

    // MARK: - Like flow

    @MainActor
    func sendLike(to peerId: String) async {
        guard canLike(peerId), let identity else {
            Swift.print("[like] guard: cannot like \(peerId)")
            return
        }
        let conversationKey = generateConversationKey()
        guard let encryptedKey = try? identity.encryptForPeer(
            plaintext: conversationKey,
            peerId:    peerId
        ) else {
            Swift.print("[like] encrypt failed for peer \(peerId)")
            return
        }
        let payload = LikePayload(
            conversationKeyEnc: encryptedKey,
            senderPeerId:       myPeerId ?? "",
            timestamp:          UInt64(Date().timeIntervalSince1970)
        )
        try? await node?.sendLike(toPeerId: peerId, payload: payload)
        let state = RelationshipState.liked
        relationships[peerId] = state
        _ = saveRelationship(peerId: peerId, state: state)
        Swift.print("[like] ✓ sent to \(peerId)")
    }

    @MainActor
    func sendLikeBack(to peerId: String, like: LikePayload) async {
        guard let identity else { return }
        let encBytes = Data(like.conversationKeyEnc)
        guard let conversationKey = try? identity.decrypt(ciphertext: encBytes) else {
            Swift.print("[like] decrypt failed for like from \(peerId)")
            return
        }
        guard let reEncryptedKey = try? identity.encryptForPeer(
            plaintext: conversationKey,
            peerId:    peerId
        ) else {
            Swift.print("[like] re-encrypt failed for peer \(peerId)")
            return
        }
        let conversationId = UUID().uuidString.lowercased()
        let payload = LikeBackPayload(
            conversationId:     conversationId,
            conversationKeyEnc: reEncryptedKey,
            senderPeerId:       myPeerId ?? "",
            timestamp:          UInt64(Date().timeIntervalSince1970)
        )
        try? await node?.sendLikeBack(toPeerId: peerId, payload: payload)
        let state = RelationshipState.matched(conversationId: conversationId)
        relationships[peerId] = state
        _ = saveRelationship(peerId: peerId, state: state)
        pendingLikes.removeValue(forKey: peerId)
        updateRequestCount()
        await openConversation(conversationId, key: conversationKey, peerId: peerId)
        Swift.print("[like] ✓ matched with \(peerId) conversation=\(conversationId)")
    }

    @MainActor
    func declineLike(from peerId: String) async {
        try? await node?.sendLikeDeclined(toPeerId: peerId)
        relationships[peerId] = .declined
        _ = saveRelationship(peerId: peerId, state: .declined)
        pendingLikes.removeValue(forKey: peerId)
        updateRequestCount()
    }

    // MARK: - Direct invite flow

    @MainActor
    func sendInvite(to peerId: String, conversationId: String) async {
        guard canInvite(peerId), let identity else {
            Swift.print("[invite] guard: cannot invite \(peerId)")
            return
        }
        let conversationKey = generateConversationKey()
        guard let encryptedKey = try? identity.encryptForPeer(
            plaintext: conversationKey,
            peerId:    peerId
        ) else {
            Swift.print("[invite] encrypt failed for peer \(peerId)")
            return
        }
        let senderName = loadUserProfile()?.name ?? "Someone"
        let payload = InvitePayload(
            conversationId:     conversationId,
            conversationKeyEnc: encryptedKey,
            senderName:         senderName,
            senderPeerId:       myPeerId ?? "",
            timestamp:          UInt64(Date().timeIntervalSince1970)
        )
        try? await node?.sendInvite(toPeerId: peerId, payload: payload)
        let state = RelationshipState.inviteSent(conversationId: conversationId)
        relationships[peerId] = state
        _ = saveRelationship(peerId: peerId, state: state)
        await openConversation(conversationId, key: conversationKey, peerId: peerId)
        Swift.print("[invite] ✓ sent to \(peerId) conversationId=\(conversationId)")
    }

    @MainActor
    func acceptInvite(from peerId: String, conversationId: String) async {
        guard let identity, let invite = pendingInvites[peerId],
              let conversationKey = try? identity.decrypt(ciphertext: invite.conversationKeyEnc)
        else {
            Swift.print("[invite] can't read the key for this invite")
            return
        }
        let payload = InviteAcceptPayload(
            conversationId: conversationId,
            acceptorPeerId: myPeerId ?? "",
            timestamp:      UInt64(Date().timeIntervalSince1970)
        )
        try? await node?.sendInviteAccept(toPeerId: peerId, payload: payload)
        let state = RelationshipState.inviteAccepted(conversationId: conversationId)
        relationships[peerId] = state
        _ = saveRelationship(peerId: peerId, state: state)
        pendingInvites.removeValue(forKey: peerId)
        updateRequestCount()
        await openConversation(conversationId, key: conversationKey, peerId: peerId)
        Swift.print("[invite] ✓ accepted from \(peerId) conversationId=\(conversationId)")
    }

    @MainActor
    func declineInvite(from peerId: String) async {
        try? await node?.sendInviteDecline(toPeerId: peerId)
        relationships[peerId] = .declined
        _ = saveRelationship(peerId: peerId, state: .declined)
        pendingInvites.removeValue(forKey: peerId)
        updateRequestCount()
    }

    @MainActor
    private func updateRequestCount() {
        pendingRequestCount = pendingLikes.count + pendingInvites.count
    }

    // MARK: - Cache management

    @MainActor
    func clearCache() async {
        rotationTask?.cancel()
        await node?.shutdown()
        node = nil
        clearAllCaches()
        peerProfiles         = [:]
        parties              = [:]
        alerts               = [:]
        conversationMessages = [:]
        unreadCounts         = [:]
        conversationPeers    = [:]
        topicConversations   = [:]
        relationships        = [:]
        pendingLikes         = [:]
        pendingInvites       = [:]
        pendingRequestCount  = 0
        connectedPeers       = [:]
        peerCount            = 0
        connectionState      = .disconnected
        Swift.print("[mesh] all caches cleared")
    }

    @MainActor
    func postParty(_ party: PartyProfile) async {
        parties[party.id] = party
        try? await node?.announceParty(party: party)
    }

    @MainActor
    func postAlert(_ alert: AlertProfile) async {
        alerts[alert.id] = alert
        try? await node?.announceAlert(alert: alert)
    }

    // MARK: - Conversation helpers

    @MainActor
    func markRead(peerId: String) {
        unreadCounts[peerId] = 0
    }

    func messages(for peerId: String) -> [ChatMessage] {
        (conversationMessages[peerId] ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Callbacks from MeshEventBridge

    @MainActor
    func handleProfileReceived(_ profile: PeerProfile) {
        Swift.print("[profile] ✓ received from \(profile.peerId) name='\(profile.name)'")
        peerProfiles[profile.peerId] = profile
        _ = savePeerProfile(profile: profile)
    }

    @MainActor
    func handleProfilesBackfilled(_ profiles: [PeerProfile]) {
        for profile in profiles {
            if let existing = peerProfiles[profile.peerId] {
                guard profile.timestamp > existing.timestamp else { continue }
            }
            peerProfiles[profile.peerId] = profile
        }
        Swift.print("[mesh] backfilled \(profiles.count) profiles")
    }

    @MainActor
    func handlePartyReceived(_ party: PartyProfile) {
        let now = UInt64(Date().timeIntervalSince1970)
        guard party.expires > now else { return }
        parties[party.id] = party
        banner = BannerEvent(kind: .party, title: "Party Alert",
                             body: "\(party.host) posted: \(party.title)")
    }

    @MainActor
    func handlePartiesBackfilled(_ incoming: [PartyProfile]) {
        let now = UInt64(Date().timeIntervalSince1970)
        for party in incoming {
            guard party.expires > now else { continue }
            if let existing = parties[party.id], party.timestamp <= existing.timestamp { continue }
            parties[party.id] = party
        }
    }

    @MainActor
    func handleAlertReceived(_ alert: AlertProfile) {
        let now = UInt64(Date().timeIntervalSince1970)
        guard alert.expires > now else { return }
        alerts[alert.id] = alert
        banner = BannerEvent(kind: .party, title: "⚠️ \(alert.name)",
                             body: alert.description.isEmpty ? "Nearby safety alert" : alert.description)

        let alertLocation = CLLocation(latitude: alert.lat, longitude: alert.lon)

        if alert.alertType == .security {
            if let userLoc = userLocation {
                let feet = userLoc.distance(from: alertLocation) * 3.28084
                if feet <= 500 {
                    Haptic.securityAlert()
                    return
                }
            }
            // Security but no location or out of range
            Haptic.notification(.error)
        } else {
            Haptic.notification(.warning)
        }
    }

    @MainActor
    func handleAlertsBackfilled(_ incoming: [AlertProfile]) {
        let now = UInt64(Date().timeIntervalSince1970)
        for alert in incoming {
            guard alert.expires > now else { continue }
            if let existing = alerts[alert.id], alert.timestamp <= existing.timestamp { continue }
            alerts[alert.id] = alert
        }
    }

    @MainActor
    func handleMessage(senderPeerId: String, topic: String, payload: Data) {
        guard let conversationId = topicConversations[topic] else { return }
        receive(payload, conversationId: conversationId, signer: senderPeerId)
    }

    /// Fetch what relays held for every conversation while we were away.
    @MainActor
    func fetchMissedMessages() async {
        guard node != nil else { return }
        for conversationId in loadAllConversationKeyIds() {
            guard let key = loadConversationKey(conversationId: conversationId) else { continue }
            do {
                let held = try await fetchForConversation(
                    grpcAddr: grpcAddr, conversationId: conversationId, key: key
                )
                for sealed in held {
                    receive(sealed, conversationId: conversationId, signer: nil, quietly: true)
                }
            } catch {
                Swift.print("[chat] fetch failed: \(error)")
            }
        }
    }

    /// Open and record one sealed message. `signer` is the account that
    /// signed a live message; nil for one fetched from a relay mailbox.
    @MainActor
    private func receive(_ sealed: Data, conversationId: String, signer: String?, quietly: Bool = false) {
        guard let key = loadConversationKey(conversationId: conversationId),
              let plaintext = try? openForConversation(key: key, conversationId: conversationId, sealed: sealed),
              let wire = try? JSONDecoder().decode(WireMessage.self, from: plaintext),
              let senderPeerId = signer ?? wire.from ?? conversationPeers[conversationId],
              senderPeerId != myPeerId,
              !blockedPeerIds.contains(senderPeerId)
        else { return }

        // Only the other member may write to a conversation. A QR chat's
        // creator learns who that is from the joiner's first message.
        if let expected = conversationPeers[conversationId] {
            guard senderPeerId == expected else { return }
        } else {
            conversationPeers[conversationId] = senderPeerId
        }

        if wire.text.hasPrefix(Self.joinedPrefix) {
            let name = String(wire.text.dropFirst(Self.joinedPrefix.count))
            if peerProfiles[senderPeerId] == nil, !name.isEmpty {
                peerProfiles[senderPeerId] = PeerProfile(
                    peerId:        senderPeerId,
                    name:          name,
                    college:       "",
                    year:          "",
                    bio:           "",
                    photoBlobIds:  [],
                    photoBlobKeys: [],
                    timestamp:     0
                )
            }
            return
        }

        let stored = StoredMessage(
            messageId:      wire.messageId,
            conversationId: conversationId,
            senderPeerId:   senderPeerId,
            text:           wire.text,
            timestamp:      wire.timestamp,
            isOwn:          false
        )
        let msg = ChatMessage(stored: stored)
        guard conversationMessages[conversationId]?.contains(msg) != true else { return }
        _ = saveMessage(message: stored)
        appendIfNew(msg, to: conversationId)
        guard !quietly else { return }
        let name = peerProfiles[senderPeerId]?.displayName ?? "New message"
        banner = BannerEvent(kind: .message, title: name, body: wire.text)
    }

    private func appendIfNew(_ msg: ChatMessage, to conversationId: String) {
        var bucket = conversationMessages[conversationId] ?? []
        guard !bucket.contains(where: { $0.id == msg.id }) else { return }
        bucket.append(msg)
        bucket.sort { $0.timestamp < $1.timestamp }
        conversationMessages[conversationId] = bucket
        if !msg.isOwn {
            unreadCounts[conversationId, default: 0] += 1
        }
    }

    @MainActor
    func handleLikeReceived(_ payload: LikePayload) {
        guard !blockedPeerIds.contains(payload.senderPeerId) else { return }
        let state = RelationshipState.likedBy(conversationKeyEnc: payload.conversationKeyEnc)
        relationships[payload.senderPeerId] = state
        _ = saveRelationship(peerId: payload.senderPeerId, state: state)
        pendingLikes[payload.senderPeerId] = payload
        updateRequestCount()
        banner = BannerEvent(kind: .like, title: "New Like",
                             body: peerProfiles[payload.senderPeerId]?.displayName ?? "Someone liked you")
        Swift.print("[like] ✓ received from \(payload.senderPeerId)")
    }

    @MainActor
    func handleLikeBackReceived(_ payload: LikeBackPayload) {
        let state = RelationshipState.matched(conversationId: payload.conversationId)
        relationships[payload.senderPeerId] = state
        _ = saveRelationship(peerId: payload.senderPeerId, state: state)
        pendingLikes.removeValue(forKey: payload.senderPeerId)
        updateRequestCount()
        // They re-encrypted our conversation key to us when they liked back.
        if let identity, let key = try? identity.decrypt(ciphertext: payload.conversationKeyEnc) {
            Task { await openConversation(payload.conversationId, key: key, peerId: payload.senderPeerId) }
        }
        Haptic.notification(.success)
        Swift.print("[like] ✓ matched with \(payload.senderPeerId) conversation=\(payload.conversationId)")
    }

    @MainActor
    func handleLikeDeclined(_ peerId: String) {
        relationships[peerId] = .declined
        _ = saveRelationship(peerId: peerId, state: .declined)
        Swift.print("[like] declined by \(peerId)")
    }

    @MainActor
    func handleInviteReceived(_ payload: InvitePayload) {
        guard !blockedPeerIds.contains(payload.senderPeerId) else { return }
        let state = RelationshipState.inviteReceived(
            conversationId:     payload.conversationId,
            fromName:           payload.senderName,
            conversationKeyEnc: payload.conversationKeyEnc
        )
        relationships[payload.senderPeerId] = state
        _ = saveRelationship(peerId: payload.senderPeerId, state: state)
        pendingInvites[payload.senderPeerId] = payload
        updateRequestCount()
        banner = BannerEvent(kind: .invite, title: "Direct Invite",
                             body: "\(payload.senderName) invited you to chat")
        Swift.print("[invite] ✓ received from \(payload.senderName)")
    }

    @MainActor
    func handleInviteAccepted(_ payload: InviteAcceptPayload) {
        let state = RelationshipState.inviteAccepted(conversationId: payload.conversationId)
        relationships[payload.acceptorPeerId] = state
        _ = saveRelationship(peerId: payload.acceptorPeerId, state: state)
        conversationPeers[payload.conversationId] = payload.acceptorPeerId
        Swift.print("[invite] ✓ accepted by \(payload.acceptorPeerId)")
    }

    @MainActor
    func handleInviteDeclined(_ peerId: String) {
        relationships[peerId] = .declined
        _ = saveRelationship(peerId: peerId, state: .declined)
        Swift.print("[invite] declined by \(peerId)")
    }

    @MainActor
    func handlePeerConnected(_ peerId: String) {
        Swift.print("[mesh] ✓ peer connected: \(peerId)")
        peerCount += 1
        connectedPeers[peerId] = Date()
    }

    @MainActor
    func handlePeerDisconnected(_ peerId: String) {
        peerCount = max(0, peerCount - 1)
        connectedPeers.removeValue(forKey: peerId)
    }

    @MainActor
    func handleConnectionStatus(_ status: String) {
        switch status {
        case "disconnected":
            connectionState = .disconnected
        case "connecting":
            break
        case let s where s.hasPrefix("connected:"):
            connectionState = .connected(relay: String(s.dropFirst("connected:".count)))
        case let s where s.hasPrefix("degraded:"):
            connectionState = .failed(String(s.dropFirst("degraded:".count)))
        default:
            break
        }
    }

    @MainActor
    func handleSendFailed(conversation: String) {}
}

// MARK: - RelayInfoViewModel

struct RelayInfoViewModel: Identifiable, Equatable {
    let id        = UUID()
    let multiaddr: String
    let peerId:    String
    let region:    String
    let load:      Int
    let meshes:    [String]

    var displayHost: String {
        let parts = multiaddr.split(separator: "/")
        if let ipIdx = parts.firstIndex(of: "ip4"), parts.count > Int(ipIdx) + 1 {
            return String(parts[Int(ipIdx) + 1])
        }
        if let dnsIdx = parts.firstIndex(of: "dns4"), parts.count > Int(dnsIdx) + 1 {
            return String(parts[Int(dnsIdx) + 1])
        }
        return multiaddr
    }

    var shortPeerId: String { String(peerId.prefix(12)) + "…" }
}

// MARK: - MeshUploadError

enum MeshUploadError: Error, LocalizedError {
    case notConnected
    var errorDescription: String? { "Not connected to the mesh" }
}

// MARK: - BannerEvent

struct BannerEvent: Identifiable {
    let id    = UUID()
    let kind:  BannerKind
    let title: String
    let body:  String

    enum BannerKind {
        case message, like, invite, party

        var icon: String {
            switch self {
            case .message: return "message.fill"
            case .like:    return "heart.fill"
            case .invite:  return "envelope.fill"
            case .party:   return "music.note"
            }
        }

        var color: Color {
            switch self {
            case .message: return .fratPink
            case .like:    return .pink
            case .invite:  return Color(red: 0.4, green: 0.3, blue: 0.9)
            case .party:   return Color(red: 0.2, green: 0.7, blue: 0.4)
            }
        }

        var tab: Tab {
            switch self {
            case .message: return .messages
            case .like:    return .messages
            case .invite:  return .messages
            case .party:   return .parties
            }
        }
    }
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable {
    let id:             String
    let text:           String
    let isOwn:          Bool
    let timestamp:      Date
    let senderPeerId:   String
    let conversationId: String

    init(stored: StoredMessage) {
        self.id             = stored.messageId
        self.text           = stored.text
        self.isOwn          = stored.isOwn
        self.timestamp      = Date(timeIntervalSince1970: TimeInterval(stored.timestamp))
        self.senderPeerId   = stored.senderPeerId
        self.conversationId = stored.conversationId
    }

    init(text: String, isOwn: Bool, conversationId: String, senderPeerId: String) {
        self.id             = UUID().uuidString
        self.text           = text
        self.isOwn          = isOwn
        self.timestamp      = Date()
        self.senderPeerId   = senderPeerId
        self.conversationId = conversationId
    }

    func toStored() -> StoredMessage {
        StoredMessage(
            messageId:      id,
            conversationId: conversationId,
            senderPeerId:   senderPeerId,
            text:           text,
            timestamp:      UInt64(timestamp.timeIntervalSince1970),
            isOwn:          isOwn
        )
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool { lhs.id == rhs.id }
}

// MARK: - MeshEventBridge

private class MeshEventBridge: SwiftEventHandler {

    private weak var manager: MeshManager?
    init(manager: MeshManager) { self.manager = manager }

    func onProfileReceived(profile: PeerProfile) {
        Task { @MainActor [weak manager] in manager?.handleProfileReceived(profile) }
    }
    func onProfilesBackfilled(profiles: [PeerProfile]) {
        Task { @MainActor [weak manager] in manager?.handleProfilesBackfilled(profiles) }
    }
    func onPartyReceived(party: PartyProfile) {
        Task { @MainActor [weak manager] in manager?.handlePartyReceived(party) }
    }
    func onPartiesBackfilled(parties: [PartyProfile]) {
        Task { @MainActor [weak manager] in manager?.handlePartiesBackfilled(parties) }
    }
    func onAlertReceived(alert: AlertProfile) {
        Task { @MainActor [weak manager] in manager?.handleAlertReceived(alert) }
    }
    func onAlertsBackfilled(alerts: [AlertProfile]) {
        Task { @MainActor [weak manager] in manager?.handleAlertsBackfilled(alerts) }
    }
    func onLikeReceived(payload: LikePayload) {
        Task { @MainActor [weak manager] in manager?.handleLikeReceived(payload) }
    }
    func onLikeBackReceived(payload: LikeBackPayload) {
        Task { @MainActor [weak manager] in manager?.handleLikeBackReceived(payload) }
    }
    func onLikeDeclined(peerId: String) {
        Task { @MainActor [weak manager] in manager?.handleLikeDeclined(peerId) }
    }
    func onInviteReceived(payload: InvitePayload) {
        Task { @MainActor [weak manager] in manager?.handleInviteReceived(payload) }
    }
    func onInviteAccepted(payload: InviteAcceptPayload) {
        Task { @MainActor [weak manager] in manager?.handleInviteAccepted(payload) }
    }
    func onInviteDeclined(peerId: String) {
        Task { @MainActor [weak manager] in manager?.handleInviteDeclined(peerId) }
    }
    func onMessage(peerId senderPeerId: String, conversation: String, payload: Data, contentType: UInt16) {
        Task { @MainActor [weak manager] in
            manager?.handleMessage(senderPeerId: senderPeerId, topic: conversation, payload: payload)
        }
    }
    func onPeerConnected(peerId: String) {
        Task { @MainActor [weak manager] in manager?.handlePeerConnected(peerId) }
    }
    func onPeerDisconnected(peerId: String) {
        Task { @MainActor [weak manager] in manager?.handlePeerDisconnected(peerId) }
    }
    func onConnectionStatus(status: String) {
        Task { @MainActor [weak manager] in manager?.handleConnectionStatus(status) }
    }
    func onSendFailed(conversation: String) {
        Task { @MainActor [weak manager] in manager?.handleSendFailed(conversation: conversation) }
    }
}
