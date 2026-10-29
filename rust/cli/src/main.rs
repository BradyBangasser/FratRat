//! FratRat terminal client, for testing against a zkrp network (usually the
//! local stack from zkrp's scripts/local-up.sh).
//!
//! It runs on the same Rust core as the iOS app (`ghost-ios`) and speaks the
//! app's protocol: sealed campus topics, likes and matches, end-to-end
//! encrypted chats with store-and-forward. So it can match and chat with a
//! phone, or with another copy of itself in a second data directory.
//!
//! It gives itself a credential and campus keys from the local stack's
//! throwaway secrets (DEV_ISSUER_KEY, and community-key beside it). That only
//! works against a stack whose secrets you hold, never production.

use std::collections::HashMap;
use std::io::Write;
use std::sync::Arc;

use ghost_ios::likes::{LikeBackPayload, LikePayload};
use ghost_ios::{
    AlertProfile, InviteAcceptPayload, InvitePayload, MeshNode, NodeIdentity, PartyProfile,
    PeerProfile, RelationshipState, StoredMessage, SwiftEventHandler, TransportConfig,
};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::mpsc;

const USAGE: &str = "\
Usage: ghost-cli [OPTIONS]

Options:
  --data <DIR>       account directory (default ./.fratrat-cli/default); use one
                     per account to run several side by side
  --relay <URL>      relay gRPC URL (default http://127.0.0.1:9001)
  --school <DOMAIN>  community to join; must be an allowed email domain of the
                     stack's auth (local default: example.edu)
  --name, --college, --year, --bio <TEXT>
                     profile fields (a random profile fills any left out)
  --autolike         like everyone who shows up
  --autoreply        answer every chat message
  --push-token <HEX> register this (stand-in) APNs sandbox token for every
                     chat, to test push against a push service in log mode
  -h, --help         this help

Environment:
  DEV_ISSUER_KEY     the stack's issuer-key file (zrp/deploy/local/secrets/);
                     community-key is read from the same directory
  FRATRAT_LOG        core log level (default error; e.g. info, debug)";

const HELP: &str = "  /peers            people seen on the network
  /like <n>         like person n from /peers
  /likes            people who liked you
  /match <n>        like person n from /likes back: opens a chat
  /chats            your conversations
  /chat <n>         talk in conversation n (then just type)
  /fetch            fetch messages relays held while you were away
  /report <n> <why> report person n from /peers (anonymously)
  /profile          show your profile
  /help, /quit";

// MARK: - Arguments

struct Args {
    data: String,
    relay: String,
    school: String,
    name: Option<String>,
    college: Option<String>,
    year: Option<String>,
    bio: Option<String>,
    autolike: bool,
    autoreply: bool,
    push_token: Option<Vec<u8>>,
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args {
        data: "./.fratrat-cli/default".into(),
        relay: "http://127.0.0.1:9001".into(),
        school: "example.edu".into(),
        name: None,
        college: None,
        year: None,
        bio: None,
        autolike: false,
        autoreply: false,
        push_token: None,
    };
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        let mut value = || it.next().ok_or(format!("{arg} needs a value"));
        match arg.as_str() {
            "--data" => args.data = value()?,
            "--relay" => args.relay = value()?,
            "--school" => args.school = value()?,
            "--name" => args.name = Some(value()?),
            "--college" => args.college = Some(value()?),
            "--year" => args.year = Some(value()?),
            "--bio" => args.bio = Some(value()?),
            "--autolike" => args.autolike = true,
            "--autoreply" => args.autoreply = true,
            "--push-token" => {
                let hex_token = value()?;
                args.push_token =
                    Some(hex::decode(&hex_token).map_err(|e| format!("--push-token: {e}"))?);
            }
            "-h" | "--help" => {
                println!("{USAGE}");
                std::process::exit(0);
            }
            _ => return Err(format!("unknown option {arg}")),
        }
    }
    Ok(args)
}

fn random_profile(args: &Args, peer_id: String) -> PeerProfile {
    let pick = |opts: &[&str]| {
        let n = ghost_ios::generate_conversation_key()[0] as usize;
        opts[n % opts.len()].to_string()
    };
    PeerProfile {
        peer_id,
        name: args.name.clone().unwrap_or_else(|| {
            pick(&[
                "Alex Chen",
                "Jordan Smith",
                "Taylor Brooks",
                "Casey Rivera",
                "Morgan Lee",
            ])
        }),
        college: args
            .college
            .clone()
            .unwrap_or_else(|| pick(&["Iowa State", "Drake", "Grinnell"])),
        year: args
            .year
            .clone()
            .unwrap_or_else(|| pick(&["Freshman", "Sophomore", "Junior", "Senior"])),
        bio: args.bio.clone().unwrap_or_else(|| {
            pick(&["here for a good time", "coffee addict ☕", "music nerd 🎶"])
        }),
        photo_blob_ids: vec![],
        photo_blob_keys: vec![],
        timestamp: now(),
    }
}

fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

// MARK: - Dev credential

/// A credential and this epoch's campus keys from the local stack's secrets,
/// as auth would issue them to a verified student of `school`.
fn dev_enroll(school: &str) -> Result<(), String> {
    let path = std::env::var("DEV_ISSUER_KEY")
        .map_err(|_| "set DEV_ISSUER_KEY to the stack's issuer-key file".to_string())?;
    let read_hex = |p: &std::path::Path| -> Result<Vec<u8>, String> {
        let raw = std::fs::read_to_string(p).map_err(|e| format!("{}: {e}", p.display()))?;
        hex::decode(raw.trim()).map_err(|e| format!("{}: {e}", p.display()))
    };
    let issuer_path = std::path::Path::new(&path);
    let sk = zkcred::IssuerSecretKey::from_bytes(&read_hex(issuer_path)?)
        .map_err(|e| format!("issuer key: {e}"))?;
    let community_secret = read_hex(&issuer_path.with_file_name("community-key"))?;

    let store = ghost_ios::store();
    let params = libghost::admit::params(zkcred::DEFAULT_PARAMS_LABEL);
    let epoch_secs = 2_592_000;
    let epoch = zkcred::epoch_at(now(), epoch_secs);
    let mut rng = zkcred::rand::rngs::OsRng;
    let (pending, req) = zkcred::request(&params, b"dev", &mut rng);
    let sig = zkcred::issue(&params, &sk, &req, b"dev", epoch, &mut rng)
        .map_err(|e| format!("issue: {e}"))?;
    let cred = zkcred::finalize(&params, pending, &sig, epoch, &sk.public_key(&params))
        .map_err(|e| format!("finalize: {e}"))?;
    libghost::admit::save_credential(store.as_ref(), &cred, params.label(), epoch_secs);
    libghost::community::save(
        store.as_ref(),
        [epoch, epoch + 1].map(|e| (e, zkcred::community_key(&community_secret, school, e))),
    );
    Ok(())
}

// MARK: - Events from the core

enum Event {
    Profile(PeerProfile),
    Like(LikePayload),
    LikeBack(LikeBackPayload),
    Declined(String),
    Invite(InvitePayload),
    Message {
        from: String,
        topic: String,
        payload: Vec<u8>,
    },
    Status(String),
}

/// Hands core callbacks to the main loop, which owns the node.
struct Events(mpsc::UnboundedSender<Event>);

impl SwiftEventHandler for Events {
    fn on_message(&self, peer_id: String, conversation: String, payload: Vec<u8>, _ct: u16) {
        let _ = self.0.send(Event::Message {
            from: peer_id,
            topic: conversation,
            payload,
        });
    }
    fn on_peer_connected(&self, _peer_id: String) {}
    fn on_peer_disconnected(&self, _peer_id: String) {}
    fn on_connection_status(&self, status: String) {
        let _ = self.0.send(Event::Status(status));
    }
    fn on_send_failed(&self, _conversation: String) {}
    fn on_profile_received(&self, profile: PeerProfile) {
        let _ = self.0.send(Event::Profile(profile));
    }
    fn on_profiles_backfilled(&self, profiles: Vec<PeerProfile>) {
        for p in profiles {
            let _ = self.0.send(Event::Profile(p));
        }
    }
    fn on_party_received(&self, _party: PartyProfile) {}
    fn on_parties_backfilled(&self, _parties: Vec<PartyProfile>) {}
    fn on_alert_received(&self, _alert: AlertProfile) {}
    fn on_alerts_backfilled(&self, _alerts: Vec<AlertProfile>) {}
    fn on_like_received(&self, payload: LikePayload) {
        let _ = self.0.send(Event::Like(payload));
    }
    fn on_like_back_received(&self, payload: LikeBackPayload) {
        let _ = self.0.send(Event::LikeBack(payload));
    }
    fn on_like_declined(&self, peer_id: String) {
        let _ = self.0.send(Event::Declined(peer_id));
    }
    fn on_invite_received(&self, payload: InvitePayload) {
        let _ = self.0.send(Event::Invite(payload));
    }
    fn on_invite_accepted(&self, _payload: InviteAcceptPayload) {}
    fn on_invite_declined(&self, _peer_id: String) {}
}

// MARK: - Chats

/// What a chat message carries, sealed; the same shape the iOS app sends.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WireMessage {
    message_id: String,
    text: String,
    timestamp: u64,
    from: Option<String>,
}

struct Chat {
    peer: String,
    key: Vec<u8>,
}

struct App {
    node: MeshNode,
    identity: NodeIdentity,
    me: String,
    grpc: String,
    profile: PeerProfile,
    autolike: bool,
    autoreply: bool,
    push_token: Option<Vec<u8>>,
    peers: Vec<PeerProfile>,
    likes: Vec<LikePayload>,
    chats: HashMap<String, Chat>,
    topics: HashMap<String, String>,
    active: Option<String>,
}

fn short(id: &str) -> &str {
    let id = id.strip_prefix("12D3KooW").unwrap_or(id);
    &id[..id.len().min(8)]
}

fn new_conversation_id() -> String {
    let b = hex::encode(&ghost_ios::generate_conversation_key()[..16]);
    format!(
        "{}-{}-{}-{}-{}",
        &b[..8],
        &b[8..12],
        &b[12..16],
        &b[16..20],
        &b[20..]
    )
}

fn say(line: &str) {
    print!("\r\x1b[K{line}\n> ");
    let _ = std::io::stdout().flush();
}

impl App {
    fn name_of(&self, peer: &str) -> String {
        self.peers
            .iter()
            .find(|p| p.peer_id == peer)
            .map(|p| p.name.clone())
            .unwrap_or_else(|| format!("peer {}", short(peer)))
    }

    /// Remember a conversation and watch its sealed mailbox topics.
    async fn open_chat(&mut self, id: String, peer: String, key: Vec<u8>) {
        ghost_ios::conversation::save_conversation_key(id.clone(), key.clone());
        if let (Ok(topics), Ok(topic_key)) = (
            ghost_ios::conversation::conversation_topics(key.clone()),
            ghost_ios::conversation::conversation_topic_key(key.clone()),
        ) {
            for topic in topics {
                if self.topics.insert(topic.clone(), id.clone()).is_none() {
                    let _ = self.node.subscribe_sealed(topic, topic_key.clone()).await;
                }
            }
        }
        if let Some(token) = self.push_token.clone() {
            let (grpc, key) = (self.grpc.clone(), key.clone());
            tokio::spawn(async move {
                let r =
                    ghost_ios::conversation::register_push_for_conversation(grpc, key, token, true);
                if let Err(e) = r.await {
                    say(&format!("\x1b[90m(push registration failed: {e})\x1b[0m"));
                }
            });
        }
        self.chats.insert(id, Chat { peer, key });
    }

    /// Conversations from earlier runs.
    async fn load_chats(&mut self) {
        for rel in ghost_ios::load_all_relationships() {
            let id = match rel.state {
                RelationshipState::Matched { conversation_id }
                | RelationshipState::InviteAccepted { conversation_id }
                | RelationshipState::InviteSent { conversation_id } => conversation_id,
                _ => continue,
            };
            if let Some(key) = ghost_ios::conversation::load_conversation_key(id.clone()) {
                self.open_chat(id, rel.peer_id, key).await;
            }
        }
    }

    async fn send_chat(&mut self, id: &str, text: &str) {
        let Some(chat) = self.chats.get(id) else {
            return;
        };
        let wire = WireMessage {
            message_id: new_conversation_id(),
            text: text.to_string(),
            timestamp: now(),
            from: Some(self.me.clone()),
        };
        let json = serde_json::to_vec(&wire).expect("serialize");
        let sealed = match ghost_ios::conversation::seal_for_conversation(
            chat.key.clone(),
            id.to_string(),
            json,
        ) {
            Ok(s) => s,
            Err(e) => return say(&format!("\x1b[31mcouldn't seal: {e}\x1b[0m")),
        };
        let Ok(topic) = ghost_ios::conversation::conversation_send_topic(chat.key.clone()) else {
            return;
        };
        if let Err(e) = self.node.send_raw(topic, sealed.clone()).await {
            return say(&format!("\x1b[31mnot sent: {e}\x1b[0m"));
        }
        let (grpc, key) = (self.grpc.clone(), chat.key.clone());
        tokio::spawn(async move {
            if let Err(e) =
                ghost_ios::conversation::deposit_for_conversation(grpc, key, sealed).await
            {
                say(&format!("\x1b[90m(relay deposit failed: {e})\x1b[0m"));
            }
        });
        ghost_ios::save_message(StoredMessage {
            message_id: wire.message_id,
            conversation_id: id.to_string(),
            sender_peer_id: self.me.clone(),
            text: wire.text,
            timestamp: wire.timestamp,
            is_own: true,
        });
    }

    /// Open, record and print a sealed chat message from the conversation's
    /// other member. `signer` is the account that signed a live message;
    /// None for one fetched from a relay mailbox. Returns the text if new.
    fn receive(&self, id: &str, signer: Option<&str>, sealed: Vec<u8>) -> Option<String> {
        let chat = self.chats.get(id)?;
        let plain =
            ghost_ios::conversation::open_for_conversation(chat.key.clone(), id.into(), sealed)
                .ok()?;
        let wire: WireMessage = serde_json::from_slice(&plain).ok()?;
        let from = signer.map(str::to_string).or(wire.from)?;
        if from != chat.peer {
            return None;
        }
        let seen = ghost_ios::load_messages(id.into())
            .iter()
            .any(|m| m.message_id == wire.message_id);
        if seen {
            return None;
        }
        ghost_ios::save_message(StoredMessage {
            message_id: wire.message_id,
            conversation_id: id.into(),
            sender_peer_id: from.clone(),
            text: wire.text.clone(),
            timestamp: wire.timestamp,
            is_own: false,
        });
        say(&format!(
            "\x1b[33m{}:\x1b[0m {}",
            self.name_of(&from),
            wire.text
        ));
        Some(wire.text)
    }

    async fn like(&mut self, peer: String) {
        if !ghost_ios::can_like(peer.clone()) {
            return say("already liked, matched or declined");
        }
        let key = ghost_ios::generate_conversation_key();
        let Ok(enc) = self.identity.encrypt_for_peer(key, peer.clone()) else {
            return say("couldn't encrypt to that account");
        };
        let payload = LikePayload {
            conversation_key_enc: enc,
            sender_peer_id: self.me.clone(),
            timestamp: now(),
        };
        match self.node.send_like(peer.clone(), payload).await {
            Ok(()) => say(&format!("\x1b[35m♥ liked {}\x1b[0m", self.name_of(&peer))),
            Err(e) => say(&format!("\x1b[31mlike failed: {e}\x1b[0m")),
        }
    }

    async fn like_back(&mut self, like: LikePayload) {
        let peer = like.sender_peer_id.clone();
        let Ok(key) = self.identity.decrypt(like.conversation_key_enc) else {
            return say("couldn't read that like's key");
        };
        let Ok(enc) = self.identity.encrypt_for_peer(key.clone(), peer.clone()) else {
            return;
        };
        let id = new_conversation_id();
        let payload = LikeBackPayload {
            conversation_id: id.clone(),
            conversation_key_enc: enc,
            sender_peer_id: self.me.clone(),
            timestamp: now(),
        };
        if let Err(e) = self.node.send_like_back(peer.clone(), payload).await {
            return say(&format!("\x1b[31mmatch failed: {e}\x1b[0m"));
        }
        ghost_ios::save_relationship(
            peer.clone(),
            RelationshipState::Matched {
                conversation_id: id.clone(),
            },
        );
        self.likes.retain(|l| l.sender_peer_id != peer);
        self.open_chat(id, peer.clone(), key).await;
        say(&format!(
            "\x1b[32m✓ matched with {}. /chats to talk\x1b[0m",
            self.name_of(&peer)
        ));
    }

    async fn fetch(&mut self) {
        // Likes and invites held while we were away arrive as events.
        self.node.fetch_inbox().await;
        if let Some(token) = self.push_token.clone() {
            self.node.register_push_inbox(token, true).await;
        }
        let chats: Vec<(String, Vec<u8>)> = self
            .chats
            .iter()
            .map(|(id, c)| (id.clone(), c.key.clone()))
            .collect();
        for (id, key) in chats {
            let fetched =
                ghost_ios::conversation::fetch_for_conversation(self.grpc.clone(), id.clone(), key)
                    .await;
            match fetched {
                Ok(held) => {
                    for sealed in held {
                        self.receive(&id, None, sealed);
                    }
                }
                Err(e) => say(&format!("\x1b[90m(fetch failed: {e})\x1b[0m")),
            }
        }
    }

    async fn on_event(&mut self, event: Event) {
        match event {
            Event::Profile(p) => {
                if p.peer_id == self.me {
                    return;
                }
                let new = !self.peers.iter().any(|q| q.peer_id == p.peer_id);
                self.peers.retain(|q| q.peer_id != p.peer_id);
                self.peers.push(p.clone());
                if new {
                    say(&format!(
                        "\x1b[32m[+]\x1b[0m {} · {} · {}  (/peers)",
                        p.name, p.college, p.year
                    ));
                    if self.autolike {
                        self.like(p.peer_id).await;
                    }
                }
            }
            Event::Like(like) => {
                let name = self.name_of(&like.sender_peer_id);
                self.likes
                    .retain(|l| l.sender_peer_id != like.sender_peer_id);
                self.likes.push(like);
                say(&format!(
                    "\x1b[35m♥ {name} liked you\x1b[0m  (/likes, /match <n>)"
                ));
            }
            Event::LikeBack(back) => {
                let peer = back.sender_peer_id.clone();
                match self.identity.decrypt(back.conversation_key_enc) {
                    Ok(key) => {
                        self.open_chat(back.conversation_id, peer.clone(), key)
                            .await;
                        say(&format!(
                            "\x1b[32m✓ {} liked you back. /chats to talk\x1b[0m",
                            self.name_of(&peer)
                        ));
                    }
                    Err(_) => say("a like-back arrived that we can't read"),
                }
            }
            Event::Declined(peer) => say(&format!("{} passed", self.name_of(&peer))),
            Event::Invite(inv) => say(&format!(
                "{} invited you to chat (invites aren't supported here; use likes)",
                inv.sender_name
            )),
            Event::Message {
                from,
                topic,
                payload,
            } => {
                let Some(id) = self.topics.get(&topic).cloned() else {
                    return;
                };
                if self.receive(&id, Some(&from), payload).is_some() && self.autoreply {
                    let p = &self.profile;
                    let reply = format!(
                        "Hey! I'm {} from {} ({}). {}",
                        p.name, p.college, p.year, p.bio
                    );
                    self.send_chat(&id, &reply).await;
                }
            }
            Event::Status(s) => say(&format!("\x1b[36m[~]\x1b[0m {s}")),
        }
    }

    /// Run one command line; false to quit.
    async fn command(&mut self, line: &str) -> bool {
        let (cmd, arg) = line.split_once(' ').unwrap_or((line, ""));
        let n = arg
            .trim()
            .parse::<usize>()
            .ok()
            .and_then(|n| n.checked_sub(1));
        match cmd {
            "/peers" => {
                if self.peers.is_empty() {
                    println!("nobody yet");
                }
                for (i, p) in self.peers.iter().enumerate() {
                    println!(
                        "  {}. {} · {} · {} — {}",
                        i + 1,
                        p.name,
                        p.college,
                        p.year,
                        p.bio
                    );
                }
            }
            "/like" => match n.and_then(|i| self.peers.get(i)) {
                Some(p) => self.like(p.peer_id.clone()).await,
                None => println!("usage: /like <n> (see /peers)"),
            },
            "/likes" => {
                if self.likes.is_empty() {
                    println!("no likes waiting");
                }
                for (i, l) in self.likes.iter().enumerate() {
                    println!("  {}. {}", i + 1, self.name_of(&l.sender_peer_id));
                }
            }
            "/match" => match n.and_then(|i| self.likes.get(i)).cloned() {
                Some(like) => self.like_back(like).await,
                None => println!("usage: /match <n> (see /likes)"),
            },
            "/chats" => {
                if self.chats.is_empty() {
                    println!("no conversations yet");
                }
                for (i, (id, peer)) in self.sorted_chats().into_iter().enumerate() {
                    let marker = if self.active.as_deref() == Some(id.as_str()) {
                        "*"
                    } else {
                        " "
                    };
                    println!(" {marker}{}. {}", i + 1, self.name_of(&peer));
                }
            }
            "/chat" => match n.and_then(|i| self.sorted_chats().into_iter().nth(i)) {
                Some((id, peer)) => {
                    let history = ghost_ios::load_messages(id.clone());
                    for m in history.iter().skip(history.len().saturating_sub(10)) {
                        let who = if m.is_own {
                            "you".into()
                        } else {
                            self.name_of(&peer)
                        };
                        println!("  \x1b[90m{who}:\x1b[0m {}", m.text);
                    }
                    println!("talking to {}", self.name_of(&peer));
                    self.active = Some(id);
                }
                None => println!("usage: /chat <n> (see /chats)"),
            },
            "/fetch" => self.fetch().await,
            "/report" => {
                let (num, why) = arg.trim().split_once(' ').unwrap_or((arg.trim(), ""));
                let target = num
                    .parse::<usize>()
                    .ok()
                    .and_then(|n| n.checked_sub(1))
                    .and_then(|i| self.peers.get(i));
                match target {
                    Some(p) => {
                        // The same shape the iOS app sends, minus messages.
                        let report = serde_json::json!({
                            "version": 1,
                            "reported": p.peer_id,
                            "reason": why,
                            "details": "",
                            "profile": { "name": p.name, "college": p.college,
                                         "year": p.year, "bio": p.bio },
                            "messages": [],
                        });
                        let mut data = b"==== FratRat report ====\n".to_vec();
                        data.extend(serde_json::to_vec_pretty(&report).expect("json"));
                        match ghost_ios::upload_report(data, self.grpc.clone()).await {
                            Ok(id) => println!("report sent: {id}"),
                            Err(e) => println!("report failed: {e}"),
                        }
                    }
                    None => println!("usage: /report <n> <reason> (see /peers)"),
                }
            }
            "/profile" => {
                let p = &self.profile;
                println!("  {} · {} · {} — {}", p.name, p.college, p.year, p.bio);
                println!("  account {}", self.me);
            }
            "/help" => println!("{HELP}"),
            "/quit" | "/exit" => return false,
            _ if line.starts_with('/') => println!("unknown command; /help"),
            _ => match self.active.clone() {
                Some(id) => self.send_chat(&id, line).await,
                None => println!("pick a conversation with /chat <n> first"),
            },
        }
        true
    }

    fn sorted_chats(&self) -> Vec<(String, String)> {
        let mut v: Vec<_> = self
            .chats
            .iter()
            .map(|(id, c)| (id.clone(), c.peer.clone()))
            .collect();
        v.sort_by_key(|(id, peer)| (self.name_of(peer), id.clone()));
        v
    }
}

#[tokio::main]
async fn main() {
    let args = parse_args().unwrap_or_else(|e| {
        eprintln!("{e}\n\n{USAGE}");
        std::process::exit(2);
    });
    if let Err(e) = run(args).await {
        eprintln!("\x1b[31m{e}\x1b[0m");
        std::process::exit(1);
    }
}

async fn run(args: Args) -> Result<(), String> {
    std::fs::create_dir_all(&args.data).map_err(|e| format!("{}: {e}", args.data))?;
    // SAFETY: set before the core reads them and before other threads run.
    unsafe {
        std::env::set_var("FRATRAT_DATA_DIR", &args.data);
        if std::env::var_os("FRATRAT_LOG").is_none() {
            std::env::set_var("FRATRAT_LOG", "error");
        }
    }

    if !ghost_ios::has_credential() || !ghost_ios::campus::has_campus_key() {
        dev_enroll(&args.school)?;
    }

    let identity = NodeIdentity::load_or_generate_default();
    let me = identity.peer_id_string();
    let given = args.name.is_some() || args.college.is_some() || args.year.is_some();
    let profile = match ghost_ios::load_user_profile() {
        Some(saved) if !given => saved,
        _ => random_profile(&args, me.clone()),
    };
    ghost_ios::save_user_profile(profile.clone());

    let network = ghost_ios::refresh_network(vec![args.relay.clone()])
        .await
        .ok_or("no relay answered")?;
    let relay = network.relays.first().ok_or("the relay listed no relays")?;
    let grpc = network
        .grpc_urls
        .first()
        .cloned()
        .unwrap_or(args.relay.clone());

    println!(
        "\x1b[1mFratRat CLI\x1b[0m  {} · {} · {}",
        profile.name, profile.college, profile.year
    );
    println!("account {me}\nrelay   {}\n", relay.multiaddr);

    let (tx, mut rx) = mpsc::unbounded_channel();
    let node = MeshNode::new(
        Arc::new(NodeIdentity::load_or_generate_default()),
        relay.multiaddr.clone(),
        Arc::new(TransportConfig::new(0, 0)),
        Box::new(Events(tx)),
        profile.clone(),
    )
    .await
    .map_err(|e| format!("connect: {e}"))?;

    let mut app = App {
        node,
        identity,
        me,
        grpc,
        profile,
        autolike: args.autolike,
        autoreply: args.autoreply,
        push_token: args.push_token,
        peers: ghost_ios::load_all_peer_profiles(),
        likes: Vec::new(),
        chats: HashMap::new(),
        topics: HashMap::new(),
        active: None,
    };
    app.load_chats().await;
    let _ = app.node.announce_profile(app.profile.clone()).await;
    app.fetch().await;
    println!("{HELP}\n");

    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    let mut tick = tokio::time::interval(std::time::Duration::from_secs(3600));
    print!("> ");
    let _ = std::io::stdout().flush();
    loop {
        tokio::select! {
            line = lines.next_line() => {
                let Ok(Some(line)) = line else { break };
                let line = line.trim();
                if !line.is_empty() && !app.command(line).await {
                    break;
                }
                print!("> ");
                let _ = std::io::stdout().flush();
            }
            Some(event) = rx.recv() => app.on_event(event).await,
            _ = tick.tick() => app.node.refresh_campus().await,
            _ = tokio::signal::ctrl_c() => break,
        }
    }
    app.node.shutdown().await;
    println!();
    Ok(())
}
