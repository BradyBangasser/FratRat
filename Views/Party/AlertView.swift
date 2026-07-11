//
//  AlertView.swift
//  FratRat
//
//  Created by Brady Bangasser on 6/1/26.
//

import SwiftUI
import MapKit

// MARK: - Alert map pin
struct AlertPin: View {
    let alert: CampusAlert
    let onTap: () -> Void
    @State private var pressed = false
    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    // Pulse ring
                    Circle()
                        .fill(alert.type.color.opacity(0.15))
                        .frame(width: pulse ? 64 : 52, height: pulse ? 64 : 52)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: pulse
                        )

                    // Main circle — diamond shape for alerts vs circle for parties
                    RoundedRectangle(cornerRadius: 10)
                        .fill(alert.type.color)
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(45))
                        .shadow(color: alert.type.color.opacity(0.5), radius: 6, y: 3)

                    Image(systemName: alert.type.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(pressed ? 0.88 : 1.0)

                // Pin tail
                Triangle()
                    .fill(alert.type.color)
                    .frame(width: 14, height: 7)
                    .offset(y: -1)

                // Time ago badge
                Text(alert.timeAgoString)
                    .font(.fratBold(10))
                    .foregroundColor(.fratDark)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                    )
                    .offset(y: 2)
            }
        }
        .buttonStyle(.plain)
        .onAppear { pulse = true }
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressing in
            withAnimation(.easeInOut(duration: 0.1)) { pressed = isPressing }
        }, perform: {})
    }
}

// MARK: - Alert detail sheet
struct AlertDetailView: View {
    let alert: CampusAlert
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion

    init(alert: CampusAlert) {
        self.alert = alert
        _region = State(initialValue: MKCoordinateRegion(
            center: alert.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        ))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.fratBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Mini map ──────────────────────────────────────────────
                    Map(coordinateRegion: $region, annotationItems: [alert]) { a in
                        MapAnnotation(coordinate: a.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(alert.type.color.opacity(0.2))
                                    .frame(width: 52, height: 52)
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(alert.type.color)
                                    .frame(width: 38, height: 38)
                                    .rotationEffect(.degrees(45))
                                    .shadow(color: alert.type.color.opacity(0.4), radius: 8)
                                Image(systemName: alert.type.icon)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(height: 200)
                    .disabled(true)

                    VStack(alignment: .leading, spacing: 20) {

                        // Type badge + title
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Capsule()
                                        .fill(alert.type.color.opacity(0.12))
                                    HStack(spacing: 5) {
                                        Image(systemName: alert.type.icon)
                                            .font(.system(size: 11, weight: .bold))
                                        Text(alert.type.rawValue)
                                            .font(.fratSemi(12))
                                    }
                                    .foregroundColor(alert.type.color)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                }
                                Text(alert.timeAgoString)
                                    .font(.fratBody(12))
                                    .foregroundColor(.fratGray)
                            }

                            Text(alert.type.rawValue)
                                .font(.system(size: 26, weight: .black))
                                .foregroundColor(.fratDark)
                        }

                        // Description if present
                        if !alert.description.isEmpty {
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.fratDark.opacity(0.08))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "text.bubble.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.fratDark)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("DETAILS")
                                        .font(.fratSemi(11))
                                        .foregroundColor(.fratGray)
                                    Text(alert.description)
                                        .font(.fratSemi(15))
                                        .foregroundColor(.fratDark)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                        }

                        // Expiry info
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.fratGray.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "clock.badge.xmark.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.fratGray)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("EXPIRES")
                                    .font(.fratSemi(11))
                                    .foregroundColor(.fratGray)
                                Text("Auto-removed after 1 hour")
                                    .font(.fratSemi(15))
                                    .foregroundColor(.fratDark)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))

                        // Anonymous notice
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.fratGray)
                            Text("Posted anonymously — no identity is shared")
                                .font(.fratBody(13))
                                .foregroundColor(.fratGray)
                        }

                        // Dismiss button
                        Button { dismiss() } label: {
                            Text("Got it, stay safe 👍")
                                .font(.fratBold(17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(alert.type.color)
                                )
                        }
                        .padding(.top, 4)
                    }
                    .padding(24)
                    .padding(.bottom, 60)
                }
            }

            // ── Close button ──────────────────────────────────────────────────
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.fratDark)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.9)))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
    }
}

// MARK: - Post alert sheet
struct PostAlertView: View {
    let onPost: (CampusAlert) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: CampusAlert.AlertType = .security
    @State private var description = ""
    @State private var confirmed = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Warning header
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Campus Safety Alert")
                                    .font(.fratBold(16))
                                    .foregroundColor(.fratDark)
                                Text("Anonymous — your identity is never shared")
                                    .font(.fratBody(13))
                                    .foregroundColor(.fratGray)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.orange.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                                )
                        )

                        // Alert type grid
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ALERT TYPE")
                                .font(.fratSemi(11))
                                .foregroundColor(.fratGray)

                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: 10
                            ) {
                                ForEach(CampusAlert.AlertType.allCases, id: \.self) { type in
                                    Button {
                                        selectedType = type
                                    } label: {
                                        HStack(spacing: 10) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(selectedType == type
                                                          ? type.color
                                                          : type.color.opacity(0.12))
                                                    .frame(width: 32, height: 32)
                                                Image(systemName: type.icon)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(selectedType == type ? .white : type.color)
                                            }
                                            Text(type.rawValue)
                                                .font(.fratSemi(13))
                                                .foregroundColor(.fratDark)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer()
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(
                                                            selectedType == type
                                                            ? selectedType.color
                                                            : Color.clear,
                                                            lineWidth: 2
                                                        )
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Optional description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DETAILS (OPTIONAL)")
                                .font(.fratSemi(11))
                                .foregroundColor(.fratGray)
                            ZStack(alignment: .topLeading) {
                                if description.isEmpty {
                                    Text("e.g. Ash Ave between Welch and Stanton")
                                        .font(.fratBody(15))
                                        .foregroundColor(.fratGray.opacity(0.6))
                                        .padding(14)
                                }
                                TextEditor(text: $description)
                                    .font(.fratBody(15))
                                    .frame(minHeight: 70)
                                    .padding(10)
                                    .scrollContentBackground(.hidden)
                            }
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                        }

                        // Confirm checkbox
                        Button {
                            withAnimation { confirmed.toggle() }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(confirmed ? Color.fratPink : Color.white)
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(
                                                    confirmed ? Color.fratPink : Color.gray.opacity(0.3),
                                                    lineWidth: 1.5
                                                )
                                        )
                                    if confirmed {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                Text("I confirm this is a genuine safety alert")
                                    .font(.fratBody(14))
                                    .foregroundColor(.fratDark)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        // Post button
                        Button {
                            postAlert()
                        } label: {
                            Text("Post alert")
                                .font(.fratBold(17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(!confirmed ? Color.fratGray : selectedType.color)
                                )
                        }
                        .disabled(!confirmed)
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Post Safety Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.fratPink)
                }
            }
        }
    }

    private func postAlert() {
        let alert = CampusAlert(
            type: selectedType,
            // Use device location when available — placeholder for now
            coordinate: CLLocationCoordinate2D(latitude: 42.0267, longitude: -93.6465),
            description: description,
            peerId: "local",
            postedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        onPost(alert)
        // TODO: broadcast over mesh
        dismiss()
    }
}

// MARK: - Incoming alert banner
// Slides in from the top when a new alert arrives over the mesh
struct AlertBanner: View {
    let alert: CampusAlert
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(alert.type.color)
                        .frame(width: 36, height: 36)
                    Image(systemName: alert.type.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.type.rawValue)
                        .font(.fratBold(14))
                        .foregroundColor(.fratDark)
                    Text(alert.description.isEmpty
                         ? "Nearby · \(alert.timeAgoString)"
                         : alert.description)
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.fratGray)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.fratBg))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(alert.type.color.opacity(0.3), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
