//! Applying a plan to the real filesystem: atomic links, a journal, and ownership checks.
//!
//! The planner decides *what* to do (spec §6); this module is the only place allowed to touch
//! the tree, and every mutation here is reversible or recorded:
//!
//! * creation is `symlink(tmp)` + `rename`, so an agent never sees a half-written link;
//! * removal requires the link to still point where the ledger says (`read_link`), and uses
//!   `remove_file` — never `remove_dir_all`;
//! * a plan writes `journal/<txid>.json` first and deletes it last, so an interrupted apply is
//!   resumed (ops are idempotent) rather than left half-applied;
//! * the ledger is written with `temp + rename`.

use std::fmt::Write as FmtWrite;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::domain::ports::DynResult;
use crate::domain::skill_install::{Conflict, ConflictKind, FsProbe, LedgerOp, LinkOp, Plan, Probe};
use crate::domain::skill_ledger::Ledger;

/// The real filesystem, as the planner sees it.
pub struct RealFs;

impl FsProbe for RealFs {
    fn probe(&self, path: &Path) -> Probe {
        match std::fs::symlink_metadata(path) {
            Err(_) => Probe::Missing,
            Ok(meta) => {
                let file_type = meta.file_type();
                if file_type.is_symlink() {
                    match std::fs::read_link(path) {
                        Ok(target) => {
                            // `metadata` follows the link: a failure means it dangles.
                            let dangling = std::fs::metadata(path).is_err();
                            Probe::Symlink {
                                target: target.to_string_lossy().into_owned(),
                                dangling,
                            }
                        }
                        Err(_) => Probe::File,
                    }
                } else if file_type.is_dir() {
                    Probe::Directory
                } else {
                    Probe::File
                }
            }
        }
    }

    fn content_exists(&self, path: &Path) -> bool {
        // Content is a directory we copied; a link to content is not content.
        std::fs::symlink_metadata(path)
            .map(|meta| meta.is_dir())
            .unwrap_or(false)
    }
}

/// Where the manager keeps its own state.
#[derive(Debug, Clone)]
pub struct SkillPaths {
    /// Write-once content (`<data>/skills/store`).
    pub store: PathBuf,
    /// Discovery cache (`<cache>/skills/git`).
    pub git_cache: PathBuf,
    /// The ledger (`<state>/skills/ledger.json`).
    pub ledger: PathBuf,
    /// In-flight transactions (`<state>/skills/journal`).
    pub journal: PathBuf,
    /// Replaced or removed items, for a week (`<state>/skills/trash`).
    pub trash: PathBuf,
}

impl SkillPaths {
    /// The XDG layout from the spec (§4), rooted at `data`/`state`/`cache`.
    pub fn new(data: PathBuf, state: PathBuf, cache: PathBuf) -> Self {
        Self {
            store: data.join("skills/store"),
            git_cache: cache.join("skills/git"),
            ledger: state.join("skills/ledger.json"),
            journal: state.join("skills/journal"),
            trash: state.join("skills/trash"),
        }
    }

    /// The default locations, honouring `XDG_DATA_HOME` / `XDG_STATE_HOME` / `XDG_CACHE_HOME`.
    pub fn from_env() -> Self {
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"));
        let data = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".local/share"));
        let state = std::env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".local/state"));
        let cache = std::env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".cache"));
        Self::new(data, state, cache)
    }

    pub fn ensure(&self) -> DynResult<()> {
        for dir in [&self.store, &self.git_cache, &self.journal, &self.trash] {
            std::fs::create_dir_all(dir)?;
        }
        if let Some(parent) = self.ledger.parent() {
            std::fs::create_dir_all(parent)?;
        }
        Ok(())
    }
}

/// What one apply did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Applied {
    pub created: usize,
    pub replaced: usize,
    pub removed: usize,
    pub copied: usize,
    pub conflicts: Vec<Conflict>,
}

impl Applied {
    pub fn is_empty(&self) -> bool {
        self.created + self.replaced + self.removed + self.copied == 0 && self.conflicts.is_empty()
    }
}

/// Read the ledger, treating a missing file as an empty one.
pub fn read_ledger(path: &Path) -> DynResult<Ledger> {
    match std::fs::read(path) {
        Ok(bytes) => Ledger::parse(&bytes).map_err(|error| error.into()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(Ledger::default()),
        Err(err) => Err(err.into()),
    }
}

/// Write the ledger atomically: a half-written ledger is a lie about what we own.
pub fn write_ledger(path: &Path, ledger: &Ledger) -> DynResult<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let temporary = path.with_extension("json.tmp");
    std::fs::write(&temporary, ledger.to_bytes())?;
    std::fs::rename(&temporary, path)?;
    Ok(())
}

/// Apply `plan` to the filesystem and the ledger.
///
/// Conflicts in the plan are *not* applied: the caller decides whether to show them or refuse.
/// A plan is applied as a unit: journal first, ops in order, ledger last, journal removed.
pub fn apply(paths: &SkillPaths, plan: &Plan, now_ms: u64) -> DynResult<Applied> {
    paths.ensure()?;
    let mut report = Applied {
        conflicts: plan.conflicts.clone(),
        ..Applied::default()
    };
    if plan.ops.is_empty() && plan.ledger.is_empty() {
        return Ok(report);
    }

    let transaction = format!("{now_ms}-{}", std::process::id());
    let journal_path = paths.journal.join(format!("{transaction}.json"));
    let journal = Journal {
        transaction: transaction.clone(),
        ops: plan.ops.clone(),
        ledger_ops: plan.ledger.clone(),
    };
    std::fs::create_dir_all(&paths.journal)?;
    std::fs::write(&journal_path, serde_json::to_vec_pretty(&journal)?)?;

    let mut ledger = read_ledger(&paths.ledger)?;
    for op in &plan.ops {
        // Conflicts are filtered by the planner; anything that fails here aborts the whole
        // transaction, and the journal stays for a later resume.
        match op {
            LinkOp::Create { link, target } => {
                atomic_symlink(link, target)?;
                report.created += 1;
            }
            LinkOp::Replace { link, target, expected } => {
                ensure_ours(link, expected)?;
                atomic_symlink(link, target)?;
                report.replaced += 1;
            }
            LinkOp::Remove { link, expected } => {
                ensure_ours(link, expected)?;
                std::fs::remove_file(link)?;
                report.removed += 1;
            }
            LinkOp::Copy { link, from } => {
                move_to_trash(paths, &transaction, link)?;
                copy_tree(from, link)?;
                report.copied += 1;
            }
            LinkOp::RemoveCopy { link } => {
                move_to_trash(paths, &transaction, link)?;
                report.removed += 1;
            }
        }
    }
    for op in &plan.ledger {
        match op {
            LedgerOp::Upsert(row) => ledger.upsert(row.clone()),
            LedgerOp::Drop { link } => {
                ledger.remove(link);
            }
        }
    }
    write_ledger(&paths.ledger, &ledger)?;
    let _ = std::fs::remove_file(&journal_path);
    Ok(report)
}

/// A plan that was in flight when the process died.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct Journal {
    transaction: String,
    ops: Vec<LinkOp>,
    ledger_ops: Vec<LedgerOp>,
}

/// Finish or discard transactions left behind by a crash.
///
/// Ops are idempotent by construction, so resuming is safe: a link that already exists with the
/// right target is a no-op, and the ledger write is the last step either way.
pub fn recover(paths: &SkillPaths) -> DynResult<usize> {
    let Ok(entries) = std::fs::read_dir(&paths.journal) else {
        return Ok(0);
    };
    let mut resumed = 0;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        let Ok(bytes) = std::fs::read(&path) else { continue };
        let Ok(journal) = serde_json::from_slice::<Journal>(&bytes) else {
            // An unreadable journal is moved aside rather than blocking every later command.
            let _ = std::fs::rename(&path, path.with_extension("json.broken"));
            continue;
        };
        let mut ledger = read_ledger(&paths.ledger)?;
        for op in &journal.ops {
            match op {
                LinkOp::Create { link, target } => {
                    let expected = Probe::Symlink {
                        target: target.clone(),
                        dangling: false,
                    };
                    if RealFs.probe(link) != expected {
                        let _ = atomic_symlink(link, target);
                    }
                }
                LinkOp::Replace { link, target, .. } => {
                    let _ = atomic_symlink(link, target);
                }
                LinkOp::Remove { link, .. } | LinkOp::RemoveCopy { link } => {
                    let _ = std::fs::remove_file(link);
                }
                LinkOp::Copy { link, from } => {
                    if RealFs.probe(link) == Probe::Missing {
                        let _ = copy_tree(from, link);
                    }
                }
            }
        }
        for op in &journal.ledger_ops {
            match op {
                LedgerOp::Upsert(row) => ledger.upsert(row.clone()),
                LedgerOp::Drop { link } => {
                    ledger.remove(link);
                }
            }
        }
        write_ledger(&paths.ledger, &ledger)?;
        let _ = std::fs::remove_file(&path);
        resumed += 1;
    }
    Ok(resumed)
}

fn ensure_ours(link: &Path, expected: &str) -> DynResult<()> {
    match std::fs::read_link(link) {
        Ok(actual) if actual.to_string_lossy() == expected => Ok(()),
        Ok(actual) => Err(format!(
            "refusing to touch {}: it points at {}, not {expected}",
            link.display(),
            actual.display()
        )
        .into()),
        Err(err) => Err(format!("refusing to touch {}: {err}", link.display()).into()),
    }
}

/// Create a symlink atomically: write a temporary name, then rename it into place.
pub fn atomic_symlink(link: &Path, target: &str) -> DynResult<()> {
    if let Some(parent) = link.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let file_name = link
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "link".to_string());
    let temporary = link.with_file_name(format!(".astral-{file_name}-{}", std::process::id()));
    let _ = std::fs::remove_file(&temporary);
    std::os::unix::fs::symlink(target, &temporary)?;
    match std::fs::rename(&temporary, link) {
        Ok(()) => Ok(()),
        Err(err) => {
            let _ = std::fs::remove_file(&temporary);
            Err(format!("cannot place {}: {err}", link.display()).into())
        }
    }
}

/// Move an existing copy aside (or unlink a symlink) before replacing it.
fn move_to_trash(paths: &SkillPaths, transaction: &str, link: &Path) -> DynResult<()> {
    match std::fs::symlink_metadata(link) {
        Err(_) => Ok(()),
        Ok(meta) if meta.file_type().is_symlink() => {
            std::fs::remove_file(link)?;
            Ok(())
        }
        Ok(_) => {
            let name = link
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_else(|| "item".to_string());
            let destination = paths.trash.join(transaction).join(name);
            if let Some(parent) = destination.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::rename(link, &destination)?;
            Ok(())
        }
    }
}

/// Copy a directory tree, preserving the executable bit (skills ship scripts).
pub fn copy_tree(from: &Path, to: &Path) -> DynResult<()> {
    std::fs::create_dir_all(to)?;
    let mut stack = vec![(from.to_path_buf(), to.to_path_buf())];
    while let Some((source, target)) = stack.pop() {
        for entry in std::fs::read_dir(&source)? {
            let entry = entry?;
            let source_path = entry.path();
            let target_path = target.join(entry.file_name());
            let metadata = entry.metadata()?;
            if metadata.is_dir() {
                std::fs::create_dir_all(&target_path)?;
                stack.push((source_path, target_path));
            } else if metadata.file_type().is_symlink() {
                // A skill may ship its own symlink; recreate it verbatim.
                if let Ok(link) = std::fs::read_link(&source_path) {
                    let _ = std::fs::remove_file(&target_path);
                    std::os::unix::fs::symlink(link, &target_path)?;
                }
            } else {
                std::fs::copy(&source_path, &target_path)?;
            }
        }
    }
    Ok(())
}

/// Remove store directories no ledger row references (spec §4).
///
/// The store is laid out `<host>/<owner>/<repo>@<ref>/<skill>`; collection walks it and removes a
/// directory only when no referenced path is inside it and it is not inside one. So `gh` survives
/// because referenced content lives under it, while `gh/owner/repo@old/beta` goes when the last
/// row pointing at it is dropped.
pub fn gc_store(paths: &SkillPaths, ledger: &Ledger) -> DynResult<Vec<PathBuf>> {
    let referenced: Vec<PathBuf> = ledger
        .links
        .iter()
        .filter_map(|row| row.origin.content_path().map(Path::to_path_buf))
        .collect();
    let mut removed = Vec::new();
    let mut stack = vec![paths.store.clone()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let touches_referenced = referenced
                .iter()
                .any(|candidate| candidate.starts_with(&path) || path.starts_with(candidate));
            if touches_referenced {
                stack.push(path);
            } else {
                std::fs::remove_dir_all(&path)?;
                removed.push(path);
            }
        }
    }
    removed.sort();
    Ok(removed)
}

/// Write the journal file for a plan without applying it (used by `--dry-run` tests).
pub fn describe_plan(plan: &Plan) -> String {
    let mut text = String::new();
    for line in plan.describe() {
        let _ = writeln!(text, "{line}");
    }
    if plan.conflicts.iter().any(|c| c.kind == ConflictKind::MissingContent) {
        let _ = writeln!(text, "note: missing content is never repaired automatically");
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::skill_install::{DesiredSkill, plan_install};
    use crate::domain::skill::SkillMeta;
    use crate::domain::skill_ledger::{LinkRecord, LinkState, Origin};
    use crate::domain::skill_targets::{Scope, target_by_id};

    struct Fixture {
        dir: tempfile::TempDir,
        paths: SkillPaths,
    }

    impl Fixture {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let paths = SkillPaths::new(
                dir.path().join("data"),
                dir.path().join("state"),
                dir.path().join("cache"),
            );
            paths.ensure().unwrap();
            Self { dir, paths }
        }
        fn content(&self, id: &str) -> PathBuf {
            let path = self.paths.store.join(format!("gh/owner/repo@main/{id}"));
            std::fs::create_dir_all(&path).unwrap();
            std::fs::write(path.join("SKILL.md"), format!("---\nname: {id}\n---\n")).unwrap();
            path
        }
        fn project(&self) -> PathBuf {
            let root = self.dir.path().join("repo");
            std::fs::create_dir_all(&root).unwrap();
            root
        }
        fn plan_for(&self, id: &str, root: &Path) -> Plan {
            let content = self.content(id);
            let desired = DesiredSkill {
                source_id: "owner-repo".to_string(),
                skill: SkillMeta {
                    id: crate::domain::skill::SkillId::parse(id).unwrap(),
                    description: String::new(),
                    subpath: id.to_string(),
                    hash: "hash".to_string(),
                    files: 1,
                    bytes: 1,
                    version: None,
                },
                origin: Origin::Store {
                    ref_name: "main".to_string(),
                    sha: "a".repeat(40),
                    path: content,
                },
                scope: Scope::Project { root: root.to_path_buf() },
            };
            let targets = vec![
                target_by_id("codex").unwrap(),
                target_by_id("claude-code").unwrap(),
            ];
            let ledger = read_ledger(&self.paths.ledger).unwrap();
            plan_install(&[desired], &targets, &ledger, &RealFs, 1)
        }
    }

    #[test]
    fn applying_a_plan_creates_links_the_filesystem_agrees_with() {
        let fixture = Fixture::new();
        let root = fixture.project();
        let plan = fixture.plan_for("alpha", &root);
        let report = apply(&fixture.paths, &plan, 42).unwrap();
        assert_eq!(report.created, 2, "{:?}", report);

        let canonical = root.join(".agents/skills/alpha");
        let claude = root.join(".claude/skills/alpha");
        assert!(canonical.is_symlink());
        assert!(claude.is_symlink());
        assert_eq!(std::fs::read_to_string(canonical.join("SKILL.md")).unwrap().contains("alpha"), true);
        assert_eq!(
            std::fs::read_link(&claude).unwrap().to_string_lossy(),
            "../../.agents/skills/alpha",
            "the second target hops through the canonical farm"
        );
        let ledger = read_ledger(&fixture.paths.ledger).unwrap();
        assert_eq!(ledger.links.len(), 2);
        assert_eq!(ledger.state_of("owner-repo", &crate::domain::skill::SkillId::parse("alpha").unwrap()),
            Some(LinkState::Linked));
        // The journal is gone once the transaction completed.
        assert_eq!(std::fs::read_dir(&fixture.paths.journal).unwrap().count(), 0);
    }

    #[test]
    fn applying_twice_is_a_no_op_and_leaves_no_journal() {
        let fixture = Fixture::new();
        let root = fixture.project();
        apply(&fixture.paths, &fixture.plan_for("alpha", &root), 1).unwrap();
        let second = fixture.plan_for("alpha", &root);
        assert!(second.is_empty(), "{:?}", second.describe());
        let report = apply(&fixture.paths, &second, 2).unwrap();
        assert!(report.is_empty());
    }

    #[test]
    fn removal_refuses_a_link_that_no_longer_matches_the_ledger() {
        let fixture = Fixture::new();
        let root = fixture.project();
        apply(&fixture.paths, &fixture.plan_for("alpha", &root), 1).unwrap();
        let claude = root.join(".claude/skills/alpha");
        std::fs::remove_file(&claude).unwrap();
        std::os::unix::fs::symlink("/tmp/elsewhere", &claude).unwrap();

        let error = ensure_ours(&claude, "../../.agents/skills/alpha").unwrap_err();
        assert!(error.to_string().contains("refusing to touch"), "got: {error}");
        assert!(claude.is_symlink(), "and the link is still there");
    }

    #[test]
    fn an_interrupted_transaction_is_resumed_rather_than_left_half_applied() {
        let fixture = Fixture::new();
        let root = fixture.project();
        let plan = fixture.plan_for("alpha", &root);
        // Simulate a crash after writing the journal but before applying anything.
        let journal = Journal {
            transaction: "t1".to_string(),
            ops: plan.ops.clone(),
            ledger_ops: plan.ledger.clone(),
        };
        std::fs::write(
            fixture.paths.journal.join("t1.json"),
            serde_json::to_vec(&journal).unwrap(),
        )
        .unwrap();

        let resumed = recover(&fixture.paths).unwrap();
        assert_eq!(resumed, 1);
        assert!(root.join(".agents/skills/alpha").is_symlink());
        assert!(root.join(".claude/skills/alpha").is_symlink());
        let ledger = read_ledger(&fixture.paths.ledger).unwrap();
        assert_eq!(ledger.links.len(), 2);
        assert_eq!(std::fs::read_dir(&fixture.paths.journal).unwrap().count(), 0);
    }

    #[test]
    fn the_ledger_write_is_atomic() {
        let fixture = Fixture::new();
        let mut ledger = Ledger::default();
        ledger.upsert(LinkRecord {
            link: PathBuf::from("/x"),
            target: "y".to_string(),
            target_id: "codex".to_string(),
            source_id: "s".to_string(),
            skill: crate::domain::skill::SkillId::parse("a").unwrap(),
            origin: Origin::Local { path: PathBuf::from("/p") },
            scope: Scope::Global,
            state: LinkState::Linked,
            hash: "h".to_string(),
            created_at: 0,
        });
        write_ledger(&fixture.paths.ledger, &ledger).unwrap();
        assert_eq!(read_ledger(&fixture.paths.ledger).unwrap(), ledger);
        assert!(!fixture.paths.ledger.with_extension("json.tmp").exists());
        // A missing ledger reads as empty rather than failing.
        assert_eq!(read_ledger(&fixture.paths.ledger.with_file_name("nope.json")).unwrap(), Ledger::default());
    }

    #[test]
    fn garbage_collection_keeps_referenced_content_only() {
        let fixture = Fixture::new();
        let root = fixture.project();
        apply(&fixture.paths, &fixture.plan_for("alpha", &root), 1).unwrap();
        let orphan = fixture.paths.store.join("gh/owner/repo@old/beta");
        std::fs::create_dir_all(&orphan).unwrap();

        let ledger = read_ledger(&fixture.paths.ledger).unwrap();
        let removed = gc_store(&fixture.paths, &ledger).unwrap();
        assert_eq!(removed.len(), 1, "one subtree goes: {removed:?}");
        assert!(!orphan.exists(), "the orphan content is gone");
        assert!(fixture.paths.store.join("gh/owner/repo@main/alpha").exists(),
            "referenced content survives");
        assert!(fixture.paths.store.join("gh/owner").is_dir(),
            "and so does the shared parent of referenced content");
    }

    #[test]
    fn a_copy_target_is_moved_to_trash_rather_than_deleted() {
        let fixture = Fixture::new();
        let target = fixture.project().join(".legacy/skills/alpha");
        std::fs::create_dir_all(&target).unwrap();
        std::fs::write(target.join("SKILL.md"), "old").unwrap();
        move_to_trash(&fixture.paths, "tx", &target).unwrap();
        assert!(!target.exists());
        let trashed = fixture.paths.trash.join("tx/alpha/SKILL.md");
        assert!(trashed.is_file(), "the old copy is recoverable at {}", trashed.display());
    }

    #[test]
    fn copying_a_tree_preserves_nested_files_and_scripts() {
        let fixture = Fixture::new();
        let source = fixture.dir.path().join("source");
        std::fs::create_dir_all(source.join("scripts")).unwrap();
        std::fs::write(source.join("SKILL.md"), "x").unwrap();
        std::fs::write(source.join("scripts/run.sh"), "echo hi").unwrap();
        let destination = fixture.dir.path().join("destination");
        copy_tree(&source, &destination).unwrap();
        assert_eq!(std::fs::read_to_string(destination.join("scripts/run.sh")).unwrap(), "echo hi");
    }

    #[test]
    fn the_probe_sees_a_dangling_link_as_a_link_not_as_absent() {
        let fixture = Fixture::new();
        let link = fixture.dir.path().join("dangling");
        std::os::unix::fs::symlink("/nonexistent/target", &link).unwrap();
        match RealFs.probe(&link) {
            Probe::Symlink { dangling, .. } => assert!(dangling),
            other => panic!("expected a dangling symlink, got {other:?}"),
        }
        assert_eq!(RealFs.probe(&fixture.dir.path().join("missing")), Probe::Missing);
    }
}
