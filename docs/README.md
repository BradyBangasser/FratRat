# FratRat documentation

FratRat is a privacy-first dating app for college students, built as a native
iOS app on zkRP's encrypted peer-to-peer network. See the
[README](../README.md) for the overview, why zkRP was chosen, and the
per-university network model.

## How the client uses zkRP

FratRat embeds the zkRP client (`libghost`) and talks to the network from the
device:

- **Mesh** (`Mesh/`) discovers zkRP relays over gRPC, connects, and tracks state.
- **Profiles** carry a name, college, year, bio, and photos; photos are stored as
  client-encrypted blobs in zkRP's blob store (the app holds the keys).
- **Matches and chats** ride zkRP mailboxes for store-and-forward delivery.
- **Parties** use shared (party) mailboxes so an event update reaches every
  attendee at once.

## Privacy properties

Building on zkRP means no central broker sees the graph: enrollment is anonymous
(nullifiers, no stored identity), messages and photos are encrypted client-side,
and bounded claims like age or distance can be proven without revealing the
values. The per-university network model keeps each campus isolated on its own
mesh.
