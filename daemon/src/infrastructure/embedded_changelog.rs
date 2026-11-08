//! The release notes this build carries.
//!
//! Compiled in rather than fetched: a shell that is offline, or that has not
//! reached the network since boot, must still be able to explain what it is
//! running and what it just installed. The same files gate the release pipeline,
//! so what a user reads is what the tag declared.

use include_dir::{include_dir, Dir};
use serde::{Deserialize, Serialize};

use crate::domain::update::compare_versions;
use std::cmp::Ordering;
use std::sync::OnceLock;

static RELEASES: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../docs/releases");

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HighlightSection {
    pub title: String,
    #[serde(default)]
    pub items: Vec<String>,
}

/// One release's authored notes (`docs/releases/<version>.json`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReleaseNotes {
    pub version: String,
    pub date: String,
    #[serde(default)]
    pub highlights: Vec<String>,
    #[serde(default)]
    pub sections: Vec<HighlightSection>,
}

impl ReleaseNotes {
    /// Whether these notes should be shown to a shell that was running
    /// `from_version` (None: a fresh install shows only the current release).
    pub fn is_newer_than(&self, from_version: Option<&str>) -> bool {
        match from_version {
            None => false,
            Some(from) => compare_versions(&self.version, from) == Ordering::Greater,
        }
    }
}

/// Every release this build knows, newest first.
pub fn all() -> &'static [ReleaseNotes] {
    static NOTES: OnceLock<Vec<ReleaseNotes>> = OnceLock::new();
    NOTES.get_or_init(|| {
        let mut notes: Vec<ReleaseNotes> = RELEASES
            .files()
            .filter(|file| file.path().extension().and_then(|e| e.to_str()) == Some("json"))
            .filter_map(|file| {
                let body = file.contents_utf8()?;
                serde_json::from_str::<ReleaseNotes>(body).ok()
            })
            .collect();
        notes.sort_by(|a, b| compare_versions(&b.version, &a.version));
        notes
    })
}

/// Notes for releases newer than `since` (all of them when `since` is None).
pub fn since(since: Option<&str>) -> Vec<&'static ReleaseNotes> {
    all()
        .iter()
        .filter(|note| match since {
            None => true,
            Some(from) => compare_versions(&note.version, from) == Ordering::Greater,
        })
        .collect()
}

/// Notes for exactly one version.
pub fn for_version(version: &str) -> Option<&'static ReleaseNotes> {
    all().iter().find(|note| note.version == version)
}
