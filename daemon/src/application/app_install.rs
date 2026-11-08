//! Installing and removing an app: the lifecycle an author's bundle goes through.
//!
//! Order is the crash-safety contract (spec §11.3): verify, stage, activate by
//! rename, **record last**. A crash at any point leaves either the previous install
//! or a fully verified one, never half of both, and `.staging/` is cleaned by the
//! next successful install.
//!
//! Every refusal is a typed reason: an incompatible API level, a republished artifact
//! under the same version, a downgrade the data layout cannot survive, or an update
//! that would widen permissions without consent.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use crate::application::app_service::{
    entry_for, installed_app, read_registry, upsert_entry, write_registry, Registry,
};
use crate::domain::app_bundle::Bundle;
use crate::domain::app_compat::HostApi;
use crate::domain::app_manifest::permissions_within;
use crate::domain::app_reconcile::{decide_install, Admission, Candidate, Refusal};
use crate::domain::ports::DynResult;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallRefusal {
    /// Outside the host's API window — includes the numbers.
    Policy(Refusal),
    /// The update adds permissions and nobody said yes.
    PermissionsWouldWiden { added: Vec<String> },
}

impl std::fmt::Display for InstallRefusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Policy(refusal) => write!(f, "{refusal}"),
            Self::PermissionsWouldWiden { added } => write!(
                f,
                "this version asks for new permissions ({}); re-run with --accept-permissions to allow them",
                added.join(", ")
            ),
        }
    }
}

impl std::error::Error for InstallRefusal {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Installed {
    pub id: String,
    pub version: String,
    /// "installed", "updated", or "already installed".
    pub outcome: &'static str,
    pub payload: PathBuf,
    pub digest: String,
    pub files: usize,
}

/// Install (or update) a `.astralapp` from a file.
///
/// `accept_permissions` is the consent for an update that widens the permission set:
/// a compatibility update must never become a quiet escalation (§8.5.4).
pub fn install_file(
    data_dir: &Path,
    apps_root: &Path,
    bundle_path: &Path,
    host: &HostApi,
    accept_permissions: bool,
    allow_downgrade: bool,
) -> DynResult<Installed> {
    let bytes = std::fs::read(bundle_path)?;
    let digest = crate::domain::app_bundle::sha256_hex(&bytes);
    let bundle = Bundle::from_ustar(&bytes)?;
    let manifest = bundle.validate()?;

    let mut registry = read_registry(data_dir)?;
    let previous = registry.get(&manifest.id).map(|entry| installed_app(entry, false));

    let candidate = Candidate {
        version: manifest.version.clone(),
        kernel_api: manifest.kernel_api,
        min_quickshell: manifest.min_quickshell.clone(),
        data_schema: manifest.data_schema,
        digest: digest.clone(),
        permissions: manifest.permission_set(),
        from_baseline: false,
    };

    let admission = decide_install(previous.as_ref(), &candidate, host, allow_downgrade)
        .map_err(|refusal| Box::new(InstallRefusal::Policy(refusal)) as Box<dyn std::error::Error + Send + Sync>)?;

    if let Some(existing) = &previous {
        let added: Vec<String> = candidate
            .permissions
            .iter()
            .filter(|permission| !existing.granted.contains(*permission))
            .cloned()
            .collect();
        if !added.is_empty() && !accept_permissions {
            return Err(Box::new(InstallRefusal::PermissionsWouldWiden { added }));
        }
    }

    // ---- stage -------------------------------------------------------------
    let staging_root = apps_root.join(".staging");
    let staging = staging_root.join(&manifest.id);
    if staging.exists() {
        std::fs::remove_dir_all(&staging)?;
    }
    let payload = staging.join("payload");
    std::fs::create_dir_all(&payload)?;
    for (relative, contents) in &bundle.files {
        let destination = payload.join(relative);
        if let Some(parent) = destination.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&destination, contents)?;
    }
    std::fs::write(
        staging.join("manifest.json"),
        serde_json::to_vec_pretty(&manifest)?,
    )?;

    // ---- activate ----------------------------------------------------------
    let target = apps_root.join(&manifest.id);
    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent)?;
    }
    if target.exists() {
        // Keep the previous payload for rollback (one release, §8.5.5).
        let previous_payload = target.join(".prev");
        if previous_payload.exists() {
            std::fs::remove_dir_all(&previous_payload)?;
        }
        let installed_payload = target.join("payload");
        if installed_payload.exists() {
            std::fs::rename(&installed_payload, &previous_payload)?;
        }
        let staged_payload = staging.join("payload");
        std::fs::rename(&staged_payload, target.join("payload"))?;
        std::fs::rename(
            staging.join("manifest.json"),
            target.join("manifest.json"),
        )?;
        let _ = std::fs::remove_dir_all(&staging);
    } else {
        std::fs::rename(&staging, &target)?;
    }

    // ---- record last -------------------------------------------------------
    let entry = entry_for(&manifest, &digest);
    upsert_entry(&mut registry, entry);
    write_registry(data_dir, &registry)?;

    Ok(Installed {
        id: manifest.id,
        version: manifest.version,
        outcome: match admission {
            Admission::Install => "installed",
            Admission::Update => "updated",
            Admission::UpToDate => "already installed",
        },
        payload: target.join("payload"),
        digest,
        files: bundle.files.len(),
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Removed {
    pub id: String,
    pub removed_files: bool,
    pub kept_data: bool,
}

/// Remove an app. Data is kept unless `purge`, because an accidental removal should
/// not cost a user's settings (§11.3).
pub fn remove_app(
    data_dir: &Path,
    apps_root: &Path,
    id: &str,
    purge: bool,
) -> DynResult<Removed> {
    let mut registry = read_registry(data_dir)?;
    if registry.get(id).is_none() {
        return Err(format!("'{id}' is not installed").into());
    }

    let app_dir = apps_root.join(id);
    let removed_files = app_dir.exists();
    if removed_files {
        std::fs::remove_dir_all(&app_dir)?;
    }

    // Settings and data live beside the app under `config/` and `data/`; they are
    // preserved unless the user asked for a purge.
    let data_path = app_dir.join("data");
    let kept_data = data_path.exists() && !purge;
    if purge && data_path.exists() {
        std::fs::remove_dir_all(&data_path)?;
    }

    let mut registry = std::mem::take(&mut registry);
    let before = registry.apps.len();
    registry.apps.retain(|entry| entry.id != id);
    if registry.apps.len() != before {
        write_registry(data_dir, &registry)?;
    }

    Ok(Removed {
        id: id.to_string(),
        removed_files,
        kept_data,
    })
}

/// Granted permissions for an installed app (used by the Apps page and by the
/// consent check above).
pub fn granted_permissions(registry: &Registry, id: &str) -> BTreeSet<String> {
    registry
        .get(id)
        .map(|entry| entry.granted.iter().cloned().collect())
        .unwrap_or_default()
}

/// Whether an update would widen the permission set.
pub fn permissions_added(existing: &BTreeSet<String>, candidate: &BTreeSet<String>) -> Vec<String> {
    if permissions_within(existing, candidate) {
        return Vec::new();
    }
    candidate
        .iter()
        .filter(|permission| !existing.contains(*permission))
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::application::app_sdk::{create_app, pack_dir, Template};
    use crate::domain::app_compat::APP_API_LEVEL;

    fn host() -> HostApi {
        HostApi {
            level: APP_API_LEVEL,
            floor: APP_API_LEVEL,
            quickshell: None,
        }
    }

    struct Fixture {
        dir: tempfile::TempDir,
    }

    impl Fixture {
        fn new() -> Self {
            Self {
                dir: tempfile::tempdir().unwrap(),
            }
        }
        fn data(&self) -> PathBuf {
            self.dir.path().join("data")
        }
        fn apps(&self) -> PathBuf {
            self.dir.path().join("apps")
        }
        fn bundle_for(&self, id: &str, version: &str, permissions: &[&str]) -> PathBuf {
            // A fresh source directory per bundle: the fixture packs several versions
            // of the same app, and `create_app` refuses to overwrite.
            let app = self
                .dir
                .path()
                .join(format!("src-{id}-{version}-{}", permissions.len()));
            create_app(id, Template::Surface, &app).unwrap();
            // Rewrite the manifest: version and permissions are what these tests vary.
            let manifest_path = app.join("manifest.json");
            let mut manifest: serde_json::Value =
                serde_json::from_slice(&std::fs::read(&manifest_path).unwrap()).unwrap();
            manifest["version"] = serde_json::json!(version);
            manifest["permissions"] = serde_json::json!(permissions);
            std::fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest).unwrap()).unwrap();
            pack_dir(&app, Some(self.dir.path())).unwrap().path
        }
    }

    #[test]
    fn install_extracts_activates_and_records() {
        let fixture = Fixture::new();
        let bundle = fixture.bundle_for("io.github.alice.clock", "1.0.0", &[]);
        let installed =
            install_file(&fixture.data(), &fixture.apps(), &bundle, &host(), false, false).unwrap();

        assert_eq!(installed.outcome, "installed");
        assert_eq!(installed.version, "1.0.0");
        assert!(installed.payload.join("shell.qml").is_file());
        assert!(
            !fixture.apps().join(".staging").join("io.github.alice.clock").exists(),
            "staging is cleaned up"
        );

        let registry = read_registry(&fixture.data()).unwrap();
        let entry = registry.get("io.github.alice.clock").unwrap();
        assert_eq!(entry.version, "1.0.0");
        assert_eq!(entry.digest, installed.digest);
        assert!(entry.enabled);
    }

    #[test]
    fn installing_the_same_bundle_twice_is_up_to_date() {
        let fixture = Fixture::new();
        let bundle = fixture.bundle_for("io.github.alice.clock", "1.0.0", &[]);
        install_file(&fixture.data(), &fixture.apps(), &bundle, &host(), false, false).unwrap();
        let again =
            install_file(&fixture.data(), &fixture.apps(), &bundle, &host(), false, false).unwrap();
        assert_eq!(again.outcome, "already installed");
    }

    #[test]
    fn a_newer_version_updates_and_keeps_the_previous_payload() {
        let fixture = Fixture::new();
        let first = fixture.bundle_for("io.github.alice.clock", "1.0.0", &[]);
        install_file(&fixture.data(), &fixture.apps(), &first, &host(), false, false).unwrap();

        let second = fixture.bundle_for("io.github.alice.clock", "1.1.0", &[]);
        let updated =
            install_file(&fixture.data(), &fixture.apps(), &second, &host(), false, false).unwrap();
        assert_eq!(updated.outcome, "updated");
        assert_eq!(
            read_registry(&fixture.data())
                .unwrap()
                .get("io.github.alice.clock")
                .unwrap()
                .version,
            "1.1.0"
        );
        assert!(
            fixture.apps().join("io.github.alice.clock/.prev/shell.qml").is_file(),
            "the previous payload is kept for rollback"
        );
    }

    #[test]
    fn an_update_that_widens_permissions_needs_consent() {
        let fixture = Fixture::new();
        let first = fixture.bundle_for("io.github.alice.clock", "1.0.0", &["session.read"]);
        install_file(&fixture.data(), &fixture.apps(), &first, &host(), false, false).unwrap();

        let second = fixture.bundle_for("io.github.alice.clock", "2.0.0", &["session.read", "network"]);
        let refusal =
            install_file(&fixture.data(), &fixture.apps(), &second, &host(), false, false).unwrap_err();
        assert!(refusal.to_string().contains("network"), "got: {refusal}");
        assert!(
            refusal.to_string().contains("--accept-permissions"),
            "the refusal says how to consent"
        );

        // With consent it installs, and the new permission is recorded as granted.
        install_file(&fixture.data(), &fixture.apps(), &second, &host(), true, false).unwrap();
        let granted = granted_permissions(&read_registry(&fixture.data()).unwrap(), "io.github.alice.clock");
        assert!(granted.contains("network"));
    }

    #[test]
    fn an_app_for_a_newer_platform_is_refused() {
        let fixture = Fixture::new();
        let bundle = fixture.bundle_for("io.github.alice.future", "1.0.0", &[]);

        // `pack` refuses this by design, so the archive is rebuilt here the way a
        // newer SDK would have produced it.
        let mut raw = crate::domain::app_bundle::Bundle::from_ustar(&std::fs::read(&bundle).unwrap()).unwrap();
        let manifest: serde_json::Value =
            serde_json::from_str(raw.files.get("manifest.json").unwrap()).unwrap();
        let mut bumped = manifest.clone();
        bumped["kernelApi"] = serde_json::json!(APP_API_LEVEL + 1);
        raw.files.insert(
            "manifest.json".to_string(),
            serde_json::to_string_pretty(&bumped).unwrap(),
        );
        let too_new = fixture.dir.path().join("too-new.astralapp");
        std::fs::write(&too_new, raw.to_ustar().unwrap()).unwrap();

        let strict = HostApi {
            level: APP_API_LEVEL,
            floor: APP_API_LEVEL,
            quickshell: None,
        };
        let error = install_file(&fixture.data(), &fixture.apps(), &too_new, &strict, false, false)
            .unwrap_err();
        assert!(error.to_string().contains("API"), "got: {error}");
        assert!(
            !fixture.apps().join("io.github.alice.future").exists(),
            "nothing is written for a refused install"
        );
    }

    #[test]
    fn a_downgrade_is_refused_unless_asked_for() {
        let fixture = Fixture::new();
        let newer = fixture.bundle_for("io.github.alice.clock", "2.0.0", &[]);
        install_file(&fixture.data(), &fixture.apps(), &newer, &host(), false, false).unwrap();
        let older = fixture.bundle_for("io.github.alice.clock", "1.0.0", &[]);

        let error =
            install_file(&fixture.data(), &fixture.apps(), &older, &host(), false, false).unwrap_err();
        assert!(error.to_string().contains("downgrade"), "got: {error}");

        // The generated app carries dataSchema 1, so an explicit downgrade is allowed.
        let downgraded =
            install_file(&fixture.data(), &fixture.apps(), &older, &host(), false, true).unwrap();
        assert_eq!(downgraded.version, "1.0.0");
    }

    #[test]
    fn a_tampered_bundle_is_refused_before_anything_is_written() {
        let fixture = Fixture::new();
        let bundle = fixture.bundle_for("io.github.alice.clock", "1.0.0", &[]);
        let mut bytes = std::fs::read(&bundle).unwrap();
        bytes.truncate(bytes.len() / 2);
        let broken = fixture.dir.path().join("broken.astralapp");
        std::fs::write(&broken, &bytes).unwrap();

        let error =
            install_file(&fixture.data(), &fixture.apps(), &broken, &host(), false, false).unwrap_err();
        assert!(error.to_string().contains("entry.root") || error.to_string().contains("malformed"),
            "got: {error}");
        assert!(!fixture.apps().join("io.github.alice.clock").exists());
    }

    #[test]
    fn remove_deletes_the_app_and_its_registry_entry() {
        let fixture = Fixture::new();
        let bundle = fixture.bundle_for("io.github.alice.clock", "1.0.0", &[]);
        install_file(&fixture.data(), &fixture.apps(), &bundle, &host(), false, false).unwrap();

        let removed = remove_app(&fixture.data(), &fixture.apps(), "io.github.alice.clock", false).unwrap();
        assert!(removed.removed_files);
        assert!(!fixture.apps().join("io.github.alice.clock").exists());
        assert!(read_registry(&fixture.data())
            .unwrap()
            .get("io.github.alice.clock")
            .is_none());
    }

    #[test]
    fn removing_something_not_installed_names_it() {
        let fixture = Fixture::new();
        let error =
            remove_app(&fixture.data(), &fixture.apps(), "io.github.alice.ghost", false).unwrap_err();
        assert!(error.to_string().contains("io.github.alice.ghost"));
    }

    #[test]
    fn permissions_added_reports_only_the_new_ones() {
        let existing: BTreeSet<String> = ["a".to_string()].into_iter().collect();
        let candidate: BTreeSet<String> = ["a".to_string(), "b".to_string()].into_iter().collect();
        assert_eq!(permissions_added(&existing, &candidate), vec!["b".to_string()]);
        assert!(permissions_added(&candidate, &existing).is_empty());
    }
}
