use astral_plasma::application::systemd_service::SystemdControlUseCase;
use astral_plasma::domain::branding;
use astral_plasma::domain::systemd::generate_unit_file_content;
use astral_plasma::infrastructure::systemd_adapter::SystemdAdapter;
use std::fs;

/// Environment variables are process-global, so the adapter test is one
/// function: two tests setting `ENV_SYSTEMD_DIR` in parallel would each read the
/// other's directory and fail for reasons unrelated to the unit they assert on.
#[test]
fn test_systemd_service_rust_use_case() {
    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_systemd_dir = tmpdir.path().join("systemd").join("user");

    std::env::set_var(branding::ENV_SYSTEMD_DIR, &mock_systemd_dir);
    std::env::set_var(branding::ENV_TEST_MODE, "1");
    std::env::set_var(branding::ENV_BIN_PATH, tmpdir.path().join("bin/astral-plasma"));

    let adapter = SystemdAdapter::new();
    let use_case = SystemdControlUseCase::new(adapter);

    // 1. Initial status: uninstalled
    let st1 = use_case.get_status().unwrap();
    assert!(!st1.installed);

    let service_file = mock_systemd_dir.join(branding::SYSTEMD_UNIT);
    assert!(!service_file.exists());

    // 2. Install
    let st2 = use_case.install().unwrap();
    assert!(st2.installed);
    assert!(service_file.exists());

    let content = fs::read_to_string(&service_file).unwrap();
    assert!(content.contains("[Unit]"));
    assert!(content.contains(branding::SYSTEMD_DESCRIPTION));

    // 3. Remove
    let st3 = use_case.remove().unwrap();
    assert!(!st3.installed);
    assert!(!service_file.exists());
}

/// The unit must start the supervisor, never Quickshell directly.
///
/// `ExecStart=quickshell -p <dir>` skips `astral-plasma run`, and with it the
/// Plasma claim, the shortcut journal and the restore-on-exit path. A service
/// install written that way displaced the user's panels and never put them back.
#[test]
fn the_user_unit_starts_the_supervisor_not_quickshell() {
    let content = generate_unit_file_content("/home/u/.local/share/astral-plasma/bin/astral-plasma", "/home/u/.local/share/astral-plasma/package");

    let exec = content
        .lines()
        .find(|line| line.starts_with("ExecStart="))
        .expect("unit has an ExecStart");
    assert!(
        exec.ends_with(" run"),
        "ExecStart must call the `run` supervisor: {exec}"
    );
    assert!(
        !exec.contains("quickshell"),
        "ExecStart must not exec quickshell directly: {exec}"
    );
    assert!(
        content.contains("ASTRAL_PLASMA_PACKAGE_DIR=/home/u/.local/share/astral-plasma/package"),
        "the unit must pin the bundle the supervisor serves, so the service and the CLI \
         cannot disagree about which package is live"
    );
}
