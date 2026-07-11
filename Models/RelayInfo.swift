//
//  RelayInfo.swift
//  FratRat
//
//  Created by Brady Bangasser on 5/25/26.
//


import Foundation

struct RelayInfo: Identifiable, Equatable {
    let id = UUID()
    let multiaddr: String   // full libp2p multiaddr including /p2p/<peer_id>
    let peerId: String
    let region: String
    let load: Int           // 0-100
    let meshes: [String]

    // Human-readable host extracted from the multiaddr
    var displayHost: String {
        // e.g. /ip4/1.2.3.4/tcp/9000/p2p/12D3KooW...
        let parts = multiaddr.split(separator: "/")
        if let ipIdx = parts.firstIndex(of: "ip4"), parts.count > Int(ipIdx) + 1 {
            return String(parts[Int(ipIdx) + 1])
        }
        return multiaddr
    }

    var shortPeerId: String {
        String(peerId.prefix(12)) + "..."
    }

    var loadColor: String {
        switch load {
        case 0..<40:  return "green"
        case 40..<75: return "yellow"
        default:      return "red"
        }
    }
}
