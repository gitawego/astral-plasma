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
}
