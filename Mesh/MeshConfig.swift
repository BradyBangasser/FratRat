//
//  MeshConfig.swift
//  FratRat
//
//  Created by Brady Bangasser on 7/13/26.
//


//
//  MeshConfig.swift
//  FratRat
//
//  One place that decides which mesh the app talks to. "Mesh address" = the
//  bootstrap gRPC endpoint used to discover relays, upload blobs, and ship logs
//  (`discoverRelays(grpcAddr:)`, `uploadPhotoBlob(grpcAddr:)`, …). It is NOT the
//  libp2p relay multiaddr — that's discovered from this endpoint or entered as a
//  custom relay in the RelayPicker/RelaySwitcher.
//
//  Resolution order (first hit wins):
//    1. In-app override   — UserDefaults "fratrat.grpcAddr" (set from Settings,
//                           survives relaunch, works on a shipped build)
//    2. Launch override   — GRPC_ADDR env var (developer convenience in Xcode)
//    3. Compiled default  — the production discovery endpoint
//
//  Before this existed, the address was only changeable via the env var, which
//  can't be set on an installed app — so there was no way to repoint a build in
//  the field. Now Settings → Mesh can edit it live.
//

import Foundation

struct MeshConfig: Equatable {

    /// Bootstrap discovery gRPC endpoint, e.g. "http://relay.…:9001".
    var grpcAddr: String
    /// Blob/CloudFront front used when decrypting peer photos.
    var cfDomain: String
    /// Relay multiaddr used if gRPC discovery returns nothing.
    var fallbackRelayMultiaddr: String

    // MARK: - Defaults

    static let defaultGrpcAddr       = "http://relay.a.central.eu.infra.zkrp.net:9001"
    static let defaultCfDomain       = "blobfront.infra.zkrp.net"
    static let defaultFallbackRelay  = "/ip4/relay.a.central.us.infra.zkrp.net/tcp/9000"
    static let defaultGrpcPort: UInt16 = 9001

    // MARK: - Persistence

    private static let grpcKey = "fratrat.grpcAddr"

    /// Resolve the active config from override → env → default.
    static var `default`: MeshConfig {
        let env = ProcessInfo.processInfo.environment
        let store = UserDefaults.standard

        let addr = store.string(forKey: grpcKey)
            ?? env["GRPC_ADDR"]
            ?? defaultGrpcAddr

        let fallback = env["RELAY_ADDR"] ?? defaultFallbackRelay

        return MeshConfig(
            grpcAddr:              addr,
            cfDomain:              defaultCfDomain,
            fallbackRelayMultiaddr: fallback
        )
    }

    /// Persist an in-app override (normalized). Empty input clears the override.
    static func saveGrpcAddr(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resetGrpcAddr()
        } else {
            UserDefaults.standard.set(normalized(trimmed), forKey: grpcKey)
        }
    }

    /// Drop the in-app override and fall back to env/default.
    static func resetGrpcAddr() {
        UserDefaults.standard.removeObject(forKey: grpcKey)
    }

    /// True when there's no in-app override stored (i.e. env/default in effect).
    static var hasOverride: Bool {
        UserDefaults.standard.string(forKey: grpcKey) != nil
    }

    // MARK: - Derived

    var isUsingDefaultGrpc: Bool { grpcAddr == Self.defaultGrpcAddr }

    /// Host:port for display, without the scheme.
    var displayHost: String {
        if let url = URL(string: grpcAddr), let host = url.host {
            if let port = url.port { return "\(host):\(port)" }
            return host
        }
        return grpcAddr
    }

    // MARK: - Normalization

    /// Accepts "host", "host:port", "http://host:port", "https://…" and returns a
    /// well-formed URL string the gRPC layer can dial. Defaults the port to 9001
    /// and the scheme to http (relays are plaintext gRPC by default; keep https
    /// if the user typed it, e.g. behind a TLS proxy).
    static func normalized(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return defaultGrpcAddr }

        var scheme = "http"
        if let range = s.range(of: "://") {
            scheme = String(s[..<range.lowerBound]).lowercased()
            s = String(s[range.upperBound...])
        }
        // Strip any path.
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }

        let host: String
        let port: UInt16
        if let colon = s.lastIndex(of: ":"),
           let p = UInt16(s[s.index(after: colon)...]) {
            host = String(s[..<colon])
            port = p
        } else {
            host = s
            port = defaultGrpcPort
        }
        guard !host.isEmpty else { return defaultGrpcAddr }
        return "\(scheme)://\(host):\(port)"
    }

    /// Cheap sanity check for the Settings editor's enable/disable state.
    static func looksValid(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        let norm = normalized(s)
        return URL(string: norm)?.host?.isEmpty == false
    }
}