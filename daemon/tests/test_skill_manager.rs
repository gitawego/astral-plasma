//! End-to-end use cases over real filesystems and real (local) git repositories.
//!
//! These are the acceptance tests for P2 of `docs/SKILLS-MANAGER-SPEC.md`: a source is added, its
//! skills are installed as links, a whole repository can be disabled and removed, an update
//! relinks only what changed, and the doctor sees drift. No network: a `file://` repository and a
//! temp home stand in for GitHub.

use std::path::{Path, PathBuf};
use std::process::Command;

use astral_plasma::application::skill_manager as manager;
use astral_plasma::domain::skill_ledger::{LinkState, Origin};
use astral_plasma::domain::skill_source::LocalSource;
use astral_plasma::domain::skill_targets::Scope;
use astral_plasma::infrastructure::skill_fs::{read_ledger, SkillPaths};

struct Fixture {
    dir: tempfile::TempDir,
    ctx: manager::SkillContext,
    project: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let paths = SkillPaths::new(
            dir.path().join("data"),
            dir.path().join("state"),
            dir.path().join("cache"),
        );
        paths.ensure().unwrap();
        let project = dir.path().join("repo");
        std::fs::create_dir_all(&project).unwrap();
        let mut ctx = manager::SkillContext::new(paths, 1_000)
            .with_targets(Some("codex,claude-code".to_string()));
        // Detection and the import scan must look at the fixture's home, not the real one.
        ctx.home = home;
        Self { dir, ctx, project }
    }

    fn scope(&self) -> Scope {
        Scope::Project { root: self.project.clone() }
    }

    fn link(&self, dir: &str, skill: &str) -> PathBuf {
        self.project.join(dir).join(skill)
    }

    fn local_source(&self, name: &str, skills: &[(&str, &str)]) -> PathBuf {
        let root = self.dir.path().join(name);
        for (id, description) in skills {
            let dir = root.join(id);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(
                dir.join("SKILL.md"),
                format!("---\nname: {id}\ndescription: {description}\n---\n# {id}\n"),
            )
            .unwrap();
            std::fs::write(dir.join("notes.md"), format!("notes for {id}")).unwrap();
        }
        root
    }
}

/// A real git repository served over `file://`.
struct GitRepo {
    dir: tempfile::TempDir,
}

impl GitRepo {
    fn new(skills: &[(&str, &str)]) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let repo = Self { dir };
        repo.write(skills);
        repo.commit("first");
        repo
    }

    fn url(&self) -> String {
        format!("file://{}", self.dir.path().display())
    }

    fn write(&self, skills: &[(&str, &str)]) {
        for (id, description) in skills {
            let dir = self.dir.path().join(id);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(
                dir.join("SKILL.md"),
                format!("---\nname: {id}\ndescription: {description}\n---\n# {id}\n"),
            )
            .unwrap();
        }
    }

    fn git(&self, args: &[&str]) -> String {
        let output = Command::new("git")
            .current_dir(self.dir.path())
            .args([
                "-c",
                "user.email=t@example.com",
                "-c",
                "user.name=Test",
                "-c",
                "init.defaultBranch=main",
                "-c",
                "commit.gpgsign=false",
            ])
            .args(args)
            .output()
            .unwrap();
        assert!(output.status.success(), "git {args:?}: {}", String::from_utf8_lossy(&output.stderr));
        String::from_utf8_lossy(&output.stdout).into_owned()
    }

    fn commit(&self, message: &str) {
        if !self.dir.path().join(".git").is_dir() {
            self.git(&["init", "-q"]);
        }
        self.git(&["add", "-A"]);
        self.git(&["commit", "-qm", message]);
    }
}

#[test]
fn a_local_folder_is_added_linked_in_place_and_listed() {
    let fixture = Fixture::new();
    let source = fixture.local_source("my-skills", &[("alpha", "first"), ("beta", "second")]);
    let added = manager::add_source(&fixture.ctx, source.to_str().unwrap(), None, None, true, false).unwrap();
    assert_eq!(added.id, "local-my-skills");

    let report = manager::install(&fixture.ctx, source.to_str().unwrap(), None, &fixture.scope(), true).unwrap();
    assert!(report.conflicts.is_empty(), "{:?}", report.conflicts);
    assert_eq!(report.installed.len(), 2);
    assert_eq!(report.created, 4, "two skills, two targets");

    // Linked in place: the canonical link resolves into the user's own folder (D8).
    let canonical = fixture.link(".agents/skills", "alpha");
    assert!(canonical.is_symlink());
    assert_eq!(
        std::fs::canonicalize(&canonical).unwrap(),
        std::fs::canonicalize(source.join("alpha")).unwrap()
    );
    assert!(fixture.link(".claude/skills", "alpha").is_symlink());

    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    let row = ledger.row_for(&canonical).expect("the canonical link is recorded");
    assert!(matches!(row.origin, Origin::Local { .. }));
    assert_eq!(row.state, LinkState::Linked);

    let list = manager::list(&fixture.ctx).unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].skills.len(), 2);
    assert_eq!(list[0].enabled_count, 2);
}

#[test]
fn a_git_repository_is_copied_into_the_store_and_linked() {
    let fixture = Fixture::new();
    let repo = GitRepo::new(&[("web-design", "UI review"), ("secure-llm", "audit")]);
    let report = manager::install(&fixture.ctx, &repo.url(), None, &fixture.scope(), true).unwrap();
    assert!(report.conflicts.is_empty(), "{:?}", report.conflicts);
    assert_eq!(report.installed.len(), 2);

    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    let canonical = fixture.link(".agents/skills", "web-design");
    let row = ledger.row_for(&canonical).unwrap();
    match &row.origin {
        Origin::Store { path, sha, ref_name } => {
            assert!(path.join("SKILL.md").is_file(), "content is copied into the store");
            assert_eq!(sha.len(), 40, "the resolved commit is recorded");
            assert!(!ref_name.is_empty());
        }
        other => panic!("expected a store origin, got {other:?}"),
    }
    // The link points into the store, so editing the source repo cannot change what an agent reads.
    let resolved = std::fs::canonicalize(&canonical).unwrap();
    assert!(resolved.starts_with(&fixture.ctx.paths.store));
}

#[test]
fn installing_needs_consent_for_a_new_source() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "a")]);
    let error = manager::install(&fixture.ctx, source.to_str().unwrap(), None, &fixture.scope(), false).unwrap_err();
    let text = error.to_string();
    assert!(text.contains("--accept"), "the refusal names the flag: {text}");
    assert!(text.contains("inspect"), "and how to review it first: {text}");
    assert!(!fixture.link(".agents/skills", "alpha").exists(), "nothing was installed");
}

#[test]
fn one_skill_of_a_source_can_be_installed_alone() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "a"), ("beta", "b")]);
    let report = manager::install(
        &fixture.ctx,
        source.to_str().unwrap(),
        Some(vec!["beta".to_string()]),
        &fixture.scope(),
        true,
    )
    .unwrap();
    assert_eq!(report.installed, vec!["beta"]);
    assert!(!fixture.link(".agents/skills", "alpha").exists());
    assert!(fixture.link(".agents/skills", "beta").is_symlink());

    let error = manager::install(
        &fixture.ctx,
        source.to_str().unwrap(),
        Some(vec!["nope".to_string()]),
        &fixture.scope(),
        true,
    )
    .unwrap_err();
    assert!(error.to_string().contains("alpha"), "the error lists what exists: {error}");
}

#[test]
fn disable_and_enable_work_per_skill_and_per_repository() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "a"), ("beta", "b")]);
    manager::install(&fixture.ctx, source.to_str().unwrap(), None, &fixture.scope(), true).unwrap();
    let source_id = "local-mine";

    // Per skill.
    let selector = astral_plasma::domain::skill_install::Selector::Skill {
        source_id: source_id.to_string(),
        skill: "alpha".to_string(),
    };
    manager::set_enabled(&fixture.ctx, &selector, false).unwrap();
    assert!(!fixture.link(".agents/skills", "alpha").exists(), "the link is gone");
    assert!(fixture.link(".agents/skills", "beta").is_symlink(), "the other skill is untouched");
    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    assert_eq!(
        ledger.state_of(source_id, &astral_plasma::domain::skill::SkillId::parse("alpha").unwrap()),
        Some(LinkState::Disabled)
    );

    manager::set_enabled(&fixture.ctx, &selector, true).unwrap();
    assert!(fixture.link(".agents/skills", "alpha").is_symlink(), "enabling relinks without a fetch");

    // Whole repository: the operation the ecosystem lacks.
    let all = astral_plasma::domain::skill_install::Selector::Source { source_id: source_id.to_string() };
    manager::set_enabled(&fixture.ctx, &all, false).unwrap();
    assert!(!fixture.link(".agents/skills", "alpha").exists());
    assert!(!fixture.link(".agents/skills", "beta").exists());
    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    assert_eq!(ledger.source(source_id).unwrap().enabled, false, "the repo default is recorded");

    manager::set_enabled(&fixture.ctx, &all, true).unwrap();
    assert!(fixture.link(".agents/skills", "alpha").is_symlink());
    assert!(fixture.link(".agents/skills", "beta").is_symlink());
}

#[test]
fn removing_a_repository_removes_every_link_and_the_record() {
    let fixture = Fixture::new();
    let repo = GitRepo::new(&[("alpha", "a"), ("beta", "b")]);
    manager::install(&fixture.ctx, &repo.url(), None, &fixture.scope(), true).unwrap();
    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    let source_id = ledger.sources.first().unwrap().id.clone();
    let store_paths: Vec<PathBuf> = ledger
        .links
        .iter()
        .filter_map(|row| row.origin.content_path().map(Path::to_path_buf))
        .collect();
    assert!(!store_paths.is_empty());

    let selector = astral_plasma::domain::skill_install::Selector::Source { source_id: source_id.clone() };
    let report = manager::remove(&fixture.ctx, &selector, true).unwrap();
    assert_eq!(report.removed, 4);
    assert!(!fixture.link(".agents/skills", "alpha").exists());
    assert!(!fixture.link(".claude/skills", "beta").exists());
    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    assert!(ledger.for_source(&source_id).is_empty());
    assert!(ledger.source(&source_id).is_none(), "the source is forgotten");
    for path in store_paths {
        assert!(!path.exists(), "content is collected: {}", path.display());
    }
}

#[test]
fn an_update_relinks_only_what_changed() {
    let fixture = Fixture::new();
    let repo = GitRepo::new(&[("alpha", "a"), ("beta", "b")]);
    manager::install(&fixture.ctx, &repo.url(), None, &fixture.scope(), true).unwrap();
    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    let source_id = ledger.sources.first().unwrap().id.clone();
    let alpha_before = ledger
        .for_skill(&astral_plasma::domain::skill::SkillId::parse("alpha").unwrap(), Some(&source_id))
        .first()
        .unwrap()
        .hash
        .clone();

    // Change one skill, commit, update.
    std::fs::write(repo.dir.path().join("alpha/SKILL.md"), "---\nname: alpha\ndescription: changed\n---\n").unwrap();
    repo.commit("update alpha");
    let report = manager::update(&fixture.ctx, &source_id).unwrap();
    assert_eq!(report.changed, vec!["alpha"], "{:?}", report);
    assert_eq!(report.unchanged, vec!["beta"]);
    assert!(report.conflicts.is_empty());

    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    let alpha_after = ledger
        .for_skill(&astral_plasma::domain::skill::SkillId::parse("alpha").unwrap(), Some(&source_id))
        .first()
        .unwrap()
        .hash
        .clone();
    assert_ne!(alpha_before, alpha_after, "the new hash is recorded");
    // The link still resolves to content that contains the change.
    let content = std::fs::read_to_string(fixture.link(".agents/skills", "alpha").join("SKILL.md")).unwrap();
    assert!(content.contains("changed"));
}

#[test]
fn the_doctor_reports_dangling_links_and_unmanaged_skills() {
    let fixture = Fixture::new();
    let repo = GitRepo::new(&[("alpha", "a")]);
    manager::install(&fixture.ctx, &repo.url(), None, &fixture.scope(), true).unwrap();
    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    let source_id = ledger.sources.first().unwrap().id.clone();

    // A manual install nobody recorded, and content we delete behind the manager's back.
    let stray = fixture.link(".agents/skills", "stray");
    std::fs::create_dir_all(&stray).unwrap();
    std::fs::write(stray.join("SKILL.md"), "---\nname: stray\n---\n").unwrap();
    let store_path = ledger
        .for_skill(&astral_plasma::domain::skill::SkillId::parse("alpha").unwrap(), Some(&source_id))
        .first()
        .unwrap()
        .origin
        .content_path()
        .unwrap()
        .to_path_buf();
    std::fs::remove_dir_all(&store_path).unwrap();

    let findings = manager::doctor(&fixture.ctx).unwrap();
    let kinds: Vec<&str> = findings.iter().map(|finding| finding.kind.as_str()).collect();
    assert!(kinds.contains(&"dangling"), "findings: {findings:?}");
    assert!(kinds.contains(&"unmanaged"), "findings: {findings:?}");
}

#[test]
fn an_existing_npx_farm_is_adopted_without_being_rewritten() {
    let fixture = Fixture::new();
    // What `npx skills` leaves behind: a real directory in the canonical farm.
    let farm = fixture.dir.path().join("home/.agents/skills/legacy");
    std::fs::create_dir_all(&farm).unwrap();
    std::fs::write(farm.join("SKILL.md"), "---\nname: legacy\ndescription: from npx\n---\n").unwrap();

    let dry = manager::import_npx(&fixture.ctx, false).unwrap();
    assert!(!dry.applied);
    assert!(dry.adopted.iter().any(|entry| entry.skill == "legacy"));
    assert!(read_ledger(&fixture.ctx.paths.ledger).unwrap().links.is_empty(), "dry run writes nothing");

    let report = manager::import_npx(&fixture.ctx, true).unwrap();
    assert!(report.applied);
    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    let row = ledger.links.iter().find(|row| row.skill.as_str() == "legacy").expect("adopted row");
    assert!(matches!(row.origin, Origin::Adopted { .. }));
    assert!(farm.join("SKILL.md").is_file(), "adoption never rewrites what it found");

    // Doctor no longer calls it unmanaged, and it can be removed like anything else.
    let findings = manager::doctor(&fixture.ctx).unwrap();
    assert!(
        !findings.iter().any(|finding| finding.skill == "legacy" && finding.kind == "unmanaged"),
        "{findings:?}"
    );
}

#[test]
fn an_inspection_describes_a_source_without_changing_anything() {
    let fixture = Fixture::new();
    let repo = GitRepo::new(&[("alpha", "a")]);
    let inspection = manager::inspect(&fixture.ctx, &repo.url()).unwrap();
    assert_eq!(inspection.skills.len(), 1);
    assert_eq!(inspection.skills[0].id, "alpha");
    assert!(!inspection.skills[0].installed);
    assert!(inspection.sha.is_some());
    assert!(read_ledger(&fixture.ctx.paths.ledger).unwrap().links.is_empty());
}

#[test]
fn preview_lists_the_operations_without_touching_the_tree() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "a")]);
    let plan = manager::preview(&fixture.ctx, source.to_str().unwrap(), &fixture.scope()).unwrap();
    assert!(plan.iter().any(|line| line.starts_with("link")), "{plan:?}");
    assert!(!fixture.link(".agents/skills", "alpha").exists());
}

#[test]
fn a_local_source_can_be_snapshotted_instead_of_linked() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "a")]);
    let mut spec = SourceSpecHelper::local(&source);
    spec.copy = true;
    manager::add_source(&fixture.ctx, source.to_str().unwrap(), None, None, true, true).unwrap();
    manager::install(&fixture.ctx, source.to_str().unwrap(), None, &fixture.scope(), true).unwrap();
    let canonical = fixture.link(".agents/skills", "alpha");
    let ledger = read_ledger(&fixture.ctx.paths.ledger).unwrap();
    let row = ledger.row_for(&canonical).unwrap();
    assert!(matches!(row.origin, Origin::Local { .. }), "a snapshot is still a local origin");
    // Editing the folder does not change what the agent reads.
    std::fs::write(source.join("alpha/SKILL.md"), "---\nname: alpha\ndescription: edited\n---\n").unwrap();
    let content = std::fs::read_to_string(canonical.join("SKILL.md")).unwrap();
    assert!(!content.contains("edited"), "the snapshot is independent");
}

struct SourceSpecHelper;

impl SourceSpecHelper {
    fn local(path: &Path) -> LocalSource {
        LocalSource {
            path: path.to_path_buf(),
            watch: true,
            copy: false,
            subpath: None,
        }
    }
}

#[test]
fn an_adopted_skill_can_be_disabled_and_removed_without_deleting_it_in_place() {
    let fixture = Fixture::new();
    let farm = fixture.dir.path().join("home/.agents/skills/legacy");
    std::fs::create_dir_all(&farm).unwrap();
    std::fs::write(farm.join("SKILL.md"), "---\nname: legacy\n---\n").unwrap();
    manager::import_npx(&fixture.ctx, true).unwrap();

    // A real directory that we adopted is not "replaced": the doctor stays quiet.
    assert!(manager::doctor(&fixture.ctx).unwrap().is_empty(), "{:?}", manager::doctor(&fixture.ctx));

    let selector = astral_plasma::domain::skill_install::Selector::Skill {
        source_id: "adopted-".to_string() + &astral_plasma::domain::skill_source::slug(&farm.display().to_string()),
        skill: "legacy".to_string(),
    };
    manager::set_enabled(&fixture.ctx, &selector, false).unwrap();
    assert!(!farm.exists(), "disabling an adopted farm moves it aside");
    let trashed = fixture
        .ctx
        .paths
        .trash
        .read_dir()
        .unwrap()
        .flatten()
        .map(|entry| entry.path().join("legacy"))
        .find(|path| path.is_dir())
        .expect("the adopted skill is recoverable from the trash");
    assert!(trashed.join("SKILL.md").is_file(), "and its content survived: {}", trashed.display());

    // Modifying adopted content is reported rather than silently accepted.
    let other = fixture.dir.path().join("home/.agents/skills/other");
    std::fs::create_dir_all(&other).unwrap();
    std::fs::write(other.join("SKILL.md"), "---\nname: other\n---\n").unwrap();
    manager::import_npx(&fixture.ctx, true).unwrap();
    std::fs::write(other.join("SKILL.md"), "---\nname: other\n# changed\n---\n").unwrap();
    let findings = manager::doctor(&fixture.ctx).unwrap();
    assert!(findings.iter().any(|finding| finding.kind == "modified"), "{findings:?}");
}

#[test]
fn a_disabled_skill_is_not_a_doctor_finding() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "a")]);
    manager::install(&fixture.ctx, source.to_str().unwrap(), None, &fixture.scope(), true).unwrap();
    let selector = astral_plasma::domain::skill_install::Selector::Skill {
        source_id: "local-mine".to_string(),
        skill: "alpha".to_string(),
    };
    manager::set_enabled(&fixture.ctx, &selector, false).unwrap();
    // Disabled on purpose: no link, no complaint. Only the unmanaged farm is reported, if any.
    let findings = manager::doctor(&fixture.ctx).unwrap();
    assert!(
        !findings.iter().any(|finding| finding.kind == "missing" || finding.kind == "dangling"),
        "{findings:?}"
    );
}

#[test]
fn an_update_can_be_rolled_back_one_commit() {
    let fixture = Fixture::new();
    let repo = GitRepo::new(&[("alpha", "first version")]);
    manager::install(&fixture.ctx, &repo.url(), None, &fixture.scope(), true).unwrap();
    let source_id = read_ledger(&fixture.ctx.paths.ledger).unwrap().sources[0].id.clone();
    let before = std::fs::read_to_string(fixture.link(".agents/skills", "alpha").join("SKILL.md")).unwrap();
    assert!(before.contains("first version"));

    std::fs::write(repo.dir.path().join("alpha/SKILL.md"), "---\nname: alpha\ndescription: second version\n---\n").unwrap();
    repo.commit("second");
    let update = manager::update(&fixture.ctx, &source_id).unwrap();
    assert_eq!(update.changed, vec!["alpha"]);
    let after = std::fs::read_to_string(fixture.link(".agents/skills", "alpha").join("SKILL.md")).unwrap();
    assert!(after.contains("second version"));

    let rollback = manager::rollback(&fixture.ctx, &source_id).unwrap();
    assert_eq!(rollback.changed, vec!["alpha"], "{:?}", rollback);
    assert!(rollback.conflicts.is_empty(), "{:?}", rollback.conflicts);
    let reverted = std::fs::read_to_string(fixture.link(".agents/skills", "alpha").join("SKILL.md")).unwrap();
    assert!(reverted.contains("first version"), "the previous content is back: {reverted}");

    // A second rollback swaps back, so the operation is not a trap.
    let again = manager::rollback(&fixture.ctx, &source_id).unwrap();
    assert_eq!(again.changed, vec!["alpha"]);
    let forward = std::fs::read_to_string(fixture.link(".agents/skills", "alpha").join("SKILL.md")).unwrap();
    assert!(forward.contains("second version"), "and rolling back twice returns: {forward}");
}

#[test]
fn a_rollback_without_a_previous_version_says_so() {
    let fixture = Fixture::new();
    let repo = GitRepo::new(&[("alpha", "a")]);
    manager::install(&fixture.ctx, &repo.url(), None, &fixture.scope(), true).unwrap();
    let source_id = read_ledger(&fixture.ctx.paths.ledger).unwrap().sources[0].id.clone();
    let error = manager::rollback(&fixture.ctx, &source_id).unwrap_err();
    assert!(error.to_string().contains("no previous version"), "got: {error}");
}

#[test]
fn a_copy_target_receives_files_where_the_others_receive_links() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "a")]);
    // D5: copying is the per-target exception, chosen by the user.
    let ctx = fixture
        .ctx
        .clone()
        .with_copy_targets(vec!["claude-code".to_string()]);
    manager::install(&ctx, source.to_str().unwrap(), None, &fixture.scope(), true).unwrap();

    let canonical = fixture.link(".agents/skills", "alpha");
    let copied = fixture.link(".claude/skills", "alpha");
    assert!(canonical.is_symlink(), "the canonical target still links");
    assert!(!copied.is_symlink() && copied.is_dir(), "the copy target holds real files");
    assert!(copied.join("SKILL.md").is_file());

    let ledger = read_ledger(&ctx.paths.ledger).unwrap();
    let row = ledger.row_for(&copied).expect("the copy is recorded too");
    assert!(row.target.starts_with("copy:"), "the record says it is a copy: {}", row.target);

    // Disabling a copy moves it to the trash rather than deleting it in place.
    let selector = astral_plasma::domain::skill_install::Selector::Skill {
        source_id: "local-mine".to_string(),
        skill: "alpha".to_string(),
    };
    manager::set_enabled(&ctx, &selector, false).unwrap();
    assert!(!copied.exists(), "the copy is gone from the farm");
    let items = astral_plasma::infrastructure::skill_fs::trash_list(&ctx.paths).unwrap();
    assert!(items.iter().any(|item| item.name == "alpha"), "and recoverable: {items:?}");
}

#[test]
fn a_skill_can_be_read_without_being_installed() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "first"), ("beta", "second")]);
    let content = manager::read_skill(&fixture.ctx, source.to_str().unwrap(), "alpha").unwrap();

    assert_eq!(content.source_id, "local-mine");
    assert_eq!(content.skill.id.as_str(), "alpha");
    assert!(content.manifest.contains("# alpha"), "the manifest is returned verbatim: {}", content.manifest);
    assert!(
        content.files.iter().any(|file| file.path == "notes.md"),
        "bundled files are listed for skill_read: {:?}",
        content.files.iter().map(|file| &file.path).collect::<Vec<_>>()
    );

    // The whole point: loading is not installing.
    assert!(read_ledger(&fixture.ctx.paths.ledger).unwrap().links.is_empty());
    assert!(!fixture.link(".agents/skills", "alpha").exists());
    assert!(!fixture.link(".claude/skills", "alpha").exists());

    let error = manager::read_skill(&fixture.ctx, source.to_str().unwrap(), "nope").unwrap_err();
    assert!(error.to_string().contains("available: alpha, beta"), "got: {error}");
}

#[test]
fn a_git_skill_can_be_read_without_being_copied_into_the_store_or_installed() {
    let fixture = Fixture::new();
    let repo = GitRepo::new(&[("alpha", "first")]);
    let content = manager::read_skill(&fixture.ctx, &repo.url(), "alpha").unwrap();

    assert_eq!(content.skill.id.as_str(), "alpha");
    assert!(content.manifest.contains("# alpha"));
    assert!(content.sha.is_some(), "a git read is pinned to the commit it read");
    assert!(read_ledger(&fixture.ctx.paths.ledger).unwrap().links.is_empty());
    assert!(!fixture.link(".agents/skills", "alpha").exists());
    assert!(
        !fixture.ctx.paths.store.exists() || fixture.ctx.paths.store.read_dir().unwrap().next().is_none(),
        "a read must not write the immutable install store"
    );
}

#[test]
fn an_added_source_is_searchable_by_id_and_across_all_added_sources() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "first"), ("beta", "second")]);
    manager::add_source(&fixture.ctx, source.to_str().unwrap(), None, None, true, false).unwrap();

    let hits = manager::search(&fixture.ctx, "alph", "local-mine", 10, None).unwrap();
    assert_eq!(hits.len(), 1, "{hits:?}");
    assert_eq!(hits[0].name, "alpha");
    assert_eq!(hits[0].source, "local-mine");

    let all = manager::search(&fixture.ctx, "", "added", 10, None).unwrap();
    let names: Vec<&str> = all.iter().map(|hit| hit.name.as_str()).collect();
    assert_eq!(names, vec!["alpha", "beta"]);

    let error = manager::search(&fixture.ctx, "", "github", 10, None).unwrap_err();
    assert!(error.to_string().contains("query is required"), "got: {error}");
}

#[test]
fn reading_a_skill_does_not_include_a_nested_skill_s_or_its_files() {
    let fixture = Fixture::new();
    let root = fixture.dir.path().join("nested");
    std::fs::create_dir_all(root.join("parent/examples/child")).unwrap();
    std::fs::write(root.join("parent/SKILL.md"), "---\nname: parent\ndescription: parent\n---\n").unwrap();
    std::fs::write(root.join("parent/notes.md"), "parent notes").unwrap();
    std::fs::write(
        root.join("parent/examples/child/SKILL.md"),
        "---\nname: child\ndescription: child\n---\n",
    )
    .unwrap();

    let content = manager::read_skill(&fixture.ctx, root.to_str().unwrap(), "parent").unwrap();
    let paths: Vec<&str> = content.files.iter().map(|file| file.path.as_str()).collect();
    assert!(paths.contains(&"notes.md"), "{paths:?}");
    assert!(
        !paths.iter().any(|path| path.contains("examples/child")),
        "the nested skill's files are its own: {paths:?}"
    );
    assert!(!content.manifest.contains("child"), "and its manifest is not loaded: {}", content.manifest);
}

#[test]
fn a_root_skill_does_not_swallow_a_nested_example_s_files() {
    let fixture = Fixture::new();
    let root = fixture.dir.path().join("root-skill");
    std::fs::create_dir_all(root.join("examples/child")).unwrap();
    std::fs::write(root.join("SKILL.md"), "---\nname: whole-repo\ndescription: root\n---\n").unwrap();
    std::fs::write(root.join("README.md"), "root readme").unwrap();
    std::fs::write(root.join("examples/child/SKILL.md"), "---\nname: child\n---\n").unwrap();

    let content = manager::read_skill(&fixture.ctx, root.to_str().unwrap(), "whole-repo").unwrap();
    let paths: Vec<&str> = content.files.iter().map(|file| file.path.as_str()).collect();
    assert!(paths.contains(&"README.md"), "{paths:?}");
    assert!(
        !paths.iter().any(|path| path.starts_with("examples/child")),
        "the example belongs to its own skill: {paths:?}"
    );
}

#[test]
fn a_broken_ledger_does_not_block_loading_a_source() {
    let fixture = Fixture::new();
    let source = fixture.local_source("mine", &[("alpha", "first")]);
    std::fs::create_dir_all(fixture.ctx.paths.ledger.parent().unwrap()).unwrap();
    std::fs::write(&fixture.ctx.paths.ledger, "{ not a ledger").unwrap();

    let content = manager::read_skill(&fixture.ctx, source.to_str().unwrap(), "alpha").unwrap();
    assert_eq!(content.skill.id.as_str(), "alpha");
    let inspection = manager::inspect(&fixture.ctx, source.to_str().unwrap()).unwrap();
    assert_eq!(inspection.skills.len(), 1);
}
