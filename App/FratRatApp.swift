//
//  FratRatApp.swift
//  FratRat
//

import SwiftUI

@main
struct FratRatApp: App {
    @StateObject private var mesh = MeshManager(
        grpcAddr: ProcessInfo.processInfo.environment["GRPC_ADDR"]
            ?? "http://relay.a.central.eu.infra.zkrp.net:9001"
    )
    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.system.rawValue

    @State private var isOnboarded = UserProfile.load().isComplete

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
            .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}
