//! Remove an install and everything it wrote, leaving the user's own files.
//!
//! Removal is the one action where being wrong is unrecoverable, so the rules
//! are explicit: files this install created are removed, files someone else owns
//! (a package manager's, a git checkout, the user's `~/.config/quickshell`) are
//! reported and left alone, and settings survive unless the caller asked for
//! `--purge`.

use std::fs;
use std::path::{Path, PathBuf};

use crate::domain::branding;
use crate::domain::install_record::{InstallMethod, InstallRecord};
use crate::domain::ports::DynResult;
use serde::{Deserialize, Serialize};

/// Every path an uninstall considers.
#[derive(Debug, Clone)]
pub struct UninstallPaths {
    pub data_dir: PathBuf,
    pub bin_path: PathBuf,
    pub state_dir: PathBuf,
    pub cache_dir: PathBuf,
    pub config_dir: PathBuf,
    pub bin_home: PathBuf,
    pub applications_dir: PathBuf,
    pub wayland_sessions_dir: PathBuf,
    pub systemd_dir: PathBuf,
    /// `~/.config/quickshell`: a user-owned config path, reported and never
    /// removed. Held here so tests can pin it to a temporary root.
    pub quickshell_link: PathBuf,
}

impl UninstallPaths {
    pub fn for_user() -> Self {
        let home = branding::home_dir();
        Self {
            data_dir: branding::data_dir(),
            bin_path: branding::bin_path(),
            state_dir: branding::state_dir(),
            cache_dir: branding::cache_dir(),
            config_dir: branding::config_home().join(branding::APP_ID),
            bin_home: home.join(".local").join("bin"),
            applications_dir: branding::applications_dir(),
            wayland_sessions_dir: branding::data_home().join("wayland-sessions"),
            systemd_dir: branding::config_home().join("systemd").join("user"),
            quickshell_link: branding::config_home().join("quickshell"),
        }
    }

    pub fn rooted_at(root: &Path) -> Self {
        let home = root.join("home");
        Self {
            data_dir: root.join("data").join(branding::DATA_DIR),
            bin_path: root
                .join("data")
                .join(branding::DATA_DIR)
                .join(branding::BIN_SUBDIR)
                .join(branding::BIN_FILE),
            state_dir: root.join("state").join(branding::STATE_DIR),
            cache_dir: root.join("cache").join(branding::CACHE_DIR),
            config_dir: root.join("config").join(branding::APP_ID),
            bin_home: home.join(".local").join("bin"),
            applications_dir: root.join("data").join("applications"),
            wayland_sessions_dir: root.join("data").join("wayland-sessions"),
            systemd_dir: root.join("config").join("systemd").join("user"),
            quickshell_link: root.join("config").join("quickshell"),
        }
    }
}

/// What an uninstall removed.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UninstallReport {
    pub removed: Vec<String>,
    pub kept: Vec<String>,
    pub settings_removed: bool,
}

/// Remove the install described by `paths`.
///
/// `keep_settings` preserves `~/.config/astral-plasma` (palette, settings,
/// imported avatars); `force` lets a package-owned install be removed anyway,
/// which the caller must only use after telling the user pacman would otherwise
/// reinstall it.
pub fn uninstall(
    paths: &UninstallPaths,
    keep_settings: bool,
    force: bool,
) -> DynResult<UninstallReport> {
    let record_path = paths.data_dir.join(branding::INSTALL_RECORD_FILE);
    let record = InstallRecord::read(&record_path)?;

    if let Some(record) = &record {
        if record.method == InstallMethod::Package && !force {
            return Err(format!(
                "this install is owned by your package manager{}. Remove it with: \
                 sudo pacman -Rns {}",
                record
                    .owner_package
                    .as_deref()
                    .map(|p| format!(" ({p})"))
                    .unwrap_or_default(),
                record
                    .owner_package
                    .as_deref()
                    .unwrap_or("astral-plasma-bin")
            )
            .into());
        }
    }

    let mut report = UninstallReport::default();

    // 1. Artifacts, newest first so an interrupted run never leaves a live
    //    bundle pointing at a half-removed binary.
    for file in [
        paths.bin_path.clone(),
        with_suffix(&paths.bin_path, branding::PREV_SUFFIX),
        paths.data_dir.join(branding::INSTALL_RECORD_FILE),
    ] {
        remove_file(&file, &mut report)?;
    }
    for dir in [
        paths.data_dir.join(branding::STAGED_PACKAGE_SUBDIR),
        paths.data_dir.join(format!("{}{}", branding::PACKAGE_SUBDIR, branding::PREV_SUFFIX)),
        paths.data_dir.join(branding::PACKAGE_SUBDIR),
    ] {
        remove_dir(&dir, &mut report)?;
    }
    // The data directory also holds things an install did not create: the AI
    // harness's sessions, and the Plasma/shortcut backups that must outlive the
    // shell. Remove the directory only once it is genuinely empty.
    let bin_dir = paths.bin_path.parent().map(Path::to_path_buf);
    if let Some(bin_dir) = bin_dir {
        remove_dir_if_empty(&bin_dir, &mut report)?;
    }
    remove_dir_if_empty(&paths.data_dir, &mut report)?;

    // 2. The PATH entry, but only when it is ours: a symlink to someone else's
    //    binary under the same name is not this install's to delete.
    if let Ok(target) = fs::read_link(paths.bin_home.join(branding::BIN_FILE)) {
        if target.starts_with(&paths.data_dir) || target == paths.bin_path {
            remove_file(&paths.bin_home.join(branding::BIN_FILE), &mut report)?;
        } else {
            report.kept.push(format!(
                "{} (points at {})",
                paths.bin_home.join(branding::BIN_FILE).display(),
                target.display()
            ));
        }
    }

    // 3. User unit and desktop integration this install created.
    remove_file(&paths.systemd_dir.join(branding::SYSTEMD_UNIT), &mut report)?;
    for dir in [&paths.applications_dir, &paths.wayland_sessions_dir] {
        remove_prefixed_entries(dir, "astral-", &mut report)?;
    }
    for name in ["astral-plasma-session", "astral-hyprland-session"] {
        let path = paths.bin_home.join(name);
        if fs::symlink_metadata(&path).is_ok() {
            remove_file(&path, &mut report)?;
        }
    }

    // 4. State this feature owns. The rest of the state directory is user data
    //    (download tasks, wallpaper selection) and survives.
    for name in [
        branding::MIGRATIONS_SUBDIR,
        "update.json",
        "update.log",
        "boot-ok",
    ] {
        let path = paths.state_dir.join(name);
        if path.is_dir() {
            remove_dir(&path, &mut report)?;
        } else {
            remove_file(&path, &mut report)?;
        }
    }
    if let Ok(entries) = fs::read_dir(&paths.state_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("restart-") && name.ends_with("-required") {
                remove_file(&entry.path(), &mut report)?;
            }
        }
    }
    remove_dir_if_empty(&paths.state_dir, &mut report)?;

    // 5. Caches and settings are the user's, not the install's: they are only
    //    removed when the caller asked for a purge.
    if keep_settings {
        for path in [&paths.config_dir, &paths.cache_dir] {
            if path.exists() {
                report.kept.push(format!("{} (pass --purge to remove)", path.display()));
            }
        }
    } else {
        remove_dir(&paths.cache_dir, &mut report)?;
        remove_dir(&paths.config_dir, &mut report)?;
        report.settings_removed = true;
    }

    // 6. Anything the user owns is reported, never removed.
    let legacy_link = &paths.quickshell_link;
    if fs::symlink_metadata(legacy_link).is_ok() {
        report.kept.push(format!(
            "{} (a config path you own; remove it yourself if it is no longer wanted)",
            legacy_link.display()
        ));
    }

    Ok(report)
}

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(suffix);
    PathBuf::from(name)
}

fn remove_file(path: &Path, report: &mut UninstallReport) -> DynResult<()> {
    match fs::remove_file(path) {
        Ok(()) => report.removed.push(path.display().to_string()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => return Err(Box::new(err)),
    }
    Ok(())
}

fn remove_dir(path: &Path, report: &mut UninstallReport) -> DynResult<()> {
    match fs::remove_dir_all(path) {
        Ok(()) => report.removed.push(path.display().to_string()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => return Err(Box::new(err)),
    }
    Ok(())
}

/// Remove a directory only when nothing else lives in it.
fn remove_dir_if_empty(path: &Path, report: &mut UninstallReport) -> DynResult<()> {
    match fs::remove_dir(path) {
        Ok(()) => report.removed.push(path.display().to_string()),
        Err(err)
            if matches!(
                err.kind(),
                std::io::ErrorKind::NotFound | std::io::ErrorKind::DirectoryNotEmpty
            ) => {}
        Err(err) => return Err(Box::new(err)),
    }
    Ok(())
}

fn remove_prefixed_entries(dir: &Path, prefix: &str, report: &mut UninstallReport) -> DynResult<()> {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(err) => return Err(Box::new(err)),
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with(prefix) {
            remove_file(&entry.path(), report)?;
        }
    }
    Ok(())
}
