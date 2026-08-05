---
title: "FratRat"
summary: "A dating app built on zkRP's encrypted peer-to-peer network."
tags: [app, p2p, cryptography, privacy]
featured: true
---

# FratRat

FratRat is a dating app built on top of [zkRP](https://github.com/BradyBangasser/zkrp),
an encrypted peer-to-peer network that uses zero-knowledge range proofs. Running
on zkRP means matching and messaging happen over an encrypted P2P transport
rather than through a central server that sees everything.

## Why zkRP

Dating data is sensitive. Building on zkRP's encrypted transport and
zero-knowledge primitives keeps user data off a central broker and lets the app
validate claims (age ranges, distance, and similar bounded values) without
exposing the underlying numbers.

> Fill in: the app's features, the platforms it runs on, and which zkRP services
> it depends on.

## Related

[zkRP](https://github.com/BradyBangasser/zkrp) is the encrypted P2P network
FratRat runs on.
