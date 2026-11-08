//! Removal must be complete where it is ours and inert where it is not.

use astral_plasma::application::install_service::{install, InstallPaths};
use astral_plasma::application::uninstall_service::{uninstall, UninstallPaths};
use astral_plasma::domain::branding;
use astral_plasma::domain::install_record::{InstallMethod, InstallRecord};
use std::fs;
use std::os::unix::fs::symlink;

fn install_fixture(root: &std::path::Path) -> (InstallPaths, UninstallPaths) {
    let install_paths = InstallPaths::rooted_at(root);
    let uninstall_paths = UninstallPaths::rooted_at(root);

    let exe = root.join("source/astral-plasma");
    fs::create_dir_all(exe.parent().unwrap()).unwrap();
    fs::write(&exe, b"#!/bin/sh\n").unwrap();
    install(
        InstallMethod::Managed,
        "stable",
        None,
        &exe,
        &install_paths,
    )
    .unwrap();

    // Unit + desktop integration + state, as a real install would have.
    fs::create_dir_all(&uninstall_paths.systemd_dir).unwrap();
    fs::write(
        uninstall_paths.systemd_dir.join(branding::SYSTEMD_UNIT),
        "[Service]\nExecStart=/x run\n",
    )
    .unwrap();
    fs::create_dir_all(&uninstall_paths.applications_dir).unwrap();
    fs::write(
        uninstall_paths.applications_dir.join("astral-launcher.desktop"),
        "[Desktop Entry]\n",
    )
    .unwrap();
    fs::create_dir_all(&uninstall_paths.wayland_sessions_dir).unwrap();
    fs::write(
        uninstall_paths.wayland_sessions_dir.join("astral-plasma.desktop"),
        "[Desktop Entry]\n",
    )
    .unwrap();
    fs::create_dir_all(&uninstall_paths.state_dir).unwrap();
    fs::write(uninstall_paths.state_dir.join("update.log"), "log").unwrap();
    fs::create_dir_all(&uninstall_paths.cache_dir).unwrap();
    fs::write(uninstall_paths.cache_dir.join("cache"), "x").unwrap();
    fs::create_dir_all(&uninstall_paths.config_dir).unwrap();
    fs::write(uninstall_paths.config_dir.join("settings.json"), "{}").unwrap();

    fs::create_dir_all(&uninstall_paths.bin_home).unwrap();
    symlink(
        &install_paths.bin_path,
        uninstall_paths.bin_home.join(branding::BIN_FILE),
    )
    .unwrap();

    (install_paths, uninstall_paths)
}

#[test]
fn an_uninstall_removes_what_it_installed_and_keeps_settings() {
    let root = tempfile::tempdir().unwrap();
    let (install_paths, paths) = install_fixture(root.path());

    let report = uninstall(&paths, true, false).unwrap();

    assert!(!install_paths.data_dir.exists(), "the managed layout must go");
    assert!(!install_paths.bin_path.exists());
    assert!(!paths.state_dir.exists(), "migration markers and logs are this install's");
    assert!(
        paths.cache_dir.exists(),
        "a cache is not the install: voice models and quota snapshots are expensive to \
         re-download, so they survive unless --purge is asked for"
    );
    assert!(
        !paths.systemd_dir.join(branding::SYSTEMD_UNIT).exists(),
        "a unit left behind would exec a binary that no longer exists"
    );
    assert!(!paths.applications_dir.join("astral-launcher.desktop").exists());
    assert!(!paths.wayland_sessions_dir.join("astral-plasma.desktop").exists());
    assert!(
        !paths.bin_home.join(branding::BIN_FILE).exists(),
        "a dangling symlink on PATH is worse than no command"
    );

    assert!(
        paths.config_dir.join("settings.json").is_file(),
        "settings survive an uninstall unless --purge was asked for"
    );
    assert!(!report.settings_removed);
    assert!(
        report
            .kept
            .iter()
            .any(|k| k.contains("config") && k.contains("--purge")),
        "the report must tell the user their settings were kept: {:?}",
        report.kept
    );
    assert!(report.removed.iter().any(|r| r.contains("package")), "{:?}", report.removed);
}

#[test]
fn purge_removes_settings_and_caches_too() {
    let root = tempfile::tempdir().unwrap();
    let (_, paths) = install_fixture(root.path());

    let report = uninstall(&paths, false, false).unwrap();
    assert!(!paths.config_dir.exists());
    assert!(!paths.cache_dir.exists());
    assert!(report.settings_removed);
}

#[test]
fn user_data_inside_the_data_directory_survives() {
    let root = tempfile::tempdir().unwrap();
    let (install_paths, paths) = install_fixture(root.path());

    // Things an install did not create, stored beside it: the AI harness's
    // sessions, and the panel/shortcut backups that must outlive the shell.
    let assistant = install_paths.data_dir.join("assistant/sessions");
    fs::create_dir_all(&assistant).unwrap();
    fs::write(assistant.join("session.json"), "{}").unwrap();
    let plasma_backup = install_paths.data_dir.join(branding::PLASMA_BACKUP_SUBDIR);
    fs::create_dir_all(&plasma_backup).unwrap();
    fs::write(plasma_backup.join("plasmarc"), "panels").unwrap();
    let downloads = paths.state_dir.join("downloads");
    fs::create_dir_all(&downloads).unwrap();
    fs::write(downloads.join("task.json"), "{}").unwrap();

    let report = uninstall(&paths, true, false).unwrap();

    assert!(
        assistant.join("session.json").is_file(),
        "an uninstall must not delete the user's AI sessions"
    );
    assert!(
        plasma_backup.join("plasmarc").is_file(),
        "the Plasma backup is the user's way back; removing it would be data loss"
    );
    assert!(
        downloads.join("task.json").is_file(),
        "download history is user data, not install state"
    );
    assert!(
        !install_paths.data_dir.join("package").exists(),
        "the bundle is ours to remove"
    );
    assert!(report.kept.iter().any(|k| k.contains("--purge")), "{:?}", report.kept);
}

#[test]
fn a_package_owned_install_is_refused_and_names_the_right_command() {
    let root = tempfile::tempdir().unwrap();
    let (install_paths, paths) = install_fixture(root.path());
    InstallRecord::new(InstallMethod::Package, "0.1.3", "stable", 1)
        .with_owner_package("astral-plasma-bin")
        .write(&install_paths.record_path)
        .unwrap();

    let err = uninstall(&paths, true, false).expect_err("pacman owns these files");
    assert!(err.to_string().contains("pacman -Rns astral-plasma-bin"), "{err}");
    assert!(
        install_paths.bin_path.exists(),
        "a refused uninstall must not remove anything"
    );

    // --force is the escape hatch for a genuinely stuck package install.
    uninstall(&paths, true, true).unwrap();
    assert!(!install_paths.bin_path.exists());
}

#[test]
fn a_foreign_symlink_on_path_is_reported_not_deleted() {
    let root = tempfile::tempdir().unwrap();
    let (_, paths) = install_fixture(root.path());
    let foreign = root.path().join("elsewhere/astral-plasma");
    fs::create_dir_all(foreign.parent().unwrap()).unwrap();
    fs::write(&foreign, b"#!/bin/sh\n").unwrap();
    let link = paths.bin_home.join(branding::BIN_FILE);
    fs::remove_file(&link).unwrap();
    symlink(&foreign, &link).unwrap();

    let report = uninstall(&paths, true, false).unwrap();
    assert!(link.exists(), "someone else's binary must not be removed");
    assert!(
        report.kept.iter().any(|k| k.contains("points at")),
        "{:?}",
        report.kept
    );
}

#[test]
fn the_users_own_quickshell_config_is_never_removed() {
    let root = tempfile::tempdir().unwrap();
    let (_, paths) = install_fixture(root.path());
    fs::create_dir_all(&paths.quickshell_link).unwrap();
    fs::write(paths.quickshell_link.join("shell.qml"), "// mine").unwrap();

    let report = uninstall(&paths, false, false).unwrap();
    assert!(
        paths.quickshell_link.join("shell.qml").is_file(),
        "~/.config/quickshell is a user config path, not an Astral artifact"
    );
    assert!(report.kept.iter().any(|k| k.contains("config path you own")));
}
