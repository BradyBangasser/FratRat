//
//  MainTabView.swift
//  FratRat
//

import SwiftUI

enum Tab {
    case discover, messages, parties, profile, settings
}

struct MainTabView: View {
    @EnvironmentObject var mesh: MeshManager
    @State private var selectedTab: Tab = .discover
    @State private var bannerEvent: BannerEvent? = nil
    @State private var bannerVisible = false
    @State private var bannerTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Tab content ───────────────────────────────────────────────────
            Group {
                switch selectedTab {
                case .discover:  DiscoverView()
                case .messages:  MatchesView()
                case .parties:   PartiesView()
                case .profile:   ProfileView()
                case .settings:  SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Tab bar ───────────────────────────────────────────────────────
            CustomTabBar(selectedTab: $selectedTab)

            // ── In-app notification banner ────────────────────────────────────
            if bannerVisible, let event = bannerEvent {
                NotificationBanner(event: event) {
                    selectedTab = event.kind.tab
                    dismissBanner()
                } onDismiss: {
                    dismissBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onReceive(mesh.$banner) { event in
            guard let event else { return }
            showBanner(event)
        }
    }

    private func showBanner(_ event: BannerEvent) {
        bannerTask?.cancel()
        bannerEvent   = event
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            bannerVisible = true
        }
        bannerTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { dismissBanner() }
        }
    }

    private func dismissBanner() {
        withAnimation(.easeInOut(duration: 0.25)) {
            bannerVisible = false
        }
    }
}

// MARK: - Notification banner

private struct NotificationBanner: View {
    let event:     BannerEvent
    let onTap:     () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(event.kind.color.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: event.kind.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(event.kind.color)
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.fratBold(14))
                        .foregroundColor(.fratDark)
                        .lineLimit(1)
                    Text(event.body)
                        .font(.fratBody(13))
                        .foregroundColor(.fratGray)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.fratGray)
                        .padding(6)
                        .background(Circle().fill(Color.fratBg))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.fratCard)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            )
            .overlay(
                // Colored left accent bar
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(event.kind.color)
                    .frame(width: 4)
                    .padding(.vertical, 8),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -30 {
                        onDismiss()
                    } else {
                        withAnimation(.spring()) { dragOffset = 0 }
                    }
                }
        )
    }
}

// MARK: - Custom tab bar

struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    @EnvironmentObject var mesh: MeshManager

    private let items: [(tab: Tab, icon: String, label: String)] = [
        (.discover, "flame.fill",     "Discover"),
        (.messages, "message.fill",   "Messages"),
        (.parties,  "music.note",     "Parties"),
        (.profile,  "person.fill",    "Profile"),
        (.settings, "gearshape.fill", "Settings"),
    ]

    private var totalBadge: Int {
        mesh.pendingRequestCount + mesh.unreadCounts.values.reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.label) { item in
                Button {
                    selectedTab = item.tab
                } label: {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 22, weight: .medium))
                            Text(item.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(selectedTab == item.tab ? .fratPink : .fratOnDark.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 28)

                        // Badge on Messages tab
                        if item.tab == .messages && totalBadge > 0 {
                            Text(totalBadge > 99 ? "99+" : "\(totalBadge)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.fratPink))
                                .offset(x: -10, y: 6)
                        }
                    }
                }
            }
        }
        .background(
            Color.fratNavBar
                .overlay(Divider().opacity(0.3), alignment: .top)
        )
    }
}

#Preview {
    MainTabView().environmentObject(MeshManager())
}
