//
//  CreateAccountView.swift
//  FratRat
//

import SwiftUI

// MARK: - CreateAccountView
// First step of onboarding — age attestation, then EduVerificationView.
// There is deliberately no third-party sign-in: the .edu email check is the
// only identity step, and the auth service keeps no record of it.
struct CreateAccountView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss
    @State private var ageConfirmed = false
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
                    Text("Next you'll verify your .edu email.\nIt's never stored or linked to you.")
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

                // ── Continue ─────────────────────────────────────────────
                Button {
                    navigateToEdu = true
                } label: {
                    Text("Continue")
                        .font(.fratBold(17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratPink))
                }
                .disabled(!ageConfirmed)
                .opacity(ageConfirmed ? 1 : 0.4)
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
}

#Preview {
    NavigationStack {
        CreateAccountView()
    }
}
