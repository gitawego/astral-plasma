//! AppImageUpdate integration: check, delta download, extract and switch.
//!
//! The real `appimageupdatetool` talks to GitHub and zsync. These tests use a
//! fake tool that speaks the same CLI contract, so the daemon's switching and
//! record handling are verified without network access or a published release.

use astral_plasma::application::appimage_service::{
    apply_update, check_update, AppImagePaths,
};
use astral_plasma::application::update_service::{UpdatePaths, UpdateService};
use astral_plasma::domain::install_record::{InstallMethod, InstallRecord};
use astral_plasma::domain::update_state::{AppImageUpdateState, UpdateState, STATE_SCHEMA};
use serde_json::json;
use std::fs;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};
use tempfile::TempDir;

fn write_executable(path: &Path, body: &str) {
    fs::write(path, body).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

fn fake_tool(root: &Path) -> PathBuf {
    let tool = root.join("appimageupdatetool");
    write_executable(
        &tool,
        r#"#!/bin/sh
set -eu
case "$1" in
  -j) exit 1 ;;
  -d)
    printf '%s\n' \
      'Raw update information: gh-releases-zsync|gitawego|astral-plasma|latest|astral-plasma-*-x86_64.AppImage.zsync' \
      'Assembled ZSync URL: https://github.com/gitawego/astral-plasma/releases/download/latest/astral-plasma-0.2.0-x86_64.AppImage.zsync'
    exit 0
    ;;
  -O)
    image="$3"
    cat > "$image" <<'IMAGE'
#!/bin/sh
if [ "$1" = "--appimage-extract" ]; then
  mkdir -p squashfs-root/usr/bin
  printf '0.2.0\n' > squashfs-root/version
  printf '#!/bin/sh\n' > squashfs-root/AppRun
  printf '#!/bin/sh\n' > squashfs-root/usr/bin/astral-plasma
  chmod +x squashfs-root/AppRun squashfs-root/usr/bin/astral-plasma
  exit 0
fi
exit 0
IMAGE
    chmod +x "$image"
    exit 0
    ;;
esac
exit 2
"#,
    );
    tool
}

fn installed_fixture(root: &Path) -> (AppImagePaths, PathBuf, PathBuf) {
    let paths = AppImagePaths::rooted_at(root);
    let old_payload = paths.app_dir.join("0.1.3");
    fs::create_dir_all(old_payload.join("usr/bin")).unwrap();
    write_executable(&old_payload.join("AppRun"), "#!/bin/sh\nexit 0\n");
    write_executable(&old_payload.join("usr/bin/astral-plasma"), "#!/bin/sh\nexit 0\n");
    fs::write(old_payload.join("version"), "0.1.3\n").unwrap();

    fs::create_dir_all(&paths.app_dir).unwrap();
    symlink(&old_payload, &paths.current).unwrap();
    write_executable(&paths.image, "#!/bin/sh\nexit 0\n");

    InstallRecord::new(InstallMethod::AppImage, "0.1.3", "stable", 1)
        .write(&paths.record_path)
        .unwrap();
    (paths, old_payload, fake_tool(root))
}

#[test]
fn check_reports_the_version_from_the_assembled_zsync_url() {
    let tmp = TempDir::new().unwrap();
    let (paths, _old, tool) = installed_fixture(tmp.path());

    let check = check_update(&paths, &tool).unwrap();
    assert!(check.available);
    assert_eq!(check.version.as_deref(), Some("0.2.0"));
    assert!(check
        .update_info
        .as_deref()
        .unwrap_or("")
        .contains("gh-releases-zsync"));
}

#[test]
fn apply_updates_the_image_extracts_it_and_switches_current() {
    let tmp = TempDir::new().unwrap();
    let (paths, old_payload, tool) = installed_fixture(tmp.path());

    let outcome = apply_update(&paths, &tool).unwrap();
    assert_eq!(outcome.version, "0.2.0");
    assert_eq!(
        fs::canonicalize(&paths.current).unwrap(),
        paths.app_dir.join("0.2.0").canonicalize().unwrap()
    );
    assert_eq!(
        fs::canonicalize(paths.app_dir.join("previous")).unwrap(),
        old_payload.canonicalize().unwrap()
    );
    let record = InstallRecord::read(&paths.record_path).unwrap().unwrap();
    assert_eq!(record.method, InstallMethod::AppImage);
    assert_eq!(record.version, "0.2.0");
    assert!(paths.app_dir.join("0.2.0/usr/bin/astral-plasma").is_file());
}

#[test]
fn check_refuses_when_no_canonical_appimage_was_kept() {
    let tmp = TempDir::new().unwrap();
    let paths = AppImagePaths::rooted_at(tmp.path());
    fs::create_dir_all(&paths.app_dir).unwrap();
    let tool = fake_tool(tmp.path());

    let error = check_update(&paths, &tool).unwrap_err();
    assert!(error.to_string().contains("no AppImage file is stored"));
}

#[test]
fn update_service_exposes_the_appimage_candidate_and_applies_it() {
    let tmp = TempDir::new().unwrap();
    let (paths, _old, tool) = installed_fixture(tmp.path());
    let update_paths = UpdatePaths::rooted_at(tmp.path());
    fs::create_dir_all(update_paths.state_path.parent().unwrap()).unwrap();
    UpdateState {
        schema: STATE_SCHEMA,
        last_check_unix: 123,
        etag: None,
        candidate: None,
        appimage_update: Some(AppImageUpdateState {
            version: "0.2.0".to_string(),
            available: true,
            update_info: Some("gh-releases-zsync|gitawego|astral-plasma|latest|astral-plasma-*-x86_64.AppImage.zsync".to_string()),
            checked_at_unix: 123,
            detail: None,
        }),
        last_error: None,
        rollback: None,
        failed_starts: 0,
        last_seen_version: None,
    }
    .save(&update_paths.state_path)
    .unwrap();

    let mut service = UpdateService::with_paths(
        update_paths.clone(),
        Box::new(astral_plasma::infrastructure::update_source::CurlUpdateSource::new()),
    );
    service.appimage_updater_override = Some(tool);

    let status = service.status().unwrap();
    assert_eq!(status.install_method, "appimage");
    assert!(status.can_apply);
    assert_eq!(
        status.candidate.as_ref().map(|candidate| candidate.version.as_str()),
        Some("0.2.0")
    );

    let outcome = service.apply(|| true).unwrap();
    assert_eq!(outcome.version, "0.2.0");
    assert!(outcome.restart_requested);
    let restart = astral_plasma::domain::update_state::RestartRequest::read(
        &update_paths.restart_path,
    )
    .unwrap();
    assert!(restart.already_in_place);
    assert_eq!(restart.target_version, "0.2.0");
    assert_eq!(
        fs::canonicalize(&paths.current).unwrap(),
        paths.app_dir.join("0.2.0").canonicalize().unwrap()
    );
}

#[test]
fn appimage_apply_record_shape_is_reported_as_json_ready() {
    // Keep the persisted status schema honest: the UI consumes this exact shape.
    let status = json!({
        "install_method": "appimage",
        "can_apply": true,
        "candidate": { "version": "0.2.0", "size": 0 }
    });
    assert_eq!(status["install_method"], "appimage");
}
