//
//  EduVerificationView.swift
//  FratRat
//

import SwiftUI
import Combine

// MARK: - EduVerificationView
// Second step of onboarding — collect the .edu email, request a magic link,
// and continue once the link has been redeemed for an anonymous credential
// (see Enrollment). The email is shown back for confirmation only; it is sent
// to the auth service once and never stored.
struct EduVerificationView: View {
    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var enrollment: Enrollment
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var emailSubmitted = false
    @FocusState private var emailFieldFocused: Bool
    @State private var navigateToProfile = false
    @State private var isSending = false
    @State private var sendError: AuthError?
    /// Cooldown before "Resend link" re-enables, so we don't hammer the mailer.
    @State private var resendAvailableAt: Date?
    /// Local tick so the resend countdown updates every second.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let resendCooldown: TimeInterval = 30

    var onOnboardingComplete: () -> Void = {}
    /// Re-verifying an expiring credential after onboarding: no back button,
    /// no profile setup afterwards; the presenting sheet closes on success.
    var isRenewal = false

    private var isValidEmail: Bool { SchoolEmail.looksValid(email) }

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // ── Back ──────────────────────────────────────────────────
                HStack {
                    if !isRenewal || emailSubmitted {
                        Button {
                            if emailSubmitted { editEmail() } else { dismiss() }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.fratDark)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.fratCard))
                        }
                        .accessibilityLabel("Back")
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                if emailSubmitted {
                    confirmationState
                } else {
                    formState
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onChange(of: enrollment.isEnrolled) { _, enrolled in
            if enrolled && !isRenewal { navigateToProfile = true }
        }
        .navigationDestination(isPresented: $navigateToProfile) {
            ProfileSetupView(onOnboardingComplete: onOnboardingComplete)
                .environmentObject(mesh)
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
                Text(isRenewal
                     ? "Your verification renews monthly. We'll send a fresh link to your school email."
                     : "FratRat is for college students only. We'll send a link to confirm your enrollment.")
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

                    TextField("you@university.edu", text: $email)
                        .font(.fratBody(16))
                        .keyboardType(.emailAddress)
                        .textContentType(.username)   // enables .edu autofill
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($emailFieldFocused)
                        .submitLabel(.send)
                        .onSubmit { if isValidEmail { submit() } }
                        .onChange(of: email) { _, _ in sendError = nil }

                    if !email.isEmpty {
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
                                .strokeBorder(fieldBorderColor, lineWidth: 1.5)
                        )
                )

                if let err = sendError {
                    AuthErrorCard(
                        error: err,
                        onRetry: { submit() },
                        onEdit: { sendError = nil; emailFieldFocused = true }
                    )
                } else if !email.isEmpty && !isValidEmail {
                    FieldErrorText(text: "Enter a valid email ending in .edu")
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
                submit()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .onAppear { if email.isEmpty { emailFieldFocused = true } }
    }

    private var fieldBorderColor: Color {
        if sendError != nil { return .red.opacity(0.5) }
        if emailFieldFocused { return .fratPink.opacity(0.4) }
        return .clear
    }

    // MARK: - Link sent ("check your inbox")

    private var confirmationState: some View {
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

            HStack(spacing: 10) {
                ProgressView().tint(.fratPink)
                if enrollment.isRedeeming {
                    Text("Signing you in…")
                        .font(.fratSemi(13)).foregroundColor(.fratDark)
                } else {
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

            if let err = enrollment.lastError ?? sendError {
                AuthErrorCard(
                    error: err,
                    onRetry: canResend ? { submit() } : nil,
                    onEdit: { editEmail() }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Resend (with cooldown) + edit
            HStack(spacing: 20) {
                Button {
                    submit()
                } label: {
                    Text(canResend ? "Resend link" : "Resend in \(resendSecondsRemaining)s")
                        .font(.fratSemi(14))
                        .foregroundColor(canResend ? .fratPink : .fratGray)
                }
                .disabled(!canResend || isSending)

                Button("Wrong email? Edit") { editEmail() }
                    .font(.fratSemi(14))
                    .foregroundColor(.fratPink)
            }
            .padding(.bottom, 36)
        }
    }

    private var canResend: Bool {
        guard let at = resendAvailableAt else { return true }
        return now >= at
    }

    private var resendSecondsRemaining: Int {
        guard let at = resendAvailableAt else { return 0 }
        return max(0, Int(at.timeIntervalSince(now).rounded(.up)))
    }

    private func editEmail() {
        sendError = nil
        resendAvailableAt = nil
        withAnimation { emailSubmitted = false }
    }

    private func submit() {
        guard isValidEmail, !isSending else { return }
        emailFieldFocused = false
        sendError = nil
        isSending = true
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSending = false }
            do {
                try await enrollment.requestLink(email: address)
                resendAvailableAt = Date().addingTimeInterval(Self.resendCooldown)
                withAnimation { emailSubmitted = true }
            } catch {
                sendError = error as? AuthError ?? .server(error.localizedDescription)
            }
        }
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

#Preview {
    NavigationStack {
        EduVerificationView()
            .environmentObject(Enrollment())
    }
}
