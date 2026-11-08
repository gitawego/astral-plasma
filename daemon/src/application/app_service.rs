//! The app registry: what is installed, and what the host may load.
//!
//! One writer (the daemon), one file (`apps.json`), one meaning per field. The
//! registry says *which* apps exist and what state they are in; the payload, the
//! digest, and the grants live beside the app in its own `install.json`.
//!
//! This module is deliberately read-only for P2: the host and `astral app list`
//! need to agree on what an entry means before anything starts writing them.

use std::collections::BTreeSet;
use std::error::Error;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::domain::app_manifest::Manifest;
use crate::domain::app_reconcile::InstalledApp;
use crate::domain::ports::DynResult;

pub const REGISTRY_SCHEMA: u32 = 1;

/// One installed app, as the daemon records it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryEntry {
    pub id: String,
    pub version: String,
    #[serde(rename = "kernelApi")]
    pub kernel_api: u32,
    #[serde(default)]
    pub enabled: bool,
    /// Baseline payload shipped in the package rather than downloaded.
    #[serde(default)]
    pub preinstalled: bool,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default, rename = "autoUpdate")]
    pub auto_update: bool,
    /// Layout version of the app's data on disk.
    #[serde(default, rename = "dataSchema")]
    pub data_schema: Option<u32>,
    /// Payload digest this entry was verified against.
    #[serde(default)]
    pub digest: String,
    /// Versions that must never be retried (a failed core-app update).
    #[serde(default)]
    pub blocked: Vec<String>,
    #[serde(default, rename = "installedAt")]
    pub installed_at: Option<u64>,
    /// Permissions the user has approved.
    #[serde(default)]
    pub granted: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Registry {
    pub schema: u32,
    #[serde(default)]
    pub apps: Vec<RegistryEntry>,
}

impl Default for Registry {
    fn default() -> Self {
        Self {
            schema: REGISTRY_SCHEMA,
            apps: Vec::new(),
        }
    }
}

impl Registry {
    pub fn parse(bytes: &[u8]) -> DynResult<Self> {
        let registry: Self = serde_json::from_slice(bytes)
            .map_err(|err| format!("apps.json is not valid JSON: {err}"))?;
        if registry.schema != REGISTRY_SCHEMA {
            return Err(format!(
                "apps.json schema {} is not supported by this build (expected {REGISTRY_SCHEMA})",
                registry.schema
            )
            .into());
        }
        registry.validate()?;
        Ok(registry)
    }

    fn validate(&self) -> DynResult<()> {
        let mut seen: BTreeSet<&str> = BTreeSet::new();
        for entry in &self.apps {
            if !crate::domain::app_manifest::is_app_id(&entry.id) {
                return Err(format!("apps.json contains an invalid app id '{}'", entry.id).into());
            }
            if !crate::domain::update::is_version(&entry.version) {
                return Err(format!(
                    "apps.json entry '{}' has an invalid version '{}'",
                    entry.id, entry.version
                )
                .into());
            }
            if !seen.insert(entry.id.as_str()) {
                return Err(format!("apps.json lists '{}' twice", entry.id).into());
            }
        }
        Ok(())
    }

    pub fn get(&self, id: &str) -> Option<&RegistryEntry> {
        self.apps.iter().find(|entry| entry.id == id)
    }

    /// Entries the host should try to load.
    pub fn enabled(&self) -> impl Iterator<Item = &RegistryEntry> {
        self.apps.iter().filter(|entry| entry.enabled)
    }
}

/// Read `apps.json` from `data_dir`.
///
/// A missing file is an empty registry, not an error: a fresh install has no apps
/// recorded yet, and treating that as a failure would make first boot a special
/// case in every caller.
pub fn read_registry(data_dir: &Path) -> DynResult<Registry> {
    let path = data_dir.join("apps.json");
    match std::fs::read(&path) {
        Ok(bytes) => Registry::parse(&bytes).map_err(|err| {
            let message = format!("{}: {err}", path.display());
            Box::new(std::io::Error::other(message)) as Box<dyn Error + Send + Sync>
        }),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(Registry::default()),
        Err(err) => Err(format!("could not read {}: {err}", path.display()).into()),
    }
}

/// Bridge a registry entry into the policy type used by `app_reconcile`.
pub fn installed_app(entry: &RegistryEntry, core: bool) -> InstalledApp {
    InstalledApp {
        id: entry.id.clone(),
        version: entry.version.clone(),
        kernel_api: entry.kernel_api,
        min_quickshell: None,
        data_schema: entry.data_schema,
        digest: entry.digest.clone(),
        pinned: entry.pinned,
        auto_update: entry.auto_update,
        granted: entry.granted.iter().cloned().collect(),
        core,
    }
}

/// Registry entry for a freshly installed app.
///
/// `preinstalled` comes from the manifest's distribution (or the catalog's), so a
/// baseline extracted from the package and the same app installed from a catalog
/// are the same kind of thing afterwards — the spec's whole point in §8.5.2.
pub fn entry_for(manifest: &Manifest, digest: &str) -> RegistryEntry {
    RegistryEntry {
        id: manifest.id.clone(),
        version: manifest.version.clone(),
        kernel_api: manifest.kernel_api,
        enabled: true,
        preinstalled: manifest.distribution().is_preinstalled(),
        pinned: false,
        auto_update: manifest.is_official(),
        data_schema: manifest.data_schema,
        digest: digest.to_string(),
        blocked: Vec::new(),
        installed_at: None,
        granted: manifest.permissions.clone(),
    }
}

impl crate::domain::app_manifest::Distribution {
    pub fn is_preinstalled(self) -> bool {
        matches!(self, Self::Preinstalled)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::app_manifest::{Entry, Manifest, Publisher};

    fn manifest(id: &str, distribution: Option<&str>, trust: &str) -> Manifest {
        Manifest {
            schema: 1,
            id: id.to_string(),
            name: "Thing".to_string(),
            version: "1.2.3".to_string(),
            kernel_api: 1,
            min_quickshell: None,
            data_schema: Some(1),
            trust: trust.to_string(),
            runtime: if trust == "official" {
                "embedded".to_string()
            } else {
                "hosted".to_string()
            },
            publisher: Publisher {
                name: "Astral".to_string(),
                key: "minisign:RWS".to_string(),
            },
            entry: Entry {
                root: if trust == "official" {
                    "Main.qml".to_string()
                } else {
                    "shell.qml".to_string()
                },
                surface: None,
                dashboard_tab: None,
                settings_page: None,
            },
            requires: Default::default(),
            permissions: vec!["session.read".to_string()],
            settings: None,
            distribution: distribution.map(str::to_string),
        }
    }

    #[test]
    fn a_missing_registry_is_empty_not_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let registry = read_registry(dir.path()).unwrap();
        assert!(registry.apps.is_empty());
        assert_eq!(registry.schema, REGISTRY_SCHEMA);
    }

    #[test]
    fn an_empty_registry_lists_nothing() {
        let registry = Registry::default();
        assert_eq!(registry.enabled().count(), 0);
    }

    #[test]
    fn disabled_apps_are_not_loaded_but_stay_recorded() {
        let registry = Registry {
            schema: 1,
            apps: vec![
                RegistryEntry {
                    id: "org.astralplasma.downloads".to_string(),
                    version: "0.2.0".to_string(),
                    kernel_api: 1,
                    enabled: true,
                    preinstalled: true,
                    pinned: false,
                    auto_update: true,
                    data_schema: Some(1),
                    digest: "sha256:a".to_string(),
                    blocked: Vec::new(),
                    installed_at: None,
                    granted: Vec::new(),
                },
                RegistryEntry {
                    id: "io.github.alice.clock".to_string(),
                    version: "1.0.0".to_string(),
                    kernel_api: 1,
                    enabled: false,
                    preinstalled: false,
                    pinned: false,
                    auto_update: false,
                    data_schema: None,
                    digest: "sha256:b".to_string(),
                    blocked: vec!["1.1.0".to_string()],
                    installed_at: None,
                    granted: vec!["session.read".to_string()],
                },
            ],
        };
        assert_eq!(registry.enabled().count(), 1);
        assert_eq!(registry.apps.len(), 2);
        assert!(registry.get("io.github.alice.clock").is_some());
    }

    #[test]
    fn duplicate_ids_are_refused_at_read_time() {
        let json = br#"{"schema":1,"apps":[
            {"id":"io.github.alice.clock","version":"1.0.0","kernelApi":1},
            {"id":"io.github.alice.clock","version":"1.0.1","kernelApi":1}
        ]}"#;
        let error = Registry::parse(json).unwrap_err().to_string();
        assert!(error.contains("twice"), "got: {error}");
    }

    #[test]
    fn a_bad_id_or_version_names_the_entry() {
        let bad_id = br#"{"schema":1,"apps":[{"id":"Clock","version":"1.0.0","kernelApi":1}]}"#;
        assert!(Registry::parse(bad_id)
            .unwrap_err()
            .to_string()
            .contains("invalid app id 'Clock'"));

        let bad_version =
            br#"{"schema":1,"apps":[{"id":"io.github.alice.clock","version":"1.0","kernelApi":1}]}"#;
        assert!(Registry::parse(bad_version)
            .unwrap_err()
            .to_string()
            .contains("invalid version '1.0'"));
    }

    #[test]
    fn an_unknown_registry_schema_is_refused() {
        let json = br#"{"schema":9,"apps":[]}"#;
        assert!(Registry::parse(json)
            .unwrap_err()
            .to_string()
            .contains("schema 9"));
    }

    #[test]
    fn a_preinstalled_manifest_lands_in_the_registry_as_preinstalled() {
        let entry = entry_for(
            &manifest("org.astralplasma.downloads", Some("preinstalled"), "official"),
            "sha256:x",
        );
        assert!(entry.preinstalled);
        assert!(entry.enabled);
        assert!(entry.auto_update, "official apps update themselves");
        assert_eq!(entry.granted, vec!["session.read".to_string()]);
    }

    #[test]
    fn a_community_app_does_not_auto_update_by_default() {
        let entry = entry_for(&manifest("io.github.alice.clock", None, "community"), "sha256:y");
        assert!(!entry.preinstalled);
        assert!(!entry.auto_update);
    }

    #[test]
    fn the_registry_bridges_into_the_reconcile_policy() {
        let entry = entry_for(
            &manifest("org.astralplasma.downloads", Some("preinstalled"), "official"),
            "sha256:x",
        );
        let installed = installed_app(&entry, true);
        assert_eq!(installed.version, "1.2.3");
        assert_eq!(installed.kernel_api, 1);
        assert!(installed.core);
        assert_eq!(installed.data_schema, Some(1));
    }

    #[test]
    fn a_registry_file_round_trips() {
        let registry = Registry {
            schema: REGISTRY_SCHEMA,
            apps: vec![entry_for(
                &manifest("org.astralplasma.media", Some("preinstalled"), "official"),
                "sha256:m",
            )],
        };
        let json = serde_json::to_vec(&registry).unwrap();
        assert_eq!(Registry::parse(&json).unwrap(), registry);
    }
}
