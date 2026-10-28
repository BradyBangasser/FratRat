//
//  JoinChatView.swift
//  FratRat
//

import SwiftUI
import AVFoundation

// MARK: - JoinChatView
// Two ways in: scan a QR code, or paste/type the invite code and
// enter a display name to introduce yourself with.
struct JoinChatView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss

    @State private var codeInput = ""
    @State private var displayName = ""
    @State private var showScanner = false
    @State private var errorMessage: String?
    @State private var navigateToChat = false
    @State private var pendingInvite: ChatInvite?
    @FocusState private var codeFieldFocused: Bool

    private var parsedInvite: ChatInvite? {
        ChatInvite.parse(codeInput)
    }

    private var canJoin: Bool {
        parsedInvite != nil && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

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

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // ── Title ─────────────────────────────────────────
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.fratPinkLight)
                                    .frame(width: 72, height: 72)
                                Image(systemName: "qrcode")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundColor(.fratPink)
                            }
                            .padding(.top, 24)
                            .padding(.bottom, 16)

                            Text("Join a chat")
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(.fratDark)
                            Text("Scan a code or enter it manually\nto start chatting.")
                                .font(.fratBody(15))
                                .foregroundColor(.fratGray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)

                        // ── Scan button ───────────────────────────────────
                        Button {
                            showScanner = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 18, weight: .medium))
                                Text("Scan QR code")
                                    .font(.fratBold(16))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratDark))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                        // ── Divider ───────────────────────────────────────
                        HStack(spacing: 12) {
                            Rectangle().fill(Color.fratGray.opacity(0.25)).frame(height: 1)
                            Text("OR")
                                .font(.fratSemi(12))
                                .foregroundColor(.fratGray)
                            Rectangle().fill(Color.fratGray.opacity(0.25)).frame(height: 1)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                        // ── Code field ────────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("INVITE CODE")
                                .font(.fratSemi(11))
                                .foregroundColor(.fratGray)

                            HStack(spacing: 10) {
                                Image(systemName: "ticket")
                                    .font(.system(size: 15))
                                    .foregroundColor(.fratGray)

                                TextField("Paste or type invite code", text: $codeInput)
                                    .font(.system(size: 14, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($codeFieldFocused)

                                if !codeInput.isEmpty {
                                    Image(systemName: parsedInvite != nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(parsedInvite != nil ? .green : .fratGray.opacity(0.5))
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.fratCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(
                                                codeFieldFocused ? Color.fratPink.opacity(0.4) : Color.clear,
                                                lineWidth: 1.5
                                            )
                                    )
                            )

                            if !codeInput.isEmpty && parsedInvite == nil {
                                Text("That doesn't look like a valid invite code")
                                    .font(.fratBody(12))
                                    .foregroundColor(.fratGray)
                            } else if let invite = parsedInvite {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.fratPink)
                                    Text("Invite from \(invite.inviterName)")
                                        .font(.fratBody(12))
                                        .foregroundColor(.fratDark)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                        // ── Display name field ────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR NAME")
                                .font(.fratSemi(11))
                                .foregroundColor(.fratGray)

                            HStack(spacing: 10) {
                                Image(systemName: "person")
                                    .font(.system(size: 15))
                                    .foregroundColor(.fratGray)

                                TextField("How should they see you?", text: $displayName)
                                    .font(.fratBody(15))
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.fratCard))

                            Text("This is shown to the person who invited you, just for this chat.")
                                .font(.fratBody(12))
                                .foregroundColor(.fratGray)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

                        // ── Error ─────────────────────────────────────────
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
                            .padding(.top, 8)
                        }
                    }
                }

                // ── Join button ───────────────────────────────────────────
                Button {
                    join()
                } label: {
                    Text("Join chat")
                        .font(.fratBold(17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canJoin ? Color.fratPink : Color.fratGray)
                        )
                }
                .disabled(!canJoin)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 12)
                .background(Color.fratBg)
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { scanned in
                showScanner = false
                codeInput = scanned
            }
        }
        .fullScreenCover(isPresented: $navigateToChat) {
            if let invite = pendingInvite {
                ChatView(match: Match(
                    name: invite.inviterName,
                    peerId: invite.conversationId,
                    lastMessage: "",
                    timestamp: Date(),
                    unread: 0
                ))
                .environmentObject(mesh)
            }
        }
        .onAppear {
            if displayName.isEmpty {
                let profile = UserProfile.load()
                displayName = profile.name
            }
        }
    }

    private func join() {
        guard let invite = parsedInvite else {
            errorMessage = "Enter a valid invite code"
            return
        }
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter a name so they know who joined"
            return
        }

        errorMessage = nil
        codeFieldFocused = false
        pendingInvite = invite

        Task {
            await mesh.openConversation(
                invite.conversationId, key: invite.key, peerId: invite.inviterPeerId
            )

            // Announce ourselves to the inviter using the name they entered
            let name = displayName.trimmingCharacters(in: .whitespaces)
            await mesh.announceJoined(conversationId: invite.conversationId, name: name)

            await MainActor.run {
                navigateToChat = true
            }
        }
    }
}

// MARK: - QR Scanner
// Lightweight AVFoundation-based scanner — avoids the VisionKit
// minimum-iOS-version requirement and works in the Simulator
// camera passthrough is unavailable, but compiles and runs on device.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUpSession()

        // Close button
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        // Hint label
        let label = UILabel()
        label.text = "Point your camera at the QR code"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func setUpSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0)

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer })?.frame = view.bounds
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }

        session.stopRunning()
        onScan?(value)
    }

    @objc private func closeTapped() {
        session.stopRunning()
        onScan?("")
        dismiss(animated: true)
    }
}

#Preview {
    NavigationStack {
        JoinChatView()
            .environmentObject(MeshManager())
    }
}
