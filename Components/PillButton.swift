//
//  PillButton.swift
//  FratRat
//
//  Created by Brady Bangasser on 7/13/26.
//


//
//  AuthComponents.swift
//  FratRat
//
//  Shared building blocks for the onboarding screens: a brand pill button with
//  proper loading/disabled/pressed states, an accurate error card + full-screen
//  error state that render an `AuthError` honestly, and the subtle "verified"
//  affordance. All respect Reduce Motion and Dynamic Type.
//
//  (Names are distinct from LandingView's existing `ErrorBanner` /
//  `ConnectionStatusBanner` so nothing collides.)
//

import SwiftUI

// MARK: - Primary pill button

/// The one big call-to-action. Handles loading + disabled without callers
/// rebuilding a ZStack every time. Honors Reduce Motion (skips the press-scale)
/// and clamps Dynamic Type so the pill never blows out the layout.
struct PillButton: View {
    enum Style { case pink, dark, plain }

    let title: String
    var style: Style = .pink
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var icon: String? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(foreground)
                } else {
                    HStack(spacing: 8) {
                        if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
                        Text(title).font(.fratBold(17))
                    }
                    .foregroundColor(foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 16).fill(background))
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onLongPressGesture(minimumDuration: 0, pressing: { p in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.1)) { pressed = p }
        }, perform: {})
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }

    private var background: Color {
        switch style {
        case .pink:  return .fratPink
        case .dark:  return .fratDark
        case .plain: return Color.white.opacity(0.7)
        }
    }
    private var foreground: Color {
        switch style {
        case .pink, .dark: return .white
        case .plain:       return .fratDark
        }
    }
}

// MARK: - Inline field error

/// One-line, specific validation text under a field. Announced to VoiceOver.
struct FieldErrorText: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.fratBody(12))
            .foregroundColor(.red)
            .accessibilityAddTraits(.isStaticText)
            .transition(.opacity)
    }
}

// MARK: - Error card (inline)

/// Compact, accurate error surface for use inside a form. Shows the specific
/// title + message from an `AuthError` and offers the right primary action.
struct AuthErrorCard: View {
    let error: AuthError
    var onRetry: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: error.symbol)
                .font(.system(size: 18))
                .foregroundColor(.red)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(error.title)
                    .font(.fratSemi(14))
                    .foregroundColor(.fratDark)
                Text(error.message)
                    .font(.fratBody(13))
                    .foregroundColor(.fratGray)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    if error.isRetryable, let onRetry {
                        Button("Try again", action: onRetry)
                            .font(.fratSemi(13))
                            .foregroundColor(.fratPink)
                    }
                    if let onEdit {
                        Button(error.isRetryable ? "Edit email" : "Fix it", action: onEdit)
                            .font(.fratSemi(13))
                            .foregroundColor(.fratPink)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Error screen (full state)

/// Full-bleed error state for when a whole step fails (e.g. attestation). Big,
/// clear, one obvious action — no dead ends.
struct AuthErrorScreen: View {
    let error: AuthError
    var primaryTitle: String? = nil
    var onPrimary: (() -> Void)? = nil
    var onSecondary: (() -> Void)? = nil
    var secondaryTitle: String = "Back"

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Color.red.opacity(0.10)).frame(width: 96, height: 96)
                Image(systemName: error.symbol)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.red)
            }
            .padding(.bottom, 24)

            Text(error.title)
                .font(.system(size: 26, weight: .black))
                .foregroundColor(.fratDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text(error.message)
                .font(.fratBody(15))
                .foregroundColor(.fratGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                if let onPrimary {
                    PillButton(
                        title: primaryTitle ?? (error.isRetryable ? "Try again" : "OK"),
                        style: .pink,
                        action: onPrimary
                    )
                }
                if let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                        .font(.fratSemi(15))
                        .foregroundColor(.fratGray)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fratBg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Verified affordance

/// The subtle "verified student" mark. Deliberately shows nothing derived from
/// the email — just a neutral confirmation and the issuer host.
struct VerifiedBadge: View {
    var host: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12))
                .foregroundColor(.fratPink)
            Text(host.map { "Verified · \($0)" } ?? "Verified student")
                .font(.fratSemi(12))
                .foregroundColor(.fratGray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.fratPinkLight))
        .accessibilityLabel("Verified student")
    }
}

// MARK: - Dev / misconfig badge

#if DEBUG
/// Loud, unmissable marker that a build is pointed at the placeholder auth host
/// or is using a bypass. Compiled out of Release entirely.
struct AuthDevBadge: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(.black)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.yellow))
    }
}
#endif