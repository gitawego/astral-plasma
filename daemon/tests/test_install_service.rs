//! Installing must produce exactly the layout the updater expects, and must
//! never touch the two things a reinstall is most likely to destroy: the user's
//! settings and the running executable.

use astral_plasma::application::install_service::{install, InstallPaths};
use astral_plasma::domain::branding;
use astral_plasma::domain::install_record::{InstallMethod, InstallRecord};
use std::fs;
use std::os::unix::fs::PermissionsExt;

fn fake_exe(root: &std::path::Path) -> std::path::PathBuf {
    let exe = root.join("downloaded/astral-plasma");
    fs::create_dir_all(exe.parent().unwrap()).unwrap();
    fs::write(&exe, b"#!/bin/sh\nexit 0\n").unwrap();
    fs::set_permissions(&exe, fs::Permissions::from_mode(0o755)).unwrap();
    exe
}

#[test]
fn a_managed_install_writes_binary_bundle_and_record() {
    let root = tempfile::tempdir().unwrap();
    let paths = InstallPaths::rooted_at(root.path());
    let exe = fake_exe(root.path());

    let outcome = install(InstallMethod::Managed, "stable", None, &exe, &paths).unwrap();
    assert!(outcome.binary_copied);

    assert!(paths.bin_path.is_file(), "the unit execs the installed binary");
    let mode = fs::metadata(&paths.bin_path).unwrap().permissions().mode();
    assert_eq!(mode & 0o777, 0o755, "an installed binary must be executable");

    assert!(
        paths.package_dir.join("shell.qml").is_file(),
        "the bundle must be extracted where the shell loads it from"
    );
    assert!(
        paths.package_dir.join("modules/Astral/Kernel/theme/Theme.qml").is_file(),
        "the whole QML tree must be present, not only the entry point"
    );

    let record = InstallRecord::read(&paths.record_path).unwrap().unwrap();
    assert_eq!(record.method, InstallMethod::Managed);
    assert_eq!(record.version, env!("CARGO_PKG_VERSION"));
    assert_eq!(record.channel, "stable");
}

#[test]
fn reinstalling_from_the_installed_binary_never_truncates_it() {
    let root = tempfile::tempdir().unwrap();
    let paths = InstallPaths::rooted_at(root.path());
    let exe = fake_exe(root.path());
    install(InstallMethod::Managed, "stable", None, &exe, &paths).unwrap();

    // Re-running from the installed path itself: copying a file onto itself
    // truncates it, which would leave an empty shell binary on disk.
    let before = fs::read(&paths.bin_path).unwrap();
    let outcome = install(InstallMethod::Managed, "stable", None, &paths.bin_path, &paths).unwrap();
    assert!(!outcome.binary_copied, "the install must recognise its own binary");
    assert_eq!(fs::read(&paths.bin_path).unwrap(), before);
}

#[test]
fn a_package_install_records_its_owner_and_keeps_it_across_a_reinstall() {
    let root = tempfile::tempdir().unwrap();
    let paths = InstallPaths::rooted_at(root.path());
    let exe = fake_exe(root.path());

    install(
        InstallMethod::Package,
        "stable",
        Some("astral-plasma-bin"),
        &exe,
        &paths,
    )
    .unwrap();

    let record = InstallRecord::read(&paths.record_path).unwrap().unwrap();
    assert_eq!(record.method, InstallMethod::Package);
    assert_eq!(record.owner_package.as_deref(), Some("astral-plasma-bin"));
    assert!(!record.method.is_self_updatable());
}

#[test]
fn an_install_never_writes_outside_its_data_directory() {
    let root = tempfile::tempdir().unwrap();
    let paths = InstallPaths::rooted_at(root.path());
    let exe = fake_exe(root.path());

    // A settings file that predates the install.
    let config = root.path().join("config").join(branding::APP_ID);
    fs::create_dir_all(&config).unwrap();
    let settings = config.join("settings.json");
    fs::write(&settings, r#"{"theme":{"blurStrength":0.7}}"#).unwrap();

    install(InstallMethod::Managed, "stable", None, &exe, &paths).unwrap();

    assert_eq!(
        fs::read_to_string(&settings).unwrap(),
        r#"{"theme":{"blurStrength":0.7}}"#,
        "an install must never rewrite user settings"
    );
    assert!(
        !root.path().join("config").join("quickshell").exists(),
        "the managed layout is self-contained: no symlink into the user's config tree"
    );
}
