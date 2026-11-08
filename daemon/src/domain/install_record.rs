//! Who owns the installed files.
//!
//! An install has exactly one owner: this daemon (`managed`), the system package
//! manager (`package`), or a git checkout the user drives by hand (`checkout`).
//! The owner is recorded when the install is created and read before anything
//! replaces a file - never inferred from the layout at update time, because a
//! checkout that happens to sit in the managed directory and a managed install
//! that was adopted by a package look identical from the filesystem alone.
//!
//! Two owners writing the same files is the failure this record exists to
//! prevent: the updater would overwrite a package manager's files, or a
//! `pacman -Syu` would silently revert an update the user just accepted.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

use crate::domain::branding;
use crate::domain::ports::DynResult;

/// Which process owns the installed files.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InstallMethod {
    /// The shell installs its own updates.
    Managed,
    /// A distribution package owns the files; updates come from the package
    /// manager and this daemon must never write them.
    Package,
    /// A git checkout the user drives with `git pull`.
    Checkout,
}

impl InstallMethod {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Managed => "managed",
            Self::Package => "package",
            Self::Checkout => "checkout",
        }
    }

    /// Whether this daemon may apply an update itself.
    pub fn is_self_updatable(self) -> bool {
        matches!(self, Self::Managed)
    }

    /// Parse the value written by the installer and by `astral-plasma install`.
    ///
    /// Unknown values are an error rather than a default: guessing `managed`
    /// from a typo would hand this daemon permission to overwrite files it does
    /// not own.
    pub fn parse(value: &str) -> DynResult<Self> {
        match value.trim() {
            "managed" => Ok(Self::Managed),
            "package" => Ok(Self::Package),
            "checkout" => Ok(Self::Checkout),
            other => Err(format!(
                "unknown install method '{other}' (expected managed, package or checkout)"
            )
            .into()),
        }
    }
}

/// Contents of `install.json`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InstallRecord {
    pub schema: u32,
    pub method: InstallMethod,
    /// Version of the bundle currently installed.
    pub version: String,
    /// Release channel this install follows (`stable` / `beta`).
    pub channel: String,
    /// Unix epoch seconds at install time, rendered as ISO-8601 by `installed_at`.
    pub installed_at_unix: u64,
    /// Package name when `method` is `package` (`astral-plasma-bin`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub owner_package: Option<String>,
}

impl InstallRecord {
    pub fn new(
        method: InstallMethod,
        version: impl Into<String>,
        channel: impl Into<String>,
        installed_at_unix: u64,
    ) -> Self {
        Self {
            schema: branding::INSTALL_RECORD_SCHEMA,
            method,
            version: version.into(),
            channel: channel.into(),
            installed_at_unix,
            owner_package: None,
        }
    }

    pub fn with_owner_package(mut self, package: impl Into<String>) -> Self {
        self.owner_package = Some(package.into());
        self
    }

    /// `installed_at_unix` as `YYYY-MM-DDTHH:MM:SSZ`.
    pub fn installed_at(&self) -> String {
        iso8601_utc(self.installed_at_unix)
    }

    /// Read a record. A missing file is `None` (a legacy or checkout install),
    /// while a malformed one is an error: an unreadable owner is not the same as
    /// no owner, and must not silently grant update permission.
    pub fn read(path: &Path) -> DynResult<Option<Self>> {
        let text = match fs::read_to_string(path) {
            Ok(text) => text,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => return Err(Box::new(err)),
        };
        let record: Self = serde_json::from_str(&text)
            .map_err(|err| format!("{} is not a valid install record: {err}", path.display()))?;
        record.validate()?;
        Ok(Some(record))
    }

    /// Write the record atomically, so a crash mid-write leaves the previous
    /// record (or none) instead of a truncated one.
    pub fn write(&self, path: &Path) -> DynResult<()> {
        self.validate()?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = path.with_extension("json.tmp");
        let body = serde_json::to_string_pretty(self)?;
        fs::write(&tmp, format!("{body}\n"))?;
        fs::rename(&tmp, path)?;
        Ok(())
    }

    fn validate(&self) -> DynResult<()> {
        if self.schema != branding::INSTALL_RECORD_SCHEMA {
            return Err(format!(
                "install record schema {} is newer than this build understands ({})",
                self.schema,
                branding::INSTALL_RECORD_SCHEMA
            )
            .into());
        }
        if self.version.trim().is_empty() {
            return Err("install record has no version".into());
        }
        if self.channel.trim().is_empty() {
            return Err("install record has no channel".into());
        }
        Ok(())
    }
}

/// The record for *this* install, if one was written.
pub fn current() -> DynResult<Option<InstallRecord>> {
    InstallRecord::read(&branding::install_record_path())
}

/// Record a version change without touching the rest of the record.
///
/// Used by the updater once a new bundle is live, so the record keeps its
/// original install time and method.
pub fn record_version(version: &str, installed_at_unix: u64) -> DynResult<InstallRecord> {
    let path = branding::install_record_path();
    let mut record = current()?.unwrap_or_else(|| {
        InstallRecord::new(
            InstallMethod::Managed,
            version,
            "stable",
            installed_at_unix,
        )
    });
    record.version = version.to_string();
    record.installed_at_unix = installed_at_unix;
    record.write(&path)?;
    Ok(record)
}

/// `unix` seconds as `YYYY-MM-DDTHH:MM:SSZ`, without a date-time dependency.
///
/// Civil-from-days after Howard Hinnant's `chrono`-compatible algorithm; it is
/// only used for a human-readable timestamp, so the simple form is enough and
/// the tests pin the values that matter (epoch, a leap day, a current date).
pub fn iso8601_utc(unix: u64) -> String {
    let secs = unix as i64;
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    let hour = rem / 3_600;
    let minute = (rem % 3_600) / 60;
    let second = rem % 60;
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
}

fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 }.div_euclid(146_097);
    let doe = z - era * 146_097; // [0, 146096]
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let mut year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    if month <= 2 {
        year += 1;
    }
    (year, month, day)
}

/// Unix seconds for "now".
pub fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Path of the record for a given data directory (tests, installer previews).
pub fn record_path_in(data_dir: &Path) -> PathBuf {
    data_dir.join(branding::INSTALL_RECORD_FILE)
}
