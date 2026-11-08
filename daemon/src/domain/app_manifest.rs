//! The app manifest: what every Astral app declares about itself.
//!
//! This is the contract the host, the installer, and the catalog all agree on.
//! It is deliberately boring: a manifest is JSON, validation is one function, and
//! every refusal names the field and the rule that rejected it. An app author
//! reads the error; a user sees a sentence; the installer decides.
//!
//! Two rules are worth stating because they are not obvious from the fields:
//!
//! * `kernelApi` is a **minimum**, never a range (`app_compat`). Authors do not
//!   get to claim combinations they never ran.
//! * `version` belongs to the app, including preinstalled apps: a fix to
//!   `downloads` ships as an app release, not as a platform release.

use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::error::Error;
use std::fmt;

use crate::domain::update::is_version;

/// Bumped only when the manifest *shape* changes.
pub const MANIFEST_SCHEMA: u32 = 1;

pub const TRUST_LEVELS: [&str; 4] = ["official", "verified", "community", "local-dev"];
pub const RUNTIMES: [&str; 2] = ["embedded", "hosted"];

/// Capabilities a manifest may declare.
///
/// P2 set: enough for the official app migration, and closed — an unknown
/// permission is a validation error rather than something the broker later
/// discovers it cannot enforce.
pub const PERMISSIONS: [&str; 12] = [
    "session.read",
    "session.control",
    "windows.read",
    "windows.control",
    "workspaces.read",
    "workspaces.control",
    "media.read",
    "media.control",
    "notifications.post",
    "network",
    "files.read",
    "files.write",
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Publisher {
    pub name: String,
    /// `minisign:<base64>` when the publisher signs. Official apps are signed by
    /// the release key; community apps may self-sign.
    #[serde(default)]
    pub key: String,
}

/// A windowed surface an embedded app may own.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SurfaceSpec {
    /// `toplevel` or `layer-shell`.
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub width: Option<u32>,
    #[serde(default)]
    pub height: Option<u32>,
    #[serde(default)]
    pub layer: Option<String>,
    #[serde(default)]
    pub anchor: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    /// Component the host instantiates (`Main.qml`) or, for hosted apps, the
    /// directory root Quickshell loads (`shell.qml`).
    pub root: String,
    #[serde(default)]
    pub surface: Option<SurfaceSpec>,
    /// Official apps only; a projection source for the dashboard.
    #[serde(default, rename = "dashboardTab")]
    pub dashboard_tab: Option<String>,
    /// Official apps only; a projection source for Nexus settings.
    #[serde(default, rename = "settingsPage")]
    pub settings_page: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Requires {
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default, rename = "qtModules")]
    pub qt_modules: Vec<String>,
    /// App ids this app needs at boot, resolved in dependency order.
    #[serde(default)]
    pub apps: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SettingsSpec {
    #[serde(default)]
    pub schema: Option<String>,
    #[serde(default)]
    pub defaults: Option<String>,
}

/// How the app arrived. Delivery only — it does not change versioning.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Distribution {
    /// Baseline payload ships in the core package; updated from the catalog.
    Preinstalled,
    /// Catalog only.
    Store,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Manifest {
    pub schema: u32,
    pub id: String,
    pub name: String,
    pub version: String,
    #[serde(rename = "kernelApi")]
    pub kernel_api: u32,
    #[serde(default, rename = "minQuickshell")]
    pub min_quickshell: Option<String>,
    /// Layout version of the app's settings/data, written by this build.
    #[serde(default, rename = "dataSchema")]
    pub data_schema: Option<u32>,
    pub trust: String,
    pub runtime: String,
    pub publisher: Publisher,
    pub entry: Entry,
    #[serde(default)]
    pub requires: Requires,
    #[serde(default)]
    pub permissions: Vec<String>,
    #[serde(default)]
    pub settings: Option<SettingsSpec>,
    /// `preinstalled` | `store`. Registry metadata; the manifest may omit it
    /// (the catalog decides) and the registry then records what it observed.
    #[serde(default)]
    pub distribution: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ManifestError {
    Schema { found: u32 },
    InvalidId { id: String, reason: &'static str },
    EmptyName,
    InvalidVersion { version: String },
    InvalidKernelApi { level: u32 },
    InvalidMinQuickshell { version: String },
    InvalidDataSchema { value: u32 },
    UnknownTrust { trust: String },
    UnknownRuntime { runtime: String },
    /// Trust decides integration: only official apps may run embedded.
    TrustCannotEmbed { trust: String, runtime: String },
    EmptyRoot,
    AbsoluteRoot { root: String },
    EscapingRoot { root: String },
    RootNotQml { root: String },
    /// A hosted app is started with `quickshell -p <payload>`, which needs
    /// `shell.qml` at the payload root.
    HostedRootNotShell { root: String },
    UnknownPermission { permission: String },
    PublisherKeyNotMinisign { key: String },
    UnknownDistribution { distribution: String },
}

impl fmt::Display for ManifestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Schema { found } => write!(
                f,
                "manifest schema {found} is not supported by this build (expected {MANIFEST_SCHEMA})"
            ),
            Self::InvalidId { id, reason } => {
                write!(f, "app id '{id}' is not a valid reverse-DNS id: {reason}")
            }
            Self::EmptyName => write!(f, "manifest has no name"),
            Self::InvalidVersion { version } => {
                write!(f, "version '{version}' is not MAJOR.MINOR.PATCH[-prerelease]")
            }
            Self::InvalidKernelApi { level } => {
                write!(f, "kernelApi {level} is not a valid API level (must be >= 1)")
            }
            Self::InvalidMinQuickshell { version } => {
                write!(f, "minQuickshell '{version}' is not a version")
            }
            Self::InvalidDataSchema { value } => {
                write!(f, "dataSchema {value} must be >= 1")
            }
            Self::UnknownTrust { trust } => write!(
                f,
                "trust '{trust}' is not one of {}",
                TRUST_LEVELS.join(", ")
            ),
            Self::UnknownRuntime { runtime } => write!(
                f,
                "runtime '{runtime}' is not one of {}",
                RUNTIMES.join(", ")
            ),
            Self::TrustCannotEmbed { trust, runtime } => write!(
                f,
                "a {trust} app cannot declare runtime '{runtime}': only official apps may run embedded"
            ),
            Self::EmptyRoot => write!(f, "entry.root is empty"),
            Self::AbsoluteRoot { root } => {
                write!(f, "entry.root '{root}' must be relative to the payload")
            }
            Self::EscapingRoot { root } => {
                write!(f, "entry.root '{root}' must not escape the payload")
            }
            Self::RootNotQml { root } => write!(f, "entry.root '{root}' must be a .qml file"),
            Self::HostedRootNotShell { root } => write!(
                f,
                "a hosted app's entry.root must be shell.qml (found '{root}')"
            ),
            Self::UnknownPermission { permission } => write!(
                f,
                "permission '{permission}' is not in the capability catalog"
            ),
            Self::PublisherKeyNotMinisign { key } => {
                write!(f, "publisher key must be a minisign key (found '{key}')")
            }
            Self::UnknownDistribution { distribution } => write!(
                f,
                "distribution '{distribution}' must be 'preinstalled' or 'store'"
            ),
        }
    }
}

impl Error for ManifestError {}

/// `io.github.alice.clock`: lower-case segments, at least two, joined by dots.
pub fn is_app_id(id: &str) -> bool {
    if id.is_empty() || id.len() > 128 {
        return false;
    }
    let segments: Vec<&str> = id.split('.').collect();
    if segments.len() < 2 {
        return false;
    }
    segments.iter().all(|segment| {
        !segment.is_empty()
            && segment.len() <= 63
            && segment.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
            && !segment.starts_with('-')
            && !segment.ends_with('-')
    })
}

fn id_problem(id: &str) -> Option<&'static str> {
    if id.is_empty() {
        return Some("it is empty");
    }
    if id.len() > 128 {
        return Some("it is longer than 128 characters");
    }
    if !id.contains('.') {
        return Some("it needs at least two dot-separated segments");
    }
    if id.chars().any(|c| c.is_ascii_uppercase()) {
        return Some("it must be lower case");
    }
    if id.chars().any(char::is_whitespace) {
        return Some("it must not contain spaces");
    }
    if id.split('.').any(str::is_empty) {
        return Some("it must not contain empty segments");
    }
    None
}

impl Manifest {
    pub fn parse(bytes: &[u8]) -> Result<Self, Box<dyn Error + Send + Sync>> {
        let manifest: Self = serde_json::from_slice(bytes)
            .map_err(|err| format!("manifest is not valid JSON: {err}"))?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn validate(&self) -> Result<(), ManifestError> {
        if self.schema != MANIFEST_SCHEMA {
            return Err(ManifestError::Schema { found: self.schema });
        }
        if let Some(reason) = id_problem(&self.id) {
            return Err(ManifestError::InvalidId {
                id: self.id.clone(),
                reason,
            });
        }
        if self.name.trim().is_empty() {
            return Err(ManifestError::EmptyName);
        }
        if !is_version(&self.version) {
            return Err(ManifestError::InvalidVersion {
                version: self.version.clone(),
            });
        }
        if self.kernel_api == 0 {
            return Err(ManifestError::InvalidKernelApi {
                level: self.kernel_api,
            });
        }
        if let Some(version) = self.min_quickshell.as_deref() {
            if !is_version(version) {
                return Err(ManifestError::InvalidMinQuickshell {
                    version: version.to_string(),
                });
            }
        }
        if self.data_schema == Some(0) {
            return Err(ManifestError::InvalidDataSchema {
                value: self.data_schema.unwrap_or(0),
            });
        }
        if !TRUST_LEVELS.contains(&self.trust.as_str()) {
            return Err(ManifestError::UnknownTrust {
                trust: self.trust.clone(),
            });
        }
        if !RUNTIMES.contains(&self.runtime.as_str()) {
            return Err(ManifestError::UnknownRuntime {
                runtime: self.runtime.clone(),
            });
        }
        if self.runtime == "embedded" && self.trust != "official" {
            return Err(ManifestError::TrustCannotEmbed {
                trust: self.trust.clone(),
                runtime: self.runtime.clone(),
            });
        }
        if !self.publisher.key.is_empty() && !self.publisher.key.starts_with("minisign:") {
            return Err(ManifestError::PublisherKeyNotMinisign {
                key: self.publisher.key.clone(),
            });
        }
        self.validate_entry()?;
        for permission in &self.permissions {
            if !PERMISSIONS.contains(&permission.as_str()) {
                return Err(ManifestError::UnknownPermission {
                    permission: permission.clone(),
                });
            }
        }
        if let Some(distribution) = self.distribution.as_deref() {
            if distribution != "preinstalled" && distribution != "store" {
                return Err(ManifestError::UnknownDistribution {
                    distribution: distribution.to_string(),
                });
            }
        }
        Ok(())
    }

    fn validate_entry(&self) -> Result<(), ManifestError> {
        let root = self.entry.root.trim();
        if root.is_empty() {
            return Err(ManifestError::EmptyRoot);
        }
        if root.starts_with('/') {
            return Err(ManifestError::AbsoluteRoot {
                root: root.to_string(),
            });
        }
        if root.split('/').any(|segment| segment == "..") {
            return Err(ManifestError::EscapingRoot {
                root: root.to_string(),
            });
        }
        if !root.ends_with(".qml") {
            return Err(ManifestError::RootNotQml {
                root: root.to_string(),
            });
        }
        if self.runtime == "hosted" && root != "shell.qml" {
            return Err(ManifestError::HostedRootNotShell {
                root: root.to_string(),
            });
        }
        Ok(())
    }

    pub fn distribution(&self) -> Distribution {
        match self.distribution.as_deref() {
            Some("preinstalled") => Distribution::Preinstalled,
            _ => Distribution::Store,
        }
    }

    pub fn is_official(&self) -> bool {
        self.trust == "official"
    }

    pub fn permission_set(&self) -> BTreeSet<String> {
        self.permissions.iter().cloned().collect()
    }
}

/// `candidate` grants nothing the user has not already approved.
///
/// This is what stops a forced compatibility update from becoming a permission
/// escalation channel (spec A30).
pub fn permissions_within(granted: &BTreeSet<String>, requested: &BTreeSet<String>) -> bool {
    requested.iter().all(|permission| granted.contains(permission))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Manifest {
        Manifest {
            schema: 1,
            id: "io.github.alice.clock".to_string(),
            name: "World Clock".to_string(),
            version: "1.4.2".to_string(),
            kernel_api: 1,
            min_quickshell: Some("0.3.0".to_string()),
            data_schema: Some(2),
            trust: "community".to_string(),
            runtime: "hosted".to_string(),
            publisher: Publisher {
                name: "Alice".to_string(),
                key: "minisign:RWS".to_string(),
            },
            entry: Entry {
                root: "shell.qml".to_string(),
                surface: Some(SurfaceSpec {
                    kind: "toplevel".to_string(),
                    width: Some(420),
                    height: Some(320),
                    layer: None,
                    anchor: None,
                }),
                dashboard_tab: None,
                settings_page: None,
            },
            requires: Requires::default(),
            permissions: vec!["session.read".to_string()],
            settings: None,
            distribution: Some("store".to_string()),
        }
    }

    #[test]
    fn a_valid_manifest_validates() {
        fixture().validate().unwrap();
    }

    #[test]
    fn a_hosted_community_app_cannot_claim_embedded() {
        let mut manifest = fixture();
        manifest.runtime = "embedded".to_string();
        assert_eq!(
            manifest.validate().unwrap_err(),
            ManifestError::TrustCannotEmbed {
                trust: "community".to_string(),
                runtime: "embedded".to_string(),
            }
        );
    }

    #[test]
    fn an_official_app_may_run_embedded_without_a_shell_root() {
        let mut manifest = fixture();
        manifest.trust = "official".to_string();
        manifest.runtime = "embedded".to_string();
        manifest.entry.root = "Main.qml".to_string();
        manifest.validate().unwrap();
    }

    #[test]
    fn a_hosted_app_must_load_shell_qml() {
        let mut manifest = fixture();
        manifest.entry.root = "Main.qml".to_string();
        assert!(matches!(
            manifest.validate().unwrap_err(),
            ManifestError::HostedRootNotShell { .. }
        ));
    }

    #[test]
    fn entry_may_not_escape_the_payload() {
        let mut manifest = fixture();
        manifest.trust = "official".to_string();
        manifest.runtime = "embedded".to_string();
        manifest.entry.root = "../main.qml".to_string();
        assert!(matches!(
            manifest.validate().unwrap_err(),
            ManifestError::EscapingRoot { .. }
        ));
    }

    #[test]
    fn versions_must_be_semver() {
        let mut manifest = fixture();
        manifest.version = "1.4".to_string();
        assert!(matches!(
            manifest.validate().unwrap_err(),
            ManifestError::InvalidVersion { .. }
        ));
    }

    #[test]
    fn an_unknown_permission_is_refused_rather_than_ignored() {
        let mut manifest = fixture();
        manifest.permissions.push("root.shell".to_string());
        assert_eq!(
            manifest.validate().unwrap_err(),
            ManifestError::UnknownPermission {
                permission: "root.shell".to_string()
            }
        );
    }

    #[test]
    fn app_ids_are_reverse_dns() {
        assert!(is_app_id("io.github.alice.clock"));
        assert!(is_app_id("org.astralplasma.downloads"));
        assert!(!is_app_id("clock"));
        assert!(!is_app_id("IO.github.alice"));
        assert!(!is_app_id("io..alice"));
        assert!(!is_app_id("io.github.alice."));
        assert!(!is_app_id("-io.github.alice"));
    }

    #[test]
    fn a_publisher_key_must_be_a_minisign_key() {
        let mut manifest = fixture();
        manifest.publisher.key = "sha256:abc".to_string();
        assert!(matches!(
            manifest.validate().unwrap_err(),
            ManifestError::PublisherKeyNotMinisign { .. }
        ));
    }

    #[test]
    fn json_round_trips_and_reports_the_offending_field() {
        let manifest = fixture();
        let json = serde_json::to_vec(&manifest).unwrap();
        let parsed = Manifest::parse(&json).unwrap();
        assert_eq!(parsed, manifest);

        let broken = serde_json::to_vec(&Manifest {
            version: "nope".to_string(),
            ..fixture()
        })
        .unwrap();
        let error = Manifest::parse(&broken).unwrap_err().to_string();
        assert!(error.contains("version 'nope'"), "got: {error}");
    }

    #[test]
    fn permissions_within_is_a_subset_check() {
        let granted: BTreeSet<String> = ["session.read", "media.read"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let same: BTreeSet<String> = ["session.read"].iter().map(|s| s.to_string()).collect();
        let more: BTreeSet<String> = ["session.read", "network"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert!(permissions_within(&granted, &same));
        assert!(!permissions_within(&granted, &more));
    }
}
