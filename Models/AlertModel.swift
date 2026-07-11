//
//  AlertModel.swift
//  FratRat
//
//  Created by Brady Bangasser on 6/1/26.
//

import SwiftUI
import MapKit

// MARK: - Alert model
struct CampusAlert: Identifiable {
    let id = UUID()
    let type: AlertType
    let coordinate: CLLocationCoordinate2D
    let description: String   // optional extra detail
    let peerId: String        // never shown in UI
    let postedAt: Date
    var expiresAt: Date       // 1 hour after posting

    var isExpired: Bool { Date() > expiresAt }

    var timeAgoString: String {
        let diff = Int(Date().timeIntervalSince(postedAt))
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(diff / 60)m ago" }
        return "\(diff / 3600)h ago"
    }

    enum AlertType: String, CaseIterable {
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
}

// MARK: - Mock alerts
extension CampusAlert {
    static let mockAlerts: [CampusAlert] = [
        CampusAlert(
            type: .security,
            coordinate: CLLocationCoordinate2D(latitude: 42.0275, longitude: -93.6470),
            description: "",
            peerId: "12D3KooWXXX",
            postedAt: Date().addingTimeInterval(-600),
            expiresAt: Date().addingTimeInterval(3000)
        ),
        CampusAlert(
            type: .disruption,
            coordinate: CLLocationCoordinate2D(latitude: 42.0260, longitude: -93.6495),
            description: "Party getting shut down on Ash Ave",
            peerId: "12D3KooWYYY",
            postedAt: Date().addingTimeInterval(-120),
            expiresAt: Date().addingTimeInterval(3480)
        ),
    ]
}
