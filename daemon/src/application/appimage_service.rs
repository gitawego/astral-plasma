//! AppImage payload installation.
//!
//! An AppImage is a single immutable file that mounts its own payload. Running
//! the shell from that mount would give every launch a new `/tmp/.mount_*`
//! path, which breaks KWin screenshot authorization, `quickshell -p` IPC and
//! global-shortcut ownership. The AppImage therefore copies its payload into a
//! stable, versioned directory and installs a wrapper that always resolves the
//! stable `current` link.
//!
//! This service owns the AppImage-specific parts: the wrapper, the login
//! session entry, and the install record. The QML bundle still comes from the
//! binary itself, so a managed install and an AppImage install cannot disagree
//! about what shell code is running.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::domain::branding;
use crate::domain::install_record::{InstallMethod, InstallRecord};
use crate::domain::ports::DynResult;
use crate::domain::systemd::generate_unit_file_content;
use crate::infrastructure::embedded_bundle::extract_embedded_theme;

const SESSION_FILE: &str = "astral-plasma.desktop";
const SESSION_SCRIPT: &str = "astral-plasma-session";
const SESSION_NAME: &str = "Astral Plasma (AppImage)";

#[derive(Debug, Clone)]
pub struct AppImagePaths {
    pub data_dir: PathBuf,
    pub app_dir: PathBuf,
    pub current: PathBuf,
    pub wrapper: PathBuf,
    pub package_dir: PathBuf,
    pub record_path: PathBuf,
    pub session_file: PathBuf,
    pub session_script: PathBuf,
    pub applications_dir: PathBuf,
    pub systemd_unit: PathBuf,
}

impl AppImagePaths {
    pub fn for_user() -> Self {
        let data_dir = branding::data_dir();
        let app_dir = data_dir.join("app");
        let session_dir = branding::data_home().join("wayland-sessions");
        let bin_home = branding::home_dir().join(".local").join("bin");
        Self {
            app_dir: app_dir.clone(),
            current: app_dir.join("current"),
            wrapper: data_dir.join(branding::BIN_SUBDIR).join(branding::BIN_FILE),
            package_dir: data_dir.join(branding::PACKAGE_SUBDIR),
            record_path: data_dir.join(branding::INSTALL_RECORD_FILE),
            session_file: session_dir.join(SESSION_FILE),
            session_script: bin_home.join(SESSION_SCRIPT),
            applications_dir: branding::applications_dir(),
            systemd_unit: branding::config_home()
                .join("systemd")
                .join("user")
                .join(branding::SYSTEMD_UNIT),
            data_dir,
        }
    }

    pub fn rooted_at(root: &Path) -> Self {
        let data_dir = root.join("data").join(branding::DATA_DIR);
        let app_dir = data_dir.join("app");
        Self {
            app_dir: app_dir.clone(),
            current: app_dir.join("current"),
            wrapper: data_dir.join(branding::BIN_SUBDIR).join(branding::BIN_FILE),
            package_dir: data_dir.join(branding::PACKAGE_SUBDIR),
            record_path: data_dir.join(branding::INSTALL_RECORD_FILE),
            session_file: root
                .join("data")
                .join("wayland-sessions")
                .join(SESSION_FILE),
            session_script: root.join("home").join(".local").join("bin").join(SESSION_SCRIPT),
            applications_dir: root.join("data").join("applications"),
            systemd_unit: root
                .join("config")
                .join("systemd")
                .join("user")
                .join(branding::SYSTEMD_UNIT),
            data_dir,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppImageStatus {
    pub installed: bool,
    pub version: String,
    pub payload: String,
    pub wrapper: String,
    pub session_installed: bool,
    pub service_installed: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppImageUninstallReport {
    pub removed: Vec<String>,
    pub kept: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct AppImageInstallOptions {
    pub install_session: bool,
    pub install_service: bool,
    pub force: bool,
}

impl Default for AppImageInstallOptions {
    fn default() -> Self {
        Self {
            install_session: true,
            install_service: false,
            force: false,
        }
    }
}

/// Install the stable wrapper, QML bundle, record and login session.
pub fn install(
    payload: &Path,
    paths: &AppImagePaths,
    options: &AppImageInstallOptions,
) -> DynResult<AppImageStatus> {
    let payload = payload.canonicalize()?;
    ensure_payload(&payload, &paths.app_dir)?;

    if let Some(existing) = InstallRecord::read(&paths.record_path)? {
        if existing.method != InstallMethod::AppImage && !options.force {
            return Err(format!(
                "this user already has a {} install; uninstall it before installing the AppImage",
                existing.method.as_str()
            )
            .into());
        }
    }

    let version = payload
        .join("version")
        .is_file()
        .then(|| fs::read_to_string(payload.join("version")).ok())
        .flatten()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string());

    fs::create_dir_all(paths.wrapper.parent().unwrap_or(&paths.data_dir))?;
    fs::create_dir_all(&paths.package_dir)?;
    fs::create_dir_all(paths.session_file.parent().unwrap_or(&paths.data_dir))?;
    fs::create_dir_all(paths.session_script.parent().unwrap_or(&paths.data_dir))?;
    fs::create_dir_all(&paths.applications_dir)?;

    if !paths.current.exists() {
        std::os::unix::fs::symlink(&payload, &paths.current)?;
    }

    write_executable(&paths.wrapper, &wrapper_script(paths))?;
    write_executable(&paths.session_script, &session_script(&paths.wrapper))?;

    extract_embedded_theme(&paths.package_dir)?;

    let record = InstallRecord::new(
        InstallMethod::AppImage,
        version.clone(),
        "stable",
        crate::domain::install_record::now_unix(),
    );
    record.write(&paths.record_path)?;

    if options.install_session {
        write_session_entry(paths)?;
    } else {
        remove_if_exists(&paths.session_file)?;
    }

    if options.install_service {
        let unit = generate_unit_file_content(
            &paths.wrapper.to_string_lossy(),
            &paths.package_dir.to_string_lossy(),
        );
        write_file(&paths.systemd_unit, unit.as_bytes())?;
        if !branding::test_mode() {
            let _ = std::process::Command::new("systemctl")
                .args(["--user", "daemon-reload"])
                .status();
            let _ = std::process::Command::new("systemctl")
                .args(["--user", "enable", branding::SYSTEMD_UNIT])
                .status();
        }
    } else {
        remove_if_exists(&paths.systemd_unit)?;
    }

    status(paths)
}

pub fn status(paths: &AppImagePaths) -> DynResult<AppImageStatus> {
    let record = InstallRecord::read(&paths.record_path)?
        .filter(|record| record.method == InstallMethod::AppImage);
    let payload = paths
        .current
        .canonicalize()
        .or_else(|_| paths.app_dir.canonicalize())
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_default();
    Ok(AppImageStatus {
        installed: record.is_some() && paths.wrapper.is_file(),
        version: record.map(|record| record.version).unwrap_or_default(),
        payload,
        wrapper: paths.wrapper.to_string_lossy().to_string(),
        session_installed: paths.session_file.is_file() && paths.session_script.is_file(),
        service_installed: paths.systemd_unit.is_file(),
    })
}

/// Remove the AppImage wrapper, login session, unit, payloads and record.
/// Settings, cache and user data are deliberately kept.
pub fn uninstall(
    paths: &AppImagePaths,
    force: bool,
) -> DynResult<AppImageUninstallReport> {
    let record = InstallRecord::read(&paths.record_path)?;
    if let Some(record) = &record {
        if record.method != InstallMethod::AppImage && !force {
            return Err(format!(
                "this is a {} install, not an AppImage; refusing to remove it",
                record.method.as_str()
            )
            .into());
        }
    }

    let mut report = AppImageUninstallReport::default();
    let had_unit = paths.systemd_unit.is_file();
    remove_file(&paths.session_file, &mut report)?;
    remove_file(&paths.session_script, &mut report)?;
    remove_file(&paths.systemd_unit, &mut report)?;
    remove_file(&paths.wrapper, &mut report)?;
    remove_file(&paths.record_path, &mut report)?;
    remove_dir(&paths.package_dir, &mut report)?;
    remove_dir(&paths.data_dir.join(branding::STAGED_PACKAGE_SUBDIR), &mut report)?;
    remove_dir(
        &paths.data_dir.join(format!(
            "{}{}",
            branding::PACKAGE_SUBDIR,
            branding::PREV_SUFFIX
        )),
        &mut report,
    )?;
    remove_dir(&paths.app_dir, &mut report)?;

    if had_unit && !branding::test_mode() {
        let _ = std::process::Command::new("systemctl")
            .args(["--user", "daemon-reload"])
            .status();
    }

    for path in [&paths.data_dir, &paths.applications_dir] {
        if path.exists() && path.read_dir().map(|mut d| d.next().is_none()).unwrap_or(false) {
            let _ = fs::remove_dir(path);
        }
    }
    for path in [&paths.session_file, &paths.session_script] {
        if path.exists() {
            report
                .kept
                .push(format!("{} (still present)", path.display()));
        }
    }
    Ok(report)
}

fn ensure_payload(payload: &Path, app_dir: &Path) -> DynResult<()> {
    if !payload.starts_with(app_dir) {
        return Err(format!(
            "AppImage payload {} is not under {}; run the AppImage first so it can extract itself",
            payload.display(),
            app_dir.display()
        )
        .into());
    }
    if !payload.join("AppRun").is_file() {
        return Err(format!("{} does not contain AppRun", payload.display()).into());
    }
    if !payload.join("usr/bin/astral-plasma").is_file() {
        return Err(format!(
            "{} does not contain usr/bin/astral-plasma",
            payload.display()
        )
        .into());
    }
    Ok(())
}

fn wrapper_script(paths: &AppImagePaths) -> String {
    format!(
        r#"#!/bin/sh
# Generated by `astral-plasma appimage install`; edits are overwritten.
set -eu
DEFAULT_ROOT={current}
ROOT="${{ASTRAL_APPIMAGE_PAYLOAD:-$DEFAULT_ROOT}}"
if [ ! -x "$ROOT/AppRun" ]; then
    echo "Astral Plasma payload is missing: $ROOT" >&2
    exit 1
fi
export ASTRAL_APPIMAGE_PAYLOAD="$ROOT"
export ASTRAL_PLASMA_PACKAGE_DIR={package}
export ASTRAL_PLASMA_THEME_DIR={package}
export ASTRAL_PLASMA_BIN_PATH={wrapper}
export ASTRAL_PLASMA_DAEMON="$ROOT/usr/bin/astral-plasma"
exec "$ROOT/AppRun" "$@"
"#,
        current = shell_quote(&paths.current.to_string_lossy()),
        package = shell_quote(&paths.package_dir.to_string_lossy()),
        wrapper = shell_quote(&paths.wrapper.to_string_lossy()),
    )
}

fn session_script(wrapper: &Path) -> String {
    let wrapper = shell_quote(&wrapper.to_string_lossy());
    format!(
        r#"#!/bin/sh
# Astral Plasma AppImage login session.
set -eu
export XDG_CURRENT_DESKTOP="KDE:Astral"
export XDG_SESSION_TYPE="wayland"
export XDG_SESSION_DESKTOP="KDE"
export QT_QPA_PLATFORM="wayland"

if [ -n "${{WAYLAND_DISPLAY:-}}" ] && command -v qdbus6 >/dev/null 2>&1 && qdbus6 org.kde.KWin /KWin >/dev/null 2>&1; then
    exec {wrapper} run "$@"
fi

if command -v kwin_wayland >/dev/null 2>&1; then
    exec kwin_wayland --no-lockscreen --exit-with-session {wrapper} run "$@"
fi

echo "kwin_wayland is required by the Astral Plasma KWin session." >&2
exit 1
"#
    )
}

fn write_session_entry(paths: &AppImagePaths) -> DynResult<()> {
    let content = format!(
        "[Desktop Entry]\nVersion=1.5\nType=Application\nName={SESSION_NAME}\nComment=Astral Plasma desktop shell from an AppImage\nExec=\"{}\"\nTryExec=\"{}\"\nDesktopNames=KDE:Astral\nKeywords=astral;quickshell;kwin;desktop;shell;\n",
        paths.session_script.display(),
        paths.wrapper.display()
    );
    write_file(&paths.session_file, content.as_bytes())
}

fn write_executable(path: &Path, content: &str) -> DynResult<()> {
    write_file(path, content.as_bytes())?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o755))?;
    Ok(())
}

fn write_file(path: &Path, body: &[u8]) -> DynResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, body)?;
    fs::rename(&tmp, path)?;
    Ok(())
}

fn remove_file(path: &Path, report: &mut AppImageUninstallReport) -> DynResult<()> {
    match fs::remove_file(path) {
        Ok(()) => report.removed.push(path.display().to_string()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => return Err(Box::new(err)),
    }
    Ok(())
}

fn remove_if_exists(path: &Path) -> DynResult<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(Box::new(err)),
    }
}

fn remove_dir(path: &Path, report: &mut AppImageUninstallReport) -> DynResult<()> {
    match fs::remove_dir_all(path) {
        Ok(()) => report.removed.push(path.display().to_string()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => return Err(Box::new(err)),
    }
    Ok(())
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}
