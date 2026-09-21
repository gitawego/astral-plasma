//! Leaving the shell.
//!
//! Quitting is the whole job: the supervisor that started the shell (`run.sh`,
//! the systemd unit) watches the shell process and restores the Plasma panels
//! when it exits, and a session that never disabled them has nothing to restore.
//! Restoring here as well would stop and start plasmashell a second time for
//! nothing.
//!
//! The shell's own IPC is the clean way out. A shell that no longer answers it is
//! killed by config path, so only *this* install's instance is affected.

use crate::domain::branding;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The config directory the running shell was started with.
pub fn shell_config_dir() -> PathBuf {
    shell_config_dir_from(branding::repo_root_from_exe())
}

/// Resolve the config directory from a candidate install directory.
///
/// A checkout (development) or the extracted package (installed) both hold
/// `shell.qml`; anything else falls back to the package directory so a stale
/// binary still addresses the shell it serves.
pub fn shell_config_dir_from(install_dir: Option<PathBuf>) -> PathBuf {
    install_dir
        .filter(|dir| dir.join("shell.qml").is_file())
        .unwrap_or_else(branding::default_package_dir)
}

/// The IPC call that asks the running shell to exit.
pub fn shell_quit_command(shell_dir: &Path) -> (String, Vec<String>) {
    (
        "quickshell".to_string(),
        vec![
            "ipc".to_string(),
            "-p".to_string(),
            shell_dir.to_string_lossy().to_string(),
            "call".to_string(),
            "shell".to_string(),
            "quit".to_string(),
        ],
    )
}

/// Last resort for a shell that does not answer its IPC: kill the instance
/// started with this config directory, and nothing else.
pub fn shell_kill_command(shell_dir: &Path) -> (String, Vec<String>) {
    (
        "pkill".to_string(),
        vec![
            "-f".to_string(),
            format!("quickshell -p {}", shell_dir.display()),
        ],
    )
}

/// Ask the running shell to exit. Returns whether it was reached.
pub fn quit_running_shell() -> bool {
    let shell_dir = shell_config_dir();

    let (program, args) = shell_quit_command(&shell_dir);
    if run(&program, &args) {
        return true;
    }

    let (program, args) = shell_kill_command(&shell_dir);
    run(&program, &args)
}

fn run(program: &str, args: &[String]) -> bool {
    Command::new(program)
        .args(args)
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}
