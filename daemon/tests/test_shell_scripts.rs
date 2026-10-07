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

#[test]
fn the_shell_claims_its_shortcuts_on_every_start() {
    // Closing the shell hands the global shortcuts back to Plasma, and the only
    // other place that binds them is the daemon's watcher - which can start
    // minutes late when a stale watcher still holds the D-Bus name. A restart
    // therefore left the whole desktop without its shortcut keys. shell.qml must
    // claim them again on every start, for the KWin profile only.
    let source = read("shell.qml");
    let completed = source
        .split("Component.onCompleted")
        .nth(1)
        .expect("shell.qml must have a Component.onCompleted block");
    let block = completed
        .split("Component.onDestruction")
        .next()
        .expect("Component.onDestruction follows Component.onCompleted");

    assert!(
        block.contains("\"shortcuts\", \"bind\""),
        "shell.qml must re-bind the KWin shortcuts on startup: a shell restart must never \
         leave the desktop without its shortcut keys"
    );
    assert!(
        block.contains("DesktopSessionFacade.profile === \"kde\""),
        "binding KDE global shortcuts is a KWin-profile concern"
    );
}

#[test]
fn shortcut_binds_are_serialised_across_callers() {
    // Two callers claim the shortcuts at startup: the shell as soon as it loads,
    // and the daemon's watcher when it comes up. Both rewrite the same KDE
    // configs and reload the same KWin script; running them concurrently left
    // KWin's scripting service and the daemon's D-Bus service wedged, so every
    // shortcut stopped doing anything. Both entry points must take one lock.
    for script in ["scripts/bind_shortcuts.sh", "scripts/restore_shortcuts.sh"] {
        let source = read(script);
        assert!(
            source.contains("flock"),
            "{script} must serialise shortcut config writes"
        );
        assert!(
            source.contains("astral-plasma-shortcuts.lock"),
            "{script} must take the shared shortcut lock"
        );
    }
}

#[test]
fn an_already_bound_shortcut_set_is_left_alone() {
    // The shell and the daemon's watcher both claim the shortcuts on every
    // start. Re-running the full bind when the requested mode is already in
    // place reloads KWin's scripting service underneath the daemon and wedges
    // its D-Bus service, so the script must recognise that state and stop.
    let source = read("scripts/bind_shortcuts.sh");
    assert!(
        source.contains("already bound"),
        "bind_shortcuts.sh must no-op when the requested mode is already bound"
    );
    assert!(
        source.contains("shortcuts_backup.json"),
        "the bound state is recognised by the session backup the script writes"
    );
}

#[test]
fn the_binding_labels_agree_across_languages() {
    // The Rust claim check recognises its own work by the exact
    // `kglobalshortcutsrc` value, and `bind_shortcuts.sh` writes that value. If
    // the labels drift apart the claim never looks current, so every reconciler
    // tick re-binds - a typo turning into a hot loop. Pin the two sides together.
    let script = read("scripts/bind_shortcuts.sh");
    assert!(
        script.contains(astral_plasma::domain::shortcuts::LAUNCHER_BINDING_LABEL),
        "bind_shortcuts.sh must write the launcher label the claim check expects"
    );
    assert!(
        script.contains(astral_plasma::domain::shortcuts::OVERVIEW_BINDING_LABEL),
        "bind_shortcuts.sh must write the overview label the claim check expects"
    );
}

#[test]
fn external_desktop_state_has_one_writer_each() {
    // Cross-domain regressions start when two components own the same external
    // file: one binds, the other restores, and the ordering is nobody's job.
    // Each of these files may only be touched by the modules listed here.
    let owners: [(&str, &[&str]); 4] = [
        (
            "kglobalshortcutsrc",
            &[
                "daemon/src/infrastructure/kwin_shortcuts.rs",
                "scripts/bind_shortcuts.sh",
                "scripts/restore_shortcuts.sh",
            ],
        ),
        (
            "kwinrulesrc",
            &[
                "daemon/src/infrastructure/kwin_window_rules.rs",
                // Forces the DSH web app window's landscape size.
                "daemon/src/infrastructure/dsh_web_desktop.rs",
            ],
        ),
        (
            "kwinrc",
            &[
                "daemon/src/infrastructure/kwin_blur.rs",
                "daemon/src/infrastructure/kwin_shortcuts.rs",
                "scripts/bind_shortcuts.sh",
                "scripts/restore_shortcuts.sh",
            ],
        ),
        (
            "shortcuts_backup.json",
            &[
                "daemon/src/infrastructure/kwin_shortcuts.rs",
                // Reads the journal to decide whether a claim is still needed.
                "scripts/bind_shortcuts.sh",
                "scripts/restore_shortcuts.sh",
            ],
        ),
    ];

    let mut sources: Vec<PathBuf> = Vec::new();
    collect(&repo_root().join("daemon/src"), &mut sources);
    collect(&repo_root().join("scripts"), &mut sources);
    for entry in ["shell.qml", "config/Config.qml", "services/WindowService.qml"] {
        sources.push(repo_root().join(entry));
    }

    for (file, allowed) in owners {
        for source in &sources {
            let Ok(content) = std::fs::read_to_string(source) else {
                continue;
            };
            // Only *code* counts as ownership: a file name in a doc comment
            // describes the state, it does not mutate it.
            let code: String = content
                .lines()
                .filter(|line| {
                    let trimmed = line.trim_start();
                    !(trimmed.starts_with("//") || trimmed.starts_with('#'))
                })
                .collect::<Vec<_>>()
                .join("\n");
            if !code.contains(file) {
                continue;
            }
            let rel = source
                .strip_prefix(repo_root())
                .unwrap_or(source)
                .to_string_lossy()
                .replace('\\', "/");
            assert!(
                allowed.contains(&rel.as_str()),
                "{rel} writes {file}, but the owner list says only {allowed:?} may. \
                 Add it deliberately or route the write through the owner."
            );
        }
    }
}

fn collect(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect(&path, out);
        } else if path.extension().is_some_and(|ext| ext == "rs" || ext == "sh") {
            out.push(path);
        }
    }
}

#[test]
fn restore_script_never_reenables_the_astral_kwin_plugin() {
    // The kwinrc plugin flag decides whether KWin loads the Astral shortcut
    // script at login. Restoring a previously-enabled value keeps KWin
    // registering Astral shortcuts (bare Meta included) with the theme not
    // running - which is how a session loses Alt+Tab without the theme. The
    // fallback restore must always leave the plugin off.
    let script = std::fs::read_to_string(
        concat!(env!("CARGO_MANIFEST_DIR"), "/../scripts/restore_shortcuts.sh"),
    )
    .expect("scripts/restore_shortcuts.sh must be readable");
    assert!(
        !script.contains("plugin_val = \"true\""),
        "the fallback restore must not restore an enabled Astral KWin plugin"
    );
    assert!(
        script.contains("\"astral-plasma-shortcutsEnabled\", \"false\""),
        "the fallback restore must write the plugin flag as false"
    );
}

#[test]
fn the_shell_teardown_hands_kwins_blur_back() {
    // The shell retunes KWin's BlurStrength for its glass. Leaving that in
    // kwinrc means the desktop keeps the shell's blur (and its flattened
    // backdrop) after the shell is gone, so the exit path must restore it.
    let run = read("run.sh");
    assert!(
        run.contains("blur restore"),
        "run.sh must hand KWin's blur back when the shell exits"
    );
}

#[test]
fn the_fallback_restore_rearms_the_recorded_live_keys() {
    // The Python fallback must do what the Rust restore does: a config rewrite
    // does not move KGlobalAccel's live registration, so the recorded key codes
    // have to be replayed or the user's shortcuts stay dead until the next login
    // (the launcher's bare Meta and Meta+W were lost exactly that way).
    let script = read("scripts/restore_shortcuts.sh");
    assert!(
        script.contains("setForeignShortcut([group, key, group, label]"),
        "the fallback restore must re-arm the recorded actions"
    );
    assert!(
        script.contains("entry.get('keys')"),
        "the fallback restore must replay the journal's recorded key codes"
    );
    assert!(
        script.contains("data.get('displaced_actions'"),
        "displaced actions must be re-armed too"
    );
}

#[test]
fn run_sh_hands_back_a_previous_boots_claim_before_it_claims_the_desktop() {
    // The claim lives in files, so a machine switched off (or crashed) while the
    // shell ran never runs the exit trap. Without this step the next login starts
    // with the shell's keys still displaced and nothing to serve them, which is
    // how bare Meta, Meta+W and Meta+D stayed dead after the user's reboot.
    let run = read("run.sh");
    let release = run
        .find("plasma release-stale")
        .expect("run.sh must hand back a claim a previous boot left behind");
    let bind = run
        .find("bind_shortcuts.sh")
        .expect("run.sh binds the shortcuts");
    let claim = run
        .find("\"$DIR/bin/astral-plasma\" plasma disable")
        .expect("run.sh claims the panels");

    assert!(
        release < bind && release < claim,
        "the release has to run before anything is bound or claimed, or the new \
         claim is reverted by the old one's hand-back"
    );
}

#[test]
fn run_sh_hides_the_plasma_desktop_without_rewriting_it() {
    // Panels are hidden through the plasmashell service lifecycle (systemd stop,
    // or `hiding = windowscover` for a targeted panel). The applet configuration
    // is never rewritten and no containment is ever removed, so a crash can never
    // cost the user's pinned tasks, widgets or panel layout.
    let run = read("run.sh");
    assert!(
        run.contains("\"$DIR/bin/astral-plasma\" plasma disable"),
        "run.sh must hide Plasma through the daemon's non-destructive path"
    );
    for destructive in [
        "plasma-org.kde.plasma.desktop-appletsrc",
        "plasmashellrc",
        "rm -f \"$HOME/.config/plasma",
    ] {
        assert!(
            !run.contains(destructive),
            "run.sh must never touch the user's Plasma configuration directly ({destructive})"
        );
    }
}
