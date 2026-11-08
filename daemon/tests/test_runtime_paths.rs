//! Runtime paths: one authority, and it must point at a file that exists.
//!
//! P1 moved the kernel into `modules/Astral/Kernel/`. Services derived the daemon as
//! `<their own directory>/../bin/astral-plasma`, which then resolved to a directory
//! that does not exist — so windows, tray, previews, clipboard and every other
//! daemon-backed surface went empty, silently (spec C.12). The suites were green
//! because nothing asserted the path.
//!
//! These tests assert the layout statically (no display needed) and the resolved
//! binary at the same relative depth, which is the invariant that broke.

use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

fn kernel_files() -> Vec<PathBuf> {
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else { return };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk(&path, out);
            } else if matches!(path.extension().and_then(|e| e.to_str()), Some("qml") | Some("js")) {
                out.push(path);
            }
        }
    }
    let mut files = Vec::new();
    walk(&repo_root().join("modules/Astral/Kernel"), &mut files);
    files
}

#[test]
fn no_kernel_file_derives_the_daemon_from_its_own_directory() {
    let mut offenders = Vec::new();
    for path in kernel_files() {
        let text = std::fs::read_to_string(&path).unwrap_or_default();
        if text.contains("\"/../bin") || text.contains("serviceDir + ") {
            offenders.push(path.display().to_string());
        }
    }
    assert!(
        offenders.is_empty(),
        "these files compute the daemon path from their own location again \
         (use Paths.daemonBin): {offenders:#?}"
    );
}

#[test]
fn paths_owns_the_daemon_and_the_depth_is_right() {
    let paths = std::fs::read_to_string(repo_root().join("modules/Astral/Kernel/config/Paths.qml"))
        .expect("Paths.qml exists");

    assert!(
        paths.contains("\"../../../..\""),
        "Paths resolves the tree root from modules/Astral/Kernel/config, i.e. four levels up"
    );
    assert!(
        paths.contains("/bin/astral-plasma"),
        "Paths names the daemon entry point"
    );

    // The same relative depth, resolved for real: this is what the shell will get.
    let root = repo_root().join("modules/Astral/Kernel/config");
    let resolved = root.join("../../../../bin/astral-plasma");
    assert!(
        resolved.is_file(),
        "{} must exist; if this fails, P1's move changed the depth and the shell has no daemon",
        resolved.display()
    );
}

#[test]
fn config_delegates_the_daemon_path() {
    let config = std::fs::read_to_string(repo_root().join("modules/Astral/Kernel/config/Config.qml"))
        .expect("Config.qml exists");
    assert!(
        config.contains("readonly property string daemonBin: Paths.daemonBin"),
        "Config.daemonBin must delegate to Paths, not compute a second path"
    );
    assert!(
        !config.contains("bin/astral-plasma\").toString()"),
        "Config must not resolve the binary itself"
    );
}

#[test]
fn every_daemon_path_property_delegates_to_paths() {
    // Any file that *defines* a daemon path must take it from Paths. A bare mention of
    // the string "astral-plasma" is not enough to judge: `~/.config/astral-plasma` is
    // a directory name, not the binary.
    let mut declarations = 0;
    for path in kernel_files() {
        let text = std::fs::read_to_string(&path).unwrap_or_default();
        if path.file_name().and_then(|n| n.to_str()) == Some("Paths.qml") {
            continue;
        }
        if !text.contains("property string daemonBin") {
            continue;
        }
        // A data holder (`ShellState`) carries the value the shell fills; it resolves
        // nothing, so it is not a second authority.
        if text.contains("property string daemonBin: \"\"") {
            continue;
        }
        declarations += 1;
        assert!(
            text.contains("Paths.daemonBin"),
            "{} defines a daemon path but does not take it from Paths",
            path.display()
        );
    }
    assert!(
        declarations >= 10,
        "expected the kernel services to define daemonBin (found {declarations})"
    );
}
