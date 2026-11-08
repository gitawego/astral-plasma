//! Bring an install into existence: binary, bundle, and the record that names
//! its owner.
//!
//! The shell scripts call this (`astral-plasma install`) instead of copying
//! files themselves, so the layout has exactly one implementation. That matters
//! because the same three steps are also what an update performs, and an update
//! that disagreed with the installer about where the bundle lives would produce
//! a desktop that boots after installation and breaks after its first update.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use crate::domain::branding;
use crate::domain::install_record::{self, InstallMethod, InstallRecord};
use crate::domain::ports::DynResult;
use crate::infrastructure::embedded_bundle::extract_embedded_theme;

/// Every path an install writes.
#[derive(Debug, Clone)]
pub struct InstallPaths {
    pub data_dir: PathBuf,
    pub bin_path: PathBuf,
    pub package_dir: PathBuf,
    pub record_path: PathBuf,
}

impl InstallPaths {
    pub fn for_user() -> Self {
        Self {
            data_dir: branding::data_dir(),
            bin_path: branding::bin_path(),
            package_dir: branding::default_package_dir(),
            record_path: branding::install_record_path(),
        }
    }

    /// A layout rooted at `root`, for tests and dry runs.
    pub fn rooted_at(root: &Path) -> Self {
        let data_dir = root.join("data").join(branding::DATA_DIR);
        Self {
            bin_path: data_dir.join(branding::BIN_SUBDIR).join(branding::BIN_FILE),
            package_dir: data_dir.join(branding::PACKAGE_SUBDIR),
            record_path: data_dir.join(branding::INSTALL_RECORD_FILE),
            data_dir,
        }
    }
}

/// What an install did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallOutcome {
    pub record: InstallRecord,
    /// False when the running executable already *is* the installed one.
    pub binary_copied: bool,
}

/// Install this executable's binary and embedded bundle into `paths`.
pub fn install(
    method: InstallMethod,
    channel: &str,
    owner_package: Option<&str>,
    source_exe: &Path,
    paths: &InstallPaths,
) -> DynResult<InstallOutcome> {
    fs::create_dir_all(paths.data_dir.join(branding::BIN_SUBDIR))?;
    fs::create_dir_all(&paths.package_dir)?;

    // The binary the unit and the session launcher will exec. Copying onto
    // itself (a managed install re-run from its own path) would truncate the
    // running executable, so identity is compared first.
    let binary_copied = !same_file(source_exe, &paths.bin_path)?;
    if binary_copied {
        copy_executable(source_exe, &paths.bin_path)?;
    }

    // The bundle this binary can actually run, not whatever a checkout happens
    // to contain: extraction is the only way binary and QML cannot desync.
    extract_embedded_theme(&paths.package_dir)?;

    let mut record = InstallRecord::new(
        method,
        env!("CARGO_PKG_VERSION"),
        channel,
        install_record::now_unix(),
    );
    if let Some(package) = owner_package {
        record = record.with_owner_package(package);
    }
    record.write(&paths.record_path)?;

    Ok(InstallOutcome {
        record,
        binary_copied,
    })
}

fn same_file(a: &Path, b: &Path) -> DynResult<bool> {
    if !b.exists() {
        return Ok(false);
    }
    let ca = fs::canonicalize(a)?;
    let cb = fs::canonicalize(b)?;
    Ok(ca == cb)
}

fn copy_executable(source: &Path, dest: &Path) -> DynResult<()> {
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = dest.with_extension("install.tmp");
    fs::copy(source, &tmp)?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(0o755))?;
    fs::rename(&tmp, dest)?;
    Ok(())
}
