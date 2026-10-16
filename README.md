---
title: "FratRat"
summary: "A privacy-first dating app for college students, built on zkRP's encrypted peer-to-peer network, with the goal of an isolated network per university."
tags: [ios, swift, p2p, cryptography, privacy]
featured: true
---

# FratRat

FratRat is a dating app for college students, built as a native iOS app on top of
[zkRP](https://github.com/BradyBangasser/zkrp), an encrypted peer-to-peer network
that puts privacy first. Matching, messaging, and photos move over zkRP's
encrypted transport and mailboxes rather than through a central server that can
see everyone's data.

## Why zkRP

Dating data is some of the most sensitive data a person has, so FratRat was built
on zkRP specifically because zkRP is privacy-first by design:

- **No central broker that sees everything.** Peers talk over an encrypted P2P
  transport; relays route messages they cannot read.
- **Anonymous enrollment.** zkRP proves an account is eligible and issues a blind
  credential without storing an identity. The only thing persisted is a set of
  nullifiers ("has this address enrolled?"), never a mapping to a person.
- **End-to-end-encrypted messaging.** Direct messages and party updates are
  encrypted client-side; the network only routes ciphertext by mailbox id.
- **Photos as encrypted blobs.** Profile photos are stored in zkRP's blob store
  as opaque, client-encrypted blobs (the app holds the keys), not as public
  images on a server.
- **Prove without revealing.** zkRP's zero-knowledge primitives let the app
  validate bounded claims such as age or distance without exposing the underlying
  values.

## A network per university

The goal is an **isolated network per university**: each school is its own
network, so students discover and match within their own campus rather than in
one global pool. This is both a privacy and a relevance decision, and it maps
cleanly onto zkRP:

- **Enrollment is tied to a university.** A student's profile carries their
  college, and enrollment is gated by a university email, so membership in a
  campus network is verifiable without the network learning who the student is.
- **Each campus is its own mesh.** zkRP relays serve named gossipsub meshes, so a
  university's traffic can live on its own mesh, isolated from every other
  school.

The app runs on a FratRat mesh today; per-university meshes are the direction
this isolation model is built toward.

## How the app uses zkRP

FratRat embeds the zkRP client (via `libghost`) and speaks to the network
directly from the phone:

- **Relay discovery and connection.** The mesh layer discovers zkRP relays over
  gRPC and connects, tracking connection state in the UI.
- **Broadcast and discovery** happen over the zkRP ghost protocol on a shared
  topic.
- **Matches and chats** use zkRP mailboxes for store-and-forward, so a message
  reaches someone whose phone is offline and is delivered on reconnect.
- **Parties** are shared mailboxes for an event: everyone at a party registers,
  and a party update reaches all of them at once.

## Platform

Native iOS, built in SwiftUI. The app is organized into Discover, Matches, Chat,
Party, Profile, and Settings, with the zkRP mesh integration in `Mesh/` and the
generated network stubs in `Generated/`. The Rust core (`rust/ios`, built into
`libs/libghost_ios.a` by an Xcode build phase) and a terminal test client
(`rust/cli`) sit on zkRP's `libghost`, pinned to the ref in `zkrp.ref`.

Network settings live in `Zkrp.xcconfig`, not in code: a bootstrap list of relay
hosts and the pinned credential issuer key. The app learns everything else
(the relay list, the auth service, the CDN) from the relays at runtime and
caches it. Put local overrides in a gitignored `Zkrp.local.xcconfig`, or set
`GRPC_ADDR` (for example `http://127.0.0.1:9001`) in the Xcode scheme.

## Related

[zkRP](https://github.com/BradyBangasser/zkrp) is the encrypted, privacy-first
P2P network FratRat runs on.
