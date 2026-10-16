//
//  Enrollment.swift
//  FratRat
//
//  Anonymous enrollment with the zkrp auth service.
//
//  1. requestLink(email)  — the auth service emails a magic link
//  2. the link opens the app (fratrat://verify#<token> or a universal link)
//  3. redeem(from: url)   — App Attest proves this is the real app on a real
//                           device, then the device receives a credential
//
//  The credential lets relays admit us without learning who we are. The email
//  address is sent to the auth service once and is never stored on device.
//

import DeviceCheck
import Foundation

enum EnrollmentError: LocalizedError {
    case attestUnsupported
    case missingToken
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .attestUnsupported:
            return "Verification needs a physical iPhone (App Attest isn't available here)."
        case .missingToken:
            return "That link is incomplete. Request a new one."
        }
    }
}

@MainActor
final class Enrollment: ObservableObject {
    @Published private(set) var isEnrolled: Bool = hasCredential()
    @Published private(set) var expiresAt: Date? = credentialExpiresAt().map {
        Date(timeIntervalSince1970: TimeInterval($0))
    }

    /// Re-verify a few days early so relays never start dropping us mid-use.
    static let renewalWindow: TimeInterval = 3 * 24 * 60 * 60

    var needsRenewal: Bool {
        guard isEnrolled, let expiresAt else { return !isEnrolled }
        return expiresAt.timeIntervalSinceNow < Self.renewalWindow
    }

    /// Re-read credential state (call when the app becomes active).
    func refresh() {
        isEnrolled = hasCredential()
        expiresAt = credentialExpiresAt().map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
    @Published private(set) var isRedeeming = false
    @Published var lastError: String?

    func requestLink(email: String) async throws {
        do {
            let authAddr = try await ZkrpNetwork.shared.authURL()
            try await enrollRequestLink(authAddr: authAddr, email: email)
        } catch {
            throw EnrollmentError.server(Self.message(for: error))
        }
    }

    /// The generated MeshError description is a debug dump; surface the
    /// server's message instead.
    private static func message(for error: Error) -> String {
        if case let MeshError.EnrollError(msg) = error { return msg }
        if case let MeshError.ConnectionError(msg) = error { return msg }
        return error.localizedDescription
    }

    /// True for URLs that look like our magic link, so other deep links pass
    /// through untouched.
    static func isVerifyLink(_ url: URL) -> Bool {
        url.scheme == "fratrat" ? url.host == "verify" : url.path.hasSuffix("/verify")
    }

    func redeem(from url: URL) async {
        guard Self.isVerifyLink(url) else { return }
        isRedeeming = true
        defer { isRedeeming = false }
        do {
            // The token rides in the fragment so it never reaches a web server
            // even if the link opens in a browser.
            guard let token = url.fragment, !token.isEmpty else { throw EnrollmentError.missingToken }

            let service = DCAppAttestService.shared
            guard service.isSupported else { throw EnrollmentError.attestUnsupported }

            let clientDataHash = try enrollBegin()
            // A fresh key per enrollment: the server keeps no key id, so there
            // is nothing that links this device across enrollments.
            let keyId = try await service.generateKey()
            let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)

            let authAddr = try await ZkrpNetwork.shared.authURL()
            _ = try await enrollFinish(
                authAddr: authAddr,
                token: token,
                attestation: attestation,
                pinnedIssuerHex: ZkrpConfig.pinnedIssuerHex
            )
            refresh()
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
        }
    }
}
