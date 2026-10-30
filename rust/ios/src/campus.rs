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

/// An account's inbox right now: (topic, mailbox id), registered as sealed so
/// libghost seals what's published there. For `ZRPHandle::publish_held`.
pub(crate) fn inbox_target(seals: &Seals, account: &str) -> Option<(String, String)> {
    let (_, key) = libghost::community::current(store().as_ref())?;
    let id = inbox(&key, account).current_id(now_unix());
    let topic = topic_for(APP, &id);
    seals.insert(topic.clone(), seal_key(&key));
    Some((topic, id))
}

/// How far back to fetch our inbox after time away; relays keep held mail
/// about this long.
const FETCH_BACK_DAYS: u64 = 7;
const INBOX_DAY_KEY: &str = "fratrat/mailbox/inbox_day";

/// Our inbox mailboxes to fetch, with their topics and sealed-topic keys:
/// every day since the last fetch (at most a week back) through tomorrow,
/// for each active campus key. `fetched` records that today was covered.
pub(crate) fn inbox_to_fetch(me: &str) -> Vec<(String, String, [u8; 32])> {
    let store = store();
    let last = store
        .get(INBOX_DAY_KEY)
        .and_then(|b| b.try_into().ok().map(u64::from_be_bytes));
    let now = now_unix();
    let mut out = Vec::new();
    for (_, key) in libghost::community::active(store.as_ref()) {
        let mb = inbox(&key, me);
        let today = mb.epoch_day(now);
        let oldest = today.saturating_sub(FETCH_BACK_DAYS);
        let first = last.map_or(oldest, |d| d.saturating_sub(1).max(oldest));
        for day in first..=today + 1 {
            let id = mb.id_for_day(day);
            out.push((topic_for(APP, &id), id, seal_key(&key)));
        }
    }
    out
}

pub(crate) fn inbox_fetched(me: &str) {
    if let Some((_, key)) = libghost::community::current(store().as_ref()) {
        let today = inbox(&key, me).epoch_day(now_unix());
        store().set(INBOX_DAY_KEY, today.to_be_bytes().to_vec());
    }
}

/// Our inbox mailboxes to register a push token under: today's and
/// tomorrow's, for the current campus key.
pub(crate) fn inbox_push_ids(me: &str) -> Vec<String> {
    let Some((_, key)) = libghost::community::current(store().as_ref()) else {
        return vec![];
    };
    let mb = inbox(&key, me);
    let today = mb.epoch_day(now_unix());
    vec![mb.id_for_day(today), mb.id_for_day(today + 1)]
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
