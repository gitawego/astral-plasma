//! Shell scripts that talk to the running shell over Quickshell IPC.
//!
//! The desktop entries installed into `~/.local/share/applications` run these
//! scripts through the `~/.config/quickshell` symlink, while the shell itself is
//! usually started from the real checkout path. Quickshell identifies instances
//! by the config path it was started with, so a script that passes its own
//! *logical* path (`pwd`, which keeps the symlink) addresses a different instance
//! than the one running - the IPC call fails, and the launcher fallback then
//! starts a SECOND shell instead of toggling the first. That is why Meta+Space
//! stopped opening the launcher.
//!
//! Every script must therefore resolve symlinks (`pwd -P`) before using `-p`.

use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

fn read(rel: &str) -> String {
    let path = repo_root().join(rel);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()))
}

/// Scripts the desktop entries invoke; each one must find the running instance.
const IPC_SCRIPTS: [&str; 4] = [
    "scripts/toggle_launcher.sh",
    "scripts/open_wallpaper.sh",
    "scripts/toggle_dashboard.sh",
    "scripts/toggle_settings.sh",
];

#[test]
fn ipc_scripts_resolve_the_symlinked_config_path() {
    for script in IPC_SCRIPTS {
        let source = read(script);
        assert!(
            source.contains("pwd -P"),
            "{script} must resolve symlinks (`pwd -P`): the desktop entries run it through \
             ~/.config/quickshell, and Quickshell matches instances by the path it was \
             started with - an unresolved path addresses nothing and the fallback spawns a \
             second shell"
        );
        assert!(
            source.contains("quickshell ipc") || source.contains("run.sh"),
            "{script} must either toggle over IPC or launch the shell"
        );
    }
}

#[test]
fn launcher_script_still_launches_the_shell_when_none_is_running() {
    let source = read("scripts/toggle_launcher.sh");
    assert!(
        source.contains("run.sh"),
        "when no instance is running the launcher script must start the shell, not fail silently"
    );
}

#[test]
fn shell_entry_points_agree_on_the_resolved_path() {
    // run.sh launches the shell; if it kept a logical (symlinked) path, the IPC
    // scripts resolving to the physical path would no longer match the instance.
    let source = read("run.sh");
    assert!(
        source.contains("pwd -P"),
        "run.sh must launch the shell with its physical path, or IPC from the installed \
         desktop entries cannot find it"
    );
}

#[test]
fn the_launcher_shortcut_has_exactly_one_owner() {
    let source = read("scripts/bind_shortcuts.sh");

    // The KWin actions own the keys: their script forwards to the daemon, which
    // runs the shell IPC (kglobalaccel's invokeShortcut on a .desktop service only
    // emits a signal that nothing launches). The `services` entries must be
    // cleared, or two owners fight over Meta+Space.
    assert!(
        source.contains("--group \"kwin\" --key \"AstralLauncher\""),
        "the KWin launcher action must be bound"
    );
    assert!(
        source.contains("--group \"kwin\" --key \"AstralWallpaper\""),
        "the KWin wallpaper action must be bound"
    );
    assert!(
        source.contains("setForeignShortcut(['kwin', 'AstralLauncher'")
            && source.contains("setForeignShortcut(['kwin', 'AstralWallpaper'"),
        "the KWin actions must be registered with kglobalaccel"
    );
    assert!(
        source.contains("setForeignShortcut(['astral-launcher.desktop', '_launch', 'default', 'Astral Plasma Launcher'], [dbus.Int32(0)])"),
        "the launcher's services action must be cleared so it cannot fight the KWin action"
    );
}

#[test]
fn desktop_entries_launch_through_the_config_symlink() {
    // The entries are copied into ~/.local/share/applications, so their Exec must
    // not depend on the checkout's location.
    for entry in ["shortcuts/astral-launcher.desktop", "shortcuts/astral-wallpaper.desktop"] {
        let source = read(entry);
        assert!(
            source.contains("$HOME/.config/quickshell/scripts/"),
            "{entry} must launch through the config symlink, not a machine-specific path"
        );
        assert!(
            !source.contains("/mnt/"),
            "{entry} must not bake in a build-machine path"
        );
    }
}

#[test]
fn run_sh_refuses_to_start_a_second_shell() {
    let source = read("run.sh");

    // Two instances of one config fight over the screen, and `quickshell ipc`
    // can only address one of them - so the desktop actions (launcher, exit)
    // would reach an instance the user is not looking at.
    assert!(
        source.contains("quickshell ipc -p \"$DIR\" show"),
        "run.sh must detect a shell already running for this config"
    );
    assert!(
        source.contains("already running"),
        "and it must stop instead of starting a duplicate"
    );
    assert!(
        source.contains("quickshell -n -p \"$DIR\""),
        "the shell must be launched with --no-duplicate as a second guard"
    );
}
