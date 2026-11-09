//! First-boot reconciliation: every bundled app is installed.
//!
//! A preinstalled app ships inside the core package; the registry is what the host,
//! the Apps page and uninstall read. The two are reconciled on every start:
//!
//! * an app with no record is recorded (enabled, `preinstalled`), so it appears in the
//!   Apps page and can be disabled or removed like any other;
//! * an existing record is left alone — its version, pin, grants and blocked list are
//!   the user's state, and a platform update must not quietly reset them (spec §8.5.2);
//! * a record whose app no longer ships stays, disabled by the host's own plan when it
//!   cannot load, never silently deleted.
//!
//! Idempotent, and it only writes when something changed.
use std::path::Path;

use crate::application::app_service::{entry_for, read_registry, upsert_entry, write_registry};
use crate::domain::app_bundle::{sha256_hex, Bundle};
use crate::domain::app_manifest::Manifest;
use crate::domain::ports::DynResult;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ReconcileOutcome {
    /// App ids recorded for the first time.
    pub added: Vec<String>,
    /// Manifest directories that were skipped, with the reason (a broken bundled
    /// manifest must not stop the desktop from starting).
    pub skipped: Vec<(String, String)>,
}

/// Record every bundled app that has no registry entry yet.
pub fn reconcile_preinstalled(data_dir: &Path, bundled_apps_dir: &Path) -> DynResult<ReconcileOutcome> {
    let mut outcome = ReconcileOutcome::default();
    let Ok(entries) = std::fs::read_dir(bundled_apps_dir) else {
        return Ok(outcome);
    };

    let mut registry = read_registry(data_dir)?;
    let mut changed = false;

    let mut dirs: Vec<std::path::PathBuf> = entries.flatten().map(|entry| entry.path()).collect();
    dirs.sort();

    for dir in dirs {
        let manifest_path = dir.join("manifest.json");
        if !manifest_path.is_file() {
            continue;
        }

        let id = dir
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_default();
        let manifest = match std::fs::read(&manifest_path)
            .map_err(|error| error.to_string())
            .and_then(|bytes| Manifest::parse(&bytes).map_err(|error| error.to_string()))
        {
            Ok(manifest) => manifest,
            Err(reason) => {
                outcome.skipped.push((id, reason));
                continue;
            }
        };
        // A bundled app the user removed stays removed until they restore or reinstall it.
        // The tombstone records the *id*: a bundled directory is named for humans (`Media`)
        // while the id is reverse-DNS, so keying on the directory silently missed.
        if registry.removed.iter().any(|removed| removed == &manifest.id) {
            continue;
        }

        if let Some(existing) = registry.apps.iter_mut().find(|entry| entry.id == manifest.id) {
            // The user's state wins (version, pin, grants, blocked). Only *metadata* the
            // record does not have yet is filled in, so a record written before a field
            // existed still reads correctly.
            if existing.name.is_empty() && !manifest.name.is_empty() {
                existing.name = manifest.name.clone();
                changed = true;
            }
            // Trust is metadata too: a record written before the field existed would
            // otherwise show no badge, which reads as "unknown publisher".
            if existing.trust.is_empty() && !manifest.trust.is_empty() {
                existing.trust = manifest.trust.clone();
                changed = true;
            }
            continue;
        }

        // A bundled app's digest covers its shipped payload: it is what a future
        // catalog update is compared against.
        let digest = match Bundle::from_dir(&dir) {
            Ok(bundle) => bundle
                .to_ustar()
                .map(|bytes| sha256_hex(&bytes))
                .unwrap_or_default(),
            Err(_) => String::new(),
        };

        let mut entry = entry_for(&manifest, &digest);
        entry.payload_digest = crate::domain::app_bundle::payload_digest(&dir).unwrap_or_default();
        upsert_entry(&mut registry, entry);
        outcome.added.push(manifest.id);
        changed = true;
    }

    if changed {
        write_registry(data_dir, &registry)?;
    }
    Ok(outcome)
}

/// The bundled directory that ships `id`, found through its manifest rather than by name.
pub fn bundled_dir_for(bundled_apps_dir: &Path, id: &str) -> Option<std::path::PathBuf> {
    let entries = std::fs::read_dir(bundled_apps_dir).ok()?;
    let mut dirs: Vec<std::path::PathBuf> = entries.flatten().map(|entry| entry.path()).collect();
    dirs.sort();
    dirs.into_iter().find(|dir| {
        std::fs::read(dir.join("manifest.json"))
            .ok()
            .and_then(|bytes| Manifest::parse(&bytes).ok())
            .is_some_and(|manifest| manifest.id == id)
    })
}

/// Restore a bundled app the user removed: clear its tombstone, then reconcile it back.
///
/// A bundled app's payload *is* the package's copy (embedded apps are loaded from it), so
/// restoring restores the record that made the app part of the desktop; the files were
/// never removed from the package.
pub fn restore_bundled(
    data_dir: &Path,
    bundled_apps_dir: &Path,
    id: &str,
) -> DynResult<String> {
    if bundled_dir_for(bundled_apps_dir, id).is_none() {
        return Err(format!("'{id}' is not a bundled app").into());
    }

    let mut registry = read_registry(data_dir)?;
    let tombstoned = registry.removed.iter().any(|removed| removed == id);
    let present = registry.get(id).is_some();
    if !tombstoned && present {
        return Err(format!("'{id}' is already installed").into());
    }

    registry.removed.retain(|removed| removed != id);
    write_registry(data_dir, &registry)?;
    reconcile_preinstalled(data_dir, bundled_apps_dir)?;

    let registry = read_registry(data_dir)?;
    if registry.get(id).is_none() {
        return Err(format!("'{id}' could not be restored from the bundled apps directory").into());
    }
    Ok(id.to_string())
}

/// Bundled apps that were removed and can be restored, in a stable order.
///
/// This is what the Apps page offers: a removed app is not a missing feature, it is a
/// decision the user can revisit.
pub fn restorable(registry: &crate::application::app_service::Registry, bundled_apps_dir: &Path) -> Vec<String> {
    let mut ids: Vec<String> = registry
        .removed
        .iter()
        .filter(|id| bundled_dir_for(bundled_apps_dir, id).is_some() && registry.get(id).is_none())
        .cloned()
        .collect();
    ids.sort();
    ids
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_app(root: &Path, id: &str, version: &str) -> std::path::PathBuf {
        let dir = root.join(id);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("manifest.json"),
            format!(
                r#"{{"schema":1,"id":"{id}","name":"App","version":"{version}","kernelApi":1,
                    "trust":"official","runtime":"embedded",
                    "publisher":{{"name":"Astral"}},"entry":{{"root":"Main.qml"}},
                    "permissions":["session.read"],"distribution":"preinstalled"}}"#
            ),
        )
        .unwrap();
        std::fs::write(dir.join("Main.qml"), "import QtQuick\nItem {}\n").unwrap();
        dir
    }

    #[test]
    fn a_fresh_install_records_every_bundled_app() {
        let tmp = tempfile::tempdir().unwrap();
        let bundled = tmp.path().join("bundled");
        write_app(&bundled, "org.astralplasma.dock", "0.1.0");
        write_app(&bundled, "org.astralplasma.media", "0.1.0");
        let data = tmp.path().join("data");

        let outcome = reconcile_preinstalled(&data, &bundled).unwrap();
        assert_eq!(outcome.added.len(), 2, "both apps are recorded");
        assert!(outcome.skipped.is_empty());

        let registry = read_registry(&data).unwrap();
        let dock = registry.get("org.astralplasma.dock").unwrap();
        assert!(dock.preinstalled);
        assert!(dock.enabled);
        assert!(!dock.digest.is_empty(), "the baseline payload has a digest");
    }

    #[test]
    fn reconciliation_is_idempotent_and_keeps_user_state() {
        let tmp = tempfile::tempdir().unwrap();
        let bundled = tmp.path().join("bundled");
        write_app(&bundled, "org.astralplasma.dock", "0.1.0");
        let data = tmp.path().join("data");
        reconcile_preinstalled(&data, &bundled).unwrap();

        // The user disables it and pins a version.
        let mut registry = read_registry(&data).unwrap();
        registry.apps[0].enabled = false;
        registry.apps[0].pinned = true;
        registry.apps[0].version = "0.9.9".to_string();
        write_registry(&data, &registry).unwrap();

        let second = reconcile_preinstalled(&data, &bundled).unwrap();
        assert!(second.added.is_empty(), "nothing is recorded twice");
        let registry = read_registry(&data).unwrap();
        assert!(!registry.apps[0].enabled, "the user's disable survives");
        assert!(registry.apps[0].pinned, "the pin survives");
        assert_eq!(registry.apps[0].version, "0.9.9", "the user's version survives");
    }

    #[test]
    fn a_broken_bundled_manifest_is_skipped_with_a_reason() {
        let tmp = tempfile::tempdir().unwrap();
        let bundled = tmp.path().join("bundled");
        write_app(&bundled, "org.astralplasma.dock", "0.1.0");
        let broken = bundled.join("org.astralplasma.broken");
        std::fs::create_dir_all(&broken).unwrap();
        std::fs::write(broken.join("manifest.json"), b"{not json").unwrap();
        let data = tmp.path().join("data");

        let outcome = reconcile_preinstalled(&data, &bundled).unwrap();
        assert_eq!(outcome.added, vec!["org.astralplasma.dock".to_string()]);
        assert_eq!(outcome.skipped.len(), 1, "the broken one is reported, not fatal");
        assert!(read_registry(&data).unwrap().apps.len() == 1);
    }

    #[test]
    fn a_record_without_a_trust_tier_gets_the_bundled_one() {
        // Existing installs predate the field; an empty badge would misreport the publisher.
        let dir = tempfile::tempdir().unwrap();
        let data = dir.path().join("data");
        let bundled = dir.path().join("bundled");
        write_app(&bundled, "org.astralplasma.media", "0.1.0");

        reconcile_preinstalled(&data, &bundled).unwrap();
        let mut registry = crate::application::app_service::read_registry(&data).unwrap();
        registry.apps[0].trust = String::new();
        crate::application::app_service::write_registry(&data, &registry).unwrap();

        reconcile_preinstalled(&data, &bundled).unwrap();
        let registry = crate::application::app_service::read_registry(&data).unwrap();
        assert_eq!(registry.apps[0].trust, "official", "the tier is filled in");
    }

    #[test]
    fn a_record_without_a_name_gets_one_and_keeps_its_state() {
        let tmp = tempfile::tempdir().unwrap();
        let bundled = tmp.path().join("bundled");
        write_app(&bundled, "org.astralplasma.dock", "0.1.0");
        let data = tmp.path().join("data");
        reconcile_preinstalled(&data, &bundled).unwrap();

        // Simulate a record written before the registry carried names.
        let mut registry = read_registry(&data).unwrap();
        registry.apps[0].name = String::new();
        registry.apps[0].enabled = false;
        write_registry(&data, &registry).unwrap();

        reconcile_preinstalled(&data, &bundled).unwrap();
        let registry = read_registry(&data).unwrap();
        assert_eq!(registry.apps[0].name, "App", "the name is filled in");
        assert!(!registry.apps[0].enabled, "the user's state is untouched");
    }

    #[test]
    fn a_missing_bundled_directory_is_not_an_error() {
        let tmp = tempfile::tempdir().unwrap();
        let outcome = reconcile_preinstalled(&tmp.path().join("data"), &tmp.path().join("nope")).unwrap();
        assert!(outcome.added.is_empty());
    }
}
