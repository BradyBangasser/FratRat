//
//  EduVerificationView.swift
//  FratRat
//
//  Second onboarding step: verify the .edu email. Sends the challenge, then
//  shows the "check your inbox" state while the controller polls the
//  verification mailbox (and/or handles the tapped universal link). On success
//  it advances to profile setup automatically — "come back and you're in."
//
//  PRIVACY NOTE: the email is shown back to the user for confirmation only and
//  is never surfaced to peers or servers by this screen. The old "just Continue"
//  bypass that skipped verification is now DEBUG-only.
//

import SwiftUI
import Combine

struct EduVerificationView: View {
    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var auth: AuthController
    @Environment(\.dismiss) private var dismiss

    @FocusState private var emailFieldFocused: Bool
    @State private var navigateToProfile = false
    /// Local tick so the resend countdown updates every second.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var onOnboardingComplete: () -> Void = {}
    /// Re-verifying an expiring credential after onboarding: no back button,
    /// no profile setup afterwards; the presenting sheet closes on success.
    var isRenewal = false

    private var isValidEmail: Bool { SchoolEmail.looksValid(auth.email) }

    private var awaitingEmail: String? {
        if case .awaitingVerification(let e) = auth.phase { return e }
        if case .redeeming = auth.phase { return auth.email }
        return nil
    }

    private var formError: AuthError? {
        if case .failed(let e) = auth.phase { return e }
        return nil
    }

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // ── Back ──────────────────────────────────────────────────
                HStack {
                    Button {
                        if awaitingEmail != nil { auth.editEmail() } else { dismiss() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.fratDark)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.fratCard))
                    }
                    .accessibilityLabel("Back")
                    Spacer()
                    #if DEBUG
                    if auth.config.isUsingPlaceholderHost {
                        AuthDevBadge(text: "auth: \(auth.config.displayHost)")
                    }
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                if let email = awaitingEmail {
                    confirmationState(email: email)
                } else {
                    formState
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onChange(of: auth.phase) { _, phase in
            if case .verified = phase { navigateToProfile = true }
        }
        .navigationDestination(isPresented: $navigateToProfile) {
            ProfileSetupView(onOnboardingComplete: onOnboardingComplete)
                .environmentObject(mesh)
                .environmentObject(auth)
                .navigationBarBackButtonHidden(true)
        }
    }

    // MARK: - Form

    private var formState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            HStack {
                Spacer()
                ZStack {
                    Circle().fill(Color.fratPinkLight).frame(width: 88, height: 88)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.fratPink)
                }
                Spacer()
            }
            .padding(.bottom, 24)

            VStack(spacing: 8) {
                Text("Verify your .edu email")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.fratDark)
                    .multilineTextAlignment(.center)
                Text("FratRat is for college students only. We'll send a link to confirm your enrollment.")
                    .font(.fratBody(15))
                    .foregroundColor(.fratGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text("SCHOOL EMAIL")
                    .font(.fratSemi(11))
                    .foregroundColor(.fratGray)

                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.fratGray)

                    TextField("you@university.edu", text: $auth.email)
                        .font(.fratBody(16))
                        .keyboardType(.emailAddress)
                        .textContentType(.username)   // enables .edu autofill
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($emailFieldFocused)
                        .submitLabel(.send)
                        .onSubmit { if isValidEmail { Task { await auth.sendChallenge() } } }
                        .onChange(of: auth.email) { _, _ in auth.clearError() }

                    if !auth.email.isEmpty {
                        Image(systemName: isValidEmail ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(isValidEmail ? .green : .fratGray.opacity(0.5))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.fratCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    fieldBorderColor,
                                    lineWidth: 1.5
                                )
                        )
                )

                if let err = formError {
                    AuthErrorCard(
                        error: err,
                        onRetry: err.isRetryable ? { Task { await auth.sendChallenge() } } : nil,
                        onEdit: { auth.clearError(); emailFieldFocused = true }
                    )
                } else if !auth.email.isEmpty && !isValidEmail {
                    FieldErrorText(text: "Enter a valid email ending in .edu")
                }
                if let sendError {
                    Text(sendError)
                        .font(.fratBody(12))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Why we ask
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 16))
                    .foregroundColor(.fratPink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Why we ask")
                        .font(.fratSemi(13))
                        .foregroundColor(.fratDark)
                    Text("Verifying your school email keeps FratRat real students only. We never show your email to anyone, and our servers never store who you are.")
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratPinkLight))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            PillButton(
                title: "Send verification link",
                style: isValidEmail ? .dark : .pink,
                isLoading: isSending,
                isEnabled: isValidEmail
            ) {
                emailFieldFocused = false
                Task { await auth.sendChallenge() }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .onAppear { if auth.email.isEmpty { emailFieldFocused = true } }
    }

    private var isSending: Bool {
        if case .sendingChallenge = auth.phase { return true }
        return false
    }

    private var fieldBorderColor: Color {
        if formError != nil { return .red.opacity(0.5) }
        if emailFieldFocused { return .fratPink.opacity(0.4) }
        return .clear
    }

    // MARK: - Awaiting verification ("check your inbox")

    private func confirmationState(email: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 88, height: 88)
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.green)
            }
            .padding(.bottom, 24)

            VStack(spacing: 8) {
                Text("Check your inbox")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.fratDark)
                Text("We sent a verification link to")
                    .font(.fratBody(15))
                    .foregroundColor(.fratGray)
                Text(email)
                    .font(.fratBold(15))
                    .foregroundColor(.fratDark)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

            // Live "we're watching for it" indicator — the mailbox poll.
            HStack(spacing: 10) {
                if case .redeeming = auth.phase {
                    ProgressView().tint(.fratPink)
                    Text("Signing you in…")
                        .font(.fratSemi(13)).foregroundColor(.fratDark)
                } else {
                    ProgressView().tint(.fratPink)
                    Text("Waiting for you to tap the link…")
                        .font(.fratBody(13)).foregroundColor(.fratGray)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Capsule().fill(Color.fratCard))
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: "1", text: "Open the email from FratRat")
                StepRow(number: "2", text: "Tap \"Verify my account\"")
                StepRow(number: "3", text: "You'll come right back here, signed in")
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            if let err = formError {
                AuthErrorCard(
                    error: err,
                    onRetry: { Task { await auth.resend() } },
                    onEdit: { auth.editEmail() }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Resend (with cooldown) + edit
            HStack(spacing: 20) {
                Button {
                    Task { await auth.resend() }
                } label: {
                    Text(resendLabel)
                        .font(.fratSemi(14))
                        .foregroundColor(auth.canResend ? .fratPink : .fratGray)
                }
                .disabled(!auth.canResend)

                Button("Wrong email? Edit") { auth.editEmail() }
                    .font(.fratSemi(14))
                    .foregroundColor(.fratPink)
            }
            .padding(.bottom, 36)
        }
    }

    private var resendLabel: String {
        auth.canResend ? "Resend link" : "Resend in \(auth.resendSecondsRemaining)s"
    }
}

// MARK: - Step row

private struct StepRow: View {
    let number: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.fratPinkLight).frame(width: 24, height: 24)
                Text(number).font(.fratBold(12)).foregroundColor(.fratPink)
            }
            Text(text).font(.fratBody(14)).foregroundColor(.fratDark)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}
