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
- **Nothing in the clear.** Every message travels on a sealed zkRP topic, so
  relays see opaque topic names and ciphertext: not the account behind a
  connection, not the content, not the school. Profiles, parties, alerts,
  likes and invites are sealed with the school's key for the month (from
  auth, with the credential), so only verified students at that school read
  them; each account's inbox topic rotates daily and only they can derive it.
  Chats are sealed again with a key only the two people hold.
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
- **Each campus has its own key.** Auth derives a key per school email domain
  per month and hands it out with the credential. Everything campus-wide is
  sealed with it, so schools share relays but never see each other's traffic,
  and relays can't tell which school a connection belongs to.

## How the app uses zkRP

FratRat embeds the zkRP client (via `libghost`) and speaks to the network
directly from the phone:

- **Relay discovery and connection.** The mesh layer discovers zkRP relays over
  gRPC and connects, tracking connection state in the UI.
- **Broadcast and discovery** happen over the zkRP ghost protocol on a shared
  topic.
- **Campus traffic** (`rust/ios/src/campus.rs`): one broadcast topic per
  month and a daily-rotating inbox per account, all sealed with the campus key.
- **Matches and chats** use rotating zkRP mailbox topics
  (`rust/ios/src/conversation.rs`). Messages go out live and are also left in
  the relay's mailbox store, fetched on reconnect, for up to 7 days.
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
