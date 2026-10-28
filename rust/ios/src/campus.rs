//! Campus traffic: profiles, parties, alerts, likes and invites.
//!
//! Everything travels on sealed topics (`libghost::sealed`) keyed by the
//! school's community key for the epoch, which auth hands out with the
//! credential. Relays see opaque `fratrat/v1/mb/<id>` topics and ciphertext:
//! not who is talking, not what about, and not which school. Other schools'
//! traffic never opens for us.
//!
//! - one broadcast topic per epoch, for announcements to the whole campus;
//! - one inbox per account, rotating daily, for messages to that account.
//!   Only key holders can work out an account's inbox, so a relay can't tell
//!   whose inbox a connection is watching.

use hmac::{Hmac, KeyInit, Mac};
use libghost::mailbox::{RotatingMailbox, topic_for};
use libghost::sealed::Seals;
use sha2::Sha256;

use crate::{APP, now_unix, store};

fn subkey(key: &[u8; 32], label: &str) -> [u8; 32] {
    let mut m = <Hmac<Sha256> as KeyInit>::new_from_slice(key).expect("hmac key");
    m.update(format!("{APP}/campus/v1/{label}").as_bytes());
    m.finalize().into_bytes().into()
}

/// The sealed-topic key for all of an epoch's campus topics.
fn seal_key(key: &[u8; 32]) -> [u8; 32] {
    subkey(key, "seal")
}

fn broadcast_topic(key: &[u8; 32]) -> String {
    topic_for(APP, &hex::encode(&subkey(key, "broadcast")[..16]))
}

fn inbox(key: &[u8; 32], account: &str) -> RotatingMailbox {
    RotatingMailbox::dm(APP, subkey(key, &format!("inbox/{account}")))
}

/// Where a campus message goes.
pub(crate) enum To<'a> {
    Campus,
    Inbox(&'a str),
}

/// The topic to publish `to` on now, registered as sealed so libghost seals
/// it. None when this device holds no key for the current epoch (not
/// verified, or the credential lapsed).
pub(crate) fn topic(seals: &Seals, to: To<'_>) -> Option<String> {
    let (_, key) = libghost::community::current(store().as_ref())?;
    let topic = match to {
        To::Campus => broadcast_topic(&key),
        To::Inbox(account) => topic_for(APP, &inbox(&key, account).current_id(now_unix())),
    };
    seals.insert(topic.clone(), seal_key(&key));
    Some(topic)
}

/// Every campus topic to listen on now, with its sealed-topic key: the
/// broadcast topic and our inbox window for each active epoch key.
pub(crate) fn listening(me: &str) -> Vec<(String, [u8; 32])> {
    let now = now_unix();
    let mut out = Vec::new();
    for (_, key) in libghost::community::active(store().as_ref()) {
        let seal = seal_key(&key);
        out.push((broadcast_topic(&key), seal));
        for topic in inbox(&key, me).active_topics(now) {
            out.push((topic, seal));
        }
    }
    out
}

/// The broadcast topics among `listening`: where our hello goes.
pub(crate) fn broadcasts() -> Vec<String> {
    libghost::community::active(store().as_ref())
        .into_iter()
        .map(|(_, key)| broadcast_topic(&key))
        .collect()
}

/// True when this device can take part: it holds the current epoch's key.
#[uniffi::export]
pub fn has_campus_key() -> bool {
    libghost::community::current(store().as_ref()).is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    const K: [u8; 32] = [5u8; 32];

    #[test]
    fn topics_differ_by_purpose_account_and_school() {
        assert_ne!(broadcast_topic(&K), broadcast_topic(&[6u8; 32]));
        let t = 1_900_000_000;
        let a = inbox(&K, "alice").current_id(t);
        assert_ne!(a, inbox(&K, "bob").current_id(t));
        assert_ne!(a, inbox(&[6u8; 32], "alice").current_id(t));
        assert!(!broadcast_topic(&K).contains("alice"));
        assert_ne!(seal_key(&K), K);
    }
}
