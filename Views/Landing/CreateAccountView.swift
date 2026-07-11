//
//  CreateAccountView.swift
//  FratRat
//

import SwiftUI
import AuthenticationServices

// MARK: - CreateAccountView
// First step of onboarding — Sign in with Apple + age attestation.
// On success, navigates to EduVerificationView.
struct CreateAccountView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss
    @State private var ageConfirmed = false
    @State private var signingIn = false
    @State private var errorMessage: String?
    @State private var navigateToEdu = false

    var onOnboardingComplete: () -> Void = {}

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Close button ──────────────────────────────────────────
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.fratGray)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.fratCard))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // ── Icon ──────────────────────────────────────────────────
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.fratPinkLight)
                            .frame(width: 88, height: 88)
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
                    Text("Sign in to get started. You'll verify\nyour .edu email next.")
                        .font(.fratBody(15))
                        .foregroundColor(.fratGray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)

                // ── Age attestation ───────────────────────────────────────
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        ageConfirmed.toggle()
                    }
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

                        Text("I am 17 years of age or older and currently enrolled at a college or university.")
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

                // ── Error message ────────────────────────────────────────
                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.fratBody(13))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }

                // ── Sign in with Apple ───────────────────────────────────
                SignInWithAppleButtonView(
                    isEnabled: ageConfirmed && !signingIn,
                    isLoading: signingIn
                ) { result in
                    handleAppleSignIn(result)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                // ── Dev skip (remove before App Store submission) ────────
                Button {
                    navigateToEdu = true
                } label: {
                    Text("Skip sign-in (dev only)")
                        .font(.fratSemi(14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                if !ageConfirmed {
                    Text("Check the box above to continue")
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }

                // ── Legal ─────────────────────────────────────────────────
                Text("By continuing, you agree to our Terms of Service and Privacy Policy.")
                    .font(.fratBody(12))
                    .foregroundColor(.fratGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 36)
            }
        }
        .navigationDestination(isPresented: $navigateToEdu) {
            EduVerificationView(onOnboardingComplete: onOnboardingComplete)
                .environmentObject(mesh)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            signingIn = true
            errorMessage = nil
            // Simulate brief sign-in delay for UX feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                signingIn = false
                navigateToEdu = true
            }

        case .failure(let error):
            signingIn = false
            let nsError = error as NSError
            // User cancelled — don't show an error
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = "Sign in failed. Please try again."
        }
    }
}

// MARK: - Sign in with Apple button wrapper
private struct SignInWithAppleButtonView: View {
    let isEnabled: Bool
    let isLoading: Bool
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        ZStack {
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: onCompletion
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)

            if isLoading {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.85))
                    .frame(height: 54)
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
    }
}
