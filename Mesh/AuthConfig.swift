//
//  AuthConfig.swift
//  FratRat
//
//  Created by Brady Bangasser on 7/13/26.
//


//
//  AuthConfig.swift
//  FratRat
//
//  Where the app talks to the anonymous-credential issuance server (the Rust
//  `auth` crate). Mirrors how MeshManager takes `grpcAddr` for the relay: the
//  address is a plain config value that gets handed to the core over FFI — Swift
//  never opens the connection itself.
//

import Foundation

/// Endpoints + tunables for the enrollment / anonymous-credential flow.
///
/// - Important: `auth.fratrat.app` is a **placeholder**. Point this at the real
///   issuer before shipping. It can be overridden at launch without a rebuild
///   via the `AUTH_ADDR` environment variable (Xcode scheme → Run → Arguments)
///   or the `fratrat.authAddr` UserDefault, matching the `GRPC_ADDR` pattern in
///   FratRatApp.
struct AuthConfig: Equatable {

    /// gRPC host for the auth service. TODO(backend): replace placeholder.
    var authAddr: String

    /// Base URL the verification email links back to. The tapped link returns a
    /// device-bound `verification_token` to the app (universal link → `.onOpenURL`).
    /// Must be the same origin configured as `VERIFY_LINK_BASE` on the server.
    var verifyLinkBase: String

    /// How long the mailbox poll keeps checking for the email round-trip before
    /// giving up and asking the user to tap the link manually.
    var mailboxPollTimeout: TimeInterval

    /// Delay between mailbox polls while waiting on the email round-trip.
    var mailboxPollInterval: TimeInterval

    /// Cooldown before "Resend link" re-enables, so we don't hammer SES.
    var resendCooldown: TimeInterval

    static let placeholderAuthAddr = "https://auth.fratrat.app"
    static let placeholderVerifyLinkBase = "https://auth.fratrat.app/v"

    static var `default`: AuthConfig {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard

        let addr = env["AUTH_ADDR"]
            ?? defaults.string(forKey: "fratrat.authAddr")
            ?? placeholderAuthAddr

        let linkBase = env["AUTH_VERIFY_BASE"]
            ?? defaults.string(forKey: "fratrat.authVerifyBase")
            ?? placeholderVerifyLinkBase

        return AuthConfig(
            authAddr:            addr,
            verifyLinkBase:      linkBase,
            mailboxPollTimeout:  10 * 60,   // email round-trips can take minutes
            mailboxPollInterval: 3,
            resendCooldown:      30
        )
    }

    /// True while still pointing at the placeholder host — surfaced as a subtle
    /// dev badge so a misconfigured build is obvious before it reaches a user.
    var isUsingPlaceholderHost: Bool {
        authAddr == Self.placeholderAuthAddr
    }

    /// The host shown in the tiny "verified by" affordance. Never shows anything
    /// derived from the user's email — only the issuer host.
    var displayHost: String {
        URL(string: authAddr)?.host ?? authAddr
    }
}