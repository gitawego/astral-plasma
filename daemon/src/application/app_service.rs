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
    /// Human name from the manifest at install time. The registry is the durable record;
    /// a list must not have to read the payload to print a name.
    #[serde(default)]
    pub name: String,
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

/// Write the registry atomically.
///
/// Crash safety is structural rather than hopeful: the bytes go to
/// `apps.json.tmp`, are `sync_all`ed, and only then rename over the real file, so
/// a reader never sees half a registry and a crash mid-write leaves the previous
/// one intact. The directory is synced too, because a rename that is only in the
/// page cache is not a rename after a power cut.
pub fn write_registry(data_dir: &Path, registry: &Registry) -> DynResult<()> {
    use std::io::Write;

    let mut candidate = registry.clone();
    candidate.schema = REGISTRY_SCHEMA;
    // Refuse to persist what a reader would refuse: a registry that cannot be
    // parsed back is a desktop that will not boot.
    candidate.validate()?;

    std::fs::create_dir_all(data_dir)?;
    let path = data_dir.join("apps.json");
    let tmp = data_dir.join("apps.json.tmp");

    let mut bytes = serde_json::to_vec_pretty(&candidate)?;
    bytes.push(b'\n');
    {
        let mut file = std::fs::File::create(&tmp)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
    }
    std::fs::rename(&tmp, &path)?;
    if let Ok(dir) = std::fs::File::open(data_dir) {
        let _ = dir.sync_all();
    }
    Ok(())
}

/// Insert or replace an entry by id, keeping the list order stable.
///
/// Returns true when an existing entry was replaced.
pub fn upsert_entry(registry: &mut Registry, entry: RegistryEntry) -> bool {
    match registry.apps.iter_mut().find(|existing| existing.id == entry.id) {
        Some(existing) => {
            *existing = entry;
            true
        }
        None => {
            registry.apps.push(entry);
            false
        }
    }
}

/// Enable or disable an installed app. An unknown id is an error, not a no-op.
pub fn set_enabled(registry: &mut Registry, id: &str, enabled: bool) -> DynResult<bool> {
    let Some(entry) = registry.apps.iter_mut().find(|entry| entry.id == id) else {
        return Err(format!("'{id}' is not installed").into());
    };
    let changed = entry.enabled != enabled;
    entry.enabled = enabled;
    Ok(changed)
}

pub fn remove_entry(registry: &mut Registry, id: &str) -> bool {
    let before = registry.apps.len();
    registry.apps.retain(|entry| entry.id != id);
    registry.apps.len() != before
}

/// Remember a version that must never be retried for this app.
///
/// Used when a core app fails to load (A28): reverting to the baseline and
/// re-offering the same build would loop. The list is capped so a hostile or
/// broken catalog cannot grow it without bound.
pub fn block_version(registry: &mut Registry, id: &str, version: &str) -> DynResult<()> {
    const MAX_BLOCKED: usize = 32;
    let Some(entry) = registry.apps.iter_mut().find(|entry| entry.id == id) else {
        return Err(format!("'{id}' is not installed").into());
    };
    if entry.blocked.iter().any(|blocked| blocked == version) {
        return Ok(());
    }
    entry.blocked.push(version.to_string());
    if entry.blocked.len() > MAX_BLOCKED {
        let excess = entry.blocked.len() - MAX_BLOCKED;
        entry.blocked.drain(0..excess);
    }
    Ok(())
}

/// Read, upsert, write: the only path that records an install.
pub fn record_install(
    data_dir: &Path,
    manifest: &Manifest,
    digest: &str,
) -> DynResult<RegistryEntry> {
    let mut registry = read_registry(data_dir)?;
    let entry = entry_for(manifest, digest);
    upsert_entry(&mut registry, entry.clone());
    write_registry(data_dir, &registry)?;
    Ok(entry)
}

/// Read, remove, write.
pub fn record_uninstall(data_dir: &Path, id: &str) -> DynResult<bool> {
    let mut registry = read_registry(data_dir)?;
    let removed = remove_entry(&mut registry, id);
    if removed {
        write_registry(data_dir, &registry)?;
    }
    Ok(removed)
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
        name: manifest.name.clone(),
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
                    name: "Fixture".to_string(),
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
                    name: "Fixture".to_string(),
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

    // ---- writer -----------------------------------------------------------

    fn sample(id: &str, version: &str) -> RegistryEntry {
        RegistryEntry {
            name: "Fixture".to_string(),
            id: id.to_string(),
            version: version.to_string(),
            kernel_api: 1,
            enabled: true,
            preinstalled: false,
            pinned: false,
            auto_update: false,
            data_schema: None,
            digest: format!("sha256:{version}"),
            blocked: Vec::new(),
            installed_at: None,
            granted: Vec::new(),
        }
    }

    #[test]
    fn a_written_registry_reads_back_identically() {
        let dir = tempfile::tempdir().unwrap();
        let registry = Registry {
            schema: REGISTRY_SCHEMA,
            apps: vec![sample("io.github.alice.clock", "1.0.0")],
        };
        write_registry(dir.path(), &registry).unwrap();
        assert_eq!(read_registry(dir.path()).unwrap(), registry);
        assert!(
            !dir.path().join("apps.json.tmp").exists(),
            "the temp file must not survive a successful write"
        );
    }

    #[test]
    fn a_failed_validation_never_replaces_the_previous_registry() {
        let dir = tempfile::tempdir().unwrap();
        let good = Registry {
            schema: REGISTRY_SCHEMA,
            apps: vec![sample("io.github.alice.clock", "1.0.0")],
        };
        write_registry(dir.path(), &good).unwrap();

        let broken = Registry {
            schema: REGISTRY_SCHEMA,
            apps: vec![sample("Clock", "1.0.0")],
        };
        assert!(write_registry(dir.path(), &broken).is_err());
        assert_eq!(read_registry(dir.path()).unwrap(), good);
    }

    #[test]
    fn a_corrupt_registry_is_not_silently_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("apps.json"), b"{not json").unwrap();
        let manifest = manifest("io.github.alice.clock", None, "community");
        let error = record_install(dir.path(), &manifest, "sha256:x").unwrap_err();
        assert!(error.to_string().contains("apps.json"), "got: {error}");
        // The user's file is still theirs.
        assert_eq!(
            std::fs::read(dir.path().join("apps.json")).unwrap(),
            b"{not json"
        );
    }

    #[test]
    fn record_install_upserts_and_keeps_the_order_stable() {
        let dir = tempfile::tempdir().unwrap();
        let first = manifest("io.github.alice.clock", None, "community");
        let second = manifest("io.github.bob.notes", None, "community");
        record_install(dir.path(), &first, "sha256:1").unwrap();
        record_install(dir.path(), &second, "sha256:2").unwrap();
        let updated = Manifest {
            version: "1.2.4".to_string(),
            ..first.clone()
        };
        record_install(dir.path(), &updated, "sha256:3").unwrap();

        let registry = read_registry(dir.path()).unwrap();
        assert_eq!(registry.apps.len(), 2, "an update must not duplicate the app");
        assert_eq!(registry.apps[0].id, "io.github.alice.clock");
        assert_eq!(registry.apps[0].version, "1.2.4");
        assert_eq!(registry.apps[1].id, "io.github.bob.notes");
    }

    #[test]
    fn disabling_an_unknown_app_is_an_error_that_names_it() {
        let mut registry = Registry::default();
        let error = set_enabled(&mut registry, "io.github.alice.ghost", false).unwrap_err();
        assert!(error.to_string().contains("io.github.alice.ghost"));
    }

    #[test]
    fn disabling_keeps_the_entry_and_its_data() {
        let mut registry = Registry {
            schema: REGISTRY_SCHEMA,
            apps: vec![sample("io.github.alice.clock", "1.0.0")],
        };
        assert!(set_enabled(&mut registry, "io.github.alice.clock", false).unwrap());
        assert!(!registry.apps[0].enabled);
        assert_eq!(registry.apps[0].version, "1.0.0");
        assert_eq!(registry.apps[0].digest, "sha256:1.0.0");
        // Setting the same state again reports "nothing changed".
        assert!(!set_enabled(&mut registry, "io.github.alice.clock", false).unwrap());
    }

    #[test]
    fn a_blocked_version_is_recorded_once_and_capped() {
        let mut registry = Registry {
            schema: REGISTRY_SCHEMA,
            apps: vec![sample("org.astralplasma.dock", "1.0.0")],
        };
        block_version(&mut registry, "org.astralplasma.dock", "1.0.1").unwrap();
        block_version(&mut registry, "org.astralplasma.dock", "1.0.1").unwrap();
        assert_eq!(
            registry.apps[0].blocked,
            vec!["1.0.1".to_string()],
            "blocking twice must not duplicate the version"
        );
        for minor in 0..40 {
            block_version(&mut registry, "org.astralplasma.dock", &format!("2.0.{minor}")).unwrap();
        }
        assert_eq!(registry.apps[0].blocked.len(), 32, "the list is bounded");
    }

    #[test]
    fn uninstalling_records_removal_and_keeps_other_apps() {
        let dir = tempfile::tempdir().unwrap();
        let clock = manifest("io.github.alice.clock", None, "community");
        let notes = manifest("io.github.bob.notes", None, "community");
        record_install(dir.path(), &clock, "sha256:1").unwrap();
        record_install(dir.path(), &notes, "sha256:2").unwrap();

        assert!(record_uninstall(dir.path(), "io.github.alice.clock").unwrap());
        let registry = read_registry(dir.path()).unwrap();
        assert_eq!(registry.apps.len(), 1);
        assert_eq!(registry.apps[0].id, "io.github.bob.notes");

        assert!(!record_uninstall(dir.path(), "io.github.alice.clock").unwrap());
    }
}
