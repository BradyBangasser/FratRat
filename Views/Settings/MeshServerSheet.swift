//
//  MeshServerSheet.swift
//  FratRat
//
//  Created by Brady Bangasser on 7/13/26.
//


//
//  MeshServerSheet.swift
//  FratRat
//
//  Edit the mesh discovery server (the bootstrap gRPC endpoint) at runtime.
//  Distinct from RelaySwitcherSheet: that switches which libp2p *relay* you're
//  connected to; this changes the *discovery server* those relays are found
//  through. Changing it repoints the whole app to a different mesh.
//
//  Present from SettingsView's Mesh section:
//
//      Button { showMeshServer = true } label: { ... }
//        .sheet(isPresented: $showMeshServer) {
//            MeshServerSheet(isPresented: $showMeshServer)
//                .environmentObject(mesh)
//        }
//

import SwiftUI

struct MeshServerSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var mesh: MeshManager

    @State private var input = ""
    @State private var applying = false
    @FocusState private var focused: Bool

    private var normalizedPreview: String { MeshConfig.normalized(input) }
    private var isValid: Bool { MeshConfig.looksValid(input) }
    private var isUnchanged: Bool { normalizedPreview == mesh.config.grpcAddr }

    var body: some View {
        NavigationView {
            ZStack {
                Color.fratBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Current
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("CURRENT DISCOVERY SERVER")
                                    .font(.fratSemi(11)).foregroundColor(.fratGray)
                                Spacer()
                                if MeshConfig.hasOverride {
                                    Text("custom")
                                        .font(.fratSemi(10)).foregroundColor(.fratPink)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.fratPinkLight))
                                } else {
                                    Text("default")
                                        .font(.fratSemi(10)).foregroundColor(.fratGray)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.fratGray.opacity(0.12)))
                                }
                            }
                            Text(mesh.config.grpcAddr)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.fratDark)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.fratCard))

                        // Editor
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEW ENDPOINT")
                                .font(.fratSemi(11)).foregroundColor(.fratGray)

                            HStack(spacing: 10) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 14)).foregroundColor(.fratGray)
                                TextField("relay.example.com:9001", text: $input)
                                    .font(.system(size: 15, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .focused($focused)
                                    .submitLabel(.go)
                                    .onSubmit { if isValid && !isUnchanged { apply() } }
                                if !input.isEmpty {
                                    Button { input = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.fratGray.opacity(0.5))
                                    }
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.fratCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(focused ? Color.fratPink.opacity(0.4) : .clear, lineWidth: 1.5)
                                    )
                            )

                            if !input.isEmpty {
                                if isValid {
                                    Label("Will dial \(normalizedPreview)", systemImage: "arrow.right.circle")
                                        .font(.fratBody(12)).foregroundColor(.fratGray)
                                        .lineLimit(1).truncationMode(.middle)
                                } else {
                                    Label("Enter a host like relay.example.com or relay.example.com:9001",
                                          systemImage: "exclamationmark.circle")
                                        .font(.fratBody(12)).foregroundColor(.red)
                                }
                            } else {
                                Text("Host, host:port, or full http(s):// URL. Port defaults to 9001.")
                                    .font(.fratBody(12)).foregroundColor(.fratGray)
                            }

                            // Quick fills
                            HStack(spacing: 8) {
                                Text("Quick fill:").font(.fratSemi(11)).foregroundColor(.fratGray)
                                quickFill("EU default", MeshConfig.defaultGrpcAddr)
                                quickFill("localhost", "127.0.0.1:9001")
                            }
                            .padding(.top, 2)
                        }

                        // Apply
                        Button(action: apply) {
                            ZStack {
                                if applying {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Apply & reconnect")
                                        .font(.fratBold(16)).foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(isValid && !isUnchanged ? Color.fratPink : Color.fratGray))
                        }
                        .disabled(!isValid || isUnchanged || applying)

                        // Reset
                        if MeshConfig.hasOverride {
                            Button {
                                applying = true
                                Task {
                                    await mesh.resetMeshEndpoint()
                                    applying = false
                                    isPresented = false
                                }
                            } label: {
                                Text("Reset to default")
                                    .font(.fratSemi(14)).foregroundColor(.fratPink)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                            }
                            .disabled(applying)
                        }

                        Text("Changing the discovery server disconnects you and finds relays on the new mesh. Only change this if you know the endpoint — a wrong address means no parties, matches, or messages will load.")
                            .font(.fratBody(12)).foregroundColor(.fratGray)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
                }
            }
            .navigationTitle("Mesh Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }.foregroundColor(.fratPink)
                }
            }
        }
        .onAppear { input = mesh.config.grpcAddr }
    }

    private func quickFill(_ label: String, _ value: String) -> some View {
        Button(label) { input = value; focused = false }
            .font(.fratSemi(11)).foregroundColor(.fratPink)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.fratPinkLight))
    }

    private func apply() {
        guard isValid, !isUnchanged else { return }
        focused = false
        applying = true
        Task {
            await mesh.updateMeshEndpoint(input)
            applying = false
            isPresented = false
        }
    }
}

#Preview {
    MeshServerSheet(isPresented: .constant(true))
        .environmentObject(MeshManager())
}