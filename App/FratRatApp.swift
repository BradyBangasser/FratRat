//
//  FratRatApp.swift
//  FratRat
//

import SwiftUI
import UserNotifications

// MARK: - Push

extension Notification.Name {
    static let pushTokenChanged = Notification.Name("fratrat.pushTokenChanged")
}

/// Receives the APNs device token. The token is only ever sent sealed to the
/// push service (see MeshManager.registerPush); relays can't read or link it.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// This launch's device token, once iOS hands it over.
    static private(set) var pushToken: Data?

    /// Development builds get tokens for Apple's sandbox push servers.
    static var pushSandbox: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Ask once for permission, then for a token (iOS remembers the answer).
    static func enablePush() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.pushToken = deviceToken
        NotificationCenter.default.post(name: .pushTokenChanged, object: nil)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Swift.print("[push] no token: \(error.localizedDescription)")
    }

    /// In the foreground the app shows its own banner; skip the system one.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        []
    }
}

@main
struct FratRatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                        .task { await AppDelegate.enablePush() }
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
                guard phase == .active else { return }
                enrollment.refresh()
                Task { await mesh.fetchMissedMessages() }
            }
            // A renewal brings this epoch's campus keys: start using them.
            .onChange(of: enrollment.expiresAt) { _, _ in
                Task { await mesh.refreshConversationSubscriptions() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushTokenChanged)) { _ in
                Task { await mesh.registerPushForAllConversations() }
            }
            .onChange(of: mesh.dataDeleted) { _, deleted in
                guard deleted else { return }
                enrollment.refresh()
                isOnboarded = false
                mesh.dataDeleted = false
            }
        }
    }
}
