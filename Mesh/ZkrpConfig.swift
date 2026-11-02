//
//  ZkrpConfig.swift
//  FratRat
//
//  The app ships no network addresses in code. Zkrp.xcconfig supplies a
//  bootstrap list of relay hosts and the pinned issuer key (via Info.plist);
//  everything else — the relay list, each relay's gRPC URL, the auth service —
//  is learned from whichever relay answers and cached on device by the Rust
//  core, so a dead bootstrap host or a moved service needs no app release.
//

import Foundation

enum ZkrpConfig {
    private static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func plist(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Relay gRPC URLs to ask first. A discovery server set in Settings wins,
    /// then the scheme's GRPC_ADDR (a full URL, e.g. http://127.0.0.1:9001 for
    /// a local relay), then the xcconfig list.
    static var bootstrapRelays: [String] {
        if let override = discoveryOverride { return [override] }
        if let override = env("GRPC_ADDR") { return [override] }
        return (plist("ZKRPBootstrapRelays") ?? "")
            .split(separator: ",")
            .map { grpcURL(fromUserInput: String($0)) }
            .filter { !$0.isEmpty }
    }

    private static let discoveryOverrideKey = "fratrat.grpcAddr"

    /// A relay to ask first instead of the bootstrap list, set from Settings so
    /// an installed build can be repointed (the env var can't be set there).
    static var discoveryOverride: String? {
        get { UserDefaults.standard.string(forKey: discoveryOverrideKey).flatMap { $0.isEmpty ? nil : $0 } }
        set {
            let url = newValue.map(grpcURL(fromUserInput:)) ?? ""
            if url.isEmpty {
                UserDefaults.standard.removeObject(forKey: discoveryOverrideKey)
            } else {
                UserDefaults.standard.set(url, forKey: discoveryOverrideKey)
            }
        }
    }

    /// The credential issuer's public key. Pinning it means the auth service
    /// can't hand individual users their own issuer key to tag them. nil
    /// accepts whatever the server returns (development only).
    static let pinnedIssuerHex: String? = env("ISSUER_PUBLIC_KEY") ?? plist("ZKRPIssuerPublicKey")

    /// A gRPC URL from what a person (or the xcconfig) wrote: a bare host or
    /// host:port means https; an explicit http:// is kept for local testing.
    static func grpcURL(fromUserInput input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") { return trimmed }
        return "https://\(trimmed)"
    }
}

/// The network as last learned from a relay.
@MainActor
final class ZkrpNetwork {
    static let shared = ZkrpNetwork()

    private(set) var info: NetworkInfo?

    /// Ask the bootstrap relays (then relays cached from earlier runs).
    /// Returns the cached copy, marked stale, when none answer.
    @discardableResult
    func refresh() async -> NetworkInfo? {
        if let fresh = await refreshNetwork(bootstrap: ZkrpConfig.bootstrapRelays) {
            info = fresh
        }
        return info
    }

    /// gRPC URL for blob and log calls.
    var grpcURL: String? {
        info?.grpcUrls.first ?? ZkrpConfig.bootstrapRelays.first
    }

    /// The enrollment service, learned from the relays.
    func authURL() async throws -> String {
        if info == nil { await refresh() }
        guard let url = info?.authUrl, !url.isEmpty else {
            throw AuthError.network
        }
        return url
    }
}
