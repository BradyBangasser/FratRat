//
//  InviteView.swift
//  FratRat
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QR code generator
private func generateQRCode(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"

    guard let outputImage = filter.outputImage else { return nil }

    // Scale up — default output is tiny (~30px)
    let scale = 10.0
    let transformed = outputImage.transformed(
        by: CGAffineTransform(scaleX: scale, y: scale)
    )

    guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}

// MARK: - InviteView
// Shows a QR code encoding a fresh conversation invite, plus a
// copyable text code as a fallback for devices without a camera.
struct InviteView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss

    @State private var invite: ChatInvite?
    @State private var copied = false
    @State private var navigateToChat = false

    var body: some View {
        ZStack {
            Color.fratBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.fratGray)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.fratCard))
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // ── Title ─────────────────────────────────────────────────
                VStack(spacing: 8) {
                    Text("Invite to chat")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.fratDark)
                    Text("Have them scan this code to start\na private chat with you.")
                        .font(.fratBody(15))
                        .foregroundColor(.fratGray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

                // ── QR code card ──────────────────────────────────────────
                VStack(spacing: 16) {
                    if let invite, let qr = generateQRCode(from: invite.encoded) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .frame(width: 220, height: 220)
                            ProgressView()
                        }
                        .padding(16)
                    }

                    // Inviter identity
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.fratPink, Color.fratPink.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                            Text(inviterInitials)
                                .font(.fratBold(13))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(inviterName)
                                .font(.fratBold(14))
                                .foregroundColor(.fratDark)
                            Text("Inviting via FratRat mesh")
                                .font(.fratBody(12))
                                .foregroundColor(.fratGray)
                        }
                        Spacer()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color.fratCard))
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // ── Text code fallback ────────────────────────────────────
                if let invite {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OR SHARE THIS CODE")
                            .font(.fratSemi(11))
                            .foregroundColor(.fratGray)

                        Button {
                            UIPasteboard.general.string = invite.encoded
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(invite.conversationId)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.fratDark)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13))
                                    .foregroundColor(copied ? .green : .fratPink)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.fratCard))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                // ── Waiting indicator ─────────────────────────────────────
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.fratPink)
                    Text("Waiting for them to join…")
                        .font(.fratBody(13))
                        .foregroundColor(.fratGray)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(isPresented: $navigateToChat) {
            if let invite {
                ChatView(match: Match(
                    name: "New chat",
                    peerId: invite.conversationId,
                    lastMessage: "",
                    timestamp: Date(),
                    unread: 0
                ))
                .environmentObject(mesh)
            }
        }
        .task {
            await setUpInvite()
        }
    }

    private var inviterName: String {
        let profile = UserProfile.load()
        return profile.name.isEmpty ? "You" : profile.name
    }

    private var inviterInitials: String {
        let parts = inviterName.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "?" : initials.uppercased()
    }

    /// Create the invite and subscribe to its conversation topic so
    /// we receive the joiner's first message as soon as they connect.
    private func setUpInvite() async {
        guard invite == nil else { return }
        let myPeerId = mesh.myPeerId ?? "local"
        let newInvite = ChatInvite.create(inviterPeerId: myPeerId, inviterName: inviterName)
        invite = newInvite
        await mesh.registerInviteConversation(newInvite.conversationId)
        try? await mesh.subscribe(topic: newInvite.topic)
    }
}

#Preview {
    NavigationStack {
        InviteView()
            .environmentObject(MeshManager())
    }
}
