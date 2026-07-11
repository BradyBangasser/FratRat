//
//  PartiesView.swift
//  FratRat
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Location manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation? = nil
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
        if authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func distanceString(to coordinate: CLLocationCoordinate2D) -> String {
        guard let loc = location else { return "? mi" }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let meters = loc.distance(from: target)
        let miles  = meters / 1609.34
        if miles < 0.1 { return "< 0.1 mi" }
        if miles < 10   { return String(format: "%.1f mi", miles) }
        return "\(Int(miles)) mi"
    }
}

// MARK: - PartyProfile display helpers
// PartyProfile is defined in ghost_ios (Rust FFI).
extension PartyProfile {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var isExpired: Bool { UInt64(Date().timeIntervalSince1970) > expires }
    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

    var timeString: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: startDate)
    }

    var vibeColor: Color {
        switch vibe.lowercased() {
        case "darty":    return Color(red: 1.0, green: 0.55, blue: 0.15)
        case "rager":    return Color.fratPink
        case "kickback": return Color(red: 0.3, green: 0.75, blue: 0.45)
        case "formal":   return Color(red: 0.35, green: 0.45, blue: 0.85)
        default:         return Color.fratGray
        }
    }

    var vibeIcon: String {
        switch vibe.lowercased() {
        case "darty":    return "sun.max.fill"
        case "rager":    return "flame.fill"
        case "kickback": return "sofa.fill"
        case "formal":   return "crown.fill"
        default:         return "music.note"
        }
    }
}

// MARK: - AlertProfile display helpers
// AlertProfile is defined in ghost_ios (Rust FFI).
extension AlertProfile {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var isExpired: Bool { UInt64(Date().timeIntervalSince1970) > expires }
    var postedAt: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

    var timeAgoString: String {
        let diff = Int(Date().timeIntervalSince(postedAt))
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(diff / 60)m ago" }
        return "\(diff / 3600)h ago"
    }

    var alertType: AlertDisplayType { AlertDisplayType(rawValue: name) ?? .general }
}

// MARK: - AlertDisplayType
// Derived from AlertProfile.name — purely for UI display, not stored.
enum AlertDisplayType: String, CaseIterable {
    case security    = "Security activity"
    case disruption  = "Event disruption"
    case noise       = "Noise complaint"
    case dispersing  = "Crowd dispersing"
    case general     = "Safety alert"

    var icon: String {
        switch self {
        case .security:   return "shield.fill"
        case .disruption: return "exclamationmark.triangle.fill"
        case .noise:      return "speaker.wave.3.fill"
        case .dispersing: return "figure.walk"
        case .general:    return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .security:   return Color(red: 0.0, green: 0.0, blue: 0.8)
        case .disruption: return Color(red: 0.95, green: 0.5, blue: 0.1)
        case .noise:      return Color(red: 0.8, green: 0.6, blue: 0.1)
        case .dispersing: return Color(red: 0.5, green: 0.4, blue: 0.8)
        case .general:    return Color(red: 0.9, green: 0.3, blue: 0.3)
        }
    }

    var emoji: String {
        switch self {
        case .security:   return "🚔"
        case .disruption: return "🔴"
        case .noise:      return "🟡"
        case .dispersing: return "🟠"
        case .general:    return "⚠️"
        }
    }
}

// MARK: - FFI type conformances
extension PartyProfile: Identifiable {}
extension AlertProfile: Identifiable {}
extension PartyProfile {
    public static func == (lhs: PartyProfile, rhs: PartyProfile) -> Bool { lhs.id == rhs.id }
}
extension AlertProfile {
    public static func == (lhs: AlertProfile, rhs: AlertProfile) -> Bool { lhs.id == rhs.id }
}

// MARK: - Map annotation wrappers
struct PartyAnnotation: Identifiable {
    let id: UInt64
    let coordinate: CLLocationCoordinate2D
    let party: PartyProfile
}

struct AlertAnnotation: Identifiable {
    let id: UInt64
    let coordinate: CLLocationCoordinate2D
    let alert: AlertProfile
}

// MARK: - PartiesView
struct PartiesView: View {
    @EnvironmentObject var mesh: MeshManager
    @State private var selectedParty: PartyProfile?
    @State private var selectedAlert: AlertProfile?
    @State private var showPost = false
    @State private var showPostAlert = false
    @State private var activeBanner: AlertProfile?
    @State private var showBanner = false
    @State private var didCenterOnUser = false
    @StateObject private var locationManager = LocationManager()

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.0267, longitude: -93.6465),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    )

    private var now: UInt64 { UInt64(Date().timeIntervalSince1970) }

    private var liveParties: [PartyProfile] {
        mesh.parties.values.filter { $0.expires > now }.sorted { $0.timestamp > $1.timestamp }
    }

    private var liveAlerts: [AlertProfile] {
        mesh.alerts.values.filter { $0.expires > now }.sorted { $0.timestamp > $1.timestamp }
    }

    private var partyAnnotations: [PartyAnnotation] {
        liveParties.map { PartyAnnotation(id: $0.id, coordinate: $0.coordinate, party: $0) }
    }

    private var alertAnnotations: [AlertAnnotation] {
        liveAlerts.map { AlertAnnotation(id: $0.id, coordinate: $0.coordinate, alert: $0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapWithAlerts(
                region: $region,
                partyAnnotations: partyAnnotations,
                alertAnnotations: alertAnnotations,
                onPartyTap: { selectedParty = $0 },
                onAlertTap: { selectedAlert = $0 }
            )
            .ignoresSafeArea()

            // ── Header ────────────────────────────────────────────────────
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Parties")
                            .font(.system(size: 30, weight: .black))
                            .foregroundColor(.fratDark)
                        HStack(spacing: 8) {
                            Text("\(liveParties.count) tonight on campus")
                                .font(.fratBody(13))
                                .foregroundColor(.fratGray)
                            if !alertAnnotations.isEmpty {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.red).frame(width: 6, height: 6)
                                    Text("\(alertAnnotations.count) alert\(alertAnnotations.count == 1 ? "" : "s")")
                                        .font(.fratSemi(12))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 14)
                .background(Color.fratBg.opacity(0.95).ignoresSafeArea(edges: .top))
            }

            // ── Alert banner ──────────────────────────────────────────────
            if showBanner, let banner = activeBanner {
                VStack {
                    AlertBanner(
                        alert: banner,
                        onTap: { selectedAlert = banner; withAnimation { showBanner = false } },
                        onDismiss: { withAnimation { showBanner = false } }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 140)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }

            // ── FABs ──────────────────────────────────────────────────────
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Button { showPostAlert = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Alert").font(.fratBold(14))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.9, green: 0.2, blue: 0.2))
                                .shadow(color: Color.red.opacity(0.4), radius: 10, y: 4)
                        )
                    }
                    .padding(.leading, 24)
                    Spacer()
                    Button { showPost = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.fratPink))
                            .shadow(color: Color.fratPink.opacity(0.5), radius: 14, y: 5)
                    }
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 100)
            }
        }
        .sheet(item: $selectedParty) { PartyDetailView(party: $0, locationManager: locationManager) }
        .sheet(item: $selectedAlert) { AlertDetailView(alert: $0) }
        .sheet(isPresented: $showPost) {
            PostPartyView { newParty in
                Task { await mesh.postParty(newParty) }
                withAnimation { region.center = newParty.coordinate }
            }
        }
        .sheet(isPresented: $showPostAlert) {
            PostAlertView { newAlert in
                Task { await mesh.postAlert(newAlert) }
                withAnimation { region.center = newAlert.coordinate }
                activeBanner = newAlert
                withAnimation { showBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { showBanner = false }
                }
            }
            .environmentObject(locationManager)
        }
        .onChange(of: locationManager.location) { loc in
            mesh.userLocation = loc        // keep MeshManager in sync for alert distance checks
            guard let loc, !didCenterOnUser else { return }
            didCenterOnUser = true
            withAnimation { region.center = loc.coordinate }
        }
    }
}

// MARK: - Unified map
private struct MapWithAlerts: View {
    @Binding var region: MKCoordinateRegion
    let partyAnnotations: [PartyAnnotation]
    let alertAnnotations: [AlertAnnotation]
    let onPartyTap: (PartyProfile) -> Void
    let onAlertTap: (AlertProfile) -> Void

    private var allItems: [MapItem] {
        partyAnnotations.map { .party($0) } + alertAnnotations.map { .alert($0) }
    }

    var body: some View {
        Map(
            coordinateRegion: $region,
            showsUserLocation: true,
            userTrackingMode: .constant(.none),
            annotationItems: allItems
        ) { item in
            MapAnnotation(coordinate: item.coordinate) {
                switch item {
                case .party(let a): PartyPin(party: a.party) { onPartyTap(a.party) }
                case .alert(let a): AlertPin(alert: a.alert) { onAlertTap(a.alert) }
                }
            }
        }
    }
}

private enum MapItem: Identifiable {
    case party(PartyAnnotation); case alert(AlertAnnotation)
    var id: UInt64 {
        switch self { case .party(let a): return a.id; case .alert(let a): return a.id }
    }
    var coordinate: CLLocationCoordinate2D {
        switch self { case .party(let a): return a.coordinate; case .alert(let a): return a.coordinate }
    }
}

// MARK: - Party pin
private struct PartyPin: View {
    let party: PartyProfile; let onTap: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(party.vibeColor.opacity(0.25)).frame(width: 56, height: 56)
                    Circle().fill(party.vibeColor).frame(width: 44, height: 44)
                        .shadow(color: party.vibeColor.opacity(0.5), radius: 6, y: 3)
                    Image(systemName: party.vibeIcon)
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                }
                .scaleEffect(pressed ? 0.88 : 1.0)
                Triangle().fill(party.vibeColor).frame(width: 14, height: 7).offset(y: -1)
                Text("\(party.attend)")
                    .font(.fratBold(11)).foregroundColor(.fratDark)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.fratCard).shadow(color: .black.opacity(0.1), radius: 3, y: 1))
                    .offset(y: 2)
            }
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressing in
            withAnimation(.easeInOut(duration: 0.1)) { pressed = isPressing }
        }, perform: {})
    }
}

// MARK: - Triangle
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Alert pin
struct AlertPin: View {
    let alert: AlertProfile; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle().fill(alert.alertType.color.opacity(0.2)).frame(width: 52, height: 52)
                Circle().fill(alert.alertType.color).frame(width: 38, height: 38)
                    .shadow(color: alert.alertType.color.opacity(0.5), radius: 6, y: 3)
                Image(systemName: alert.alertType.icon)
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Party detail
struct PartyDetailView: View {
    let party: PartyProfile; let locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion

    init(party: PartyProfile, locationManager: LocationManager) {
        self.party = party; self.locationManager = locationManager
        _region = State(initialValue: MKCoordinateRegion(
            center: party.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        ))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.fratBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Mini map
                    ZStack {
                        Map(coordinateRegion: $region, annotationItems: [party]) { p in
                            MapAnnotation(coordinate: p.coordinate) {
                                ZStack {
                                    Circle().fill(party.vibeColor.opacity(0.25)).frame(width: 52, height: 52)
                                    Circle().fill(party.vibeColor).frame(width: 40, height: 40)
                                        .shadow(color: party.vibeColor.opacity(0.4), radius: 8)
                                    Image(systemName: party.vibeIcon)
                                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                }
                            }
                        }
                        .frame(height: 220).disabled(true)
                        VStack { Spacer()
                            HStack { Spacer()
                                Button { openInMaps() } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                            .font(.system(size: 14))
                                        Text("Directions").font(.fratSemi(13))
                                    }
                                    .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(Color.fratDark.opacity(0.85)))
                                }.padding(12)
                            }
                        }
                    }
                    .frame(height: 220)

                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(party.title)
                                .font(.system(size: 28, weight: .black)).foregroundColor(.fratDark)
                            HStack(spacing: 5) {
                                Image(systemName: party.vibeIcon).font(.system(size: 10, weight: .bold))
                                Text(party.vibe).font(.fratSemi(12))
                            }
                            .foregroundColor(party.vibeColor)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(party.vibeColor.opacity(0.12)))
                        }

                        HStack(spacing: 12) {
                            StatPill(icon: "clock.fill", value: party.timeString, label: "start time", color: party.vibeColor)
                            StatPill(icon: "person.2.fill", value: "\(party.attend)", label: "going", color: party.vibeColor)
                            StatPill(icon: "location.fill",
                                     value: locationManager.distanceString(to: party.coordinate),
                                     label: "away", color: party.vibeColor)
                            if party.cap > 0 {
                                StatPill(icon: "door.left.hand.open", value: "\(party.cap)", label: "cap", color: party.vibeColor)
                            }
                        }

                        DetailRow(icon: "person.fill", iconColor: .fratDark, title: "Hosted by", value: party.host)
                        DetailRow(icon: "mappin.circle.fill", iconColor: party.vibeColor, title: "Location", value: party.address)
                        if !party.description.isEmpty {
                            DetailRow(icon: "text.bubble.fill", iconColor: .fratGray, title: "Details", value: party.description)
                        }
                        DetailRow(icon: "clock.badge.xmark.fill", iconColor: .fratGray, title: "Auto-expires", value: "24 hours after posting")

                        Button {} label: {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                Text("I'm going 🎉").font(.fratBold(17))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(RoundedRectangle(cornerRadius: 16).fill(party.vibeColor))
                        }
                        .padding(.top, 4)
                    }
                    .padding(24).padding(.bottom, 60)
                }
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.fratDark)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.fratCard.opacity(0.9)))
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 56)
        }
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: party.coordinate))
        item.name = party.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

// MARK: - Alert detail
struct AlertDetailView: View {
    let alert: AlertProfile
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()
            VStack(spacing: 20) {
                Capsule().fill(Color.fratGray.opacity(0.3)).frame(width: 36, height: 4).padding(.top, 10)
                ZStack {
                    Circle().fill(alert.alertType.color.opacity(0.15)).frame(width: 72, height: 72)
                    Image(systemName: alert.alertType.icon).font(.system(size: 30)).foregroundColor(alert.alertType.color)
                }
                VStack(spacing: 6) {
                    Text(alert.alertType.emoji + " " + alert.name)
                        .font(.fratBold(22)).foregroundColor(.fratDark).multilineTextAlignment(.center)
                    Text(alert.timeAgoString).font(.fratBody(13)).foregroundColor(.fratGray)
                }
                if !alert.description.isEmpty {
                    Text(alert.description).font(.fratBody(15)).foregroundColor(.fratDark)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
                Spacer()
                Button { dismiss() } label: {
                    Text("Dismiss").font(.fratSemi(16)).foregroundColor(.fratDark)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Alert banner
struct AlertBanner: View {
    let alert: AlertProfile; let onTap: () -> Void; let onDismiss: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(alert.alertType.color.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: alert.alertType.icon).font(.system(size: 16)).foregroundColor(alert.alertType.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.name).font(.fratBold(14)).foregroundColor(.white)
                    Text("Tap to view details").font(.fratBody(12)).foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(alert.alertType.color)
                    .shadow(color: alert.alertType.color.opacity(0.4), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat pill
private struct StatPill: View {
    let icon: String; let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 15)).foregroundColor(color)
            Text(value).font(.fratBold(14)).foregroundColor(.fratDark)
            Text(label).font(.fratBody(10)).foregroundColor(.fratGray)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
    }
}

// MARK: - Detail row
private struct DetailRow: View {
    let icon: String; let iconColor: Color; let title: String; let value: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(iconColor.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.fratSemi(11)).foregroundColor(.fratGray)
                Text(value).font(.fratSemi(15)).foregroundColor(.fratDark)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
    }
}

// MARK: - Post party
struct PostPartyView: View {
    let onPost: (PartyProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var address = ""
    @State private var description = ""
    @State private var selectedVibe = "Rager"
    @State private var startTime = Date()
    @State private var capacity = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedLocation: MKMapItem?

    let vibes: [(String, String)] = [
        ("Rager","flame.fill"),("Darty","sun.max.fill"),
        ("Kickback","sofa.fill"),("Formal","crown.fill")
    ]

    var canPost: Bool { !title.isEmpty && selectedLocation != nil }

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        PostField(label: "PARTY NAME") {
                            TextField("e.g. SAE Friday Night", text: $title).font(.fratBody(15))
                        }

                        PostField(label: "ADDRESS") {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    TextField("Search address…", text: $address).font(.fratBody(15))
                                        .onChange(of: address) { searchLocation($0) }
                                    if selectedLocation != nil {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                    }
                                }
                                if !searchResults.isEmpty {
                                    Divider().padding(.top, 8)
                                    ForEach(searchResults, id: \.self) { item in
                                        Button {
                                            selectedLocation = item
                                            address = item.name ?? ""
                                            searchResults = []
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "mappin.circle.fill").foregroundColor(.fratPink)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name ?? "").font(.fratSemi(14)).foregroundColor(.fratDark)
                                                    Text(item.placemark.title ?? "")
                                                        .font(.fratBody(12)).foregroundColor(.fratGray).lineLimit(1)
                                                }
                                            }.padding(.vertical, 8)
                                        }.buttonStyle(.plain)
                                        if item != searchResults.last { Divider() }
                                    }
                                }
                            }
                        }

                        PostField(label: "DETAILS (OPTIONAL)") {
                            TextField("Any extra info…", text: $description, axis: .vertical)
                                .font(.fratBody(15)).lineLimit(1...3)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("VIBE").font(.fratSemi(11)).foregroundColor(.fratGray)
                            HStack(spacing: 10) {
                                ForEach(vibes, id: \.0) { vibe, icon in
                                    Button { selectedVibe = vibe } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle().fill(selectedVibe == vibe ? vibeColor(vibe) : Color.fratCard).frame(width: 48, height: 48)
                                                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                                                    .foregroundColor(selectedVibe == vibe ? .white : .fratGray)
                                            }
                                            Text(vibe).font(.fratSemi(11))
                                                .foregroundColor(selectedVibe == vibe ? vibeColor(vibe) : .fratGray)
                                        }.frame(maxWidth: .infinity)
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
                        }

                        PostField(label: "START TIME") {
                            DatePicker("", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().tint(.fratPink)
                        }

                        PostField(label: "CAPACITY (OPTIONAL)") {
                            TextField("e.g. 50", text: $capacity).font(.fratBody(15)).keyboardType(.numberPad)
                        }

                        Button { postParty() } label: {
                            Text("Post party").font(.fratBold(17)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                                .background(RoundedRectangle(cornerRadius: 16).fill(canPost ? Color.fratPink : Color.fratGray))
                        }.disabled(!canPost).padding(.bottom, 40)
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                }
            }
            .navigationTitle("Post a Party").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.fratPink)
                }
            }
        }
    }

    private func vibeColor(_ vibe: String) -> Color {
        switch vibe.lowercased() {
        case "darty": return Color(red: 1.0, green: 0.55, blue: 0.15)
        case "rager": return Color.fratPink
        case "kickback": return Color(red: 0.3, green: 0.75, blue: 0.45)
        case "formal": return Color(red: 0.35, green: 0.45, blue: 0.85)
        default: return Color.fratGray
        }
    }

    private func searchLocation(_ query: String) {
        selectedLocation = nil
        guard query.count > 2 else { searchResults = []; return }
        let req = MKLocalSearch.Request(); req.naturalLanguageQuery = query
        MKLocalSearch(request: req).start { response, _ in
            searchResults = Array((response?.mapItems ?? []).prefix(4))
        }
    }

    private func postParty() {
        guard let location = selectedLocation else { return }
        let coord = location.placemark.coordinate
        let now = UInt64(Date().timeIntervalSince1970)
        let party = PartyProfile(
            id: now,
            title: title,
            vibe: selectedVibe,
            cap: UInt16(capacity) ?? 0,
            attend: 1,
            expires: now + 86400,
            host: "You",
            address: address,
            lat: coord.latitude,
            lon: coord.longitude,
            description: description,
            imgUrl: nil,
            timestamp: UInt64(startTime.timeIntervalSince1970)
        )
        onPost(party)
        dismiss()
    }
}

// MARK: - Post alert
struct PostAlertView: View {
    let onPost: (AlertProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: AlertDisplayType = .general
    @State private var detail = ""
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ALERT TYPE").font(.fratSemi(11)).foregroundColor(.fratGray)
                            VStack(spacing: 0) {
                                ForEach(AlertDisplayType.allCases, id: \.self) { type in
                                    Button { selectedType = type } label: {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                Circle().fill(type.color.opacity(selectedType == type ? 0.2 : 0.08)).frame(width: 40, height: 40)
                                                Image(systemName: type.icon).font(.system(size: 16)).foregroundColor(type.color)
                                            }
                                            Text(type.emoji + " " + type.rawValue).font(.fratSemi(15)).foregroundColor(.fratDark)
                                            Spacer()
                                            if selectedType == type {
                                                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundColor(type.color)
                                            }
                                        }.padding(14)
                                    }.buttonStyle(.plain)
                                    if type != AlertDisplayType.allCases.last { Divider().padding(.leading, 68) }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
                        }

                        PostField(label: "DETAILS (OPTIONAL)") {
                            TextField("Additional information…", text: $detail, axis: .vertical)
                                .font(.fratBody(15)).lineLimit(1...4)
                        }

                        Button { postAlert() } label: {
                            Text("Post Alert").font(.fratBold(17)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.9, green: 0.2, blue: 0.2)))
                        }.padding(.bottom, 40)
                    }
                    .padding(.horizontal, 24).padding(.top, 8)
                }
            }
            .navigationTitle("Post Alert").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.fratPink)
                }
            }
        }
    }

    private func postAlert() {
        let now = UInt64(Date().timeIntervalSince1970)
        // Use real user location if available, fall back to campus center
        let userLoc = locationManager.location
        let lat = userLoc?.coordinate.latitude ?? 42.0267
        let lon = userLoc?.coordinate.longitude ?? -93.6465
        let alert = AlertProfile(
            name: selectedType.rawValue,
            id: now,
            description: detail,
            expires: now + 3600,
            lat: lat,
            lon: lon,
            timestamp: now
        )
        onPost(alert)
        dismiss()
    }
}

// MARK: - Post field
private struct PostField<Content: View>: View {
    let label: String; let content: Content
    init(label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.fratSemi(11)).foregroundColor(.fratGray)
            content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
        }
    }
}

// MARK: - Mock data (Previews only)
#if DEBUG
extension MeshManager {
    static var preview: MeshManager {
        let m = MeshManager()
        let now = UInt64(Date().timeIntervalSince1970)
        m.parties = [
            now+1: PartyProfile(id: now+1, title: "SAE Friday Darty", vibe: "Darty", cap: 80, attend: 34,
                expires: now+86400, host: "SAE Iowa State", address: "432 Ash Ave, Ames",
                lat: 42.0295, lon: -93.6490, description: "", imgUrl: nil,
                timestamp: UInt64(Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!.timeIntervalSince1970)),
            now+2: PartyProfile(id: now+2, title: "PKL Saturday Rager", vibe: "Rager", cap: 0, attend: 67,
                expires: now+86400, host: "PKL House", address: "215 Lynn Ave, Ames",
                lat: 42.0248, lon: -93.6438, description: "", imgUrl: nil,
                timestamp: UInt64(Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!.timeIntervalSince1970)),
        ]
        m.alerts = [
            now+10: AlertProfile(name: "Security activity", id: now+10, description: "",
                expires: now+3000, lat: 42.0275, lon: -93.6470, timestamp: now-600),
            now+11: AlertProfile(name: "Event disruption", id: now+11,
                description: "Party getting shut down on Ash Ave",
                expires: now+3480, lat: 42.0260, lon: -93.6495, timestamp: now-120),
        ]
        return m
    }
}
#endif

