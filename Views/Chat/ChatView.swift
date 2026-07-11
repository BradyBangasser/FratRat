//
//  ChatView.swift
//  FratRat
//

import SwiftUI

struct ChatView: View {
    let match: Match
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss

    @State private var inputText      = ""
    @State private var localMessages: [ChatMessage] = []
    @FocusState private var inputFocused: Bool
    @State private var showProfileSheet = false

    private var conversationTopic: String {
        if mesh.isInviteConversation(match.peerId) {
            return "fratrat/v1/invite/\(match.peerId)"
        }
        let a = mesh.myPeerId ?? "local"
        let b = match.peerId
        return "fratrat/v1/dm/\(min(a, b))/\(max(a, b))"
    }

    private var isOnline: Bool {
        mesh.connectedPeers[match.peerId] != nil || mesh.isInviteConversation(match.peerId)
    }

    private var profile: PeerProfile? { mesh.peerProfiles[match.peerId] }

    // First photo and its key — both required to decrypt
    private var firstBlobId:  String? { profile?.photoBlobIds.first }
    private var firstBlobKey: Data?   { profile?.photoBlobKeys.first }

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(spacing: 0) {
                ChatNavBar(
                    name:     profile?.displayName ?? match.name,
                    subtitle: profile.map { "\($0.college) · \($0.year)" },
                    isOnline: isOnline,
                    blobId:   firstBlobId,
                    blobKey:  firstBlobKey,
                    initials: profile?.avatarInitials ?? match.avatarInitials,
                    onBack:        { dismiss() },
                    onTapProfile:  { showProfileSheet = true }
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if localMessages.isEmpty {
                                EmptyChatState(
                                    name:    profile?.displayName ?? match.name,
                                    blobId:  firstBlobId,
                                    blobKey: firstBlobKey,
                                    initials: profile?.avatarInitials ?? match.avatarInitials
                                )
                                .padding(.top, 50)
                            } else {
                                ForEach(groupedMessages, id: \.0) { dateLabel, msgs in
                                    DateDivider(label: dateLabel)
                                        .padding(.top, 14)
                                        .padding(.bottom, 6)

                                    ForEach(Array(msgs.enumerated()), id: \.element.id) { idx, msg in
                                        let showTail = idx == msgs.count - 1
                                            || msgs[idx + 1].isOwn != msg.isOwn
                                        MessageBubble(message: msg, showTail: showTail)
                                            .id(msg.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: localMessages) { _ in
                        if let last = localMessages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let last = localMessages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                if !isOnline { OfflineBanner() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InputBar(
                text:        $inputText,
                placeholder: "Message \((profile?.displayName ?? match.name))…",
                isFocused:   $inputFocused,
                onSend:      sendMessage
            )
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showProfileSheet) {
            ChatProfileSheet(
                name:     profile?.displayName ?? match.name,
                college:  profile?.college,
                year:     profile?.year,
                bio:      profile?.bio,
                blobId:   firstBlobId,
                blobKey:  firstBlobKey,
                initials: profile?.avatarInitials ?? match.avatarInitials
            )
            .presentationDetents([.medium])
        }
        .onReceive(mesh.$conversationMessages) { all in
            let incoming = all[match.peerId] ?? []
            let newOnes  = incoming.filter { msg in
                !localMessages.contains(where: { $0.id == msg.id })
            }
            if !newOnes.isEmpty { localMessages.append(contentsOf: newOnes) }
        }
        .task {
            try? await mesh.subscribe(topic: conversationTopic)
            localMessages = mesh.messages(for: match.peerId)
            mesh.markRead(peerId: match.peerId)
        }
        .onDisappear {
            mesh.markRead(peerId: match.peerId)
        }
    }

    private var groupedMessages: [(String, [ChatMessage])] {
        let calendar = Calendar.current
        let grouped  = Dictionary(grouping: localMessages) { msg in
            calendar.startOfDay(for: msg.timestamp)
        }
        return grouped.keys.sorted().map { day in
            (day.dayLabel, grouped[day] ?? [])
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await mesh.send(text, topic: conversationTopic) }
    }
}

// MARK: - Chat nav bar

private struct ChatNavBar: View {
    let name:         String
    let subtitle:     String?
    let isOnline:     Bool
    let blobId:       String?
    let blobKey:      Data?
    let initials:     String
    let onBack:       () -> Void
    let onTapProfile: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.fratDark)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.fratBg))
            }

            Button(action: onTapProfile) {
                HStack(spacing: 10) {
                    MeshImage.circle(
                        blobId:   blobId,
                        blobKey:  blobKey,
                        initials: initials,
                        size:     38
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.fratBold(16))
                            .foregroundColor(.fratDark)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isOnline ? Color.green : Color.fratGray)
                                .frame(width: 6, height: 6)
                            Text(isOnline ? "Online" : (subtitle ?? "Offline"))
                                .font(.fratBody(12))
                                .foregroundColor(.fratGray)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.fratCard)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Empty chat state

private struct EmptyChatState: View {
    let name:     String
    let blobId:   String?
    let blobKey:  Data?
    let initials: String

    var body: some View {
        VStack(spacing: 14) {
            MeshImage.circle(
                blobId:   blobId,
                blobKey:  blobKey,
                initials: initials,
                size:     72
            )
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)

            VStack(spacing: 4) {
                Text(name)
                    .font(.fratBold(20))
                    .foregroundColor(.fratDark)
                Text("Say hi 👋 — be the first to break the ice.")
                    .font(.fratBody(14))
                    .foregroundColor(.fratGray)
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text("End-to-end encrypted over the mesh").font(.fratBody(12))
            }
            .foregroundColor(.fratGray)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.fratCard))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

// MARK: - Date divider

private struct DateDivider: View {
    let label: String
    var body: some View {
        HStack {
            Spacer()
            Text(label)
                .font(.fratSemi(11))
                .foregroundColor(.fratGray)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.fratCard))
            Spacer()
        }
    }
}

// MARK: - Offline banner

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 12))
            Text("Peer is offline — messages will be queued and retried")
                .font(.fratBody(12))
        }
        .foregroundColor(.fratGray)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.fratCard)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Input bar

private struct InputBar: View {
    @Binding var text: String
    let placeholder:   String
    var isFocused:     FocusState<Bool>.Binding
    let onSend:        () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.fratBody(15))
                .lineLimit(1...5)
                .focused(isFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratBg))

            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(canSend ? Color.fratPink : Color.fratGray.opacity(0.3))
                        .frame(width: 38, height: 38)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.fratCard)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message:  ChatMessage
    var showTail: Bool = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isOwn { Spacer(minLength: 50) }

            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.fratBody(15))
                    .foregroundColor(message.isOwn ? .white : .fratDark)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(bubbleShape.fill(message.isOwn ? Color.fratPink : Color.fratCard))

                if showTail {
                    Text(message.timestamp.shortTime)
                        .font(.fratBody(10))
                        .foregroundColor(.fratGray)
                        .padding(.horizontal, 6).padding(.bottom, 2)
                }
            }

            if !message.isOwn { Spacer(minLength: 50) }
        }
        .padding(.vertical, 1)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let tailCorner: CGFloat = showTail ? 4 : 18
        if message.isOwn {
            return UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 18,
                bottomTrailingRadius: tailCorner, topTrailingRadius: 18
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: tailCorner,
                bottomTrailingRadius: 18, topTrailingRadius: 18
            )
        }
    }
}

// MARK: - Chat profile sheet

private struct ChatProfileSheet: View {
    let name:     String
    let college:  String?
    let year:     String?
    let bio:      String?
    let blobId:   String?
    let blobKey:  Data?
    let initials: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()
            VStack(spacing: 18) {
                Capsule().fill(Color.fratGray.opacity(0.3))
                    .frame(width: 36, height: 4).padding(.top, 10)

                MeshImage.circle(
                    blobId:   blobId,
                    blobKey:  blobKey,
                    initials: initials,
                    size:     96
                )
                .shadow(color: .black.opacity(0.1), radius: 12, y: 6)

                VStack(spacing: 4) {
                    Text(name).font(.fratBold(22)).foregroundColor(.fratDark)
                    if let college, let year, !college.isEmpty {
                        Text("\(college) · \(year)")
                            .font(.fratBody(14)).foregroundColor(.fratGray)
                    }
                }

                if let bio, !bio.isEmpty {
                    Text(bio)
                        .font(.fratBody(15)).foregroundColor(.fratDark)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }

                Spacer()

                Button { dismiss() } label: {
                    Text("Close")
                        .font(.fratSemi(16)).foregroundColor(.fratDark)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Date helpers

extension Date {
    var shortTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: self)
    }

    var relativeString: String {
        let diff = Calendar.current.dateComponents([.minute, .hour, .day], from: self, to: Date())
        if let day = diff.day,    day  > 0 { return "\(day)d" }
        if let hour = diff.hour,  hour > 0 { return "\(hour)h" }
        if let min  = diff.minute, min > 0 { return "\(min)m" }
        return "now"
    }

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self)     { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: self)
    }
}

#Preview {
    ChatView(match: Match(
        name: "Sarah Johnson",
        peerId: "12D3KooWABC",
        lastMessage: "Hey!",
        timestamp: Date(),
        unread: 0
    ))
    .environmentObject(MeshManager())
}
