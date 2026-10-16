//
//  AuthService.swift
//  FratRat
//
//  The seam between the onboarding UI and the anonymous-credential backend.
//
//  ARCHITECTURE NOTE (read before "finishing the backend"):
//  Everything in the real flow — App Attest, talking to auth.fratrat.app,
//  redeeming the blind-signature credential — touches identity, crypto and the
//  network, so per the project rule it must live in the Rust `ios` crate and be
//  reached over UniFFI. Swift must NOT open gRPC channels, run App Attest, or
//  build credential requests itself. This file therefore defines a protocol the
//  UI drives, plus a `StubAuthService` that fakes the round-trips locally so the
//  screens are fully clickable today. Replace the stub with `LiveAuthService`
//  once the FFI below exists.
//
//  Proposed additions to zkrp/ios/src/lib.rs (match existing async gRPC fns like
//  `upload_photo_blob(data, grpc_addr) -> Result<String, MeshError>`):
//
//      #[uniffi::export]
//      pub async fn auth_request_challenge(
//          email: String, auth_addr: String,
//      ) -> Result<ChallengeHandle, MeshError>;   // calls AuthService::GetChallenge,
//                                                  // returns opaque handle (challenge +
//                                                  // client-held verification state)
//
//      #[uniffi::export]
//      pub async fn auth_poll_verification(
//          handle: ChallengeHandle, auth_addr: String,
//      ) -> Result<Option<Vec<u8>>, MeshError>;   // the "mailbox check": Some(token)
//                                                  // once the emailed link is redeemed
//
//      #[uniffi::export]
//      pub async fn auth_attest_device(
//          age_gate_passed: bool,
//      ) -> Result<Vec<u8>, MeshError>;           // App Attest assertion, on-device
//
//      #[uniffi::export]
//      pub async fn auth_redeem_credential(
//          verification_token: Vec<u8>, assertion: Vec<u8>, auth_addr: String,
//      ) -> Result<(), MeshError>;                // calls AuthService::Redeem and
//                                                  // stores the issued credential in
//                                                  // the core; nothing sensitive returns
//                                                  // to Swift.
//
//  (ChallengeHandle would be a `#[derive(uniffi::Record)]` wrapping the server
//  challenge bytes + the opaque, MAC'd verification token the server hands back;
//  the app persists it so the poll/redeem survives an app restart.)

import Foundation

// MARK: - Opaque handles

/// Opaque token returned by `requestChallenge`, carried by the client across the
/// (minutes-long) email round-trip. Treated as a black box in Swift — its bytes
/// come from and go back to the core.
struct ChallengeHandle: Equatable, Codable {
    let opaque: Data
    /// Advisory only, for the "expires in N min" copy. The server is the source
    /// of truth and will reject an expired token regardless of this value.
    let expiresAt: Date
}

// MARK: - Errors

/// Every failure the onboarding UI can show. Kept small and specific so each one
/// maps to a real, honest message instead of a generic "something went wrong".
enum AuthError: Error, Equatable {
    /// Address isn't shaped like a school email (no `@`, not `.edu`, etc.).
    case malformedEmail
    /// Well-formed, but this school isn't enrolled with FratRat yet.
    case schoolNotEligible
    /// This address already redeemed a credential (server nullifier hit).
    case alreadyEnrolled
    /// Device couldn't be attested (jailbroken, App Attest unavailable, etc.).
    case attestationFailed
    /// User declined the "18+" gate.
    case ageGateNotMet
    /// The emailed link expired before it was tapped.
    case verificationExpired
    /// Too many attempts; try again later.
    case rateLimited(retryAfter: TimeInterval)
    /// No network / server unreachable. Distinct from a rejection.
    case network
    /// Sign in with Apple failed for a non-cancel reason.
    case appleSignInFailed
    /// A catch-all with a server-supplied detail, still shown honestly.
    case server(String)

    /// Short headline for the error card / screen.
    var title: String {
        switch self {
        case .malformedEmail:      return "Check that email"
        case .schoolNotEligible:   return "School not on FratRat yet"
        case .alreadyEnrolled:     return "Already verified"
        case .attestationFailed:   return "Couldn't verify this device"
        case .ageGateNotMet:       return "You must be 18 or older"
        case .verificationExpired: return "That link expired"
        case .rateLimited:         return "Too many tries"
        case .network:             return "You're offline"
        case .appleSignInFailed:   return "Sign in didn't finish"
        case .server:              return "Something went wrong"
        }
    }

    /// Full, specific, non-blamey explanation + what to do next.
    var message: String {
        switch self {
        case .malformedEmail:
            return "Enter your full school email — it should look like you@university.edu."
        case .schoolNotEligible:
            return "We couldn't find your school in the FratRat network yet. Double-check the address, or ask us to add your campus."
        case .alreadyEnrolled:
            return "This email has already verified an account. You can restore it on this device, or contact support if that wasn't you."
        case .attestationFailed:
            return "FratRat couldn't confirm this is a genuine, unmodified iPhone. Attestation isn't available in the Simulator — try a real device."
        case .ageGateNotMet:
            return "FratRat is 18+. Confirm you're at least 18 and enrolled at a college to continue."
        case .verificationExpired:
            return "For your security the link only works for a few minutes. Send a fresh one and tap it right away."
        case .rateLimited(let after):
            let mins = max(1, Int((after / 60).rounded(.up)))
            return "You've asked for a few links in a row. Give it about \(mins) minute\(mins == 1 ? "" : "s") and try again."
        case .network:
            return "We couldn't reach FratRat. Check your connection — your progress is saved and we'll pick up where you left off."
        case .appleSignInFailed:
            return "Sign in with Apple didn't complete. Give it another tap."
        case .server(let detail):
            return detail.isEmpty
                ? "An unexpected error came back from the server. Please try again."
                : detail
        }
    }

    /// SF Symbol for the error illustration.
    var symbol: String {
        switch self {
        case .malformedEmail:      return "envelope.badge.shield.half.filled"
        case .schoolNotEligible:   return "building.columns"
        case .alreadyEnrolled:     return "checkmark.seal"
        case .attestationFailed:   return "iphone.slash"
        case .ageGateNotMet:       return "person.crop.circle.badge.exclamationmark"
        case .verificationExpired: return "clock.badge.xmark"
        case .rateLimited:         return "hourglass"
        case .network:             return "wifi.slash"
        case .appleSignInFailed:   return "apple.logo"
        case .server:              return "exclamationmark.triangle"
        }
    }

    /// Whether the primary action should be "Try again" vs. "Edit email"/etc.
    var isRetryable: Bool {
        switch self {
        case .malformedEmail, .schoolNotEligible, .alreadyEnrolled, .ageGateNotMet:
            return false
        case .attestationFailed, .verificationExpired, .rateLimited, .network,
             .appleSignInFailed, .server:
            return true
        }
    }
}

extension AuthError: LocalizedError {
    var errorDescription: String? { message }
}

// MARK: - Email shape check (client-side, best-effort only)

enum SchoolEmail {
    /// Cheap, forgiving shape check. The server is the real gatekeeper (it knows
    /// the allow-list of enrolled domains); this only catches obvious typos so we
    /// don't fire a request for "bob@gmail".
    static func looksValid(_ raw: String) -> Bool {
        let e = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = e.firstIndex(of: "@"), e.filter({ $0 == "@" }).count == 1 else { return false }
        let domain = e[e.index(after: at)...]
        return domain.contains(".") && domain.hasSuffix(".edu") && domain.count > 4
    }

    /// The domain, for display only ("Verifying umn.edu…"). Never the local part.
    static func domain(of raw: String) -> String? {
        let e = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = e.firstIndex(of: "@") else { return nil }
        return String(e[e.index(after: at)...])
    }
}

// MARK: - Service protocol

/// The calls onboarding needs. One implementation fakes it (`StubAuthService`),
/// the other will forward to the core over FFI (`LiveAuthService`, TODO).
protocol AuthService {

    /// App Attest + age gate. Returns nothing sensitive to Swift; on success the
    /// device is attested for the subsequent redeem.
    func attestDevice(ageGatePassed: Bool) async throws

    /// AuthService::GetChallenge — triggers the verification email and returns a
    /// handle to carry across the round-trip.
    func requestChallenge(email: String) async throws -> ChallengeHandle

    /// The "mailbox check": has the emailed link been tapped/redeemed yet?
    /// Returns `true` once verification is complete. Safe to call repeatedly.
    func pollVerification(handle: ChallengeHandle) async throws -> Bool

    /// Complete a verification that arrived via universal link (`.onOpenURL`),
    /// carrying the device-bound token straight from the tapped email.
    func completeVerification(fromLink url: URL, handle: ChallengeHandle?) async throws -> Bool

    /// AuthService::Redeem — exchange the completed verification for an anonymous
    /// credential, stored in the core. Nothing sensitive returns to Swift.
    func redeemCredential(handle: ChallengeHandle) async throws
}

// MARK: - Stub implementation

/// Local fake so the whole flow is clickable with no backend. Swap for the FFI-
/// backed `LiveAuthService` later; the UI shouldn't need to change.
///
/// Behaviour is tunable so you can exercise every error screen from the Debug
/// menu without a server.
final class StubAuthService: AuthService {

    struct Behavior {
        var latency: TimeInterval = 0.7
        /// Schools other than these report `.schoolNotEligible` (mimics the
        /// server allow-list). Empty set = accept any well-formed .edu.
        var eligibleDomains: Set<String> = []
        /// Force a specific failure for testing; nil = happy path.
        var forcedError: AuthError? = nil
        /// How many polls before the fake "email gets tapped".
        var pollsUntilVerified: Int = 2
        /// Simulate attestation working (false ⇒ `.attestationFailed`).
        var attestationSucceeds: Bool = true

        static let happy = Behavior()
    }

    private var behavior: Behavior
    private var polls = 0

    init(behavior: Behavior = .happy) {
        self.behavior = behavior
    }

    private func sleep() async throws {
        try await Task.sleep(nanoseconds: UInt64(behavior.latency * 1_000_000_000))
    }

    func attestDevice(ageGatePassed: Bool) async throws {
        try await sleep()
        guard ageGatePassed else { throw AuthError.ageGateNotMet }
        if let forced = behavior.forcedError, case .attestationFailed = forced {
            throw AuthError.attestationFailed
        }
        guard behavior.attestationSucceeds else { throw AuthError.attestationFailed }
    }

    func requestChallenge(email: String) async throws -> ChallengeHandle {
        try await sleep()
        if let forced = behavior.forcedError { throw forced }

        guard SchoolEmail.looksValid(email) else { throw AuthError.malformedEmail }
        if !behavior.eligibleDomains.isEmpty,
           let d = SchoolEmail.domain(of: email),
           !behavior.eligibleDomains.contains(d) {
            throw AuthError.schoolNotEligible
        }

        polls = 0
        return ChallengeHandle(
            opaque: Data("stub-challenge".utf8),
            expiresAt: Date().addingTimeInterval(15 * 60)
        )
    }

    func pollVerification(handle: ChallengeHandle) async throws -> Bool {
        try await sleep()
        if let forced = behavior.forcedError, case .network = forced { throw AuthError.network }
        polls += 1
        return polls >= behavior.pollsUntilVerified
    }

    func completeVerification(fromLink url: URL, handle: ChallengeHandle?) async throws -> Bool {
        try await sleep()
        // A real impl validates the token in the link against `handle` via FFI.
        return url.absoluteString.contains("/v")
    }

    func redeemCredential(handle: ChallengeHandle) async throws {
        try await sleep()
        if let forced = behavior.forcedError,
           case .verificationExpired = forced { throw AuthError.verificationExpired }
        // Success: the (fake) credential is now "held by the core".
    }
}
