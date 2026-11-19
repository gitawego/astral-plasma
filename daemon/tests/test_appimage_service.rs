use astral_plasma::application::appimage_service::{
    install, status, uninstall, AppImageInstallOptions, AppImagePaths,
};
use astral_plasma::domain::install_record::{InstallMethod, InstallRecord};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

fn fixture(root: &Path) -> (AppImagePaths, PathBuf) {
    let payload = root
        .join("data")
        .join("astral-plasma")
        .join("app")
        .join("0.1.3");
    fs::create_dir_all(payload.join("usr/bin")).unwrap();
    fs::write(payload.join("AppRun"), "#!/bin/sh\nexit 0\n").unwrap();
    let binary = payload.join("usr/bin/astral-plasma");
    fs::write(&binary, "binary").unwrap();
    fs::set_permissions(&binary, fs::Permissions::from_mode(0o755)).unwrap();
    fs::write(payload.join("version"), "0.1.3\n").unwrap();
    (AppImagePaths::rooted_at(root), payload)
}

#[test]
fn installs_a_stable_wrapper_and_login_session() {
    let tmp = tempfile::tempdir().unwrap();
    let (paths, payload) = fixture(tmp.path());
    let options = AppImageInstallOptions::default();

    let installed = install(&payload, &paths, &options).unwrap();
    assert!(installed.installed);
    assert_eq!(installed.version, "0.1.3");
    assert!(installed.session_installed);
    assert!(!installed.service_installed);

    let wrapper = fs::read_to_string(&paths.wrapper).unwrap();
    assert!(wrapper.contains("ASTRAL_APPIMAGE_PAYLOAD"));
    assert!(wrapper.contains("ASTRAL_PLASMA_PACKAGE_DIR"));
    assert!(wrapper.contains(&paths.current.to_string_lossy().to_string()));
    assert!(fs::metadata(&paths.wrapper).unwrap().permissions().mode() & 0o111 != 0);

    let session = fs::read_to_string(&paths.session_file).unwrap();
    assert!(session.contains("Name=Astral Plasma (AppImage)"));
    assert!(session.contains(&paths.session_script.to_string_lossy().to_string()));
    assert!(paths.session_script.is_file());
    assert!(paths.package_dir.join("shell.qml").is_file());

    let record = InstallRecord::read(&paths.record_path).unwrap().unwrap();
    assert_eq!(record.method, InstallMethod::AppImage);
    assert_eq!(record.version, "0.1.3");

    // Reinstalling the same payload is idempotent.
    install(&payload, &paths, &options).unwrap();
    assert!(status(&paths).unwrap().installed);
}

#[test]
fn rejects_a_payload_outside_the_managed_app_directory() {
    let tmp = tempfile::tempdir().unwrap();
    let (paths, _) = fixture(tmp.path());
    let outside = tmp.path().join("Downloads/astral-plasma");
    fs::create_dir_all(outside.join("usr/bin")).unwrap();
    fs::write(outside.join("AppRun"), "#!/bin/sh\nexit 0\n").unwrap();
    fs::write(outside.join("usr/bin/astral-plasma"), "binary").unwrap();

    let error = install(&outside, &paths, &AppImageInstallOptions::default()).unwrap_err();
    assert!(error.to_string().contains("run the AppImage first"));
}

#[test]
fn refuses_to_replace_another_owner_without_force() {
    let tmp = tempfile::tempdir().unwrap();
    let (paths, payload) = fixture(tmp.path());
    fs::create_dir_all(paths.record_path.parent().unwrap()).unwrap();
    InstallRecord::new(InstallMethod::Package, "0.1.3", "stable", 1)
        .with_owner_package("astral-plasma-bin")
        .write(&paths.record_path)
        .unwrap();

    let error = install(&payload, &paths, &AppImageInstallOptions::default()).unwrap_err();
    assert!(error.to_string().contains("already has a package install"));

    let forced = AppImageInstallOptions {
        force: true,
        ..AppImageInstallOptions::default()
    };
    install(&payload, &paths, &forced).unwrap();
}

#[test]
fn uninstall_removes_the_payload_and_session_but_keeps_user_data() {
    let tmp = tempfile::tempdir().unwrap();
    let (paths, payload) = fixture(tmp.path());
    install(&payload, &paths, &AppImageInstallOptions::default()).unwrap();
    let settings = paths.data_dir.join("settings.json");
    fs::write(&settings, "{}").unwrap();

    let report = uninstall(&paths, false).unwrap();
    assert!(!paths.wrapper.exists());
    assert!(!paths.session_file.exists());
    assert!(!paths.record_path.exists());
    assert!(!paths.app_dir.exists());
    assert!(settings.exists(), "uninstall must keep user settings");
    assert!(report
        .removed
        .iter()
        .any(|path| path.ends_with("astral-plasma.desktop")));
}

#[test]
fn uninstall_refuses_a_foreign_install_without_force() {
    let tmp = tempfile::tempdir().unwrap();
    let (paths, _) = fixture(tmp.path());
    fs::create_dir_all(paths.record_path.parent().unwrap()).unwrap();
    InstallRecord::new(InstallMethod::Package, "0.1.3", "stable", 1)
        .write(&paths.record_path)
        .unwrap();

    let error = uninstall(&paths, false).unwrap_err();
    assert!(error.to_string().contains("not an AppImage"));
}
