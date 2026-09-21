//! Leaving the shell from the interface.
//!
//! `astral-plasma shell exit` is what the settings page, the launcher command
//! and the power menu call. It must address *this* install's shell instance - a
//! second checkout or another Quickshell config must never be touched - and it
//! must fail loudly instead of silently doing nothing when the shell is gone.

use astral_plasma::application::shell_lifecycle::{shell_kill_command, shell_quit_command};
use std::fs;
use std::path::Path;

#[test]
fn the_quit_call_uses_the_shell_ipc() {
    let (program, args) = shell_quit_command(Path::new("/opt/astral-plasma"));

    assert_eq!(program, "quickshell");
    assert_eq!(
        args,
        vec![
            "ipc".to_string(),
            "-p".to_string(),
            "/opt/astral-plasma".to_string(),
            "call".to_string(),
            "shell".to_string(),
            "quit".to_string(),
        ],
        "the running instance is addressed by its config path"
    );
}

#[test]
fn the_kill_fallback_only_targets_this_config() {
    let (program, args) = shell_kill_command(Path::new("/opt/astral-plasma"));

    assert_eq!(program, "pkill");
    assert_eq!(args[0], "-f");
    assert_eq!(
        args[1], "quickshell -p /opt/astral-plasma",
        "a wedged shell is killed by its config path, so another instance survives"
    );
}

#[test]
fn the_shell_config_dir_is_the_one_holding_shell_qml() {
    use astral_plasma::application::shell_lifecycle::shell_config_dir_from;
    use astral_plasma::domain::branding;

    // A checkout (development) or the extracted package (installed) both hold
    // shell.qml, and that is what the IPC must be pointed at.
    let install = tempfile::tempdir().unwrap();
    fs::write(install.path().join("shell.qml"), b"// root").unwrap();
    assert_eq!(
        shell_config_dir_from(Some(install.path().to_path_buf())),
        install.path()
    );

    // A stale binary that no longer sits in an install falls back to the
    // extracted package rather than addressing nothing.
    assert_eq!(
        shell_config_dir_from(None),
        branding::default_package_dir()
    );
}
