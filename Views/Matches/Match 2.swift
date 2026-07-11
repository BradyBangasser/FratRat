//
//  Match 2.swift
//  FratRat
//
//  Created by Brady Bangasser on 5/26/26.
//


//
//  Match.swift
//  FratRat
//
//  Created by Brady Bangasser on 5/26/26.
//


//
//  MatchesView.swift
//  FratRat
//

import SwiftUI

// MARK: - Match model
struct Match: Identifiable {
    let id = UUID()
    let name: String
    let peerId: String
    let lastMessage: String
    let timestamp: Date
    let unread: Int
    var avatarInitials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}

// MARK: - MatchesView
struct MatchesView: View {
    @EnvironmentObject var mesh: MeshManager
    @State private var matches: [Match] = Match.mockMatches
    @State private var selectedMatch: Match?
    @State private var showChat = false

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Header ───────────────────────────────────────────────────
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Matches")
                            .font(.system(size: 34, weight: .black))
                            .foregroundColor(.fratDark)
                        Text("\(matches.count) connection\(matches.count == 1 ? "" : "s")")
                            .font(.fratBody(15))
                            .foregroundColor(.fratGray)
                    }
                    Spacer()

                    // Peer count pill
                    if mesh.peerCount > 0 {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                            Text("\(mesh.peerCount) online")
                                .font(.fratSemi(12))
                                .foregroundColor(.fratDark)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 20)

                // ── Section label ────────────────────────────────────────────
                Text("MESSAGES")
                    .font(.fratSemi(12))
                    .foregroundColor(.fratGray)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                // ── Content ──────────────────────────────────────────────────
                if matches.isEmpty {
                    EmptyMatchesCard()
                        .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(matches) { match in
                                MatchRow(match: match) {
                                    selectedMatch = match
                                    showChat = true
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
        .sheet(isPresented: $showChat) {
            if let match = selectedMatch {
                ChatView(match: match)
                    .environmentObject(mesh)
            }
        }
        .onChange(of: mesh.messages) { messages in
            guard let latest = messages.last, !latest.isOwn else { return }
            // TODO: map conversation topic → match and update lastMessage + unread
        }
    }
}

// MARK: - Empty state
private struct EmptyMatchesCard: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.fratPinkLight)
                    .frame(width: 72, height: 72)
                Image(systemName: "message.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.fratPink)
            }
            Text("No matches yet")
                .font(.fratBold(20))
                .foregroundColor(.fratDark)
            Text("Start swiping to make connections.")
                .font(.fratBody(15))
                .foregroundColor(.fratGray)
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
                // Avatar
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

                // Text
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

// MARK: - Chat view
struct ChatView: View {
    let match: Match
    @EnvironmentObject var mesh: MeshManager
    @State private var inputText = ""
    @State private var localMessages: [ChatMessage] = []
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    // Per-conversation topic: sorted peer IDs so both sides get same topic hash
    private var conversationTopic: String {
        let a = mesh.selectedRelay?.peerId ?? "local"
        let b = match.peerId
        return "dm/\(min(a, b))/\(max(a, b))"
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Messages ─────────────────────────────────────────────
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(localMessages) { msg in
                                    MessageBubble(message: msg)
                                        .id(msg.id)
                                }
                                if localMessages.isEmpty {
                                    Text("Say hi to \(match.name) 👋")
                                        .font(.fratBody(14))
                                        .foregroundColor(.fratGray)
                                        .padding(.top, 40)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: localMessages) { _ in
                            if let last = localMessages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    // ── Input bar ────────────────────────────────────────────
                    HStack(spacing: 12) {
                        TextField("Message \(match.name)…", text: $inputText, axis: .vertical)
                            .font(.fratBody(15))
                            .lineLimit(1...4)
                            .focused($inputFocused)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Color.white)
                            )

                        Button { sendMessage() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(inputText.isEmpty ? .fratGray : .fratPink)
                        }
                        .disabled(inputText.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                }
            }
            .navigationTitle(match.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.fratPink)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(match.name)
                            .font(.fratBold(16))
                            .foregroundColor(.fratDark)
                        Text(match.peerId.prefix(10) + "…")
                            .font(.fratBody(10))
                            .foregroundColor(.fratGray)
                    }
                }
            }
            // Pull in mesh messages that belong to this conversation
            .onReceive(mesh.$messages) { all in
                let newIncoming = all.filter { msg in
                    !msg.isOwn &&
                    !localMessages.contains(where: { $0.id == msg.id })
                }
                localMessages.append(contentsOf: newIncoming)
            }
            .onAppear {
                inputFocused = true
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await mesh.send(text, topic: conversationTopic)
        }
    }
}

// MARK: - Message bubble
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isOwn { Spacer(minLength: 60) }

            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.fratBody(15))
                    .foregroundColor(message.isOwn ? .white : .fratDark)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(message.isOwn ? Color.fratPink : Color.white)
                    )

                Text(message.timestamp.shortTime)
                    .font(.fratBody(11))
                    .foregroundColor(.fratGray)
                    .padding(.horizontal, 4)
            }

            if !message.isOwn { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Date helpers
private extension Date {
    var relativeString: String {
        let diff = Calendar.current.dateComponents([.minute, .hour, .day], from: self, to: Date())
        if let day = diff.day, day > 0 { return "\(day)d" }
        if let hour = diff.hour, hour > 0 { return "\(hour)h" }
        if let min = diff.minute, min > 0 { return "\(min)m" }
        return "now"
    }

    var shortTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: self)
    }
}

// MARK: - Mock data (replace with real match data from mesh)
extension Match {
    static let mockMatches: [Match] = [
        Match(
            name: "Sarah Johnson",
            peerId: "12D3KooWABC",
            lastMessage: "Hey! Are you going to the party tonight?",
            timestamp: Date().addingTimeInterval(-300),
            unread: 2
        ),
        Match(
            name: "Jake Miller",
            peerId: "12D3KooWDEF",
            lastMessage: "That was so fun last night 😂",
            timestamp: Date().addingTimeInterval(-3600),
            unread: 0
        ),
        Match(
            name: "Emma Davis",
            peerId: "12D3KooWGHI",
            lastMessage: "What's your major?",
            timestamp: Date().addingTimeInterval(-86400),
            unread: 1
        ),
    ]
}

// MARK: - Preview
#Preview {
    MatchesView()
        .environmentObject(MeshManager())
}
