//
//  AuthError.swift
//  FratRat
//
//  Every failure enrollment can show (see Enrollment). Kept small and specific
//  so each one maps to a real, honest message instead of a generic "something
//  went wrong".
//

import Foundation

enum AuthError: Error, Equatable {
    /// Address isn't shaped like a school email (no `@`, not `.edu`, etc.).
    case malformedEmail
    /// App Attest isn't available (Simulator, or the device refused).
    case attestationFailed
    /// The magic link opened without its token.
    case linkIncomplete
    /// The relays (and so the auth service) can't be reached.
    case network
    /// A rejection from the auth service, shown as the server worded it.
    case server(String)

    /// Short headline for the error card / screen.
    var title: String {
        switch self {
        case .malformedEmail:    return "Check that email"
        case .attestationFailed: return "Couldn't verify this device"
        case .linkIncomplete:    return "That link is incomplete"
        case .network:           return "You're offline"
        case .server:            return "Couldn't verify"
        }
    }

    /// Full, specific, non-blamey explanation + what to do next.
    var message: String {
        switch self {
        case .malformedEmail:
            return "Enter your full school email — it should look like you@university.edu."
        case .attestationFailed:
            return "Verification needs a physical iPhone (App Attest isn't available here)."
        case .linkIncomplete:
            return "Request a new link and open it from the email."
        case .network:
            return "Can't reach FratRat right now. Check your connection and try again."
        case .server(let detail):
            return detail.isEmpty
                ? "An unexpected error came back from the server. Please try again."
                : detail
        }
    }

    /// SF Symbol for the error illustration.
    var symbol: String {
        switch self {
        case .malformedEmail:    return "envelope.badge.shield.half.filled"
        case .attestationFailed: return "iphone.slash"
        case .linkIncomplete:    return "link.badge.plus"
        case .network:           return "wifi.slash"
        case .server:            return "exclamationmark.triangle"
        }
    }

    /// Whether the primary action should be "Try again" vs. "Edit email".
    var isRetryable: Bool {
        switch self {
        case .malformedEmail:
            return false
        case .attestationFailed, .linkIncomplete, .network, .server:
            return true
        }
    }
}

extension AuthError: LocalizedError {
    var errorDescription: String? { message }
}

// MARK: - Email shape check (client-side, best-effort only)

enum SchoolEmail {
    /// Cheap, forgiving shape check. The auth service is the real gatekeeper
    /// (it knows which domains are allowed); this only catches obvious typos so
    /// we don't fire a request for "bob@gmail".
    static func looksValid(_ raw: String) -> Bool {
        let e = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = e.firstIndex(of: "@"), e.filter({ $0 == "@" }).count == 1 else { return false }
        let domain = e[e.index(after: at)...]
        return domain.contains(".") && domain.hasSuffix(".edu") && domain.count > 4
    }
}
