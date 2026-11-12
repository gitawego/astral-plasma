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
        self.run_env(args, &[])
    }

    fn run_env(&self, args: &[&str], envs: &[(&str, &str)]) -> (bool, String, String) {
        let home = self.home();
        std::fs::create_dir_all(&home).unwrap();
        let mut command = Command::new(env!("CARGO_BIN_EXE_astral-plasma"));
        command
            .args(args)
            .env("HOME", &home)
            .env("XDG_DATA_HOME", self.dir.path().join("data"))
            .env("XDG_STATE_HOME", self.dir.path().join("state"))
            .env("XDG_CACHE_HOME", self.dir.path().join("cache"));
        for (name, value) in envs {
            command.env(name, value);
        }
        let output = command.output().expect("the binary runs");
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
fn skills_sh_search_does_not_ask_for_a_token() {
    // The catalog's `/api/search` is public (their own CLI uses it). This test is network
    // independent: an offline machine may fail, but never for want of a token — the regression
    // this guards is the refusal that shipped when only the authenticated `/api/v1` family was
    // known.
    let sandbox = Sandbox::new();
    let (_, stdout, stderr) = sandbox.run(&["skills", "search", "web design", "--source", "skills.sh"]);
    let combined = format!("{stdout}{stderr}").to_lowercase();
    assert!(!combined.contains("vercel oidc"), "no OIDC token is required: {combined}");
    assert!(!combined.contains("needs a vercel"), "{combined}");
    assert!(!combined.contains("search github instead"), "{combined}");
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

#[test]
fn the_cli_searches_an_added_source_without_a_catalog() {
    let sandbox = Sandbox::new();
    let source = sandbox.source();
    let (ok, output, _) = sandbox.run(&["skills", "source", "add", source.to_str().unwrap()]);
    assert!(ok, "adding a source failed: {output}");

    let (ok, stdout, stderr) = sandbox.run(&[
        "skills", "search", "alph", "--source", "local-my-skills", "--json",
    ]);
    assert!(ok, "{stderr}");
    let hits: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(hits.as_array().unwrap().len(), 1, "{stdout}");
    assert_eq!(hits[0]["source"], "local-my-skills");
    assert_eq!(hits[0]["name"], "alpha");
    assert_eq!(hits[0]["kind"], "skill");
}

#[test]
fn the_mcp_command_names_the_transport_it_offers() {
    let sandbox = Sandbox::new();
    let (ok, stdout, stderr) = sandbox.run(&["skills", "mcp", "--transport", "bogus"]);
    assert!(!ok, "an unknown transport must fail: {stdout}{stderr}");
    assert!(
        stderr.contains("unknown MCP transport") && stderr.contains("--http"),
        "the refusal names the two transports: {stderr}"
    );
}

#[test]
fn the_cli_reports_mcp_status_and_uninstalls_an_agent_entry() {
    let sandbox = Sandbox::new();
    let pi_dir = sandbox.home().join(".pi/agent");
    std::fs::create_dir_all(&pi_dir).unwrap();
    std::fs::write(
        pi_dir.join("mcp.json"),
        r#"{"mcpServers":{"astral-skills":{"url":"http://127.0.0.1:1/mcp"},"other":{"url":"http://example.com/mcp"}}}"#,
    )
    .unwrap();

    let (ok, stdout, stderr) = sandbox.run_env(
        &["skills", "mcp", "status", "--json"],
        &[("ASTRAL_API_PORT", "1")],
    );
    assert!(ok, "{stderr}");
    let report: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(report["server"]["state"], "down", "{report}");
    assert_eq!(report["agents"].as_array().unwrap().len(), 7);
    let pi = report["agents"]
        .as_array()
        .unwrap()
        .iter()
        .find(|agent| agent["id"] == "pi")
        .unwrap();
    assert_eq!(pi["configured"], true, "{pi}");

    let (ok, stdout, stderr) = sandbox.run_env(
        &["skills", "mcp", "uninstall", "--agent", "pi", "--json"],
        &[("ASTRAL_API_PORT", "1")],
    );
    assert!(ok, "{stderr}");
    let removal: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(removal["removed"][0]["agent"], "pi", "{removal}");
    let config = std::fs::read_to_string(pi_dir.join("mcp.json")).unwrap();
    assert!(!config.contains("astral-skills"), "{config}");
    assert!(config.contains("example.com"), "the sibling survives: {config}");
}

#[test]
fn the_cli_installs_and_uninstalls_an_agent_mcp_entry() {
    let sandbox = Sandbox::new();
    let (ok, stdout, stderr) = sandbox.run_env(
        &["skills", "mcp", "install", "--agent", "pi", "--json"],
        &[("ASTRAL_API_PORT", "1")],
    );
    assert!(ok, "{stderr}");
    let installation: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(installation["installed"][0]["agent"], "pi", "{installation}");
    let config = std::fs::read_to_string(sandbox.home().join(".pi/agent/mcp.json")).unwrap();
    assert!(config.contains("astral-skills"), "{config}");
    assert!(config.contains("http://127.0.0.1:1/mcp"), "{config}");

    let (ok, stdout, stderr) = sandbox.run_env(
        &["skills", "mcp", "uninstall", "--agent", "pi", "--json"],
        &[("ASTRAL_API_PORT", "1")],
    );
    assert!(ok, "{stderr}");
    let removal: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(removal["removed"][0]["agent"], "pi", "{removal}");
    let config = std::fs::read_to_string(sandbox.home().join(".pi/agent/mcp.json")).unwrap();
    assert!(!config.contains("astral-skills"), "{config}");
}
