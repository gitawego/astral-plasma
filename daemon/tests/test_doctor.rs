use astral_plasma::domain::doctor::{is_version_compatible, parse_semver, CheckStatus, DependencyCheck, DoctorReport};
use astral_plasma::application::doctor_service::DoctorService;

#[test]
fn test_semver_parsing_standard() {
    assert_eq!(parse_semver("0.3.1"), Some((0, 3, 1)));
    assert_eq!(parse_semver("0.3.0"), Some((0, 3, 0)));
    assert_eq!(parse_semver("1.0.0"), Some((1, 0, 0)));
    assert_eq!(parse_semver("6.7.5"), Some((6, 7, 5)));
}

#[test]
fn test_semver_parsing_with_suffixes_and_prefixes() {
    // Suffixes from Arch Linux / CachyOS packages
    assert_eq!(parse_semver("6.11.2-3.1"), Some((6, 11, 2)));
    assert_eq!(parse_semver("0.3.1-1.1"), Some((0, 3, 1)));
    // Prefix 'v'
    assert_eq!(parse_semver("v4.2.0"), Some((4, 2, 0)));
    assert_eq!(parse_semver("Quickshell 0.3.1"), Some((0, 3, 1)));
}

#[test]
fn test_version_compatibility_rules() {
    // Quickshell requirement: >= 0.3.0
    assert!(is_version_compatible("0.3.1", "0.3.0"));
    assert!(is_version_compatible("0.3.0", "0.3.0"));
    assert!(is_version_compatible("0.4.0", "0.3.0"));
    assert!(is_version_compatible("1.0.0", "0.3.0"));
    assert!(!is_version_compatible("0.2.9", "0.3.0"));
    assert!(!is_version_compatible("0.1.0", "0.3.0"));

    // Qt6 requirement: >= 6.6.0
    assert!(is_version_compatible("6.11.2", "6.6.0"));
    assert!(is_version_compatible("6.7.5", "6.6.0"));
    assert!(is_version_compatible("6.6.0", "6.6.0"));
    assert!(!is_version_compatible("6.5.3", "6.6.0"));
    assert!(!is_version_compatible("5.15.2", "6.6.0"));
}

#[test]
fn test_doctor_report_status_evaluation() {
    // All required pass, optional warning -> overall pass
    let checks = vec![
        DependencyCheck {
            name: "Quickshell".to_string(),
            category: "Core Display Engine".to_string(),
            required: true,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: Some("0.3.1".to_string()),
            required_version: Some("0.3.0".to_string()),
            binary_path: Some("/usr/bin/quickshell".to_string()),
            message: "Compatible".to_string(),
            recommendation: None,
        },
        DependencyCheck {
            name: "Matugen".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Warning,
            installed: false,
            detected_version: None,
            required_version: None,
            binary_path: None,
            message: "Missing optional".to_string(),
            recommendation: Some("Install matugen".to_string()),
        },
    ];

    let report = DoctorReport::new(checks);
    assert!(report.all_required_satisfied);
    assert!(report.summary.contains("All required dependencies are satisfied"));

    // Required fail -> overall fail
    let checks_fail = vec![
        DependencyCheck {
            name: "Quickshell".to_string(),
            category: "Core Display Engine".to_string(),
            required: true,
            status: CheckStatus::Fail,
            installed: false,
            detected_version: None,
            required_version: Some("0.3.0".to_string()),
            binary_path: None,
            message: "Missing".to_string(),
            recommendation: Some("Install quickshell".to_string()),
        },
    ];

    let report_fail = DoctorReport::new(checks_fail);
    assert!(!report_fail.all_required_satisfied);
    assert!(report_fail.summary.contains("missing or outdated"));
}

#[test]
fn test_doctor_report_terminal_rendering() {
    let checks = vec![
        DependencyCheck {
            name: "Quickshell".to_string(),
            category: "Core Display Engine".to_string(),
            required: true,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: Some("0.3.1".to_string()),
            required_version: Some("0.3.0".to_string()),
            binary_path: Some("/usr/bin/quickshell".to_string()),
            message: "OK".to_string(),
            recommendation: None,
        },
    ];
    let report = DoctorReport::new(checks);
    let output = report.render_terminal();
    assert!(output.contains("ASTRAL PLASMA SYSTEM DOCTOR"));
    assert!(output.contains("Core Display Engine"));
    assert!(output.contains("Quickshell"));
    assert!(output.contains("0.3.1"));
}

#[test]
fn test_live_diagnostics_collection() {
    let service = DoctorService::new();
    let report = service.run_diagnostics();
    assert!(!report.checks.is_empty(), "Doctor must perform at least one check");
    
    // Quickshell check must be present
    let qs_check = report.checks.iter().find(|c| c.name == "Quickshell");
    assert!(qs_check.is_some(), "Quickshell check must exist");
    let qs = qs_check.unwrap();
    assert_eq!(qs.required, true);
    let expected_installed = std::process::Command::new("which")
        .arg("quickshell")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    assert_eq!(qs.installed, expected_installed);

    // Download Manager (aria2) check must be present
    let aria_check = report.checks.iter().find(|c| c.name.contains("aria2"));
    assert!(aria_check.is_some(), "Download Manager (aria2) check must exist");
    let aria = aria_check.unwrap();
    assert_eq!(aria.required, false, "aria2 must be optional");
    assert_eq!(aria.category, "Optional Enhancements");
    if !aria.installed {
        assert!(aria.recommendation.is_some());
        assert!(aria.recommendation.as_ref().unwrap().contains("aria2"));
    }
}

// ============================================================================
// Pi harness check
// ============================================================================
// The AI Copilot runs on the user's own `pi` installation, and pi 1.0 changed two
// things Astral depends on. `doctor` therefore reports which pi is installed and
// names the update command - as an *optional* check: a missing or older pi must
// never make the shell report itself broken.
#[test]
fn pi_harness_check_reports_the_installed_version_and_how_to_update() {
    use astral_plasma::application::doctor_service::check_pi_harness;
    use astral_plasma::domain::doctor::CheckStatus;

    // Not installed: optional, a warning, and the install command.
    let missing = check_pi_harness(None);
    assert!(!missing.required, "the AI Copilot harness is optional");
    assert!(!missing.installed);
    assert_eq!(missing.status, CheckStatus::Warning);
    assert!(
        missing.recommendation.as_deref().unwrap_or("").contains("pi-coding-agent"),
        "the recommendation must name the package, got: {:?}",
        missing.recommendation
    );

    // An older pi, or one without built-in MCP: current enough to be found, and
    // the update command is what the user needs.
    let stale = fake_pi("0.50.0", false);
    let stale_check = check_pi_harness(Some(stale.clone()));
    assert!(stale_check.installed);
    assert_eq!(stale_check.status, CheckStatus::Warning);
    assert_eq!(stale_check.detected_version.as_deref(), Some("0.50.0"));
    assert!(
        stale_check.recommendation.as_deref().unwrap_or("").contains("pi update self"),
        "an outdated harness must be told how to update, got: {:?}",
        stale_check.recommendation
    );

    // pi 1.0 with built-in MCP: pass, version reported, nothing to do.
    let current = fake_pi("1.0.0", true);
    let current_check = check_pi_harness(Some(current.clone()));
    assert_eq!(current_check.status, CheckStatus::Pass);
    assert_eq!(current_check.detected_version.as_deref(), Some("1.0.0"));
    assert!(current_check.recommendation.is_none(),
        "a current harness needs no recommendation, got: {:?}", current_check.recommendation);
    assert!(!current_check.name.is_empty() && !current_check.message.is_empty());

    std::fs::remove_file(&stale).ok();
    std::fs::remove_file(&current).ok();
}

/// A fake `pi` that answers `--version` and, when `mcp` is true, `mcp --help`.
fn fake_pi(version: &str, mcp: bool) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
        "astral-doctor-pi-{}-{}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos(),
        version.replace('.', "_"),
        mcp
    ));
    let mcp_exit = if mcp { 0 } else { 1 };
    std::fs::write(
        &path,
        format!(
            "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo {version}; exit 0; fi\nif [ \"$1\" = \"mcp\" ]; then exit {mcp_exit}; fi\nexit 0\n"
        ),
    )
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
