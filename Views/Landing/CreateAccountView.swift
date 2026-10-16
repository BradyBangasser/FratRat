//
//  CreateAccountView.swift
//  FratRat
//
//  First onboarding step: Sign in with Apple + the 18+ gate. On success we run
//  device attestation (App Attest, via the core) through AuthController, then
//  hand off to .edu verification.
//
//  PRIVACY NOTES (for review):
//  • Age gate is 18+ to match the product rule and the auth server ("students
//    18+"). It previously read 17+ here and on the landing screen — corrected.
//  • The Apple request asks for NO scopes ([]). The product model is "no
//    accounts, identity invisible to us," so we use SIWA purely as an Apple-ID /
//    anti-abuse ceremony and never pull the user's name/email from Apple. The
//    profile name is collected later; the school email is the .edu, not Apple's.
//    If product wants Apple's name to pre-fill the profile, restore
//    `[.fullName]` — but never send it to any server.
//  • The dev "skip" affordance is compiled out of Release (#if DEBUG).
//

import SwiftUI
import AuthenticationServices
import CryptoKit

struct CreateAccountView: View {
    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var auth: AuthController
    @Environment(\.dismiss) private var dismiss

    @State private var ageConfirmed = false
    @State private var navigateToEdu = false
    /// Client-side nonce for the SIWA ceremony (replay protection). The real
    /// flow should bind this to the App Attest challenge issued by the core.
    @State private var currentNonce: String?

    var onOnboardingComplete: () -> Void = {}

    private var isBusy: Bool {
        if case .attesting = auth.phase { return true }
        return false
    }

    private var currentError: AuthError? {
        if case .failed(let e) = auth.phase { return e }
        return nil
    }

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Close ─────────────────────────────────────────────────
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.fratGray)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.fratCard))
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // ── Icon ──────────────────────────────────────────────────
                HStack {
                    Spacer()
                    ZStack {
                        Circle().fill(Color.fratPinkLight).frame(width: 88, height: 88)
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundColor(.fratPink)
                    }
                    Spacer()
                }
                .padding(.bottom, 24)

                // ── Title ─────────────────────────────────────────────────
                VStack(spacing: 8) {
                    Text("Create your account")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.fratDark)
                        .multilineTextAlignment(.center)
                    Text("Sign in to get started. You'll verify your .edu email next.")
                        .font(.fratBody(15))
                        .foregroundColor(.fratGray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)

                // ── 18+ gate ──────────────────────────────────────────────
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { ageConfirmed.toggle() }
                    auth.clearError()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ageConfirmed ? Color.fratPink : Color.fratCard)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(
                                            ageConfirmed ? Color.fratPink : Color.fratGray.opacity(0.4),
                                            lineWidth: 1.5
                                        )
                                )
                            if ageConfirmed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.top, 2)

                        Text("I am 18 years of age or older and currently enrolled at a college or university.")
                            .font(.fratBody(14))
                            .foregroundColor(.fratDark)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .accessibilityAddTraits(ageConfirmed ? [.isSelected] : [])

                // ── Error ─────────────────────────────────────────────────
                if let err = currentError {
                    AuthErrorCard(error: err, onRetry: { auth.clearError() })
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }

                // ── Sign in with Apple ───────────────────────────────────
                SignInWithAppleButton(
                    .signIn,
                    onRequest: configureRequest,
                    onCompletion: handleAppleResult
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .disabled(!ageConfirmed || isBusy)
                .opacity(ageConfirmed && !isBusy ? 1 : 0.4)
                .overlay {
                    if isBusy {
                        RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.85))
                        ProgressView().tint(.white)
                    }
                }
                .disabled(!ageConfirmed)
                .opacity(ageConfirmed ? 1 : 0.4)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                if !ageConfirmed {
                    Text("Confirm you're 18+ to continue")
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }

                #if DEBUG
                // Debug-only bypass. Compiled out of Release so it can never ship.
                HStack(spacing: 8) {
                    AuthDevBadge(text: "debug")
                    Button {
                        auth.debugForceVerified()
                        navigateToEdu = true
                    } label: {
                        Text("Skip sign-in")
                            .font(.fratSemi(14))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                #endif

                // ── Legal ─────────────────────────────────────────────────
                Text("By continuing, you agree to our Terms of Service and Privacy Policy.")
                    .font(.fratBody(12))
                    .foregroundColor(.fratGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 36)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentError)
        .navigationDestination(isPresented: $navigateToEdu) {
            EduVerificationView(onOnboardingComplete: onOnboardingComplete)
                .environmentObject(mesh)
                .environmentObject(auth)
        }
        .onChange(of: auth.phase) { _, phase in
            if case .attested = phase { navigateToEdu = true }
        }
    }

    // MARK: - SIWA plumbing

    private func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        // No name/email scopes — see privacy note at the top of this file.
        request.requestedScopes = []
        request.nonce = Self.sha256(nonce)
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            // Apple ceremony done. Now attest the device + age gate via the core.
            Task { await auth.attestDevice(ageConfirmed: ageConfirmed) }

        case .failure(let error):
            let ns = error as NSError
            // User tapping "Cancel" isn't an error — stay put, show nothing.
            if ns.code == ASAuthorizationError.canceled.rawValue { return }
            // Any other Apple failure gets an honest, specific message.
            auth.reportFailure(.appleSignInFailed)
        }
    }

    // MARK: - Nonce helpers (client-side SIWA ceremony only)

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(rng.next() % UInt64(chars.count))] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
