//
//  RelaySwitcherSheet.swift
//  FratRat
//
//  Created by Brady Bangasser on 6/20/26.
//


//
//  RelaySwitcherSheet.swift
//  FratRat
//
//  Lets the user switch relays while already connected — distinct
//  from RelayPickerSheet (LandingView.swift) which is the first-time
//  connect flow. This one shows the CURRENT relay clearly, warns that
//  switching disconnects active peers, and supports the same
//  auto-discover + custom relay input pattern.
//
//  Present from SettingsView's "Mesh Network" section, e.g.:
//
//    Button { showRelaySwitcher = true } label: { ... }
//      .sheet(isPresented: $showRelaySwitcher) {
//          RelaySwitcherSheet(isPresented: $showRelaySwitcher)
//              .environmentObject(mesh)
//      }
//

import SwiftUI

struct RelaySwitcherSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var mesh: MeshManager

    @State private var showCustomRelay = false
    @State private var hostInput = ""
    @State private var resolvedMultiaddr: String? = nil
    @State private var resolveState: ResolveState = .idle
    @State private var resolveError: String? = nil
    @FocusState private var hostFieldFocused: Bool

    // Confirmation before actually switching — switching disconnects
    // current peers, worth a beat of friction so it's not accidental.
    @State private var pendingRelay: RelayInfoViewModel? = nil
    @State private var showSwitchConfirm = false

    enum ResolveState: Equatable {
        case idle, resolving, resolved, failed
    }

    private var isConnecting: Bool {
        if case .connecting = mesh.connectionState { return true }
        return false
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // ── Current relay card ───────────────────────────
                        CurrentRelayCard(
                            relay: mesh.selectedRelay,
                            state: mesh.connectionState,
                            peerCount: mesh.peerCount
                        )

                        // ── Error ─────────────────────────────────────────
                        if case .failed(let msg) = mesh.connectionState {
                            ErrorBanner(
                                title: "Couldn't connect to the mesh",
                                message: msg
                            ) {
                                Task { await mesh.findRelays() }
                            }
                        }

                        // ── Connecting state ─────────────────────────────
                        if isConnecting {
                            VStack(spacing: 12) {
                                ProgressView().scaleEffect(1.2).tint(.fratPink)
                                Text("Switching relay…")
                                    .font(.fratBody(14))
                                    .foregroundColor(.fratGray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(28)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratCard))
                        }

                        // ── Available relays ─────────────────────────────
                        if mesh.connectionState == .discoveringRelays {
                            VStack(spacing: 12) {
                                ProgressView().scaleEffect(1.2).tint(.fratPink)
                                Text("Finding relays…")
                                    .font(.fratBody(14))
                                    .foregroundColor(.fratGray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(28)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratCard))
                        } else if !mesh.availableRelays.isEmpty {
                            SectionLabel("AVAILABLE RELAYS")

                            ForEach(mesh.availableRelays) { relay in
                                SwitchableRelayRow(
                                    relay: relay,
                                    isCurrent: relay.multiaddr == mesh.selectedRelay?.multiaddr,
                                    isConnecting: isConnecting && pendingRelay?.multiaddr == relay.multiaddr
                                ) {
                                    requestSwitch(to: relay)
                                }
                                .disabled(isConnecting)
                                .opacity(isConnecting && pendingRelay?.multiaddr != relay.multiaddr ? 0.5 : 1)
                            }
                        }

                        // ── Custom relay ──────────────────────────────────
                        SectionLabel("CUSTOM RELAY")

                        VStack(spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showCustomRelay.toggle()
                                    resolveError = nil
                                    resolveState = .idle
                                    resolvedMultiaddr = nil
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.fratDark)
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 16))
                                    }
                                    Text("Add custom relay")
                                        .font(.fratSemi(15))
                                        .foregroundColor(.fratDark)
                                    Spacer()
                                    Image(systemName: showCustomRelay ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.fratGray)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratCard))
                            }
                            .buttonStyle(.plain)
                            .disabled(isConnecting)

                            if showCustomRelay {
                                CustomRelaySwitchInput(
                                    hostInput:        $hostInput,
                                    resolvedMultiaddr: $resolvedMultiaddr,
                                    resolveState:     $resolveState,
                                    resolveError:     $resolveError,
                                    hostFieldFocused: $hostFieldFocused,
                                    isConnecting:     isConnecting,
                                    onConnect: {
                                        guard let multiaddr = resolvedMultiaddr else { return }
                                        let relay = RelayInfoViewModel(
                                            multiaddr: multiaddr,
                                            peerId: multiaddr.components(separatedBy: "/p2p/").last ?? "unknown",
                                            region: "custom",
                                            load: 0,
                                            meshes: ["fratrat-v1"]
                                        )
                                        requestSwitch(to: relay)
                                    }
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Switch Relay")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                        .foregroundColor(.fratPink)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await mesh.findRelays() }
                    } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(.fratPink)
                    }
                    .disabled(mesh.connectionState == .discoveringRelays || isConnecting)
                }
            }
        }
        .alert("Switch relay?", isPresented: $showSwitchConfirm, presenting: pendingRelay) { relay in
            Button("Switch", role: .destructive) {
                Task { await mesh.connect(to: relay) }
            }
            Button("Cancel", role: .cancel) {
                pendingRelay = nil
            }
        } message: { relay in
            Text("You'll disconnect from \(mesh.selectedRelay?.displayHost ?? "the current relay") and reconnect via \(relay.displayHost). Active chats will reconnect automatically once you're back online.")
        }
        .onAppear {
            if mesh.availableRelays.isEmpty {
                Task { await mesh.findRelays() }
            }
        }
    }

    private func requestSwitch(to relay: RelayInfoViewModel) {
        // Already on this relay — nothing to do
        if relay.multiaddr == mesh.selectedRelay?.multiaddr { return }
        pendingRelay = relay
        showSwitchConfirm = true
    }
}

// MARK: - Current relay card
private struct CurrentRelayCard: View {
    let relay: RelayInfoViewModel?
    let state: MeshConnectionState
    let peerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.6), radius: 4)
                Text("CURRENT RELAY")
                    .font(.fratSemi(11))
                    .foregroundColor(.fratGray)
                Spacer()
            }

            if let relay {
                VStack(alignment: .leading, spacing: 4) {
                    Text(relay.displayHost)
                        .font(.fratBold(18))
                        .foregroundColor(.fratDark)
                    HStack(spacing: 10) {
                        Label(relay.region, systemImage: "mappin.circle")
                            .font(.fratBody(13))
                            .foregroundColor(.fratGray)
                        Label("\(peerCount) peer\(peerCount == 1 ? "" : "s")", systemImage: "person.2.fill")
                            .font(.fratBody(13))
                            .foregroundColor(.fratGray)
                    }
                }
            } else {
                Text("Not connected")
                    .font(.fratBold(18))
                    .foregroundColor(.fratGray)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratCard))
    }

    private var dotColor: Color {
        switch state {
        case .connected:                      return .green
        case .connecting, .discoveringRelays: return .yellow
        case .disconnected:                   return .fratGray
        case .failed:                         return .red
        }
    }
}

// MARK: - Switchable relay row
private struct SwitchableRelayRow: View {
    let relay: RelayInfoViewModel
    let isCurrent: Bool
    let isConnecting: Bool
    let onSwitch: () -> Void

    var body: some View {
        Button(action: onSwitch) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCurrent ? Color.green.opacity(0.15) : Color.fratDark)
                        .frame(width: 44, height: 44)
                    Image(systemName: isCurrent ? "checkmark" : (relay.region == "custom" ? "personalhotspot" : "server.rack"))
                        .foregroundColor(isCurrent ? .green : .white)
                        .font(.system(size: 18, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(relay.displayHost)
                        .font(.fratBold(15))
                        .foregroundColor(.fratDark)
                    HStack(spacing: 8) {
                        Label(relay.region, systemImage: "mappin.circle")
                            .font(.fratBody(12))
                            .foregroundColor(.fratGray)
                        HStack(spacing: 4) {
                            Circle().fill(loadColor(relay.load)).frame(width: 6, height: 6)
                            Text("\(relay.load)% load")
                                .font(.fratBody(12))
                                .foregroundColor(.fratGray)
                        }
                    }
                }

                Spacer()

                if isConnecting {
                    ProgressView().tint(.fratPink).frame(width: 36)
                } else if isCurrent {
                    Text("Current")
                        .font(.fratSemi(12))
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Text("Switch")
                        .font(.fratSemi(13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.fratDark))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratCard))
        }
        .buttonStyle(.plain)
    }

    private func loadColor(_ load: Int) -> Color {
        switch load {
        case 0..<40:  return .green
        case 40..<75: return .yellow
        default:      return .red
        }
    }
}

// MARK: - Section label
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack {
            Text(text).font(.fratSemi(11)).foregroundColor(.fratGray)
            Spacer()
        }
    }
}

// MARK: - Custom relay input (switch variant)
private struct CustomRelaySwitchInput: View {
    @Binding var hostInput: String
    @Binding var resolvedMultiaddr: String?
    @Binding var resolveState: RelaySwitcherSheet.ResolveState
    @Binding var resolveError: String?
    var hostFieldFocused: FocusState<Bool>.Binding
    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RELAY HOST")
                    .font(.fratSemi(11))
                    .foregroundColor(.fratGray)

                HStack(spacing: 10) {
                    TextField("relay.example.com  or  1.2.3.4", text: $hostInput)
                        .font(.system(size: 15, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .focused(hostFieldFocused)
                        .onChange(of: hostInput) { _ in
                            resolveState = .idle
                            resolvedMultiaddr = nil
                            resolveError = nil
                        }

                    Button {
                        if resolveState == .resolving {
                            resolveState = .idle
                            resolveError = "Cancelled"
                        } else {
                            Task { await resolveHost() }
                        }
                    } label: {
                        Group {
                            if resolveState == .resolving {
                                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            } else if resolveState == .resolved {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                            } else if resolveState == .failed {
                                Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold))
                            } else {
                                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(buttonColor))
                    }
                    .disabled(hostInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.fratBg)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderColor, lineWidth: 1.5))
                )

                if resolveState == .resolving {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8).tint(.fratPink)
                        Text("Connecting to relay via gRPC…")
                            .font(.fratBody(12))
                            .foregroundColor(.fratGray)
                        Spacer()
                        Text("tap × to cancel")
                            .font(.fratBody(11))
                            .foregroundColor(.fratGray.opacity(0.7))
                    }
                } else if let err = resolveError {
                    Label(err, systemImage: "exclamationmark.circle")
                        .font(.fratBody(12))
                        .foregroundColor(.red)
                } else if let multiaddr = resolvedMultiaddr {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Relay found", systemImage: "checkmark.circle.fill")
                            .font(.fratSemi(12))
                            .foregroundColor(.green)
                        Text(multiaddr)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.fratGray)
                            .lineLimit(2)
                    }
                } else {
                    Text("Enter a domain name or IP address")
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                }
            }

            Button(action: onConnect) {
                ZStack {
                    if isConnecting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Switch to this relay")
                            .font(.fratBold(15))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(resolvedMultiaddr == nil ? Color.fratGray : Color.fratPink))
            }
            .disabled(resolvedMultiaddr == nil || isConnecting)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratCard))
    }

    private var borderColor: Color {
        switch resolveState {
        case .resolved: return .green.opacity(0.5)
        case .failed:   return .red.opacity(0.5)
        default:        return .clear
        }
    }

    private var buttonColor: Color {
        switch resolveState {
        case .resolved:  return .green
        case .failed:    return Color(red: 0.8, green: 0.2, blue: 0.2)
        case .resolving: return .fratGray
        default:         return .fratDark
        }
    }

    private struct TimeoutError: Error {}

    private func resolveHost() async {
        let host = hostInput.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }

        resolveState = .resolving
        resolveError = nil
        resolvedMultiaddr = nil

        // https unless the person typed http:// (local testing).
        let grpcAddr = ZkrpConfig.grpcURL(fromUserInput: host)

        do {
            let results = try await withThrowingTaskGroup(of: [RelayInfo].self) { group in
                group.addTask {
                    await Task.detached(priority: .userInitiated) {
                        discoverRelays(grpcAddr: grpcAddr)
                    }.value
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw TimeoutError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            if let first = results.first {
                resolvedMultiaddr = first.multiaddr
                resolveState = .resolved
                resolveError = nil
            } else {
                resolveState = .failed
                resolveError = "No relays registered at \(grpcAddr) — is the relay running?"
            }
        } catch is TimeoutError {
            resolveState = .failed
            resolveError = "Connection timed out after 5s — check the host and port"
        } catch {
            resolveState = .failed
            resolveError = "Failed to connect: \(error.localizedDescription)"
        }
    }

}

#Preview {
    RelaySwitcherSheet(isPresented: .constant(true))
        .environmentObject(MeshManager())
}