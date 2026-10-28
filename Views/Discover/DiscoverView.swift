//
//  DiscoverView.swift
//  FratRat
//

import SwiftUI
import PhotosUI

// MARK: - Swipe card model

struct SwipeProfile: Identifiable {
    let id = UUID()
    let name:          String
    let college:       String
    let year:          String
    let bio:           String
    let peerId:        String
    var photoBlobIds:  [String] = []
    var photoBlobKeys: [Data]   = []

    var hasPhotos: Bool { !photoBlobIds.isEmpty }

    var avatarInitials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}

// MARK: - DiscoverView

struct DiscoverView: View {
    @EnvironmentObject var mesh: MeshManager
    @State private var dragOffset:    CGSize = .zero
    @State private var showDieUpSheet = false
    @State private var dieUpStats    = (liked: 0, matched: 0)
    @State private var passedPeerIds: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: DiscoverView.passedKey) ?? [])

    /// Profiles passed on stay passed across launches (until Refresh).
    static let passedKey = "fratrat.passedPeerIds"

    /// Ranking puts people at your own college first.
    @State private var myCollege = UserProfile.load().college

    // Die Up animation state
    @State private var dieUpBatch:      [SwipeProfile] = []
    @State private var dieUpIndex:      Int            = 0
    @State private var dieUpCardOffset: CGSize         = .zero

    private var isDieingUp: Bool {
        !dieUpBatch.isEmpty && dieUpIndex < dieUpBatch.count
    }

    private func shouldShow(_ peerId: String) -> Bool {
        guard peerId != mesh.myPeerId else { return false }
        guard peerId != mesh.selectedRelay?.peerId else { return false }
        guard !passedPeerIds.contains(peerId) else { return false }
        guard !mesh.blockedPeerIds.contains(peerId) else { return false }
        switch mesh.relationships[peerId] {
        case .liked, .likedBy, .matched,
             .inviteSent, .inviteReceived, .inviteAccepted, .declined:
            return false
        case .some(.none): return true
        case .none:        return true
        }
    }

    private var profiles: [SwipeProfile] {
        let candidates = mesh.peerProfiles.values.filter { shouldShow($0.peerId) }
        return rankProfiles(myCollege: myCollege, profiles: Array(candidates))
            .map { p in
                SwipeProfile(
                    name:          p.displayName,
                    college:       p.college,
                    year:          p.year,
                    bio:           p.bio,
                    peerId:        p.peerId,
                    photoBlobIds:  p.photoBlobIds,
                    photoBlobKeys: p.photoBlobKeys
                )
            }
    }

    private var displayProfiles: [SwipeProfile] {
        #if REVIEW_BUILD
        return profiles.isEmpty ? SwipeProfile.mockProfiles : profiles
        #else
        return profiles
        #endif
    }

    private var currentProfile: SwipeProfile? { displayProfiles.first }

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Discover")
                            .font(.system(size: 34, weight: .black))
                            .foregroundColor(.fratDark)
                        HStack(spacing: 6) {
                            if mesh.connectionState.isConnected {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                    .shadow(color: .green.opacity(0.5), radius: 3)
                                Text("\(profiles.count) to discover")
                                    .font(.fratBody(14)).foregroundColor(.fratGray)
                            } else {
                                Image(systemName: "wifi.slash").font(.system(size: 12)).foregroundColor(.fratGray)
                                Text(mesh.connectionState.label).font(.fratBody(14)).foregroundColor(.fratGray)
                            }
                        }
                    }
                    Spacer()
                    Button { refreshProfiles() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 17, weight: .medium))
                            .foregroundColor(.fratDark).frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.fratCard))
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 16)

                // ── Card stack ────────────────────────────────────────────────
                ZStack {
                    if isDieingUp {
                        dieUpCardStack
                    } else if displayProfiles.isEmpty {
                        NoPeersCard(isConnected: mesh.connectionState.isConnected)
                    } else {
                        normalCardStack
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)

                // ── Action buttons ────────────────────────────────────────────
                HStack(spacing: 20) {
                    ActionButton(icon: "xmark", color: .fratPink, size: 58) { swipeLeft() }
                        .opacity(currentProfile == nil || isDieingUp ? 0.3 : 1)
                        .disabled(currentProfile == nil || isDieingUp)

                    Button { dieUp() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "dice.fill").font(.system(size: 18))
                            Text("Die Up").font(.fratBold(17))
                        }
                        .foregroundColor(.white).padding(.horizontal, 28).padding(.vertical, 18)
                        .background(Capsule().fill(
                            displayProfiles.isEmpty || isDieingUp ? Color.fratGray : Color.fratNavBar
                        ))
                    }
                    .disabled(displayProfiles.isEmpty || isDieingUp)

                    ActionButton(icon: "heart.fill", color: .fratPink, size: 58) { swipeRight() }
                        .opacity(currentProfile == nil || isDieingUp ? 0.3 : 1)
                        .disabled(currentProfile == nil || isDieingUp)
                }
                .padding(.bottom, 110).padding(.top, 8)
            }
        }
        .onChange(of: passedPeerIds) { _, ids in
            UserDefaults.standard.set(Array(ids), forKey: Self.passedKey)
        }
        .sheet(isPresented: $showDieUpSheet) {
            DieUpSheet(liked: dieUpStats.liked, matched: dieUpStats.matched, isPresented: $showDieUpSheet)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Normal card stack

    @ViewBuilder
    private var normalCardStack: some View {
        if displayProfiles.count > 1 {
            SwipeCard(profile: displayProfiles[1], offset: .zero)
                .scaleEffect(0.95).offset(y: 8)
        }
        if let profile = currentProfile {
            SwipeCard(profile: profile, offset: dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width) / 20))
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = $0.translation }
                        .onEnded { handleSwipe(translation: $0.translation) }
                )
                .overlay(
                    ZStack {
                        if dragOffset.width > 40 {
                            SwipeLabel(text: "LIKE", color: .green, rotation: -15)
                                .opacity(Double(min(dragOffset.width / 80, 1.0)))
                        }
                        if dragOffset.width < -40 {
                            SwipeLabel(text: "NOPE", color: .red, rotation: 15)
                                .opacity(Double(min(-dragOffset.width / 80, 1.0)))
                        }
                    }
                )
                .animation(.interactiveSpring(), value: dragOffset)
        }
    }

    // MARK: - Die Up card stack

    @ViewBuilder
    private var dieUpCardStack: some View {
        // Peek cards behind the flying card
        let remaining = Array(dieUpBatch.dropFirst(dieUpIndex + 1).prefix(2))
        ForEach(Array(remaining.enumerated()), id: \.element.peerId) { i, profile in
            SwipeCard(profile: profile, offset: .zero)
                .scaleEffect(1.0 - CGFloat(i + 1) * 0.05)
                .offset(y: CGFloat(i + 1) * 8)
                .allowsHitTesting(false)
        }

        // Current card flying off
        SwipeCard(profile: dieUpBatch[dieUpIndex], offset: dieUpCardOffset)
            .rotationEffect(.degrees(Double(dieUpCardOffset.width) / 20))
            .overlay(
                SwipeLabel(text: "LIKE", color: .green, rotation: -15)
                    .opacity(dieUpCardOffset.width > 40
                             ? Double(min(dieUpCardOffset.width / 80, 1.0)) : 0)
            )
            .allowsHitTesting(false)
    }

    // MARK: - Swipe actions

    private func handleSwipe(translation: CGSize) {
        if translation.width > 100      { swipeRight() }
        else if translation.width < -100 { swipeLeft() }
        else { withAnimation(.spring()) { dragOffset = .zero } }
    }

    private func swipeRight() {
        guard let profile = currentProfile else { return }
        Haptic.impact(.medium)
        withAnimation(.easeOut(duration: 0.3)) { dragOffset = CGSize(width: 500, height: 0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dragOffset = .zero
            Task { await mesh.sendLike(to: profile.peerId) }
        }
    }

    private func swipeLeft() {
        guard let profile = currentProfile else { return }
        Haptic.impact(.light)
        withAnimation(.easeOut(duration: 0.3)) { dragOffset = CGSize(width: -500, height: 0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            passedPeerIds.insert(profile.peerId)
            dragOffset = .zero
        }
    }

    // MARK: - Die Up

    private func dieUp() {
        guard !isDieingUp else { return }
        let batch = Array(displayProfiles.prefix(6))
        guard !batch.isEmpty else { return }

        Haptic.impact(.heavy)
        dieUpBatch      = batch
        dieUpIndex      = 0
        dieUpCardOffset = .zero
        dieUpStats      = (liked: batch.count, matched: 0)

        animateNextDieUpCard()
    }

    private func animateNextDieUpCard() {
        guard dieUpIndex < dieUpBatch.count else {
            // All cards done — clean up and show the sheet
            dieUpBatch      = []
            dieUpIndex      = 0
            dieUpCardOffset = .zero
            showDieUpSheet  = true
            return
        }

        let profile = dieUpBatch[dieUpIndex]
        Haptic.impact(.medium)

        withAnimation(.easeOut(duration: 0.25)) {
            dieUpCardOffset = CGSize(width: 500, height: -20)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // Send the like
            Task { await mesh.sendLike(to: profile.peerId) }

            // Snap offset back to zero without animation, advance index
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                dieUpIndex     += 1
                dieUpCardOffset = .zero
            }

            // Brief pause so the next card "lands" visually before flying off
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                animateNextDieUpCard()
            }
        }
    }

    private func refreshProfiles() {
        withAnimation { passedPeerIds = []; dragOffset = .zero }
    }
}

// MARK: - Swipe card

private struct SwipeCard: View {
    let profile: SwipeProfile
    let offset:  CGSize
    @EnvironmentObject var mesh: MeshManager

    var body: some View {
        ZStack(alignment: .bottom) {
            if profile.hasPhotos {
                MeshBlobPhotoCarousel(blobIds: profile.photoBlobIds, blobKeys: profile.photoBlobKeys,
                                      initials: profile.avatarInitials)
            } else {
                NoPhotoFallback(profile: profile)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(profile.name).font(.system(size: 26, weight: .black))
                                .foregroundColor(profile.hasPhotos ? .white : .fratDark)
                            Text(profile.year).font(.fratSemi(16))
                                .foregroundColor(profile.hasPhotos ? .white.opacity(0.9) : .fratGray)
                        }
                        Text(profile.college).font(.fratSemi(15))
                            .foregroundColor(profile.hasPhotos ? .white.opacity(0.85) : .fratGray)
                        if !profile.bio.isEmpty {
                            Text(profile.bio).font(.fratBody(14)).lineLimit(2)
                                .foregroundColor(profile.hasPhotos ? .white.opacity(0.8) : .fratGray)
                        }
                    }
                    Spacer()
                }
                .padding(20)
                .background(profile.hasPhotos
                    ? LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .offset(offset)
    }
}

// MARK: - Mesh blob photo carousel

private struct MeshBlobPhotoCarousel: View {
    let blobIds:  [String]
    let blobKeys: [Data]
    let initials: String
    @State private var currentIndex = 0
    @EnvironmentObject var mesh: MeshManager

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                MeshImage(
                    blobId:      blobIds.indices.contains(currentIndex) ? blobIds[currentIndex] : nil,
                    blobKey:     blobKeys.indices.contains(currentIndex) ? blobKeys[currentIndex] : nil,
                    initials:    initials,
                    size:        geo.size.height,
                    cornerRadius: 0,
                    contentMode: .fill
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                if blobIds.count > 1 {
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if currentIndex > 0 { withAnimation { currentIndex -= 1 } }
                            }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if currentIndex < blobIds.count - 1 { withAnimation { currentIndex += 1 } }
                            }
                    }

                    HStack(spacing: 4) {
                        ForEach(blobIds.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == currentIndex ? Color.white : Color.white.opacity(0.5))
                                .frame(width: i == currentIndex ? 20 : 6, height: 4)
                                .animation(.easeInOut(duration: 0.2), value: currentIndex)
                        }
                    }
                    .padding(.bottom, 72)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - No photo fallback

private struct NoPhotoFallback: View {
    let profile: SwipeProfile
    private var gradient: LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.95, green: 0.85, blue: 0.9), Color(red: 0.9, green: 0.75, blue: 0.85)],
            [Color(red: 0.85, green: 0.9, blue: 0.95), Color(red: 0.75, green: 0.82, blue: 0.92)],
            [Color(red: 0.92, green: 0.88, blue: 0.95), Color(red: 0.84, green: 0.78, blue: 0.92)],
            [Color(red: 0.95, green: 0.92, blue: 0.85), Color(red: 0.9, green: 0.85, blue: 0.75)],
        ]
        let idx = abs(profile.peerId.hashValue) % palettes.count
        return LinearGradient(colors: palettes[idx], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var body: some View {
        ZStack {
            gradient
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.4)).frame(width: 110, height: 110)
                    Text(profile.avatarInitials.isEmpty ? "?" : profile.avatarInitials)
                        .font(.system(size: 44, weight: .black)).foregroundColor(.fratDark.opacity(0.7))
                }
                VStack(spacing: 6) {
                    Text(profile.name).font(.system(size: 24, weight: .black)).foregroundColor(.fratDark)
                    Text(profile.college).font(.fratSemi(15)).foregroundColor(.fratDark.opacity(0.6))
                    HStack(spacing: 5) {
                        Image(systemName: "photo.slash").font(.system(size: 11))
                        Text("No photos yet").font(.fratSemi(12))
                    }
                    .foregroundColor(.fratDark.opacity(0.5))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.4))).padding(.top, 4)
                }
                if !profile.bio.isEmpty {
                    Text(profile.bio).font(.fratBody(15)).foregroundColor(.fratDark.opacity(0.7))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers

private struct NoPeersCard: View {
    let isConnected: Bool
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.fratPinkLight).frame(width: 80, height: 80)
                Image(systemName: isConnected ? "person.2.slash" : "wifi.slash")
                    .font(.system(size: 32)).foregroundColor(.fratPink)
            }
            Text(isConnected ? "No one nearby yet" : "Not connected")
                .font(.fratBold(22)).foregroundColor(.fratDark)
            Text(isConnected
                 ? "Waiting for other students to join the mesh.\nTry again at a campus event."
                 : "Connect to a relay from the landing screen\nto find people nearby.")
                .font(.fratBody(15)).foregroundColor(.fratGray).multilineTextAlignment(.center)
        }
        .padding(36).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.fratCard))
    }
}

private struct SwipeLabel: View {
    let text: String; let color: Color; let rotation: Double
    var body: some View {
        Text(text).font(.system(size: 36, weight: .black)).foregroundColor(color)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 4))
            .rotationEffect(.degrees(rotation))
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: text == "LIKE" ? .topLeading : .topTrailing)
            .padding(24)
    }
}

private struct ActionButton: View {
    let icon: String; let color: Color; let size: CGFloat; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.38, weight: .bold)).foregroundColor(color)
                .frame(width: size, height: size).background(Circle().fill(Color.fratCard))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
    }
}

struct DieUpSheet: View {
    let liked: Int; let matched: Int
    @Binding var isPresented: Bool
    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()
            VStack(spacing: 20) {
                Capsule().fill(Color.fratGray.opacity(0.3)).frame(width: 36, height: 4).padding(.top, 12)
                Spacer()
                ZStack {
                    Circle().fill(Color.fratPinkLight).frame(width: 80, height: 80)
                    Image(systemName: "dice.fill").font(.system(size: 32)).foregroundColor(.fratPink)
                }
                Text("Die Up").font(.system(size: 26, weight: .black)).foregroundColor(.fratDark)
                Text("Liked \(liked) profile\(liked == 1 ? "" : "s") · \(matched) new match\(matched == 1 ? "" : "es")")
                    .font(.fratBody(15)).foregroundColor(.fratGray)
                Button { isPresented = false } label: {
                    Text("Nice").font(.fratSemi(17)).foregroundColor(.fratGray)
                        .padding(.horizontal, 44).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
                }
                .padding(.top, 4)
                Spacer()
            }
        }
    }
}

extension SwipeProfile {
    static let mockProfiles: [SwipeProfile] = [
        SwipeProfile(name: "Sarah Johnson", college: "Iowa State", year: "Junior",
                     bio: "ΑΧΩ · loves hiking & live music 🎶", peerId: "12D3KooWABC123"),
        SwipeProfile(name: "Jake Miller",   college: "Iowa State", year: "Senior",
                     bio: "ΣΑΕ · pre-law, intramural champ 🏆", peerId: "12D3KooWDEF456"),
        SwipeProfile(name: "Emma Davis",    college: "Iowa State", year: "Sophomore",
                     bio: "ΔΔΔ · coffee addict & art major ☕",  peerId: "12D3KooWGHI789"),
        SwipeProfile(name: "Tyler Brooks",  college: "Iowa State", year: "Junior",
                     bio: "ΠΚΑ · STEM nerd who throws parties 🎉", peerId: "12D3KooWJKL012"),
        SwipeProfile(name: "Maya Chen",     college: "Iowa State", year: "Freshman",
                     bio: "ΚΚΓ · pre-med & dance captain 💃",    peerId: "12D3KooWMNO345"),
        SwipeProfile(name: "Jordan Lee",    college: "Iowa State", year: "Senior",
                     bio: "ΔΧ · CS major & startup guy 🚀",      peerId: "12D3KooWPQR678"),
    ]
}

#Preview { DiscoverView().environmentObject(MeshManager()) }
