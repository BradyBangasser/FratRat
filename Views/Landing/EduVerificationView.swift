//
//  EduVerificationView.swift
//  FratRat
//

import SwiftUI

// MARK: - EduVerificationView
// Second step of onboarding — collect .edu email.
// UI only for now: no network calls, validates the email format
// looks like a .edu address and shows a "check your inbox" state.
struct EduVerificationView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var emailSubmitted = false
    @FocusState private var emailFieldFocused: Bool
    @State private var navigateToProfile = false

    var onOnboardingComplete: () -> Void = {}

    private var isValidEduEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        // Basic shape check: something@something.edu
        return trimmed.contains("@") &&
               trimmed.hasSuffix(".edu") &&
               trimmed.split(separator: "@").count == 2 &&
               (trimmed.split(separator: "@").last?.count ?? 0) > 4
    }

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Back button ───────────────────────────────────────────
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.fratDark)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.fratCard))
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
        .navigationDestination(isPresented: $navigateToProfile) {
            ProfileSetupView(onOnboardingComplete: onOnboardingComplete)
                .environmentObject(mesh)
                .navigationBarBackButtonHidden(true)
        }
    }

    // MARK: - Form state
    private var formState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // ── Icon ──────────────────────────────────────────────────
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.fratPinkLight)
                        .frame(width: 88, height: 88)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.fratPink)
                }
                Spacer()
            }
            .padding(.bottom, 24)

            // ── Title ─────────────────────────────────────────────────
            VStack(spacing: 8) {
                Text("Verify your .edu email")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.fratDark)
                    .multilineTextAlignment(.center)
                Text("FratRat is for college students only.\nWe'll send a link to confirm your enrollment.")
                    .font(.fratBody(15))
                    .foregroundColor(.fratGray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            // ── Email field ───────────────────────────────────────────
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
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($emailFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if isValidEduEmail { submit() }
                        }

                    if !email.isEmpty {
                        Image(systemName: isValidEduEmail ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(isValidEduEmail ? .green : .fratGray.opacity(0.5))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.fratCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    emailFieldFocused ? Color.fratPink.opacity(0.4) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                )

                if !email.isEmpty && !isValidEduEmail {
                    Text("Enter a valid email ending in .edu")
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // ── Why .edu info card ────────────────────────────────────
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 16))
                    .foregroundColor(.fratPink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Why we ask")
                        .font(.fratSemi(13))
                        .foregroundColor(.fratDark)
                    Text("Verifying your school email keeps FratRat a community of real students. Your email is never shown to other users.")
                        .font(.fratBody(12))
                        .foregroundColor(.fratGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratPinkLight))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // ── Continue button ───────────────────────────────────────
            Button {
                submit()
            } label: {
                Text("Send verification link")
                    .font(.fratBold(17))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isValidEduEmail ? Color.fratDark : Color.fratGray)
                    )
            }
            .disabled(!isValidEduEmail)
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .onAppear {
            emailFieldFocused = true
        }
    }

    // MARK: - Confirmation state
    private var confirmationState: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 88, height: 88)
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
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: "1", text: "Open the email from FratRat")
                StepRow(number: "2", text: "Tap \"Verify my account\"")
                StepRow(number: "3", text: "Come back here — you'll be signed in automatically")
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Button {
                emailSubmitted = false
            } label: {
                Text("Wrong email? Edit")
                    .font(.fratSemi(14))
                    .foregroundColor(.fratPink)
            }
            .padding(.bottom, 16)

            // For now (no backend yet) — allow continuing directly.
            // Remove this once magic-link verification is wired up.
            Button {
                navigateToProfile = true
            } label: {
                Text("Continue")
                    .font(.fratBold(17))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratDark))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    private func submit() {
        emailFieldFocused = false
        withAnimation {
            emailSubmitted = true
        }
        // NOTE: no network call yet — UI only.
        // When the backend is ready, call the magic-link endpoint here:
        //   await AuthService.sendMagicLink(email: email)
    }
}

// MARK: - Step row
private struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.fratPinkLight)
                    .frame(width: 24, height: 24)
                Text(number)
                    .font(.fratBold(12))
                    .foregroundColor(.fratPink)
            }
            Text(text)
                .font(.fratBody(14))
                .foregroundColor(.fratDark)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        EduVerificationView()
    }
}
