//! Product identity: canonical values and a repo-wide guard that keeps any
//! other name from creeping into code, scripts or documentation.

use astral_plasma::application::watch_events::{get_focus_restore_script, get_kwin_watcher_script};
use astral_plasma::domain::branding;
use std::path::{Path, PathBuf};

#[test]
fn canonical_paths_and_temporary_names_are_derived_from_one_identity() {
    assert_eq!(branding::APP_ID, "astral-plasma");
    assert!(branding::data_dir().ends_with(branding::DATA_DIR));
    assert!(branding::cache_dir().ends_with(branding::CACHE_DIR));
    assert!(branding::state_dir().ends_with(branding::STATE_DIR));
    assert!(branding::default_package_dir().ends_with(branding::PACKAGE_SUBDIR));

    let tmp = branding::tmp_file("kwin_query.js");
    assert_eq!(
        tmp.file_name().unwrap().to_string_lossy(),
        "astral_plasma_kwin_query.js"
    );
    assert!(branding::art_cache_dir().to_string_lossy().contains(branding::TMP_PREFIX));
}

#[test]
fn every_shell_identifier_is_astral_branded() {
    for value in [
        branding::APP_NAME,
        branding::DBUS_PREFIX,
        branding::DBUS_WATCHER_NAME,
        branding::WINDOW_CLASS,
        branding::WINDOW_CLASS_SETTINGS,
        branding::DATA_DIR,
        branding::CACHE_DIR,
        branding::STATE_DIR,
        branding::SYSTEMD_UNIT,
        branding::SYSTEMD_DESCRIPTION,
        branding::KWIN_SCRIPT_SHORTCUTS,
        branding::KWIN_SCRIPT_WATCHER,
        branding::KWIN_SHORTCUTS_ENABLED_KEY,
        branding::SHORTCUT_LAUNCHER_KEY,
        branding::SHORTCUT_WALLPAPER_KEY,
        branding::SHORTCUT_LAUNCHER_LABEL,
        branding::SHORTCUT_WALLPAPER_LABEL,
        branding::LAYER_NAMESPACE_WALLPAPER,
        branding::ENV_TEST_MODE,
        branding::ENV_PACKAGE_DIR,
        branding::ENV_THEME_DIR,
        branding::ENV_SYSTEMD_DIR,
        branding::ENV_PLASMA_BACKUP_DIR,
        branding::ENV_SHORTCUTS_BACKUP_DIR,
        branding::ENV_LAUNCHER_OPEN,
        branding::ENV_LAUNCHER_MODE,
        branding::ENV_DASHBOARD_OPEN,
        branding::ENV_SETTINGS_OPEN,
        branding::ENV_SETTINGS_PAGE,
    ] {
        assert!(
            value.to_lowercase().contains("astral"),
            "identifier {value:?} is not Astral-branded"
        );
    }
}

#[test]
fn dbus_interface_name_matches_the_branding_constant() {
    use astral_plasma::application::watch_events::WatcherService;
    use zbus::object_server::Interface;

    let interface = <WatcherService as Interface>::name().to_string();
    assert_eq!(
        interface,
        branding::DBUS_WATCHER_NAME,
        "the #[zbus::interface] attribute cannot use a const, so this keeps it honest"
    );
    assert!(branding::DBUS_WATCHER_NAME.starts_with(branding::DBUS_PREFIX));
    assert_eq!(branding::DBUS_WATCHER_PATH, "/Watcher");
}

#[test]
fn generated_kwin_scripts_use_the_canonical_identifiers() {
    let watcher = get_kwin_watcher_script();
    assert!(watcher.contains(branding::DBUS_WATCHER_NAME));
    for class in astral_plasma::domain::app_identity::SHELL_WINDOW_CLASSES {
        assert!(watcher.contains(class), "watcher script missing {class}");
    }
    assert!(
        !watcher.contains("@DBUS_WATCHER_NAME@") && !watcher.contains("@SHELL_WINDOW_CLASSES@"),
        "unsubstituted token left in the generated script"
    );

    let focus = get_focus_restore_script();
    for class in astral_plasma::domain::app_identity::SHELL_WINDOW_CLASSES {
        assert!(focus.contains(class), "focus script missing {class}");
    }
    assert!(focus.contains("ASTRAL_PLASMA_FOCUS_RESTORED"));
}

/// The rename is only complete if no other name can silently return. This walks
/// the repository and fails on any occurrence other than the upstream
/// attribution link (`caelestia-dots/shell`) and this test's own search needle.
#[test]
fn repository_contains_no_stray_foreign_branding() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf();

    // The guard itself must name what it searches for.
    let allowed_files: [&str; 1] = ["daemon/tests/test_branding.rs"];

    let mut offenders: Vec<String> = Vec::new();
    walk(&root, &root, &allowed_files, &mut offenders);

    assert!(
        offenders.is_empty(),
        "foreign branding leaked into:\n{}",
        offenders.join("\n")
    );
}

const TEXT_EXTENSIONS: [&str; 16] = [
    "rs", "qml", "js", "sh", "py", "json", "jsonc", "toml", "md", "desktop", "ini", "conf", "yaml",
    "yml", "css", "txt",
];

fn walk(dir: &Path, root: &Path, allowed: &[&str], offenders: &mut Vec<String>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if path.is_dir() {
            if matches!(name.as_str(), ".git" | "target" | "bin" | "node_modules") {
                continue;
            }
            walk(&path, root, allowed, offenders);
            continue;
        }

        let rel = path
            .strip_prefix(root)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();
        if allowed.contains(&rel.as_str()) {
            continue;
        }

        let is_makefile = name == "Makefile";
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or_default()
            .to_lowercase();
        if !is_makefile && !TEXT_EXTENSIONS.contains(&ext.as_str()) {
            continue;
        }

        let Ok(content) = std::fs::read_to_string(&path) else {
            continue;
        };
        for (number, line) in content.lines().enumerate() {
            if !line.to_lowercase().contains("caelestia") {
                continue;
            }
            // Upstream attribution is the one legitimate mention: the design
            // lineage credits the caelestia-dots/shell project by name.
            if line.contains("caelestia-dots") {
                continue;
            }
            offenders.push(format!("{rel}:{}: {}", number + 1, line.trim()));
        }
    }
}
