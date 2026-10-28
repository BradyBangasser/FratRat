//
//  LandingView.swift
//  FratRat
//

import SwiftUI

struct LandingView: View {
    @EnvironmentObject var mesh: MeshManager
    @State private var showRelayPicker = false
    @State private var showCreateAccount = false

    /// Called once the user has either connected with an existing
    /// account or finished onboarding — triggers the app root to
    /// switch away from the auth flow entirely (see FratRatApp.swift).
    var onOnboardingComplete: () -> Void = {}

    private let features: [(icon: String, title: String, subtitle: String)] = [
        ("heart.fill",         "Swipe & match",   "Find students near your campus."),
        ("dice.fill",          "Die Up",           "Auto-like 6 profiles in one tap."),
        ("exclamationmark.triangle.fill", "Safety alerts", "Real-time campus safety reports."),
        ("graduationcap.fill", ".edu verified",    "A community of real students only.")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fratBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {

                    // ── Badge ────────────────────────────────────────────────
                    HStack {
                        Text("FOR COLLEGE STUDENTS")
                            .font(.fratSemi(12))
                            .foregroundColor(.fratPink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.fratPinkLight))
                        Spacer()
                    }
                    .padding(.top, 64)
                    .padding(.horizontal, 24)

                    // ── Title ────────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Frat Rat")
                            .font(.system(size: 52, weight: .black))
                            .foregroundColor(.fratDark)
                        Text("Dating & parties, made for campus.")
                            .font(.fratBody(17))
                            .foregroundColor(.fratGray)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // ── Feature grid ─────────────────────────────────────────
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 14
                    ) {
                        ForEach(features, id: \.title) { f in
                            LandingFeatureCard(icon: f.icon, title: f.title, subtitle: f.subtitle)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                    Spacer()

                    // ── Error banner ─────────────────────────────────────────
                    if case .failed(let msg) = mesh.connectionState {
                        ErrorBanner(
                            title: "Couldn't connect to the mesh",
                            message: msg
                        ) {
                            Task { await mesh.findRelays() }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // ── Connection status ─────────────────────────────────────
                    ConnectionStatusBanner(state: mesh.connectionState) {
                        showRelayPicker = true
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // ── CTAs ──────────────────────────────────────────────────
                    VStack(spacing: 12) {
                        Button {
                            showCreateAccount = true
                        } label: {
                            Text("Create account")
                                .font(.fratSemi(17))
                                .foregroundColor(.fratDark)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.7))
                                )
                        }

                        Button {
                            Task { await connectAndEnter() }
                        } label: {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("I already have an account")
                                        .font(.fratBold(17))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.fratDark)
                            )
                        }
                        .disabled(isLoading)

                        Text("You must be 17+ and enrolled at a college or university.")
                            .font(.fratBody(13))
                            .foregroundColor(.fratGray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                }
                .animation(.easeInOut(duration: 0.25), value: mesh.connectionState.isFailed)
            }
            .navigationDestination(isPresented: $showCreateAccount) {
                CreateAccountView(onOnboardingComplete: onOnboardingComplete)
                    .environmentObject(mesh)
                    .navigationBarBackButtonHidden(true)
            }
            .sheet(isPresented: $showRelayPicker) {
                RelayPickerSheet(isPresented: $showRelayPicker) {
                    onOnboardingComplete()
                }
                .environmentObject(mesh)
            }
            .onAppear {
                Task { await mesh.findRelays() }
            }
        }
    }

    private var isLoading: Bool {
        mesh.connectionState == .discoveringRelays ||
        mesh.connectionState == .connecting(relay: mesh.selectedRelay?.displayHost ?? "")
    }

    private func connectAndEnter() async {
        if mesh.connectionState.isConnected {
            onOnboardingComplete()
            return
        }
        if mesh.availableRelays.isEmpty {
            await mesh.findRelays()
        }
        if mesh.availableRelays.isEmpty {
            showRelayPicker = true
            return
        }
        await mesh.connectToBestRelay()
        if mesh.connectionState.isConnected {
            onOnboardingComplete()
        } else {
            showRelayPicker = true
        }
    }
}

// MARK: - Feature card
private struct LandingFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.fratPinkLight)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.fratPink)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.fratBold(15))
                    .foregroundColor(.fratDark)
                Text(subtitle)
                    .font(.fratBody(13))
                    .foregroundColor(.fratGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratCard))
    }
}

// MARK: - Error banner
struct ErrorBanner: View {
    var title: String? = nil
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 15))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.fratSemi(13))
                        .foregroundColor(.fratDark)
                }
                Text(message)
                    .font(.fratBody(13))
                    .foregroundColor(title == nil ? .fratDark : .fratGray)
                    .lineLimit(3)
            }

            Spacer()

            Button("Retry", action: onRetry)
                .font(.fratSemi(13))
                .foregroundColor(.fratPink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Connection status banner
struct ConnectionStatusBanner: View {
    let state: MeshConnectionState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.6), radius: 4)
                Text(state.label)
                    .font(.fratSemi(13))
                    .foregroundColor(.fratDark)
                Spacer()
                if case .disconnected = state {
                    Text("Choose relay")
                        .font(.fratSemi(12))
                        .foregroundColor(.fratPink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
        }
        .buttonStyle(.plain)
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

// MARK: - Relay picker sheet
struct RelayPickerSheet: View {
    @Binding var isPresented: Bool
    var onConnected: (() -> Void)? = nil
    @EnvironmentObject var mesh: MeshManager

    // Custom relay input
    @State private var showCustomRelay = false
    @State private var hostInput = ""          // domain or IP user types
    @State private var resolvedMultiaddr: String? = nil
    @State private var resolveState: ResolveState = .idle
    @State private var resolveError: String? = nil
    @FocusState private var hostFieldFocused: Bool

    enum ResolveState: Equatable {
        case idle
        case resolving
        case resolved
        case failed
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // ── Error ─────────────────────────────────────────────
                        if case .failed(let msg) = mesh.connectionState {
                            ErrorBanner(
                                title: "Couldn't connect to the mesh",
                                message: msg
                            ) {
                                Task { await mesh.findRelays() }
                            }
                        }

                        // ── Loading ───────────────────────────────────────────
                        if mesh.connectionState == .discoveringRelays {
                            VStack(spacing: 12) {
                                ProgressView().scaleEffect(1.3).tint(.fratPink)
                                Text("Finding relays…")
                                    .font(.fratBody(14))
                                    .foregroundColor(.fratGray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(32)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratCard))
                        }

                        // ── Connecting ────────────────────────────────────────
                        if case .connecting(let relayName) = mesh.connectionState {
                            VStack(spacing: 12) {
                                ProgressView().scaleEffect(1.3).tint(.fratPink)
                                Text("Connecting to \(relayName)…")
                                    .font(.fratBody(14))
                                    .foregroundColor(.fratGray)
                                Text("This can take up to 15 seconds")
                                    .font(.fratBody(11))
                                    .foregroundColor(.fratGray.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(32)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratCard))
                        }

                        // ── Auto connect ──────────────────────────────────────
                        if !mesh.availableRelays.isEmpty {
                            Button {
                                Task {
                                    await mesh.connectToBestRelay()
                                    if mesh.connectionState.isConnected {
                                        isPresented = false
                                        onConnected?()
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "bolt.fill")
                                    Text("Auto-connect (best relay)")
                                        .font(.fratBold(15))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratPink))
                            }
                            .disabled(mesh.connectionState == .discoveringRelays || isConnecting)

                            SectionLabel("AVAILABLE RELAYS")

                            ForEach(mesh.availableRelays) { relay in
                                RelayRow(
                                    relay: relay,
                                    isConnecting: {
                                        if case .connecting(let r) = mesh.connectionState {
                                            return r == relay.displayHost
                                        }
                                        return false
                                    }()
                                ) {
                                    Task {
                                        await mesh.connect(to: relay)
                                        if mesh.connectionState.isConnected {
                                            isPresented = false
                                            onConnected?()
                                        }
                                    }
                                }
                                .disabled(isConnecting)
                                .opacity(isConnecting ? 0.6 : 1)
                            }
                        } else if mesh.connectionState != .discoveringRelays {
                            VStack(spacing: 12) {
                                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                    .font(.system(size: 36))
                                    .foregroundColor(.fratGray)
                                Text("No relays found")
                                    .font(.fratBold(17))
                                    .foregroundColor(.fratDark)
                                Text("Check your connection or add a custom relay below.")
                                    .font(.fratBody(14))
                                    .foregroundColor(.fratGray)
                                    .multilineTextAlignment(.center)
                                Button("Try again") {
                                    Task { await mesh.findRelays() }
                                }
                                .font(.fratSemi(14))
                                .foregroundColor(.fratPink)
                            }
                            .padding(28)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.fratCard))
                        }

                        // ── Custom relay ──────────────────────────────────────
                        SectionLabel("CUSTOM RELAY")

                        VStack(spacing: 12) {
                            // Toggle row
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
                                CustomRelayInput(
                                    hostInput:        $hostInput,
                                    resolvedMultiaddr: $resolvedMultiaddr,
                                    resolveState:     $resolveState,
                                    resolveError:     $resolveError,
                                    hostFieldFocused: $hostFieldFocused,
                                    isConnecting:     isConnecting,
                                    onConnect: {
                                        connectCustomRelay()
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
            .navigationTitle("Connect to mesh")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.fratPink)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await mesh.findRelays() }
                    } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(.fratPink)
                    }
                    .disabled(mesh.connectionState == .discoveringRelays)
                }
            }
        }
    }

    private var isConnecting: Bool {
        if case .connecting = mesh.connectionState { return true }
        return false
    }

    private func connectCustomRelay() {
        guard let multiaddr = resolvedMultiaddr else { return }
        hostFieldFocused = false

        let relay = RelayInfoViewModel(
            multiaddr: multiaddr,
            peerId:    multiaddr.components(separatedBy: "/p2p/").last ?? "unknown",
            region:    "custom",
            load:      0,
            meshes:    ["fratrat-v1"]
        )
        Task {
            await mesh.connect(to: relay)
            if mesh.connectionState.isConnected {
                isPresented = false
                onConnected?()
            }
        }
    }
}

// MARK: - Custom relay input
// Accepts a domain or IP, calls gRPC to resolve the full multiaddr
private struct CustomRelayInput: View {
    @Binding var hostInput: String
    @Binding var resolvedMultiaddr: String?
    @Binding var resolveState: RelayPickerSheet.ResolveState
    @Binding var resolveError: String?
    var hostFieldFocused: FocusState<Bool>.Binding
    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Host field ────────────────────────────────────────────────
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

                    // Resolve / cancel button
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
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                            } else if resolveState == .resolved {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                            } else if resolveState == .failed {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(buttonColor)
                        )
                    }
                    .disabled(hostInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.fratBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: 1.5)
                        )
                )

                // Status message
                if resolveState == .resolving {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.fratPink)
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

            // ── Quick fills ───────────────────────────────────────────────
            HStack(spacing: 8) {
                Text("Quick fill:")
                    .font(.fratSemi(11))
                    .foregroundColor(.fratGray)
                Button("localhost") {
                    hostInput = "127.0.0.1"
                    resolveState = .idle
                    resolvedMultiaddr = nil
                }
                .font(.fratSemi(11))
                .foregroundColor(.fratPink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.fratPinkLight))
            }

            // ── Connect button ────────────────────────────────────────────
            Button(action: onConnect) {
                ZStack {
                    if isConnecting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Connect to this relay")
                            .font(.fratBold(15))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(resolvedMultiaddr == nil ? Color.fratGray : Color.fratPink)
                )
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

    /// Call gRPC on the entered host to get the full multiaddr + peer ID
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
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5s
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

    private struct TimeoutError: Error {}

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

// MARK: - Relay row
private struct RelayRow: View {
    let relay: RelayInfoViewModel
    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.fratDark)
                    .frame(width: 44, height: 44)
                Image(systemName: relay.region == "custom" ? "personalhotspot" : "server.rack")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
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
                HStack(spacing: 4) {
                    ForEach(relay.meshes, id: \.self) { m in
                        Text(m)
                            .font(.fratSemi(10))
                            .foregroundColor(.fratPink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.fratPinkLight))
                    }
                }
            }

            Spacer()

            if isConnecting {
                ProgressView().tint(.fratPink).frame(width: 44)
            } else {
                Button(action: onConnect) {
                    Text("Connect")
                        .font(.fratSemi(13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.fratDark))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratCard))
    }

    private func loadColor(_ load: Int) -> Color {
        switch load {
        case 0..<40:  return .green
        case 40..<75: return .yellow
        default:      return .red
        }
    }
}

#Preview {
    LandingView()
        .environmentObject(MeshManager())
}
