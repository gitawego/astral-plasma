//! Planning the link farm: desired state + ledger + what is on disk → a list of operations.
//!
//! This module is pure (spec §5, §6): the filesystem enters only through [`FsProbe`], so every
//! rule below — idempotence, conflicts, ownership-checked removal, relative link computation — is
//! asserted in unit tests instead of discovered by a user with a broken agent.

use std::path::{Component, Path, PathBuf};

use crate::domain::skill::SkillMeta;
use crate::domain::skill_ledger::{Ledger, LinkRecord, LinkState, Origin};
use crate::domain::skill_targets::{Scope, Target};

/// What sits at a path, as far as planning is concerned.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Probe {
    Missing,
    /// A symlink with the given target, and whether that target resolves.
    Symlink { target: String, dangling: bool },
    Directory,
    File,
}

/// The filesystem, narrowed to the questions planning asks.
pub trait FsProbe {
    fn probe(&self, path: &Path) -> Probe;
    /// Whether content exists (used to refuse enabling a skill whose bytes went away).
    fn content_exists(&self, path: &Path) -> bool {
        self.probe(path) != Probe::Missing
    }
}

/// A skill that should be linked, with where it comes from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DesiredSkill {
    pub source_id: String,
    pub skill: SkillMeta,
    pub origin: Origin,
    pub scope: Scope,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConflictKind {
    /// A link we did not create (a user's own, or another tool's).
    UnmanagedLink,
    /// A real directory or file where the skill should go.
    Occupied,
    /// Our link, but the filesystem no longer points where the ledger says.
    Drifted,
    /// The skill's content is missing, so linking would create a dangling link.
    MissingContent,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Conflict {
    pub link: PathBuf,
    pub kind: ConflictKind,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum LinkOp {
    Create { link: PathBuf, target: String },
    Replace { link: PathBuf, target: String, expected: String },
    Remove { link: PathBuf, expected: String },
    /// Copy `from` to `link` for a target that does not follow links (D5).
    Copy { link: PathBuf, from: PathBuf },
    /// Remove a copied directory (never a symlink) for a `Copy` target.
    RemoveCopy { link: PathBuf },
}

/// The ledger changes a plan implies.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(tag = "ledger", rename_all = "snake_case")]
pub enum LedgerOp {
    Upsert(LinkRecord),
    Drop { link: PathBuf },
}

#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Plan {
    pub ops: Vec<LinkOp>,
    pub ledger: Vec<LedgerOp>,
    pub conflicts: Vec<Conflict>,
    pub notes: Vec<String>,
}

impl Plan {
    pub fn is_empty(&self) -> bool {
        self.ops.is_empty() && self.ledger.is_empty()
    }

    pub fn is_blocked(&self) -> bool {
        !self.conflicts.is_empty()
    }

    /// One line per op, for the CLI and the consent card.
    pub fn describe(&self) -> Vec<String> {
        let mut lines: Vec<String> = self
            .ops
            .iter()
            .map(|op| match op {
                LinkOp::Create { link, target } => format!("link    {} -> {target}", link.display()),
                LinkOp::Replace { link, target, expected } => {
                    format!("relink  {} -> {target} (was {expected})", link.display())
                }
                LinkOp::Remove { link, .. } => format!("unlink  {}", link.display()),
                LinkOp::Copy { link, from } => format!("copy    {} <- {}", link.display(), from.display()),
                LinkOp::RemoveCopy { link } => format!("delete  {} (copy)", link.display()),
            })
            .collect();
        for conflict in &self.conflicts {
            lines.push(format!(
                "conflict {}: {} ({:?})",
                conflict.link.display(),
                conflict.detail,
                conflict.kind
            ));
        }
        lines
    }
}

/// Which records an operation applies to.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(tag = "selector", rename_all = "snake_case")]
pub enum Selector {
    /// One skill of one source.
    Skill { source_id: String, skill: String },
    /// Every skill of one source (the repository-level operation the ecosystem lacks).
    Source { source_id: String },
}

impl Selector {
    fn matches(&self, row: &LinkRecord) -> bool {
        match self {
            Self::Skill { source_id, skill } => {
                row.source_id == *source_id && row.skill.as_str() == skill
            }
            Self::Source { source_id } => row.source_id == *source_id,
        }
    }
}

/// Plan installing `desired` skills into `targets`.
///
/// `now` stamps new records; the caller supplies it so tests and the CLI agree.
pub fn plan_install(
    desired: &[DesiredSkill],
    targets: &[&Target],
    ledger: &Ledger,
    probe: &dyn FsProbe,
    now: u64,
) -> Plan {
    let mut plan = Plan::default();
    let canonical = targets.iter().copied().find(|target| target.canonical);

    for want in desired {
        let Some(content) = want.origin.content_path() else {
            plan.conflicts.push(Conflict {
                link: PathBuf::new(),
                kind: ConflictKind::MissingContent,
                detail: format!(
                    "'{}' is adopted, so its bytes are wherever it was installed; reinstall it to manage it",
                    want.skill.id
                ),
            });
            continue;
        };
        if !probe.content_exists(content) {
            plan.conflicts.push(Conflict {
                link: content.to_path_buf(),
                kind: ConflictKind::MissingContent,
                detail: format!("content for '{}' is missing at {}", want.skill.id, content.display()),
            });
            continue;
        }

        let canonical_link = canonical.map(|target| target.dir_for(&want.scope).join(want.skill.id.as_str()));

        for target in targets {
            let dir = target.dir_for(&want.scope);
            let link = dir.join(want.skill.id.as_str());
            // The canonical farm points at the content; every other target points at the
            // canonical entry, which is the ecosystem's layout (D10) and keeps one hop of truth.
            let dest: PathBuf = match (target.canonical, &canonical_link) {
                (true, _) => content.to_path_buf(),
                (false, Some(canonical_link)) => canonical_link.clone(),
                (false, None) => content.to_path_buf(),
            };
            let target_text = if target.style == crate::domain::skill_targets::LinkStyle::Copy {
                format!("copy:{}", content.display())
            } else {
                rel_link(&link, &dest)
            };

            let existing = ledger.row_for(&link);
            match (probe.probe(&link), existing) {
                (Probe::Symlink { target: actual, .. }, Some(row)) if row.target == target_text => {
                    // Already right; refresh the record (origin may have moved to a new ref).
                    if row.origin != want.origin || row.hash != want.skill.hash {
                        plan.ledger.push(LedgerOp::Upsert(record_for(want, target, &link, &target_text, LinkState::Linked, now)));
                    }
                    let _ = actual;
                }
                (Probe::Symlink { target: actual, .. }, existing) => {
                    let ours = existing.is_some();
                    if !ours {
                        plan.conflicts.push(Conflict {
                            link: link.clone(),
                            kind: ConflictKind::UnmanagedLink,
                            detail: format!("a link this manager did not create points at {actual}; adopt it or move it aside"),
                        });
                        continue;
                    }
                    plan.ops.push(LinkOp::Replace {
                        link: link.clone(),
                        target: target_text.clone(),
                        expected: actual,
                    });
                    plan.ledger.push(LedgerOp::Upsert(record_for(want, target, &link, &target_text, LinkState::Linked, now)));
                }
                // An adopted farm holds real directories; adopting it again is a no-op unless the
                // content changed.
                (Probe::Directory, Some(row)) if matches!(row.origin, Origin::Adopted { .. }) => {
                    if row.hash != want.skill.hash {
                        plan.notes.push(format!(
                            "'{}' was adopted and its content changed; review it, then re-adopt",
                            want.skill.id
                        ));
                    }
                }
                (Probe::Directory, Some(row)) if target.style == crate::domain::skill_targets::LinkStyle::Copy => {
                    // A copy that is already ours: rewrite it only when the content changed.
                    if row.hash != want.skill.hash || row.origin != want.origin {
                        plan.ops.push(LinkOp::Copy { link: link.clone(), from: content.to_path_buf() });
                        plan.ledger.push(LedgerOp::Upsert(record_for(want, target, &link, &target_text, LinkState::Linked, now)));
                    }
                }
                (Probe::Directory, _) | (Probe::File, _) => {
                    plan.conflicts.push(Conflict {
                        link: link.clone(),
                        kind: ConflictKind::Occupied,
                        detail: "something that is not this manager's link is in the way; it will not be deleted".to_string(),
                    });
                }
                (Probe::Missing, existing) => {
                    if target.style == crate::domain::skill_targets::LinkStyle::Copy {
                        plan.ops.push(LinkOp::Copy { link: link.clone(), from: content.to_path_buf() });
                    } else {
                        plan.ops.push(LinkOp::Create {
                            link: link.clone(),
                            target: target_text.clone(),
                        });
                    }
                    if existing.map(|row| row.target != target_text || row.state != LinkState::Linked).unwrap_or(true) {
                        plan.ledger.push(LedgerOp::Upsert(record_for(want, target, &link, &target_text, LinkState::Linked, now)));
                    }
                }
            }
        }
    }

    plan
}

fn record_for(
    want: &DesiredSkill,
    target: &Target,
    link: &Path,
    target_text: &str,
    state: LinkState,
    now: u64,
) -> LinkRecord {
    LinkRecord {
        link: link.to_path_buf(),
        target: target_text.to_string(),
        target_id: target.id.to_string(),
        source_id: want.source_id.clone(),
        skill: want.skill.id.clone(),
        origin: want.origin.clone(),
        scope: want.scope.clone(),
        state,
        hash: want.skill.hash.clone(),
        created_at: now,
    }
}

/// Plan enabling or disabling the records matched by `selector`.
///
/// Disabling removes the links and keeps the content (spec §7); enabling recreates them from the
/// recorded origin. Removal is ownership-checked: a link whose target changed is a conflict, not
/// something to delete.
pub fn plan_set_state(
    ledger: &Ledger,
    selector: &Selector,
    enable: bool,
    probe: &dyn FsProbe,
    now: u64,
) -> Plan {
    let mut plan = Plan::default();
    for row in ledger.links.iter().filter(|row| selector.matches(row)) {
        let desired_state = if enable { LinkState::Linked } else { LinkState::Disabled };
        match (enable, row.state, probe.probe(&row.link)) {
            // Already in the requested state and on disk: nothing to do.
            (true, LinkState::Linked, _) | (false, LinkState::Disabled, Probe::Missing) => {}
            (true, _, Probe::Symlink { target, .. }) if target == row.target => {
                plan.ledger.push(LedgerOp::Upsert(LinkRecord { state: desired_state, ..row.clone() }));
            }
            (false, _, Probe::Symlink { target, .. }) => {
                if target != row.target {
                    plan.conflicts.push(Conflict {
                        link: row.link.clone(),
                        kind: ConflictKind::Drifted,
                        detail: format!("points at {target}, but the ledger recorded {}; left alone", row.target),
                    });
                    continue;
                }
                plan.ops.push(LinkOp::Remove {
                    link: row.link.clone(),
                    expected: row.target.clone(),
                });
                plan.ledger.push(LedgerOp::Upsert(LinkRecord { state: desired_state, ..row.clone() }));
            }
            (false, _, Probe::Directory) if row.target.starts_with("copy:") => {
                plan.ops.push(LinkOp::RemoveCopy { link: row.link.clone() });
                plan.ledger.push(LedgerOp::Upsert(LinkRecord { state: desired_state, ..row.clone() }));
            }
            // The row says linked, but nothing is on disk: disabling is only a record.
            (false, _, Probe::Missing) => {
                plan.ledger.push(LedgerOp::Upsert(LinkRecord { state: desired_state, ..row.clone() }));
            }
            // An adopted farm is a real directory: disabling it moves it to the trash, which is
            // recoverable and leaves nothing for an agent to load.
            (false, _, Probe::Directory) if matches!(row.origin, Origin::Adopted { .. }) => {
                plan.ops.push(LinkOp::RemoveCopy { link: row.link.clone() });
                plan.ledger.push(LedgerOp::Upsert(LinkRecord { state: desired_state, ..row.clone() }));
            }
            // Disabling must not delete a real file or directory, even if it is where our link was.
            (false, _, Probe::Directory) | (false, _, Probe::File) => {
                plan.conflicts.push(Conflict {
                    link: row.link.clone(),
                    kind: ConflictKind::Drifted,
                    detail: "the managed link is gone and something else is here; left alone".to_string(),
                });
            }
            (true, _, _) => {
                let Some(content) = row.origin.content_path() else {
                    plan.conflicts.push(Conflict {
                        link: row.link.clone(),
                        kind: ConflictKind::MissingContent,
                        detail: "the recorded origin has no Astral-managed content".to_string(),
                    });
                    continue;
                };
                if !probe.content_exists(content) {
                    plan.conflicts.push(Conflict {
                        link: row.link.clone(),
                        kind: ConflictKind::MissingContent,
                        detail: format!("content is gone from {}; reinstall the skill", content.display()),
                    });
                    continue;
                }
                let target_text = if row.target.starts_with("copy:") {
                    format!("copy:{}", content.display())
                } else {
                    rel_link(&row.link, content)
                };
                match probe.probe(&row.link) {
                    Probe::Missing => plan.ops.push(LinkOp::Create {
                        link: row.link.clone(),
                        target: target_text.clone(),
                    }),
                    Probe::Symlink { target, .. } if target == row.target => {
                        plan.ops.push(LinkOp::Replace {
                            link: row.link.clone(),
                            target: target_text.clone(),
                            expected: target,
                        })
                    }
                    _ => {
                        plan.conflicts.push(Conflict {
                            link: row.link.clone(),
                            kind: ConflictKind::Occupied,
                            detail: "something else took the path while the skill was disabled".to_string(),
                        });
                        continue;
                    }
                }
                plan.ledger.push(LedgerOp::Upsert(LinkRecord {
                    target: target_text,
                    state: LinkState::Linked,
                    created_at: now,
                    ..row.clone()
                }));
            }
        }
    }
    plan
}

/// Plan removing the records matched by `selector`: unlink what we still own, drop the rows.
pub fn plan_remove(ledger: &Ledger, selector: &Selector, probe: &dyn FsProbe) -> Plan {
    let mut plan = Plan::default();
    for row in ledger.links.iter().filter(|row| selector.matches(row)) {
        match probe.probe(&row.link) {
            Probe::Symlink { target, .. } => {
                if target != row.target {
                    plan.conflicts.push(Conflict {
                        link: row.link.clone(),
                        kind: ConflictKind::Drifted,
                        detail: format!("points at {target}, not {}; left alone", row.target),
                    });
                    continue;
                }
                plan.ops.push(LinkOp::Remove {
                    link: row.link.clone(),
                    expected: row.target.clone(),
                });
            }
            Probe::Directory if row.target.starts_with("copy:") || matches!(row.origin, Origin::Adopted { .. }) => {
                plan.ops.push(LinkOp::RemoveCopy { link: row.link.clone() });
            }
            Probe::Directory | Probe::File => {
                plan.conflicts.push(Conflict {
                    link: row.link.clone(),
                    kind: ConflictKind::Drifted,
                    detail: "the managed link is gone and something else is here; left alone".to_string(),
                });
                continue;
            }
            Probe::Missing => {}
        }
        plan.ledger.push(LedgerOp::Drop { link: row.link.clone() });
    }
    plan
}

/// A relative path from the directory containing `link` to `dest`.
///
/// Links are relative so a farm can move (or be committed in a project) and still resolve. When
/// the two paths share no prefix the absolute path is returned — still correct, just not movable.
pub fn rel_link(link: &Path, dest: &Path) -> String {
    let from = link.parent().unwrap_or(Path::new("/"));
    if let Some(relative) = relative_path(from, dest) {
        return relative;
    }
    dest.display().to_string()
}

fn relative_path(from: &Path, to: &Path) -> Option<String> {
    let from = normalise(from);
    let to = normalise(to);
    let mut from_iter = from.components().peekable();
    let mut to_iter = to.components().peekable();
    let mut common = 0usize;
    while let (Some(a), Some(b)) = (from_iter.peek(), to_iter.peek()) {
        if a != b {
            break;
        }
        from_iter.next();
        to_iter.next();
        common += 1;
    }
    if common == 0 {
        return None;
    }
    let mut parts: Vec<String> = Vec::new();
    for _ in from_iter {
        parts.push("..".to_string());
    }
    for component in to_iter {
        match component {
            Component::Normal(part) => parts.push(part.to_string_lossy().into_owned()),
            Component::RootDir | Component::CurDir => {}
            Component::ParentDir => parts.push("..".to_string()),
            Component::Prefix(_) => {}
        }
    }
    if parts.is_empty() {
        return Some(".".to_string());
    }
    Some(parts.join("/"))
}

fn normalise(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::skill::SkillMeta;
    use crate::domain::skill_ledger::{LinkRecord, Origin};
    use crate::domain::skill_targets::{target_by_id, LinkStyle, Scope, TARGETS};
    use std::collections::BTreeMap;

    /// An in-memory filesystem: the whole planning matrix without touching a disk.
    #[derive(Default)]
    struct FakeFs {
        entries: BTreeMap<PathBuf, Probe>,
    }

    impl FakeFs {
        fn with(mut self, path: impl Into<PathBuf>, probe: Probe) -> Self {
            self.entries.insert(path.into(), probe);
            self
        }
        fn apply(&mut self, plan: &Plan) {
            for op in &plan.ops {
                match op {
                    LinkOp::Create { link, target } => {
                        self.entries.insert(link.clone(), Probe::Symlink { target: target.clone(), dangling: false });
                    }
                    LinkOp::Replace { link, target, .. } => {
                        self.entries.insert(link.clone(), Probe::Symlink { target: target.clone(), dangling: false });
                    }
                    LinkOp::Remove { link, .. } | LinkOp::RemoveCopy { link } => {
                        self.entries.remove(link);
                    }
                    LinkOp::Copy { link, .. } => {
                        self.entries.insert(link.clone(), Probe::Directory);
                    }
                }
            }
        }
    }

    impl FsProbe for FakeFs {
        fn probe(&self, path: &Path) -> Probe {
            self.entries.get(path).cloned().unwrap_or(Probe::Missing)
        }
    }

    fn skill(id: &str, hash: &str) -> SkillMeta {
        SkillMeta {
            id: crate::domain::skill::SkillId::parse(id).unwrap(),
            description: String::new(),
            subpath: id.to_string(),
            hash: hash.to_string(),
            files: 1,
            bytes: 10,
            version: None,
        }
    }

    fn project() -> Scope {
        Scope::Project { root: PathBuf::from("/repo") }
    }

    fn origin() -> Origin {
        Origin::Store {
            ref_name: "main".to_string(),
            sha: "a".repeat(40),
            path: PathBuf::from("/store/gh/owner/repo@main/skill-a"),
        }
    }

    fn desired(id: &str) -> DesiredSkill {
        DesiredSkill {
            source_id: "owner-repo".to_string(),
            skill: skill(id, "hash1"),
            origin: origin(),
            scope: project(),
        }
    }

    fn targets(ids: &[&str]) -> Vec<&'static Target> {
        ids.iter().map(|id| target_by_id(id).unwrap()).collect()
    }

    fn link(dir: &str, id: &str) -> String {
        format!("/repo/{dir}/{id}")
    }

    #[test]
    fn a_fresh_install_links_the_canonical_farm_and_points_others_at_it() {
        let fs = FakeFs::default().with("/store/gh/owner/repo@main/skill-a", Probe::Directory);
        let plan = plan_install(&[desired("skill-a")], &targets(&["codex", "claude-code"]), &Ledger::default(), &fs, 7);
        assert!(plan.conflicts.is_empty(), "{:?}", plan.conflicts);
        let ops = plan.describe();
        assert_eq!(ops.len(), 2, "{ops:?}");
        // The canonical farm points into the store...
        assert_eq!(plan.ops[0], LinkOp::Create {
            link: PathBuf::from(link(".agents/skills", "skill-a")),
            target: "../../../store/gh/owner/repo@main/skill-a".to_string(),
        });
        // ...and Claude Code points at the canonical entry, one hop from truth.
        assert_eq!(plan.ops[1], LinkOp::Create {
            link: PathBuf::from(link(".claude/skills", "skill-a")),
            target: "../../.agents/skills/skill-a".to_string(),
        });
        // Every created link is recorded, so we own exactly what we made.
        assert_eq!(plan.ledger.len(), 2);
        match &plan.ledger[0] {
            LedgerOp::Upsert(row) => {
                assert_eq!(row.target_id, "codex");
                assert_eq!(row.state, LinkState::Linked);
                assert_eq!(row.created_at, 7);
            }
            other => panic!("expected an upsert, got {other:?}"),
        }
    }

    #[test]
    fn applying_the_same_install_twice_changes_nothing() {
        let mut fs = FakeFs::default()
            .with("/store/gh/owner/repo@main/skill-a", Probe::Directory);
        let ledger = Ledger::default();
        let first = plan_install(&[desired("skill-a")], &targets(&["codex", "claude-code"]), &ledger, &fs, 1);
        fs.apply(&first);
        let mut ledger_after = ledger.clone();
        for op in &first.ledger {
            if let LedgerOp::Upsert(row) = op {
                ledger_after.upsert(row.clone());
            }
        }
        let second = plan_install(&[desired("skill-a")], &targets(&["codex", "claude-code"]), &ledger_after, &fs, 2);
        assert!(second.is_empty(), "second plan must be empty: {:?}", second.describe());
    }

    #[test]
    fn a_link_we_did_not_create_is_a_conflict_never_a_silent_takeover() {
        let fs = FakeFs::default()
            .with("/store/gh/owner/repo@main/skill-a", Probe::Directory)
            .with(link(".claude/skills", "skill-a"), Probe::Symlink {
                target: "/home/me/my-own".to_string(),
                dangling: false,
            });
        let plan = plan_install(&[desired("skill-a")], &targets(&["claude-code"]), &Ledger::default(), &fs, 1);
        assert_eq!(plan.conflicts.len(), 1);
        assert_eq!(plan.conflicts[0].kind, ConflictKind::UnmanagedLink);
        assert_eq!(plan.conflicts[0].link, PathBuf::from(link(".claude/skills", "skill-a")));
        assert!(plan.ops.is_empty(), "nothing is written when a conflict is reported");
    }

    #[test]
    fn a_real_directory_in_the_way_is_never_deleted() {
        let fs = FakeFs::default()
            .with("/store/gh/owner/repo@main/skill-a", Probe::Directory)
            .with(link(".agents/skills", "skill-a"), Probe::Directory);
        let plan = plan_install(&[desired("skill-a")], &targets(&["codex"]), &Ledger::default(), &fs, 1);
        assert_eq!(plan.conflicts.len(), 1);
        assert_eq!(plan.conflicts[0].kind, ConflictKind::Occupied);
        assert!(plan.ops.is_empty());
    }

    #[test]
    fn our_link_to_an_old_place_is_replaced_and_a_foreign_one_is_not() {
        let ours = {
            let mut ledger = Ledger::default();
            ledger.upsert(LinkRecord {
                link: PathBuf::from(link(".agents/skills", "skill-a")),
                target: "../old".to_string(),
                target_id: "codex".to_string(),
                source_id: "owner-repo".to_string(),
                skill: skill("skill-a", "hash0").id.clone(),
                origin: origin(),
                scope: project(),
                state: LinkState::Linked,
                hash: "hash0".to_string(),
                created_at: 1,
            });
            ledger
        };
        let fs = FakeFs::default()
            .with("/store/gh/owner/repo@main/skill-a", Probe::Directory)
            .with(link(".agents/skills", "skill-a"), Probe::Symlink {
                target: "../old".to_string(),
                dangling: true,
            });
        let plan = plan_install(&[desired("skill-a")], &targets(&["codex"]), &ours, &fs, 2);
        assert!(plan.conflicts.is_empty(), "{:?}", plan.conflicts);
        assert!(matches!(plan.ops[0], LinkOp::Replace { .. }), "{:?}", plan.ops);
    }

    #[test]
    fn disabling_unlinks_and_keeps_the_content_and_enabling_restores_it() {
        let mut fs = FakeFs::default().with("/store/gh/owner/repo@main/skill-a", Probe::Directory);
        let installed = plan_install(&[desired("skill-a")], &targets(&["codex", "claude-code"]), &Ledger::default(), &fs, 1);
        fs.apply(&installed);
        let mut ledger = Ledger::default();
        for op in &installed.ledger {
            if let LedgerOp::Upsert(row) = op {
                ledger.upsert(row.clone());
            }
        }

        let selector = Selector::Skill {
            source_id: "owner-repo".to_string(),
            skill: "skill-a".to_string(),
        };
        let disable = plan_set_state(&ledger, &selector, false, &fs, 2);
        assert_eq!(disable.ops.len(), 2, "{:?}", disable.describe());
        assert!(disable.conflicts.is_empty());
        fs.apply(&disable);
        for op in &disable.ledger {
            if let LedgerOp::Upsert(row) = op {
                ledger.upsert(row.clone());
            }
        }
        assert_eq!(ledger.state_of("owner-repo", &skill("skill-a", "").id), Some(LinkState::Disabled));
        // Content is untouched, so enabling is instant and needs no fetch.
        assert!(fs.probe(Path::new("/store/gh/owner/repo@main/skill-a")) != Probe::Missing);

        let enable = plan_set_state(&ledger, &selector, true, &fs, 3);
        assert_eq!(enable.ops.len(), 2, "{:?}", enable.describe());
        fs.apply(&enable);
    }

    #[test]
    fn disabling_twice_is_a_no_op() {
        let mut fs = FakeFs::default().with("/store/gh/owner/repo@main/skill-a", Probe::Directory);
        let installed = plan_install(&[desired("skill-a")], &targets(&["codex"]), &Ledger::default(), &fs, 1);
        fs.apply(&installed);
        let mut ledger = Ledger::default();
        for op in &installed.ledger {
            if let LedgerOp::Upsert(row) = op {
                ledger.upsert(row.clone());
            }
        }
        let selector = Selector::Source { source_id: "owner-repo".to_string() };
        let first = plan_set_state(&ledger, &selector, false, &fs, 2);
        for op in &first.ledger {
            if let LedgerOp::Upsert(row) = op {
                ledger.upsert(row.clone());
            }
        }
        fs.apply(&first);
        let second = plan_set_state(&ledger, &selector, false, &fs, 3);
        assert!(second.is_empty(), "{:?}", second.describe());
    }

    #[test]
    fn enabling_a_skill_whose_content_is_gone_is_refused_with_a_reason() {
        let mut ledger = Ledger::default();
        ledger.upsert(LinkRecord {
            link: PathBuf::from(link(".agents/skills", "skill-a")),
            target: "../../store/x".to_string(),
            target_id: "codex".to_string(),
            source_id: "owner-repo".to_string(),
            skill: skill("skill-a", "h").id.clone(),
            origin: Origin::Store {
                ref_name: "main".to_string(),
                sha: "a".repeat(40),
                path: PathBuf::from("/store/gone"),
            },
            scope: project(),
            state: LinkState::Disabled,
            hash: "h".to_string(),
            created_at: 1,
        });
        let plan = plan_set_state(
            &ledger,
            &Selector::Source { source_id: "owner-repo".to_string() },
            true,
            &FakeFs::default(),
            2,
        );
        assert_eq!(plan.conflicts.len(), 1);
        assert_eq!(plan.conflicts[0].kind, ConflictKind::MissingContent);
        assert!(plan.conflicts[0].detail.contains("/store/gone"));
    }

    #[test]
    fn a_repo_selector_touches_only_that_repository() {
        let mut ledger = Ledger::default();
        for (source, name) in [("owner-repo", "alpha"), ("other-repo", "beta")] {
            ledger.upsert(LinkRecord {
                link: PathBuf::from(link(".agents/skills", name)),
                target: "../../store/x".to_string(),
                target_id: "codex".to_string(),
                source_id: source.to_string(),
                skill: skill(name, "h").id.clone(),
                origin: origin(),
                scope: project(),
                state: LinkState::Linked,
                hash: "h".to_string(),
                created_at: 1,
            });
        }
        let mut fs = FakeFs::default();
        for name in ["alpha", "beta"] {
            fs = fs.with(link(".agents/skills", name), Probe::Symlink {
                target: "../../store/x".to_string(),
                dangling: false,
            });
        }
        let plan = plan_remove(&ledger, &Selector::Source { source_id: "owner-repo".to_string() }, &fs);
        assert_eq!(plan.ops.len(), 1);
        assert_eq!(plan.ops[0], LinkOp::Remove {
            link: PathBuf::from(link(".agents/skills", "alpha")),
            expected: "../../store/x".to_string(),
        });
        assert_eq!(plan.ledger, vec![LedgerOp::Drop { link: PathBuf::from(link(".agents/skills", "alpha")) }]);
    }

    #[test]
    fn removal_leaves_a_drifted_link_alone_and_keeps_its_row() {
        let mut ledger = Ledger::default();
        ledger.upsert(LinkRecord {
            link: PathBuf::from(link(".claude/skills", "alpha")),
            target: "../../.agents/skills/alpha".to_string(),
            target_id: "claude-code".to_string(),
            source_id: "owner-repo".to_string(),
            skill: skill("alpha", "h").id.clone(),
            origin: origin(),
            scope: project(),
            state: LinkState::Linked,
            hash: "h".to_string(),
            created_at: 1,
        });
        let fs = FakeFs::default().with(link(".claude/skills", "alpha"), Probe::Symlink {
            target: "/somewhere/else".to_string(),
            dangling: false,
        });
        let plan = plan_remove(&ledger, &Selector::Source { source_id: "owner-repo".to_string() }, &fs);
        assert_eq!(plan.conflicts.len(), 1);
        assert_eq!(plan.conflicts[0].kind, ConflictKind::Drifted);
        assert!(plan.ops.is_empty());
        assert!(plan.ledger.is_empty(), "the row stays, so the drift is still known");
    }

    #[test]
    fn a_replaced_farm_member_is_reported_not_deleted() {
        let mut ledger = Ledger::default();
        ledger.upsert(LinkRecord {
            link: PathBuf::from(link(".agents/skills", "alpha")),
            target: "../../store/x".to_string(),
            target_id: "codex".to_string(),
            source_id: "owner-repo".to_string(),
            skill: skill("alpha", "h").id.clone(),
            origin: origin(),
            scope: project(),
            state: LinkState::Linked,
            hash: "h".to_string(),
            created_at: 1,
        });
        let fs = FakeFs::default().with(link(".agents/skills", "alpha"), Probe::Directory);
        let plan = plan_remove(&ledger, &Selector::Source { source_id: "owner-repo".to_string() }, &fs);
        assert_eq!(plan.conflicts.len(), 1);
        assert_eq!(plan.conflicts[0].kind, ConflictKind::Drifted);
    }

    #[test]
    fn relative_links_survive_depth_and_never_escape_the_tree() {
        assert_eq!(
            rel_link(Path::new("/repo/.claude/skills/a"), Path::new("/repo/.agents/skills/a")),
            "../../.agents/skills/a"
        );
        // Sibling skills: the link names the neighbour, not a path through the root.
        assert_eq!(
            rel_link(Path::new("/repo/.agents/skills/a"), Path::new("/repo/.agents/skills/b")),
            "b"
        );
        assert_eq!(
            // /repo/.agents/skills -> / is three levels up, then into the store.
            rel_link(Path::new("/repo/.agents/skills/a"), Path::new("/store/x")),
            "../../../store/x"
        );
        // Two absolute paths always share `/`, so the result stays relative.
        assert_eq!(rel_link(Path::new("/a/b"), Path::new("/c/d")), "../c/d");
        // Paths with no shared component cannot be made relative; the destination is kept as-is
        // rather than producing a link that would not resolve.
        assert_eq!(rel_link(Path::new("a/b"), Path::new("c/d")), "c/d");
    }

    #[test]
    fn a_copy_target_copies_instead_of_linking_and_is_idempotent() {
        let copy_target = Target {
            id: "legacy",
            label: "Legacy",
            project_dir: ".legacy/skills",
            global_dir: "~/.legacy/skills",
            canonical: false,
            style: LinkStyle::Copy,
        };
        let mut fs = FakeFs::default().with("/store/gh/owner/repo@main/skill-a", Probe::Directory);
        let plan = plan_install(&[desired("skill-a")], &[&copy_target], &Ledger::default(), &fs, 1);
        assert!(matches!(plan.ops[0], LinkOp::Copy { .. }), "{:?}", plan.ops);
        fs.apply(&plan);
        let mut ledger = Ledger::default();
        for op in &plan.ledger {
            if let LedgerOp::Upsert(row) = op {
                ledger.upsert(row.clone());
            }
        }
        let again = plan_install(&[desired("skill-a")], &[&copy_target], &ledger, &fs, 2);
        assert!(again.is_empty(), "an unchanged copy is not rewritten: {:?}", again.describe());
    }

    #[test]
    fn every_target_in_the_table_resolves_to_a_link_under_its_own_directory() {
        let fs = FakeFs::default().with("/store/gh/owner/repo@main/skill-a", Probe::Directory);
        let all: Vec<&'static Target> = TARGETS.iter().collect();
        let plan = plan_install(&[desired("skill-a")], &all, &Ledger::default(), &fs, 1);
        assert_eq!(plan.ops.len(), TARGETS.len());
        for (op, target) in plan.ops.iter().zip(TARGETS.iter()) {
            match op {
                LinkOp::Create { link, .. } => {
                    assert_eq!(link, &target.dir_for(&project()).join("skill-a"));
                }
                other => panic!("expected a create, got {other:?}"),
            }
        }
    }
}
