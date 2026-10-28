//
//  SettingsView.swift
//  FratRat
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var enrollment: Enrollment
    @Environment(\.colorScheme) var colorScheme
    @State private var settings = AppSettings.load()
    @State private var profile = UserProfile.load()
    @State private var showLogoutConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var showDeleteDataConfirm = false
    @State private var showBlockedUsers = false
    @State private var showRelayPicker = false
    @State private var showRelaySwitcher = false
    @State private var copiedKey: String? = nil
    @State private var isUploadingLogs = false
    @State private var logResult: String? = nil

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // ── Header ────────────────────────────────────────────────
                    HStack {
                        Text("Settings")
                            .font(.system(size: 34, weight: .black))
                            .foregroundColor(.fratDark)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 24)

                    VStack(spacing: 14) {

                        // ── Account ───────────────────────────────────────────
                        SettingsCard {
                            HStack(spacing: 14) {
                                SettingsIcon(systemName: "person.circle.fill", color: Color(red: 0.3, green: 0.1, blue: 0.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ACCOUNT")
                                        .font(.fratSemi(11))
                                        .foregroundColor(.fratGray)
                                    Text(verificationLabel)
                                        .font(.fratBold(15))
                                        .foregroundColor(.fratDark)
                                    if !profile.name.isEmpty || !profile.college.isEmpty {
                                        Text([profile.name, profile.college]
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " · "))
                                            .font(.fratBody(13))
                                            .foregroundColor(.fratGray)
                                    }
                                }
                                Spacer()
                            }
                        }

                        // ── Appearance ────────────────────────────────────────
                        SettingsCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "circle.lefthalf.filled", color: Color(red: 0.1, green: 0.2, blue: 0.5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("APPEARANCE")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text(settings.appearance.label)
                                            .font(.fratBold(15))
                                            .foregroundColor(.fratDark)
                                    }
                                    Spacer()
                                }
                                AppearancePicker(selection: $settings.appearance)
                                    .onChange(of: settings.appearance) { _ in settings.save() }
                            }
                        }

                        // ── Mesh connection ───────────────────────────────────
                        SettingsSectionHeader("MESH NETWORK")

                        SettingsCard {
                            VStack(spacing: 14) {
                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "antenna.radiowaves.left.and.right", color: Color(red: 0.1, green: 0.3, blue: 0.5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("CONNECTION")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text(mesh.connectionState.label)
                                            .font(.fratBold(15))
                                            .foregroundColor(.fratDark)
                                        Text("\(mesh.peerCount) peer\(mesh.peerCount == 1 ? "" : "s") connected")
                                            .font(.fratBody(13))
                                            .foregroundColor(.fratGray)
                                    }
                                    Spacer()
                                    Circle()
                                        .fill(connectionDotColor)
                                        .frame(width: 10, height: 10)
                                        .shadow(color: connectionDotColor.opacity(0.5), radius: 4)
                                }

                                Divider()

                                if let relay = mesh.selectedRelay {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("RELAY")
                                                .font(.fratSemi(11))
                                                .foregroundColor(.fratGray)
                                            Spacer()
                                            Button {
                                                showRelaySwitcher = true
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                        .font(.system(size: 11, weight: .semibold))
                                                    Text("Switch")
                                                        .font(.fratSemi(12))
                                                }
                                                .foregroundColor(.fratPink)
                                            }
                                        }

                                        InfoRow(label: "Host", value: relay.displayHost)
                                        InfoRow(label: "Region", value: relay.region)
                                        InfoRow(label: "Load", value: "\(relay.load)%")

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("MULTIADDR")
                                                .font(.fratSemi(11))
                                                .foregroundColor(.fratGray)
                                            HStack(spacing: 8) {
                                                Text(relay.multiaddr)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(.fratGray)
                                                    .lineLimit(2)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Spacer()
                                                CopyButton(value: relay.multiaddr, copiedKey: $copiedKey, id: "relay_multiaddr")
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("RELAY PEER ID")
                                                .font(.fratSemi(11))
                                                .foregroundColor(.fratGray)
                                            HStack(spacing: 8) {
                                                Text(relay.peerId)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(.fratGray)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                Spacer()
                                                CopyButton(value: relay.peerId, copiedKey: $copiedKey, id: "relay_peer_id")
                                            }
                                        }
                                    }
                                } else {
                                    Button {
                                        showRelayPicker = true
                                    } label: {
                                        HStack {
                                            Text("Not connected to a relay")
                                                .font(.fratBody(14))
                                                .foregroundColor(.fratGray)
                                            Spacer()
                                            Text("Connect")
                                                .font(.fratSemi(13))
                                                .foregroundColor(.fratPink)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // ── Our identity ──────────────────────────────────────
                        SettingsCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "key.fill", color: Color(red: 0.5, green: 0.35, blue: 0.0))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("MESH IDENTITY")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text("Your peer ID")
                                            .font(.fratBold(15))
                                            .foregroundColor(.fratDark)
                                    }
                                    Spacer()
                                }

                                if let peerId = mesh.myPeerId {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("PEER ID")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        HStack(spacing: 8) {
                                            Text(peerId)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.fratGray)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            CopyButton(value: peerId, copiedKey: $copiedKey, id: "peer_id")
                                        }
                                    }
                                }

                                Divider()

                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "lock.shield.fill", color: Color(red: 0.1, green: 0.4, blue: 0.2))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("KEY BUNDLE")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text("X3DH + Ed25519")
                                            .font(.fratBold(15))
                                            .foregroundColor(.fratDark)
                                        Text("Identity key, signed prekey, one-time prekeys stored securely on device.")
                                            .font(.fratBody(12))
                                            .foregroundColor(.fratGray)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }

                                Divider()

                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "lock.fill", color: Color(red: 0.1, green: 0.3, blue: 0.5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("TRANSPORT")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text("Noise Protocol")
                                            .font(.fratBold(15))
                                            .foregroundColor(.fratDark)
                                        Text("All peer-to-peer traffic is encrypted in transit.")
                                            .font(.fratBody(12))
                                            .foregroundColor(.fratGray)
                                    }
                                }
                            }
                        }

                        // ── Subscribed topics ─────────────────────────────────
                        SettingsCard {
                            HStack(spacing: 14) {
                                SettingsIcon(systemName: "dot.radiowaves.left.and.right", color: Color(red: 0.1, green: 0.3, blue: 0.5))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("GOSSIPSUB TOPICS")
                                        .font(.fratSemi(11))
                                        .foregroundColor(.fratGray)
                                    Text("fratrat/v1/broadcast")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.fratDark)
                                    Text("fratrat/v1/profiles")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.fratDark)
                                    if let peerId = mesh.myPeerId {
                                        Text("fratrat/v1/profiles/dm/\(String(peerId.prefix(12)))…")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.fratDark)
                                    }
                                }
                                Spacer()
                            }
                        }

                        // ── Distance ──────────────────────────────────────────
                        SettingsSectionHeader("DISCOVERY")

                        SettingsCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "location.fill", color: Color(red: 0.5, green: 0.1, blue: 0.2))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("MAX DISTANCE")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text("\(Int(settings.maxDistanceKm)) km")
                                            .font(.system(size: 22, weight: .black))
                                            .foregroundColor(.fratDark)
                                    }
                                    Spacer()
                                }
                                Slider(value: $settings.maxDistanceKm, in: 1...100, step: 1)
                                    .tint(.fratPink)
                                    .onChange(of: settings.maxDistanceKm) { _ in settings.save() }
                                Text("Used to filter nearby students in Discover.")
                                    .font(.fratBody(13))
                                    .foregroundColor(.fratGray)
                            }
                        }

                        // ── Safety ────────────────────────────────────────────
                        SettingsSectionHeader("SAFETY")

                        Button { showBlockedUsers = true } label: {
                            SettingsCard {
                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "nosign", color: Color(red: 0.3, green: 0.2, blue: 0.0))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("BLOCKED USERS")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text(mesh.blockedPeerIds.isEmpty
                                             ? "None blocked"
                                             : "\(mesh.blockedPeerIds.count) blocked")
                                            .font(.fratBody(15))
                                            .foregroundColor(.fratDark)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.fratGray)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        SettingsCard {
                            HStack(spacing: 14) {
                                SettingsIcon(systemName: "checkmark.shield.fill", color: Color(red: 0.1, green: 0.3, blue: 0.3))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("SAFETY & PRIVACY")
                                        .font(.fratSemi(11))
                                        .foregroundColor(.fratGray)
                                    Text("Block or report people from the ••• menu in a chat. Party posts expire after 24h. Campus alerts expire after 1h. Location only used for nearby matching.")
                                        .font(.fratBody(13))
                                        .foregroundColor(.fratDark)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                        }

                        // ── Data ──────────────────────────────────────────────
                        SettingsSectionHeader("DATA")

                        Button { showClearCacheConfirm = true } label: {
                            SettingsCard {
                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "trash.fill", color: Color(red: 0.7, green: 0.1, blue: 0.1))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("CLEAR CACHE")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text("Clear local data")
                                            .font(.fratBold(15))
                                            .foregroundColor(.fratDark)
                                        Text("Removes cached profiles, messages, parties, alerts, and relationship history. Your identity (peer ID) is preserved.")
                                            .font(.fratBody(12))
                                            .foregroundColor(.fratGray)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.fratGray)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Button { showDeleteDataConfirm = true } label: {
                            SettingsCard {
                                HStack(spacing: 14) {
                                    SettingsIcon(systemName: "person.crop.circle.badge.xmark", color: Color(red: 0.7, green: 0.1, blue: 0.1))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("DELETE MY DATA")
                                            .font(.fratSemi(11))
                                            .foregroundColor(.fratGray)
                                        Text("Delete account from this phone")
                                            .font(.fratBold(15))
                                            .foregroundColor(.red)
                                        Text("Erases your identity, verification, profile, photos and conversations. You'll start over as a new user.")
                                            .font(.fratBody(12))
                                            .foregroundColor(.fratGray)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.fratGray)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // ── Version + logout ──────────────────────────────────
                        Text("FratRat v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.fratBody(12))
                            .foregroundColor(.fratGray)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)

                        // ── Upload logs ───────────────────────────────────────
                        Button { Task { await uploadLogs() } } label: {
                            HStack(spacing: 8) {
                                if isUploadingLogs {
                                    ProgressView().tint(.fratPink)
                                } else {
                                    Image(systemName: "arrow.up.doc")
                                }
                                Text(isUploadingLogs ? "Uploading…" : "Upload debug logs")
                                    .font(.fratSemi(15))
                            }
                            .foregroundColor(.fratPink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
                        }
                        .disabled(isUploadingLogs)

                        if let logResult {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green).font(.system(size: 12))
                                Text("Log ID: \(logResult)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.fratGray)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = logResult
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12)).foregroundColor(.fratPink)
                                }
                            }
                            .padding(.horizontal, 4)
                        }

                        Button { showLogoutConfirm = true } label: {
                            Text("Disconnect & log out")
                                .font(.fratBold(17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratNavBar))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120)
                }
            }
        }
        .alert("Log out?", isPresented: $showLogoutConfirm) {
            Button("Log out", role: .destructive) {
                Task { await mesh.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be disconnected from the mesh.")
        }
        .alert("Clear cache?", isPresented: $showClearCacheConfirm) {
            Button("Clear", role: .destructive) {
                Task { await mesh.clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all locally cached data — profiles, messages, parties, alerts, and relationship history. Your peer identity is preserved. You'll need to reconnect to the relay.")
        }
        .alert("Delete your data?", isPresented: $showDeleteDataConfirm) {
            Button("Delete", role: .destructive) {
                Task { await mesh.deleteAllData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Your profile and photos stop being announced, but copies people already received stay on their phones until their caches expire.")
        }
        .sheet(isPresented: $showBlockedUsers) {
            BlockedUsersView()
                .environmentObject(mesh)
        }
        .sheet(isPresented: $showRelayPicker) {
            RelayPickerSheet(isPresented: $showRelayPicker)
                .environmentObject(mesh)
        }
        .sheet(isPresented: $showRelaySwitcher) {
            RelaySwitcherSheet(isPresented: $showRelaySwitcher)
                .environmentObject(mesh)
        }
    }

    private var verificationLabel: String {
        guard enrollment.isEnrolled, let expiresAt = enrollment.expiresAt else {
            return "Not verified"
        }
        return "Verified until \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var connectionDotColor: Color {
        switch mesh.connectionState {
        case .connected:                      return .green
        case .connecting, .discoveringRelays: return .yellow
        case .disconnected:                   return .fratGray
        case .failed:                         return .red
        }
    }

    @MainActor
    private func uploadLogs() async {
        guard !isUploadingLogs else { return }
        isUploadingLogs = true
        logResult = nil

        let data = LogCapture.shared.currentLogData()
        guard !data.isEmpty else {
            isUploadingLogs = false
            logResult = "No logs captured yet"
            return
        }

        do {
            let url = try await mesh.uploadLogs(data)
            logResult = url
        } catch {
            logResult = "Upload failed: \(error.localizedDescription)"
        }
        isUploadingLogs = false
    }
}

// MARK: - 3-stage appearance picker
struct AppearancePicker: View {
    @Binding var selection: AppearanceMode
    var body: some View {
        HStack(spacing: 0) {
            ForEach([AppearanceMode.light, .system, .dark], id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = mode }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon).font(.system(size: 13))
                        Text(mode.label).font(.fratSemi(13))
                    }
                    .foregroundColor(selection == mode ? .white : .fratGray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(selection == mode ? Color.fratDark : Color.clear))
                }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratBg))
    }
}

// MARK: - Info row
private struct InfoRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).font(.fratBody(13)).foregroundColor(.fratGray)
            Spacer()
            Text(value).font(.fratSemi(13)).foregroundColor(.fratDark)
        }
    }
}

// MARK: - Copy button
private struct CopyButton: View {
    let value: String
    @Binding var copiedKey: String?
    let id: String
    var body: some View {
        Button {
            UIPasteboard.general.string = value
            withAnimation { copiedKey = id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { copiedKey = nil }
            }
        } label: {
            Image(systemName: copiedKey == id ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13))
                .foregroundColor(copiedKey == id ? .green : .fratPink)
        }
    }
}

// MARK: - Section header
private struct SettingsSectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack {
            Text(text).font(.fratSemi(12)).foregroundColor(.fratGray)
            Spacer()
        }
        .padding(.top, 6)
    }
}

// MARK: - Blocked users
private struct BlockedUsersView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()
                if mesh.blockedPeerIds.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.system(size: 40)).foregroundColor(.fratGray)
                        Text("No blocked users").font(.fratBold(18)).foregroundColor(.fratDark)
                        Text("Users you block from chat will appear here.")
                            .font(.fratBody(14)).foregroundColor(.fratGray).multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    List {
                        ForEach(mesh.blockedPeerIds.sorted(), id: \.self) { peerId in
                            HStack {
                                Text(mesh.peerProfiles[peerId]?.displayName ?? String(peerId.prefix(16)) + "…")
                                    .font(.fratBody(15)).foregroundColor(.fratDark)
                                Spacer()
                                Button("Unblock") {
                                    mesh.unblock(peerId)
                                }
                                .font(.fratSemi(13)).foregroundColor(.fratPink)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Blocked Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.fratPink)
                }
            }
        }
    }
}

// MARK: - Settings card
struct SettingsCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratCard))
    }
}

// MARK: - Settings icon
struct SettingsIcon: View {
    let systemName: String; let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(color).frame(width: 44, height: 44)
            Image(systemName: systemName).foregroundColor(.white).font(.system(size: 18))
        }
    }
}

#Preview {
    SettingsView().environmentObject(MeshManager())
}
