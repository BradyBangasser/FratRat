//! Discover ordering. Everything here runs on the device, from profiles the
//! mesh already delivered; nothing about who you swipe on leaves the phone.

use crate::PeerProfile;

/// Order Discover candidates: people at your college first, then profiles
/// with photos, then with a bio, then the most recently updated. Ties break
/// on peer id so the order is stable between renders.
#[uniffi::export]
pub fn rank_profiles(my_college: String, profiles: Vec<PeerProfile>) -> Vec<PeerProfile> {
    let mine = normalize(&my_college);
    let mut ranked = profiles;
    ranked.sort_by(|a, b| {
        score(b, &mine)
            .cmp(&score(a, &mine))
            .then(b.timestamp.cmp(&a.timestamp))
            .then(a.peer_id.cmp(&b.peer_id))
    });
    ranked
}

fn normalize(college: &str) -> String {
    college.trim().to_lowercase()
}

fn score(p: &PeerProfile, my_college: &str) -> u8 {
    let same_college = !my_college.is_empty() && normalize(&p.college) == my_college;
    (same_college as u8) * 4
        + (!p.photo_blob_ids.is_empty() as u8) * 2
        + (!p.bio.trim().is_empty() as u8)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn profile(id: &str, college: &str, photos: bool, bio: &str, ts: u64) -> PeerProfile {
        PeerProfile {
            peer_id: id.into(),
            name: String::new(),
            college: college.into(),
            year: String::new(),
            bio: bio.into(),
            photo_blob_ids: if photos { vec!["x".into()] } else { vec![] },
            photo_blob_keys: vec![],
            timestamp: ts,
        }
    }

    fn ids(v: Vec<PeerProfile>) -> Vec<String> {
        v.into_iter().map(|p| p.peer_id).collect()
    }

    #[test]
    fn college_then_photos_then_bio_then_recency() {
        let ranked = rank_profiles(
            "Iowa State".into(),
            vec![
                profile("other-full", "Drake", true, "hi", 9),
                profile("same-bare", " iowa state ", false, "", 1),
                profile("same-photo", "Iowa State", true, "", 1),
                profile("same-photo-new", "Iowa State", true, "", 5),
                profile("other-bio", "Drake", false, "hi", 9),
            ],
        );
        assert_eq!(
            ids(ranked),
            [
                "same-photo-new",
                "same-photo",
                "same-bare",
                "other-full",
                "other-bio"
            ]
        );
    }

    #[test]
    fn no_college_of_my_own_matches_nobody() {
        let ranked = rank_profiles(
            String::new(),
            vec![
                profile("b", "", false, "", 1),
                profile("a", "", false, "", 1),
            ],
        );
        assert_eq!(ids(ranked), ["a", "b"]);
    }
}
