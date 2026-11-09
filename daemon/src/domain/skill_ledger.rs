//! The ledger: every link this manager created, and every source it added.
//!
//! Ownership is the whole safety story (spec §6.4): a link is ours only because a row says so,
//! and removal is allowed only when the filesystem still agrees with that row. Anything else on
//! disk belongs to the user and is reported, never deleted.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::domain::skill::SkillId;
use crate::domain::skill_source::AddedSource;
use crate::domain::skill_targets::Scope;

pub const LEDGER_SCHEMA: u32 = 1;

/// Where a skill's bytes come from.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Origin {
    /// Immutable copy in Astral's store, pinned to a ref and the resolved commit.
    Store {
        #[serde(rename = "refName")]
        ref_name: String,
        sha: String,
        /// Directory inside the store.
        path: PathBuf,
    },
    /// The user's own folder, linked in place (D8).
    Local { path: PathBuf },
    /// A farm `npx skills` created, adopted (D4): we may unlink it, we never claim we made it.
    Adopted { by: String, hash: String },
}

impl Origin {
    /// The directory the link points at, for `Store` and `Local`.
    pub fn content_path(&self) -> Option<&Path> {
        match self {
            Self::Store { path, .. } => Some(path),
            Self::Local { path } => Some(path),
            Self::Adopted { .. } => None,
        }
    }

    pub fn label(&self) -> String {
        match self {
            Self::Store { ref_name, sha, .. } => format!("{}@{}", ref_name, &sha[..sha.len().min(7)]),
            Self::Local { .. } => "local · live".to_string(),
            Self::Adopted { by, .. } => format!("adopted · {by}"),
        }
    }
}

/// Whether a skill is linked into its targets.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LinkState {
    Linked,
    Disabled,
}

/// One link we manage.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkRecord {
    pub link: PathBuf,
    /// The link target as we created it (relative for target links, absolute into the store).
    pub target: String,
    #[serde(rename = "targetId")]
    pub target_id: String,
    #[serde(rename = "sourceId")]
    pub source_id: String,
    pub skill: SkillId,
    pub origin: Origin,
    pub scope: Scope,
    pub state: LinkState,
    pub hash: String,
    #[serde(rename = "createdAt")]
    pub created_at: u64,
}

/// The persisted document: links and the sources they came from.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ledger {
    pub schema: u32,
    #[serde(default)]
    pub links: Vec<LinkRecord>,
    #[serde(default)]
    pub sources: Vec<AddedSource>,
}

impl Default for Ledger {
    fn default() -> Self {
        Self {
            schema: LEDGER_SCHEMA,
            links: Vec::new(),
            sources: Vec::new(),
        }
    }
}

impl Ledger {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        let ledger: Self = serde_json::from_slice(bytes).map_err(|e| format!("ledger is not readable JSON: {e}"))?;
        if ledger.schema != LEDGER_SCHEMA {
            return Err(format!(
                "ledger schema {} is not supported (this build understands {LEDGER_SCHEMA})",
                ledger.schema
            ));
        }
        Ok(ledger)
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut text = serde_json::to_vec_pretty(self).unwrap_or_else(|_| b"{}".to_vec());
        text.push(b'\n');
        text
    }

    /// The row for a link path, if we own it.
    pub fn row_for(&self, link: &Path) -> Option<&LinkRecord> {
        self.links.iter().find(|row| row.link == link)
    }

    /// Rows belonging to one added source.
    pub fn for_source(&self, source_id: &str) -> Vec<&LinkRecord> {
        self.links.iter().filter(|row| row.source_id == source_id).collect()
    }

    /// Rows for one skill (across sources), and for one source when given.
    pub fn for_skill(&self, skill: &SkillId, source_id: Option<&str>) -> Vec<&LinkRecord> {
        self.links
            .iter()
            .filter(|row| &row.skill == skill)
            .filter(|row| source_id.map(|id| row.source_id == id).unwrap_or(true))
            .collect()
    }

    /// Every skill of a source, deduplicated, in a stable order.
    pub fn skills_of(&self, source_id: &str) -> Vec<SkillId> {
        let mut skills: Vec<SkillId> = self
            .links
            .iter()
            .filter(|row| row.source_id == source_id)
            .map(|row| row.skill.clone())
            .collect();
        skills.sort();
        skills.dedup();
        skills
    }

    pub fn upsert(&mut self, row: LinkRecord) {
        match self.links.iter_mut().find(|existing| existing.link == row.link) {
            Some(existing) => *existing = row,
            None => self.links.push(row),
        }
        self.links.sort_by(|a, b| a.link.cmp(&b.link));
    }

    pub fn remove(&mut self, link: &Path) -> bool {
        let before = self.links.len();
        self.links.retain(|row| row.link != link);
        self.links.len() != before
    }

    pub fn source(&self, id: &str) -> Option<&AddedSource> {
        self.sources.iter().find(|source| source.id == id)
    }

    pub fn upsert_source(&mut self, source: AddedSource) {
        match self.sources.iter_mut().find(|existing| existing.id == source.id) {
            Some(existing) => *existing = source,
            None => self.sources.push(source),
        }
        self.sources.sort_by(|a, b| a.id.cmp(&b.id));
    }

    pub fn remove_source(&mut self, id: &str) -> bool {
        let before = self.sources.len();
        self.sources.retain(|source| source.id != id);
        self.sources.len() != before
    }

    /// How a skill's state reads in the UI: disabled if any row says so.
    pub fn state_of(&self, source_id: &str, skill: &SkillId) -> Option<LinkState> {
        let rows = self.for_skill(skill, Some(source_id));
        if rows.is_empty() {
            return None;
        }
        if rows.iter().all(|row| row.state == LinkState::Disabled) {
            Some(LinkState::Disabled)
        } else {
            Some(LinkState::Linked)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(link: &str, source: &str, skill: &str, state: LinkState) -> LinkRecord {
        LinkRecord {
            link: PathBuf::from(link),
            target: "store/x".to_string(),
            target_id: "codex".to_string(),
            source_id: source.to_string(),
            skill: SkillId::parse(skill).unwrap(),
            origin: Origin::Store {
                ref_name: "main".to_string(),
                sha: "a".repeat(40),
                path: PathBuf::from("/store/x"),
            },
            scope: Scope::Global,
            state,
            hash: "h".to_string(),
            created_at: 1,
        }
    }

    fn source(id: &str) -> AddedSource {
        AddedSource {
            id: id.to_string(),
            label: id.to_string(),
            spec: crate::domain::skill_source::parse_source("owner/repo").unwrap(),
            enabled: true,
            added_at: 1,
            last_seen: None,
        }
    }

    #[test]
    fn the_ledger_round_trips_and_reports_its_schema() {
        let mut ledger = Ledger::default();
        ledger.upsert(record("/l/a", "src", "alpha", LinkState::Linked));
        ledger.upsert_source(source("src"));
        let parsed = Ledger::parse(&ledger.to_bytes()).unwrap();
        assert_eq!(parsed, ledger);
        assert!(Ledger::parse(b"{\"schema\":99,\"links\":[]}").unwrap_err().contains("schema 99"));
        assert!(Ledger::parse(b"not json").is_err());
    }

    #[test]
    fn rows_are_owned_per_link_not_per_name() {
        let mut ledger = Ledger::default();
        ledger.upsert(record("/l/a", "one", "alpha", LinkState::Linked));
        ledger.upsert(record("/l/b", "two", "alpha", LinkState::Linked));
        assert!(ledger.row_for(Path::new("/l/a")).is_some());
        assert_eq!(ledger.for_source("one").len(), 1);
        assert_eq!(ledger.for_skill(&SkillId::parse("alpha").unwrap(), None).len(), 2);
        assert_eq!(ledger.for_skill(&SkillId::parse("alpha").unwrap(), Some("two")).len(), 1);
        assert_eq!(ledger.skills_of("one"), vec![SkillId::parse("alpha").unwrap()]);
    }

    #[test]
    fn upsert_replaces_and_remove_reports_what_it_did() {
        let mut ledger = Ledger::default();
        ledger.upsert(record("/l/a", "src", "alpha", LinkState::Linked));
        ledger.upsert(record("/l/a", "src", "alpha", LinkState::Disabled));
        assert_eq!(ledger.links.len(), 1);
        assert_eq!(ledger.row_for(Path::new("/l/a")).unwrap().state, LinkState::Disabled);
        assert!(ledger.remove(Path::new("/l/a")));
        assert!(!ledger.remove(Path::new("/l/a")), "removing twice is not an error, it is a no-op");
    }

    #[test]
    fn a_skill_is_disabled_only_when_every_link_is() {
        let mut ledger = Ledger::default();
        ledger.upsert(record("/l/a", "src", "alpha", LinkState::Disabled));
        assert_eq!(ledger.state_of("src", &SkillId::parse("alpha").unwrap()), Some(LinkState::Disabled));
        ledger.upsert(record("/l/b", "src", "alpha", LinkState::Linked));
        assert_eq!(ledger.state_of("src", &SkillId::parse("alpha").unwrap()), Some(LinkState::Linked));
        assert_eq!(ledger.state_of("src", &SkillId::parse("ghost").unwrap()), None);
    }

    #[test]
    fn origins_render_a_label_a_person_can_read() {
        let store = Origin::Store {
            ref_name: "main".to_string(),
            sha: "abcdef1234567".to_string(),
            path: PathBuf::from("/s"),
        };
        assert_eq!(store.label(), "main@abcdef1");
        assert_eq!(Origin::Local { path: PathBuf::from("/p") }.label(), "local · live");
        assert!(Origin::Adopted { by: "npx skills".into(), hash: "h".into() }.label().contains("adopted"));
        assert!(Origin::Adopted { by: "x".into(), hash: "h".into() }.content_path().is_none(),
            "an adopted row has no Astral store to garbage-collect");
    }
}
