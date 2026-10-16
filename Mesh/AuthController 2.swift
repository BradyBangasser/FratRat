//
//  AuthController 2.swift
//  FratRat
//
//  Created by Brady Bangasser on 7/13/26.
//


//
//  AuthController.swift
//  FratRat
//
//  The state layer for onboarding auth. Views observe `phase` and stay dumb;
//  all the sequencing — attest → send challenge → poll the mailbox → redeem —
//  lives here, wired to the (stubbed) AuthService. No crypto or networking in
//  this file; it only orchestrates FFI-backed calls.
//

import Foundation
import Combine

@MainActor
final class AuthController: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        case attesting                     // App Attest + age gate (SIWA step)
        case attested                      // device ok, ready for email step
        case sendingChallenge
        case awaitingVerification(email: String)   // "check your inbox" + polling
        case redeeming
        case verified
        case failed(AuthError)

        var isBusy: Bool {
            switch self {
            case .attesting, .sendingChallenge, .redeeming: return true
            case .awaitingVerification:                     return true // poll running
            default:                                        return false
            }
        }
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .idle
    /// Bound to the email field.
    @Published var email: String = UserProfile.load().email
    /// Drives the resend button's cooldown countdown.
    @Published private(set) var resendAvailableAt: Date? = nil
    /// True once the emailed link round-trip is confirmed. Views watch this to
    /// advance. Persisted so it survives the rest of onboarding across relaunch.
    @Published private(set) var isVerified: Bool = AuthController.persistedVerified

    let config: AuthConfig
    private let service: AuthService
    private var handle: ChallengeHandle?
    private var pollTask: Task<Void, Never>?

    init(config: AuthConfig = .default, service: AuthService? = nil) {
        self.config = config
        // Default to the stub until LiveAuthService (FFI) is wired up.
        self.service = service ?? StubAuthService()
    }

    deinit { pollTask?.cancel() }

    // MARK: - Step 1: device attestation (Create-account screen)

    /// Called after a successful Sign in with Apple. Runs App Attest + the age
    /// gate via the core. On success the caller may advance to the email step.
    func attestDevice(ageConfirmed: Bool) async {
        phase = .attesting
        do {
            try await service.attestDevice(ageGatePassed: ageConfirmed)
            phase = .attested
        } catch let e as AuthError {
            phase = .failed(e)
        } catch {
            phase = .failed(.server(error.localizedDescription))
        }
    }

    // MARK: - Step 2: email challenge (Edu screen)

    func sendChallenge() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SchoolEmail.looksValid(trimmed) else {
            phase = .failed(.malformedEmail)
            return
        }
        phase = .sendingChallenge
        do {
            let h = try await service.requestChallenge(email: trimmed)
            handle = h
            persistEmail(trimmed)
            startAwaiting(email: trimmed)
        } catch let e as AuthError {
            phase = .failed(e)
        } catch {
            phase = .failed(.network)
        }
    }

    /// Re-send the link. No-ops while the cooldown is active.
    func resend() async {
        if let at = resendAvailableAt, at > Date() { return }
        await sendChallenge()
    }

    var canResend: Bool {
        guard let at = resendAvailableAt else { return true }
        return Date() >= at
    }

    var resendSecondsRemaining: Int {
        guard let at = resendAvailableAt else { return 0 }
        return max(0, Int(at.timeIntervalSinceNow.rounded(.up)))
    }

    // MARK: - Step 3: the mailbox check (poll) + redeem

    private func startAwaiting(email: String) {
        phase = .awaitingVerification(email: email)
        resendAvailableAt = Date().addingTimeInterval(config.resendCooldown)
        beginPolling()
    }

    /// Polls the verification mailbox until the emailed link is redeemed, the
    /// timeout elapses, or something fails — then redeems the credential.
    private func beginPolling() {
        pollTask?.cancel()
        guard let handle else { return }
        let deadline = Date().addingTimeInterval(config.mailboxPollTimeout)

        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && Date() < deadline {
                do {
                    let done = try await self.service.pollVerification(handle: handle)
                    if done {
                        await self.redeem()
                        return
                    }
                } catch let e as AuthError {
                    // Network blips during polling shouldn't nuke the screen —
                    // surface a soft note and keep trying until the deadline.
                    if case .network = e { /* transient: keep polling */ }
                    else { await self.fail(e); return }
                } catch {
                    // keep polling
                }
                try? await Task.sleep(nanoseconds: UInt64(self.config.mailboxPollInterval * 1_000_000_000))
            }
            if !Task.isCancelled {
                await self.fail(.verificationExpired)
            }
        }
    }

    /// Completion via a tapped universal link (email → app). Called from
    /// `.onOpenURL`. Short-circuits the poll.
    func handleVerificationLink(_ url: URL) async {
        guard url.absoluteString.hasPrefix(config.verifyLinkBase) else { return }
        do {
            let ok = try await service.completeVerification(fromLink: url, handle: handle)
            if ok { await redeem() }
        } catch let e as AuthError {
            await fail(e)
        } catch {
            await fail(.server(error.localizedDescription))
        }
    }

    private func redeem() async {
        pollTask?.cancel()
        phase = .redeeming
        guard let handle else { await fail(.server("Lost verification handle")); return }
        do {
            try await service.redeemCredential(handle: handle)
            markVerified()
            phase = .verified
        } catch let e as AuthError {
            await fail(e)
        } catch {
            await fail(.server(error.localizedDescription))
        }
    }

    private func fail(_ e: AuthError) async {
        pollTask?.cancel()
        phase = .failed(e)
    }

    /// Surface a failure raised outside the controller (e.g. a Sign in with
    /// Apple error handled in the view).
    func reportFailure(_ e: AuthError) {
        pollTask?.cancel()
        phase = .failed(e)
    }

    // MARK: - Reset / retry

    /// Back out to the email form (e.g. "wrong email? edit").
    func editEmail() {
        pollTask?.cancel()
        resendAvailableAt = nil
        phase = .idle
    }

    func clearError() {
        if case .failed = phase { phase = .idle }
    }

    // MARK: - Persistence (lightweight; the real credential lives in the core)

    private static let verifiedKey = "fratrat.emailVerified"
    private static var persistedVerified: Bool {
        UserDefaults.standard.bool(forKey: verifiedKey)
    }

    private func markVerified() {
        isVerified = true
        UserDefaults.standard.set(true, forKey: Self.verifiedKey)
    }

    private func persistEmail(_ email: String) {
        var p = UserProfile.load()
        p.email = email
        p.save()
    }

    #if DEBUG
    /// Debug-only shortcut used by the gated "skip" affordance.
    func debugForceVerified() { markVerified(); phase = .verified }
    #endif
}