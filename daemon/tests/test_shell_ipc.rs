//! Shortcut forwarding: the KWin script -> daemon -> shell IPC.
//!
//! A KWin script cannot launch processes, and invoking a `.desktop` service
//! through kglobalaccel only emits a signal that nothing in this shell listens
//! to (Plasma's own panel does the launching for the shortcuts it registers).
//! Meta+Space therefore ended up doing nothing at all.
//!
//! The shortcut script now forwards to the daemon, which runs the shell's IPC
//! command. The action names are a whitelist: a D-Bus method that executes
//! arbitrary commands would be a local privilege hole.

use astral_plasma::application::watch_events::shell_ipc_arguments;
use std::path::PathBuf;

fn read(rel: &str) -> String {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf();
    let path = root.join(rel);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()))
}

#[test]
fn known_actions_map_to_the_shell_ipc_command() {
    assert_eq!(
        shell_ipc_arguments("launcher.toggle"),
        Some(vec!["call", "launcher", "toggle"]),
        "Meta+Space must toggle the command launcher"
    );
    assert_eq!(
        shell_ipc_arguments("launcher.wallpaper"),
        Some(vec!["call", "launcher", "open", "wallpaper"])
    );
    assert_eq!(
        shell_ipc_arguments("dashboard.toggle"),
        Some(vec!["call", "dashboard", "toggle"])
    );
    assert_eq!(
        shell_ipc_arguments("settings.toggle"),
        Some(vec!["call", "settings", "toggle"])
    );
}

#[test]
fn unknown_actions_are_refused() {
    // The daemon must never turn a D-Bus argument into an arbitrary command.
    for action in ["", "rm -rf /", "launcher.toggle; sh", "../escape", "call"] {
        assert!(
            shell_ipc_arguments(action).is_none(),
            "{action:?} must not be executable through the daemon"
        );
    }
}

#[test]
fn the_kwin_shortcut_script_forwards_to_the_daemon() {
    let script = read("kwin/astral-plasma-shortcuts/contents/code/main.js");
    assert!(
        script.contains("org.astralplasma.WindowWatcher") && script.contains("ShellIpc"),
        "the shortcut script must forward to the daemon's ShellIpc method"
    );
    assert!(
        !script.contains("invokeShortcut"),
        "invoking a .desktop service through kglobalaccel only emits a signal nobody listens \
         to - that is what made Meta+Space a no-op"
    );
    assert!(
        script.contains("launcher.toggle"),
        "the launcher shortcut must use the whitelisted action name"
    );
}
