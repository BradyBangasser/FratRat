//! End-to-end encrypted conversations.
//!
//! Each match, accepted invite, or QR chat has a 32-byte conversation key that
//! only the two people in it hold (exchanged encrypted to each other's account
//! key, or carried in the QR code). Three subkeys come from it:
//!
//! - a mailbox root: messages travel on a rotating `fratrat/v1/mb/<id>` topic
//!   (`libghost::mailbox::RotatingMailbox::dm`), so relays see an opaque id that
//!   changes daily and never an account id;
//! - an encryption key: every payload is sealed with ChaCha20-Poly1305 before it
//!   is published or deposited, so relays only ever see ciphertext;
//! - a topic key: libghost seals the signed envelope around that payload
//!   (`libghost::sealed`), hiding which account sent it.

use chacha20poly1305::aead::{Aead, AeadCore, KeyInit as _, OsRng, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use hmac::{Hmac, KeyInit, Mac};
use libghost::mailbox::{RotatingMailbox, topic_for};
use sha2::Sha256;

use crate::{APP, MeshError, now_unix, store};

const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 12;
pub(crate) const CONVERSATION_KEY_PREFIX: &str = "fratrat/conv_key/";

fn conversation_key_key(conversation_id: &str) -> String {
    format!("{CONVERSATION_KEY_PREFIX}{conversation_id}")
}

fn key32(key: &[u8]) -> Result<[u8; KEY_LEN], MeshError> {
    key.try_into().map_err(|_| MeshError::ConnectionError {
        msg: format!(
            "conversation key must be {KEY_LEN} bytes, got {}",
            key.len()
        ),
    })
}

fn subkey(key: &[u8; KEY_LEN], label: &str) -> [u8; KEY_LEN] {
    let mut m = <Hmac<Sha256> as KeyInit>::new_from_slice(key).expect("hmac key");
    m.update(format!("{APP}/conversation/v1/{label}").as_bytes());
    m.finalize().into_bytes().into()
}

fn mailbox(key: &[u8]) -> Result<RotatingMailbox, MeshError> {
    Ok(RotatingMailbox::dm(APP, subkey(&key32(key)?, "mailbox")))
}

// MARK: - Key storage

/// Remember a conversation's key on this device.
#[uniffi::export]
pub fn save_conversation_key(conversation_id: String, key: Vec<u8>) -> bool {
    if key.len() != KEY_LEN {
        return false;
    }
    store().set(&conversation_key_key(&conversation_id), key);
    true
}

#[uniffi::export]
pub fn load_conversation_key(conversation_id: String) -> Option<Vec<u8>> {
    store()
        .get(&conversation_key_key(&conversation_id))
        .filter(|k| k.len() == KEY_LEN)
}

/// Every conversation this device holds a key for.
#[uniffi::export]
pub fn load_all_conversation_key_ids() -> Vec<String> {
    store()
        .list(CONVERSATION_KEY_PREFIX)
        .into_iter()
        .filter_map(|k| k.strip_prefix(CONVERSATION_KEY_PREFIX).map(str::to_string))
        .collect()
}

#[uniffi::export]
pub fn delete_conversation_key(conversation_id: String) {
    store().delete(&conversation_key_key(&conversation_id));
}

// MARK: - Topics

/// The topics to watch for a conversation right now: yesterday's, today's and
/// tomorrow's mailbox, so nothing is missed across the daily rotation.
#[uniffi::export]
pub fn conversation_topics(key: Vec<u8>) -> Result<Vec<String>, MeshError> {
    Ok(mailbox(&key)?.active_topics(now_unix()).to_vec())
}

/// The key libghost seals this conversation's topics with, so relays don't
/// see whose account sent each message (`MeshNode::subscribe_sealed`).
#[uniffi::export]
pub fn conversation_topic_key(key: Vec<u8>) -> Result<Vec<u8>, MeshError> {
    Ok(subkey(&key32(&key)?, "topic").to_vec())
}

/// Today's mailbox topic, where a message is published.
#[uniffi::export]
pub fn conversation_send_topic(key: Vec<u8>) -> Result<String, MeshError> {
    Ok(topic_for(APP, &mailbox(&key)?.current_id(now_unix())))
}

// MARK: - Store-and-forward

/// Local mailbox bookkeeping: `cursor/<mailbox id>` is the last relay msg_id
/// read from that mailbox; `day/<conversation id>` the last day fetched.
pub(crate) const MAILBOX_STATE_PREFIX: &str = "fratrat/mailbox/";
/// How far back a fetch reaches for someone who's been away. Relays should
/// expire held messages after about as long (deploy/README.md in zkrp).
const FETCH_BACK_DAYS: u64 = 7;
/// Pages fetched per mailbox per call, so one busy mailbox can't stall the rest.
const MAX_FETCH_PAGES: usize = 10;

fn rpc_error(e: impl std::fmt::Display) -> MeshError {
    MeshError::ConnectionError { msg: e.to_string() }
}

/// Leave a sealed message in today's mailbox on the relay, so the other
/// member gets it on reconnect even if they're offline now.
#[uniffi::export]
pub async fn deposit_for_conversation(
    grpc_addr: String,
    key: Vec<u8>,
    sealed: Vec<u8>,
) -> Result<(), MeshError> {
    let mailbox_id = mailbox(&key)?.current_id(now_unix());
    crate::get_runtime()
        .spawn(async move {
            libghost::mailbox::deposit(store().as_ref(), &grpc_addr, &mailbox_id, sealed)
                .await
                .map(|_| ())
                .map_err(rpc_error)
        })
        .await
        .map_err(rpc_error)?
}

/// Sealed messages the relay holds for a conversation that this device
/// hasn't read yet, oldest first per mailbox. Covers every day since the last
/// fetch (at most `FETCH_BACK_DAYS` back) through tomorrow.
#[uniffi::export]
pub async fn fetch_for_conversation(
    grpc_addr: String,
    conversation_id: String,
    key: Vec<u8>,
) -> Result<Vec<Vec<u8>>, MeshError> {
    let mailbox = mailbox(&key)?;
    crate::get_runtime()
        .spawn(async move {
            let store = store();
            let today = mailbox.epoch_day(now_unix());
            let day_key = format!("{MAILBOX_STATE_PREFIX}day/{conversation_id}");
            let oldest = today.saturating_sub(FETCH_BACK_DAYS);
            let first = store
                .get(&day_key)
                .and_then(|b| b.try_into().ok().map(u64::from_be_bytes))
                .map_or(oldest, |last: u64| last.saturating_sub(1).max(oldest));

            let mut out = Vec::new();
            for day in first..=today + 1 {
                let id = mailbox.id_for_day(day);
                let cursor_key = format!("{MAILBOX_STATE_PREFIX}cursor/{id}");
                let mut after = store
                    .get(&cursor_key)
                    .and_then(|b| String::from_utf8(b).ok())
                    .unwrap_or_default();
                for _ in 0..MAX_FETCH_PAGES {
                    let (held, more) =
                        match libghost::mailbox::fetch(store.as_ref(), &grpc_addr, &id, &after)
                            .await
                        {
                            Ok(page) => page,
                            // Cursors already moved past what's in `out`, so
                            // hand that over rather than dropping it.
                            Err(e) if out.is_empty() => return Err(rpc_error(e)),
                            Err(_) => return Ok(out),
                        };
                    let Some(last) = held.last() else { break };
                    after = last.msg_id.clone();
                    out.extend(held.into_iter().map(|h| h.ciphertext));
                    store.set(&cursor_key, after.clone().into_bytes());
                    if !more {
                        break;
                    }
                }
            }
            store.set(&day_key, today.to_be_bytes().to_vec());
            Ok(out)
        })
        .await
        .map_err(rpc_error)?
}

// MARK: - Sealing

/// Encrypt a payload for a conversation: `nonce(12) || ciphertext`. The
/// conversation id is bound as associated data, so a message can't be replayed
/// into another conversation that shares no key anyway, or relabelled.
#[uniffi::export]
pub fn seal_for_conversation(
    key: Vec<u8>,
    conversation_id: String,
    plaintext: Vec<u8>,
) -> Result<Vec<u8>, MeshError> {
    let enc = subkey(&key32(&key)?, "enc");
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&enc));
    let nonce = ChaCha20Poly1305::generate_nonce(&mut OsRng);
    let ciphertext = cipher
        .encrypt(
            &nonce,
            Payload {
                msg: &plaintext,
                aad: conversation_id.as_bytes(),
            },
        )
        .map_err(|_| MeshError::ConnectionError {
            msg: "encrypt failed".into(),
        })?;
    let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    out.extend_from_slice(nonce.as_slice());
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

/// Decrypt what `seal_for_conversation` produced. Fails on anything not sealed
/// with this conversation's key and id.
#[uniffi::export]
pub fn open_for_conversation(
    key: Vec<u8>,
    conversation_id: String,
    sealed: Vec<u8>,
) -> Result<Vec<u8>, MeshError> {
    if sealed.len() < NONCE_LEN + 16 {
        return Err(MeshError::ConnectionError {
            msg: "sealed message too short".into(),
        });
    }
    let enc = subkey(&key32(&key)?, "enc");
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&enc));
    let (nonce, ciphertext) = sealed.split_at(NONCE_LEN);
    cipher
        .decrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: ciphertext,
                aad: conversation_id.as_bytes(),
            },
        )
        .map_err(|_| MeshError::ConnectionError {
            msg: "decrypt failed".into(),
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use libghost::mailbox::mailbox_id_from_topic;

    const K: [u8; 32] = [7u8; 32];

    #[test]
    fn seal_round_trips() {
        let sealed = seal_for_conversation(K.to_vec(), "c1".into(), b"hi".to_vec()).unwrap();
        assert_ne!(&sealed[NONCE_LEN..], b"hi");
        let opened = open_for_conversation(K.to_vec(), "c1".into(), sealed).unwrap();
        assert_eq!(opened, b"hi");
    }

    #[test]
    fn wrong_key_or_conversation_fails() {
        let sealed = seal_for_conversation(K.to_vec(), "c1".into(), b"hi".to_vec()).unwrap();
        assert!(open_for_conversation([8u8; 32].to_vec(), "c1".into(), sealed.clone()).is_err());
        assert!(open_for_conversation(K.to_vec(), "c2".into(), sealed).is_err());
    }

    #[test]
    fn topics_are_opaque_mailboxes() {
        let send = conversation_send_topic(K.to_vec()).unwrap();
        assert!(mailbox_id_from_topic(APP, &send).is_some());
        assert!(conversation_topics(K.to_vec()).unwrap().contains(&send));
        // The mailbox root is a subkey, not the conversation key itself.
        assert_ne!(
            send,
            topic_for(APP, &RotatingMailbox::dm(APP, K).current_id(now_unix()))
        );
    }

    /// A credential signed with the local stack's throwaway issuer key, as the
    /// test CLI does. Useless against production.
    fn dev_credential() {
        let path = std::env::var("DEV_ISSUER_KEY").expect("DEV_ISSUER_KEY");
        let key = std::fs::read_to_string(path).expect("read DEV_ISSUER_KEY");
        let sk = zkcred::IssuerSecretKey::from_bytes(&hex::decode(key.trim()).expect("hex"))
            .expect("issuer key");
        let params = libghost::admit::params(zkcred::DEFAULT_PARAMS_LABEL);
        let epoch_secs = 2_592_000;
        let epoch = zkcred::epoch_at(now_unix(), epoch_secs);
        let mut rng = zkcred::rand::rngs::OsRng;
        let (pending, req) = zkcred::request(&params, b"dev", &mut rng);
        let sig = zkcred::issue(&params, &sk, &req, b"dev", epoch, &mut rng).expect("issue");
        let cred = zkcred::finalize(&params, pending, &sig, epoch, &sk.public_key(&params))
            .expect("finalize");
        libghost::admit::save_credential(store().as_ref(), &cred, params.label(), epoch_secs);
    }

    /// Store-and-forward through a real relay. Start the local stack
    /// (zkrp's scripts/local-up.sh), then:
    ///
    ///   ZKRP_E2E_GRPC=http://127.0.0.1:9001 \
    ///   DEV_ISSUER_KEY=/abs/path/to/zrp/deploy/local/secrets/issuer-key \
    ///   cargo test -p ghost-ios -- --ignored relay_holds_sealed_messages
    #[test]
    #[ignore]
    fn relay_holds_sealed_messages() {
        let grpc = std::env::var("ZKRP_E2E_GRPC").expect("ZKRP_E2E_GRPC");
        // A store of its own, not the developer's ~/.ghost.
        let home = std::env::temp_dir().join(format!("fratrat-e2e-{}", std::process::id()));
        std::fs::create_dir_all(home.join(".ghost")).unwrap();
        // SAFETY: set before anything reads HOME; no other test touches it.
        unsafe { std::env::set_var("HOME", &home) };
        dev_credential();

        let key = libghost::identity::NodeIdentity::generate_conversation_key();
        crate::get_runtime().block_on(async {
            for text in [b"one".as_slice(), b"two"] {
                let sealed = seal_for_conversation(key.clone(), "c".into(), text.to_vec()).unwrap();
                deposit_for_conversation(grpc.clone(), key.clone(), sealed)
                    .await
                    .unwrap();
            }
            let mut texts: Vec<Vec<u8>> =
                fetch_for_conversation(grpc.clone(), "c".into(), key.clone())
                    .await
                    .unwrap()
                    .into_iter()
                    .map(|s| open_for_conversation(key.clone(), "c".into(), s).unwrap())
                    .collect();
            texts.sort();
            assert_eq!(texts, [b"one".to_vec(), b"two".to_vec()]);
            // The cursor moved on: a second fetch brings nothing new.
            assert!(
                fetch_for_conversation(grpc, "c".into(), key)
                    .await
                    .unwrap()
                    .is_empty()
            );
        });
        let _ = std::fs::remove_dir_all(home);
    }

    #[test]
    fn rejects_bad_key_length() {
        assert!(conversation_topics(vec![1, 2, 3]).is_err());
        assert!(seal_for_conversation(vec![1; 16], "c".into(), vec![]).is_err());
    }
}
