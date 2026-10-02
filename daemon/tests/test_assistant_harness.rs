use astral_plasma::application::assistant_service::AssistantService;
use astral_plasma::domain::assistant::ToolCallProposal;
use astral_plasma::infrastructure::assistant_harness::runtime_provisioner::RuntimeProvisioner;
use astral_plasma::infrastructure::crash_monitor::CrashMonitor;

#[test]
fn test_harness_discovery_and_skills() {
    let service = AssistantService::new();
    let harnesses = service.list_harnesses();
    assert!(!harnesses.is_empty(), "Must list available harnesses");

    let pi_harness = harnesses.iter().find(|h| h.id == "pi");
    assert!(pi_harness.is_some(), "Pi harness must be reported");

    let skills = service.list_skills();
    assert!(!skills.is_empty(), "Must discover predefined skills");

    let has_sys_diag = skills.iter().any(|s| s.name == "system-diagnostics");
    assert!(has_sys_diag, "Must discover system-diagnostics skill");
}

#[test]
fn test_runtime_provisioning_status() {
    let status = RuntimeProvisioner::get_status();
    assert_eq!(status.pi_executable, RuntimeProvisioner::locate_pi());
    if status.pi_executable.is_some() {
        assert!(status.has_mcp_support, "pi built-in MCP should be available when pi is installed");
    } else {
        assert!(!status.has_mcp_support, "MCP should not be reported when pi is not installed");
    }
}

#[test]
fn test_tool_safety_classification() {
    // Read-only commands are safe
    let (d1, s1) = ToolCallProposal::assess_safety("journalctl -n 20");
    assert!(!d1 && !s1);

    // Destructive or sudo commands require approval
    let (d2, s2) = ToolCallProposal::assess_safety("sudo pacman -Syu");
    assert!(d2 && s2);

    let (d3, s3) = ToolCallProposal::assess_safety("kill -9 9999");
    assert!(d3 && !s3);
}

#[test]
fn test_crash_monitor_scan() {
    let crashes = CrashMonitor::scan_recent_crashes(3);
    // Scan runs without panicking
    println!("Detected {} crash incidents", crashes.len());
}

#[test]
fn test_provider_and_model_listing() {
    let service = AssistantService::new();
    let providers = service.list_providers();
    assert!(!providers.is_empty(), "Must return discovered providers");

    let opencode = providers.iter().find(|p| p.id == "opencode-go");
    assert!(opencode.is_some(), "Must list opencode-go provider");

    let gemini = providers.iter().find(|p| p.id == "gemini");
    assert!(gemini.is_some(), "Must list gemini provider");
    assert!(!gemini.unwrap().models.is_empty(), "Gemini must have models listed");

    let claude = providers.iter().find(|p| p.id == "claude");
    assert!(claude.is_some(), "Claude must have models listed");
}

// ============================================================================
// Pi 1.0 contract
// ============================================================================
// Astral does not pin a pi version: it reports the installed one and builds the
// invocation from what pi 1.0 accepts. Two things changed in 1.0 that this
// integration has to respect, and both are asserted here:
//
//   * `--provider` without `--model` is now a hard failure (pi #10236), so a
//     provider is only ever passed together with a model;
//   * the reported harness version must be the real one (it used to be a
//     hardcoded "0.87.1", which made every UI and status line lie after an
//     upgrade).
use astral_plasma::infrastructure::assistant_harness::pi_harness::{pi_argv, PiHarness};
use astral_plasma::infrastructure::assistant_harness::runtime_provisioner::parse_pi_version;
use std::path::{Path, PathBuf};

fn fake_pi(version_output: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!(
        "astral-fake-pi-{}-{}",
        std::process::id(),
        version_output.replace(['.', '\n'], "_")
    ));
    std::fs::write(&path, format!("#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo {}; exit 0; fi\nexit 0\n", version_output.trim()))
        .expect("write fake pi");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&path).expect("stat").permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&path, perms).expect("chmod");
    }
    path
}

#[test]
fn test_pi_version_is_read_from_the_binary() {
    let bin = fake_pi("9.9.9");
    let status = RuntimeProvisioner::get_status();
    assert_eq!(status.pi_version, RuntimeProvisioner::probe_pi_version(status.pi_executable.as_deref()),
        "the reported version comes from the installed binary");

    assert_eq!(parse_pi_version("9.9.9\n").as_deref(), Some("9.9.9"));
    assert_eq!(parse_pi_version("pi 1.0.0 (build 42)").as_deref(), Some("1.0.0"),
        "a decorated version line still yields the version");
    assert_eq!(parse_pi_version("no version here"), None);
    assert_eq!(parse_pi_version(""), None);

    // A binary that answers is the only source of a version.
    assert_eq!(RuntimeProvisioner::probe_pi_version(None), None);
    assert_eq!(RuntimeProvisioner::probe_pi_version(Some(Path::new("/nonexistent/pi"))), None);
    assert_eq!(RuntimeProvisioner::probe_pi_version(Some(bin.as_path())).as_deref(), Some("9.9.9"));
    std::fs::remove_file(&bin).ok();
}

#[test]
fn test_harness_info_reports_the_installed_version_not_a_constant() {
    let harness = PiHarness::new();
    let info = harness.harness_info();
    let expected = RuntimeProvisioner::probe_pi_version(RuntimeProvisioner::locate_pi().as_deref());
    assert_eq!(info.version, expected,
        "harness_info must report what pi --version says (got {:?})", info.version);
    if info.is_available {
        assert!(info.version.is_some(), "an installed pi must report a version");
    }
}

#[test]
fn test_provider_is_only_passed_with_a_model() {
    // pi 1.0 fails the run when --provider arrives without --model, so a lone
    // provider falls back to pi's own defaultProvider instead of failing.
    let argv = pi_argv("hi", Some("gemini"), None, None);
    assert!(!argv.contains(&"--provider".to_string()),
        "a provider without a model must not be passed: {argv:?}");
    assert_eq!(argv[0], "-p");
    assert!(argv.contains(&"--mode".to_string()) && argv.contains(&"json".to_string()));

    let argv = pi_argv("hi", Some("gemini"), Some("gemini-2.5-flash"), None);
    assert!(argv.contains(&"--provider".to_string()) && argv.contains(&"gemini".to_string()));
    assert!(argv.contains(&"--model".to_string()) && argv.contains(&"gemini-2.5-flash".to_string()));

    let argv = pi_argv("hi", None, Some("deepseek-v4.1-flash"), None);
    assert!(argv.contains(&"--model".to_string()));
    assert!(!argv.contains(&"--provider".to_string()));

    // Empty strings are "not configured", never arguments.
    let argv = pi_argv("hi", Some(""), Some(""), None);
    assert!(!argv.contains(&"--provider".to_string()) && !argv.contains(&"--model".to_string()));

    // The skills directory is an argument of its own when it exists.
    let skills = std::env::temp_dir().join(format!("astral-pi-skills-{}", std::process::id()));
    std::fs::create_dir_all(&skills).unwrap();
    let argv = pi_argv("hi", None, None, Some(skills.as_path()));
    assert_eq!(argv.iter().filter(|a| *a == "--skill").count(), 1);
    assert!(argv.contains(&skills.to_string_lossy().to_string()));
    // A directory that does not exist is not an argument: pi would reject it.
    let argv = pi_argv("hi", None, None, Some(Path::new("/nonexistent/skills")));
    assert!(!argv.contains(&"--skill".to_string()));
    std::fs::remove_dir_all(&skills).ok();
}

#[test]
fn test_pi_package_entries_are_recognised_in_both_settings_shapes() {
    // pi writes plain strings, its docs also show `{ source: ... }` objects: both
    // must satisfy the pi-subagents requirement, or Astral would try to reinstall
    // an already-installed package on every provisioning pass.
    let dir = std::env::temp_dir();
    let strings = dir.join(format!("astral-pi-pkg-strings-{}.json", std::process::id()));
    std::fs::write(&strings, r#"{"packages":["npm:pi-web-access","npm:pi-subagents"]}"#).unwrap();
    let objects = dir.join(format!("astral-pi-pkg-objects-{}.json", std::process::id()));
    std::fs::write(&objects, r#"{"packages":[{"source":"npm:pi-subagents","enabled":true}]}"#).unwrap();
    let other = dir.join(format!("astral-pi-pkg-other-{}.json", std::process::id()));
    std::fs::write(&other, r#"{"packages":[{"source":"npm:pi-web-access"}]}"#).unwrap();

    for path in [&strings, &objects] {
        assert!(
            astral_plasma::infrastructure::assistant_harness::runtime_provisioner::PiPackages::from_settings(path).subagents,
            "{} must satisfy the subagents requirement",
            path.display()
        );
    }
    assert!(!astral_plasma::infrastructure::assistant_harness::runtime_provisioner::PiPackages::from_settings(&other).subagents);
    for path in [strings, objects, other] {
        std::fs::remove_file(&path).ok();
    }
}

#[test]
fn test_parses_the_real_pi_1_0_json_stream() {
    // Verbatim records from `pi --mode json` (pi 1.0.0): the session header is new
    // in JSON mode and carries no assistant content, the streaming events are
    // delta-only, and the run is only settled after the retry/compaction window.
    let stream = [
        r#"{"type":"session","version":3,"id":"01a0fd3c-ec6d-760b-9aaa-b8ede5ce28c0","timestamp":"2026-10-02T15:30:23.469Z","cwd":"/tmp"}"#,
        r#"{"type":"agent_start"}"#,
        r#"{"type":"turn_start"}"#,
        r#"{"type":"message_update","usage":{"input":16922,"output":2,"totalTokens":16924},"assistantMessageEvent":{"type":"text_start","contentIndex":0}}"#,
        r#"{"type":"message_update","usage":{"input":16922,"output":2,"totalTokens":16924},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"ok"}}"#,
        r#"{"type":"message_update","usage":{"input":16922,"output":2,"totalTokens":16924},"assistantMessageEvent":{"type":"text_end","contentIndex":0,"content":"ok"}}"#,
        r#"{"type":"tool_execution_start","toolCallId":"call_1","toolName":"bash","args":{"command":"ls -la"}}"#,
        r#"{"type":"agent_end","messages":[],"willRetry":false}"#,
        r#"{"type":"agent_settled"}"#,
    ];

    let mut text = String::new();
    let mut errors = 0;
    for line in stream {
        if let Some(events) = PiHarness::parse_pi_json_event(line) {
            for event in events {
                match event {
                    astral_plasma::domain::assistant::AssistantEvent::TextChunk(chunk) => text.push_str(&chunk),
                    astral_plasma::domain::assistant::AssistantEvent::Error(_) => errors += 1,
                    _ => {}
                }
            }
        }
    }

    assert!(text.contains("ok"), "the text delta must reach the UI: {text:?}");
    assert_eq!(errors, 0, "a clean 1.0 stream must not report an error");
}

// ============================================================================
// Updating the harness from the shell
// ============================================================================
// The AI page offers "Update Pi" instead of asking the user to leave the shell
// and remember a command. The daemon owns that update (QML never spawns pi), and
// the report has to say what actually happened: which version was there before,
// which one is there after, and the output when something went wrong.
use astral_plasma::application::assistant_service::{pi_update_argv, PiUpdateTarget};

/// A fake pi whose `--version` reads a file and whose `update …` rewrites it.
fn fake_updatable_pi(before: &str, after: &str, update_exit: i32) -> (PathBuf, PathBuf) {
    let dir = std::env::temp_dir().join(format!(
        "astral-pi-update-{}-{}-{}-{}",
        std::process::id(),
        before.replace('.', "_"),
        after.replace('.', "_"),
        update_exit
    ));
    std::fs::create_dir_all(&dir).expect("create fake pi dir");
    let version_file = dir.join("version");
    std::fs::write(&version_file, format!("{before}\n")).expect("write version");
    let bin = dir.join("pi");
    std::fs::write(
        &bin,
        format!(
            "#!/bin/sh\nVF=\"{}\"\nif [ \"$1\" = \"--version\" ]; then cat \"$VF\"; exit 0; fi\nif [ \"$1\" = \"update\" ]; then echo \"updating {}\"; echo \"{after}\" > \"$VF\"; exit {}; fi\nif [ \"$1\" = \"mcp\" ]; then exit 0; fi\nexit 0\n",
            version_file.display(),
            if update_exit == 0 { "packages" } else { "failed" },
            update_exit
        ),
    )
    .expect("write fake pi");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&bin).expect("stat").permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&bin, perms).expect("chmod");
    }
    (bin, dir)
}

#[test]
fn test_pi_update_targets_map_to_the_pi_cli() {
    // pi 1.0's own table (docs/cli.md): `pi update` updates *pi only* and skips
    // extensions ("Extensions are skipped. Run pi update --extensions"), so each
    // target names its flag explicitly instead of relying on the bare default.
    assert_eq!(pi_update_argv(PiUpdateTarget::Pi), vec!["update", "self"]);
    assert_eq!(pi_update_argv(PiUpdateTarget::Extensions), vec!["update", "--extensions"]);
    assert_eq!(pi_update_argv(PiUpdateTarget::Models), vec!["update", "--models"]);
}

#[test]
fn test_updating_pi_reports_the_version_it_moved_between() {
    let (bin, dir) = fake_updatable_pi("1.0.0", "1.0.2", 0);
    let report = AssistantService::update_harness_with(Some(bin.as_path()), PiUpdateTarget::Pi)
        .expect("the update runs");

    assert_eq!(report.before.as_deref(), Some("1.0.0"));
    assert_eq!(report.after.as_deref(), Some("1.0.2"));
    assert_eq!(report.changed, Some(true), "a version change must be reported as such");
    assert!(!report.output.trim().is_empty(), "the update output is kept for the UI");
    assert_eq!(report.target, "pi");

    // Nothing to do: the next run finds the same version and says so.
    let unchanged = AssistantService::update_harness_with(Some(bin.as_path()), PiUpdateTarget::Pi)
        .expect("second update");
    assert_eq!(unchanged.before, unchanged.after);
    assert_eq!(unchanged.changed, Some(false));

    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn test_updating_extensions_is_not_a_version_claim() {
    let (bin, dir) = fake_updatable_pi("1.0.0", "1.0.0", 0);
    let report = AssistantService::update_harness_with(Some(bin.as_path()), PiUpdateTarget::Extensions)
        .expect("extensions update runs");
    assert_eq!(report.target, "extensions");
    assert_eq!(report.changed, None,
        "extensions update without moving the pi version: the output is the evidence");
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn test_updating_without_pi_names_the_install_command() {
    let err = AssistantService::update_harness_with(None, PiUpdateTarget::Pi)
        .expect_err("no pi to update");
    assert!(err.contains("pi-coding-agent"), "the error must name the package: {err}");
}

#[test]
fn test_a_failed_update_surfaces_its_output() {
    let (bin, dir) = fake_updatable_pi("1.0.0", "1.0.0", 7);
    let err = AssistantService::update_harness_with(Some(bin.as_path()), PiUpdateTarget::Pi)
        .expect_err("a failing update is an error");
    assert!(err.contains("failed"), "the error must say the update failed: {err}");
    assert!(err.contains("updating failed"), "the output must be carried: {err}");
    std::fs::remove_dir_all(&dir).ok();
}
