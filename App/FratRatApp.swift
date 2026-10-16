//
//  FratRatApp.swift
//  FratRat
//

import SwiftUI

@main
struct FratRatApp: App {
    @StateObject private var mesh = MeshManager()
    @StateObject private var enrollment = Enrollment()
    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.system.rawValue

    @State private var isOnboarded = UserProfile.load().isComplete
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Start capturing stdout/stderr (Rust tracing + Swift print) to disk
        // as early as possible so the log file covers the whole session.
        LogCapture.shared.start()
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isOnboarded {
                    MainTabView()
                        .environmentObject(mesh)
                        // Credentials expire with the epoch; re-verify before
                        // relays start refusing us.
                        .sheet(isPresented: .constant(enrollment.needsRenewal)) {
                            NavigationStack {
                                EduVerificationView(isRenewal: true)
                                    .environmentObject(mesh)
                                    .environmentObject(enrollment)
                            }
                            .interactiveDismissDisabled()
                        }
                        .task {
                            if !mesh.connectionState.isConnected {
                                await mesh.findRelays()
                                if !mesh.availableRelays.isEmpty {
                                    await mesh.connectToBestRelay()
                                }
                            }
                        }
                } else {
                    LandingView(onOnboardingComplete: {
                        isOnboarded = true
                    })
                    .environmentObject(mesh)
                }
            }
            .environmentObject(enrollment)
            // Magic links: fratrat://verify#<token>, or a universal link.
            .onOpenURL { url in
                Task { await enrollment.redeem(from: url) }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                Task { await enrollment.redeem(from: url) }
            }
            .preferredColorScheme(appearanceMode.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { enrollment.refresh() }
            }
        }
    }
}
