import SwiftUI

// MARK: - Appearance mode

enum AppearanceMode: String, Codable {
    case light, dark, system

    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    var label: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }

    var icon: String {
        switch self {
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Brand colors

extension Color {
    // ── Fixed ───────────────────────────────────────────────────────────────
    static let fratPink = Color(red: 0.98, green: 0.27, blue: 0.49)

    static let fratPinkLight = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.98, green: 0.27, blue: 0.49, alpha: 0.20)
        : UIColor(red: 0.98, green: 0.27, blue: 0.49, alpha: 0.12)
    })

    // ── Adaptive surfaces ────────────────────────────────────────────────────

    /// Page background
    static let fratBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
            : UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1)
    })

    /// Card / elevated surface (white in light, dark elevated in dark)
    static let fratCard = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
            : UIColor.white
    })

    /// Navigation bar / tab bar — stays dark in both modes
    static let fratNavBar = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
            : UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    })

    // ── Adaptive text ────────────────────────────────────────────────────────

    /// Primary text — near-black in light, near-white in dark
    static let fratDark = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
            : UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    })

    /// Secondary / caption text
    static let fratGray = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.60, green: 0.60, blue: 0.63, alpha: 1)
            : UIColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
    })

    /// Always-white text — use on colored (pink) or dark (navBar) backgrounds only
    static let fratOnDark = Color.white
}

// MARK: - Typography

extension Font {
    static func fratBlack(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }
    static func fratBold(_ size: CGFloat)  -> Font { .system(size: size, weight: .bold) }
    static func fratSemi(_ size: CGFloat)  -> Font { .system(size: size, weight: .semibold) }
    static func fratBody(_ size: CGFloat)  -> Font { .system(size: size, weight: .regular) }
}
