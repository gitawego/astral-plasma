//! The `astral-plasma skills` CLI, exercised as a user exercises it.
//!
//! These run the real binary against a scratch `HOME`/`XDG_*`, because two bugs lived exactly
//! here and no unit test could see them: `skills remove --source <id>` read the flag's value as a
//! skill name and removed nothing, and the ledger was written to `~/.local/state/skills` (missing
//! the product directory) so the shell watched a path the daemon never wrote.

use std::path::{Path, PathBuf};
use std::process::Command;

struct Sandbox {
    dir: tempfile::TempDir,
}

impl Sandbox {
    fn new() -> Self {
        Self { dir: tempfile::tempdir().unwrap() }
    }

    fn home(&self) -> PathBuf {
        self.dir.path().join("home")
    }

    fn source(&self) -> PathBuf {
        let root = self.dir.path().join("my-skills");
        for (id, description) in [("alpha", "first"), ("beta", "second")] {
            let dir = root.join(id);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(
                dir.join("SKILL.md"),
                format!("---\nname: {id}\ndescription: {description}\n---\n"),
            )
            .unwrap();
        }
        root
    }

    fn ledger(&self) -> PathBuf {
        self.dir
            .path()
            .join("state/astral-plasma/skills/ledger.json")
    }

    fn run(&self, args: &[&str]) -> (bool, String, String) {
        let home = self.home();
        std::fs::create_dir_all(&home).unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_astral-plasma"))
            .args(args)
            .env("HOME", &home)
            .env("XDG_DATA_HOME", self.dir.path().join("data"))
            .env("XDG_STATE_HOME", self.dir.path().join("state"))
            .env("XDG_CACHE_HOME", self.dir.path().join("cache"))
            .output()
            .expect("the binary runs");
        (
            output.status.success(),
            String::from_utf8_lossy(&output.stdout).into_owned(),
            String::from_utf8_lossy(&output.stderr).into_owned(),
        )
    }

    fn link(&self, dir: &str, skill: &str) -> PathBuf {
        self.home().join(dir).join(skill)
    }
}

#[test]
fn install_list_disable_enable_and_remove_a_whole_source() {
    let sandbox = Sandbox::new();
    let source = sandbox.source();
    let source_str = source.to_str().unwrap();

    // Consent is required for a new source.
    let (ok, _, stderr) = sandbox.run(&["skills", "install", source_str, "--target", "codex,claude-code"]);
    assert!(!ok, "installing without --accept must fail");
    assert!(stderr.contains("--accept"), "the refusal names the flag: {stderr}");

    let (ok, stdout, stderr) = sandbox.run(&[
        "skills", "install", source_str, "--accept", "--target", "codex,claude-code",
    ]);
    assert!(ok, "install failed: {stderr}");
    assert!(stdout.contains("alpha"), "{stdout}");
    assert!(sandbox.link(".agents/skills", "alpha").is_symlink());
    assert!(sandbox.link(".claude/skills", "alpha").is_symlink());
    assert!(sandbox.ledger().is_file(), "the ledger is under the product's state dir: {}", sandbox.ledger().display());

    // The list is JSON the GUI renders verbatim.
    let (ok, stdout, _) = sandbox.run(&["skills", "list", "--json"]);
    assert!(ok);
    let parsed: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(parsed[0]["id"], "local-my-skills");
    assert_eq!(parsed[0]["enabledCount"], 2);
    assert_eq!(parsed[0]["skills"].as_array().unwrap().len(), 2);

    // Disable one skill by `<skill>@<source>`.
    let (ok, stdout, stderr) = sandbox.run(&["skills", "disable", "alpha@local-my-skills"]);
    assert!(ok, "{stderr}");
    assert!(stdout.contains("removed"), "{stdout}");
    assert!(!sandbox.link(".agents/skills", "alpha").exists(), "the link is gone");
    assert!(sandbox.link(".agents/skills", "beta").is_symlink(), "the sibling is untouched");

    let (ok, _, _) = sandbox.run(&["skills", "enable", "alpha@local-my-skills"]);
    assert!(ok);
    assert!(sandbox.link(".agents/skills", "alpha").is_symlink(), "enabling relinks");

    // The regression: `--source` must mean the whole repository, not a skill named after its id.
    let (ok, stdout, stderr) = sandbox.run(&["skills", "remove", "--source", "local-my-skills", "--purge"]);
    assert!(ok, "{stderr}");
    assert!(stdout.contains("Removed 4 link(s)"), "all four links went: {stdout}");
    assert!(!sandbox.link(".agents/skills", "alpha").exists());
    assert!(!sandbox.link(".claude/skills", "beta").exists());

    let (_, stdout, _) = sandbox.run(&["skills", "list", "--json"]);
    assert_eq!(stdout.trim(), "[]", "the source is forgotten: {stdout}");
}

#[test]
fn the_doctor_reports_an_unmanaged_farm_and_the_cli_can_adopt_it() {
    let sandbox = Sandbox::new();
    let legacy = sandbox.link(".agents/skills", "legacy");
    std::fs::create_dir_all(&legacy).unwrap();
    std::fs::write(legacy.join("SKILL.md"), "---\nname: legacy\n---\n").unwrap();

    let (ok, stdout, _) = sandbox.run(&["skills", "doctor", "--json"]);
    assert!(ok);
    let findings: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert!(
        findings.as_array().unwrap().iter().any(|finding| finding["kind"] == "unmanaged"),
        "{stdout}"
    );

    // Adoption is dry-run unless `--apply`, and never rewrites what it finds.
    let (ok, dry, _) = sandbox.run(&["skills", "import", "--json"]);
    assert!(ok);
    let dry: serde_json::Value = serde_json::from_str(&dry).unwrap();
    assert_eq!(dry["applied"], false);
    assert!(
        !sandbox.ledger().exists() || std::fs::read_to_string(sandbox.ledger()).unwrap().contains("\"links\": []"),
        "a dry run records nothing"
    );

    let (ok, _, _) = sandbox.run(&["skills", "import", "--apply"]);
    assert!(ok);
    assert!(legacy.join("SKILL.md").is_file(), "adoption is not a rewrite");
    let (_, stdout, _) = sandbox.run(&["skills", "doctor", "--json"]);
    let findings: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert!(
        !findings.as_array().unwrap().iter().any(|finding| finding["skill"] == "legacy" && finding["kind"] == "unmanaged"),
        "an adopted skill is managed: {stdout}"
    );
}

#[test]
fn search_explains_why_skills_sh_needs_a_token() {
    let sandbox = Sandbox::new();
    let (ok, stdout, stderr) = sandbox.run(&["skills", "search", "design", "--source", "skills.sh"]);
    assert!(!ok, "a refusal exits non-zero so a script can notice");
    let combined = format!("{stdout}{stderr}");
    assert!(
        combined.to_lowercase().contains("token") || combined.to_lowercase().contains("github"),
        "the message says what to do instead: {combined}"
    );
}

#[test]
fn adding_a_source_proves_access_without_installing() {
    let sandbox = Sandbox::new();
    let source = sandbox.source();
    let (ok, stdout, stderr) = sandbox.run(&["skills", "source", "add", source.to_str().unwrap()]);
    assert!(ok, "{stderr}");
    assert!(stdout.contains("local-my-skills"), "{stdout}");
    let _ = Path::new(&source);
    let (_, stdout, _) = sandbox.run(&["skills", "source", "--json"]);
    let sources: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(sources[0]["id"], "local-my-skills");
    assert_eq!(sources[0]["enabled"], true);
}

#[test]
fn update_rollback_and_trash_are_reachable_from_the_cli() {
    let sandbox = Sandbox::new();
    // A git remote served from the sandbox, at two commits.
    let repo = sandbox.dir.path().join("repo");
    std::fs::create_dir_all(repo.join("alpha")).unwrap();
    std::fs::write(repo.join("alpha/SKILL.md"), "---\nname: alpha\ndescription: one\n---\n").unwrap();
    let git = |args: &[&str]| {
        let output = Command::new("git")
            .current_dir(&repo)
            .args(["-c", "user.email=t@e", "-c", "user.name=t", "-c", "init.defaultBranch=main", "-c", "commit.gpgsign=false"])
            .args(args)
            .output()
            .unwrap();
        assert!(output.status.success(), "git {args:?}");
    };
    git(&["init", "-q"]);
    git(&["add", "-A"]);
    git(&["commit", "-qm", "one"]);

    let url = format!("file://{}", repo.display());
    let (ok, _, stderr) = sandbox.run(&["skills", "install", &url, "--accept", "--target", "codex"]);
    assert!(ok, "{stderr}");

    std::fs::write(repo.join("alpha/SKILL.md"), "---\nname: alpha\ndescription: two\n---\n").unwrap();
    git(&["commit", "-qam", "two"]);
    let (ok, stdout, stderr) = sandbox.run(&["skills", "update"]);
    assert!(ok, "{stderr}");
    assert!(stdout.contains("1 changed"), "{stdout}");

    let source_id = {
        let (_, stdout, _) = sandbox.run(&["skills", "source", "--json"]);
        let sources: serde_json::Value = serde_json::from_str(&stdout).unwrap();
        sources[0]["id"].as_str().unwrap().to_string()
    };
    let (ok, stdout, stderr) = sandbox.run(&["skills", "rollback", "--source", &source_id]);
    assert!(ok, "{stderr}");
    assert!(stdout.contains("Rolled back"), "{stdout}");
    let content = std::fs::read_to_string(sandbox.home().join(".agents/skills/alpha/SKILL.md")).unwrap();
    assert!(content.contains("one"), "the previous version is live again: {content}");

    // The trash is a listing plus a restore, not a black hole.
    let (ok, stdout, _) = sandbox.run(&["skills", "trash", "--json"]);
    assert!(ok);
    let items: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert!(items.is_array());
}
