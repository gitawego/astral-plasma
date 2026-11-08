//! `install <id>`: resolve an app from a catalog, verify it, install it.
//!
//! The catalog says *what* an app is and where its artifact lives; this service is
//! the only place that turns that into an install, and every step is a refusal
//! rather than a guess:
//!
//! 1. the id resolves, and the entry is not revoked;
//! 2. the artifact is fetched (a path relative to a local catalog, or an HTTPS URL)
//!    and its SHA-256 matches the entry — a catalog that vouches for the wrong bytes
//!    is a bug, not a shortcut;
//! 3. the bundle is installed through the same pipeline as a local file, so
//!    compatibility, permissions, downgrade and staging rules are identical.
//!
//! Nothing here trusts the artifact because the catalog did: the digest is the
//! contract, and the signature only authenticates *the index*.

use std::path::{Path, PathBuf};

use crate::application::app_install::{install_file, Installed};
use crate::domain::app_catalog::{load_local, Catalog, CatalogEntry};
use crate::domain::app_compat::HostApi;
use crate::domain::ports::DynResult;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CatalogRefusal {
    UnknownApp { id: String },
    Revoked { id: String },
    DigestMismatch { expected: String, actual: String },
    NoArtifact { id: String, artifact: String },
}

impl std::fmt::Display for CatalogRefusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnknownApp { id } => write!(f, "'{id}' is not in this catalog"),
            Self::Revoked { id } => write!(
                f,
                "'{id}' was revoked by the catalog publisher and will not be installed"
            ),
            Self::DigestMismatch { expected, actual } => write!(
                f,
                "the artifact does not match the catalog: expected sha256:{expected}, got sha256:{actual}"
            ),
            Self::NoArtifact { id, artifact } => write!(
                f,
                "'{id}' points at '{artifact}', which is neither a URL nor a file beside the catalog"
            ),
        }
    }
}

impl std::error::Error for CatalogRefusal {}

/// Where the catalog lives, so a relative artifact can be resolved against it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CatalogSource {
    File(PathBuf),
    Url(String),
}

impl CatalogSource {
    pub fn parse(text: &str) -> Self {
        if text.starts_with("http://") || text.starts_with("https://") {
            Self::Url(text.to_string())
        } else {
            Self::File(PathBuf::from(text))
        }
    }
}

pub fn load(source: &CatalogSource) -> DynResult<Catalog> {
    match source {
        CatalogSource::File(path) => Ok(load_local(path)?.catalog),
        CatalogSource::Url(_) => Err(
            "remote catalogs need the artifact transport (curl + pinned key); use a local catalog for now"
                .into(),
        ),
    }
}

/// Install `id` from `catalog`, verifying the artifact against the entry's digest.
pub fn install_from_catalog(
    catalog: &Catalog,
    source: &CatalogSource,
    data_dir: &Path,
    apps_root: &Path,
    id: &str,
    host: &HostApi,
    accept_permissions: bool,
    allow_downgrade: bool,
) -> DynResult<Installed> {
    let entry = catalog
        .resolve(id)
        .ok_or_else(|| Box::new(CatalogRefusal::UnknownApp { id: id.to_string() }) as Box<dyn std::error::Error + Send + Sync>)?;
    if entry.revoked {
        return Err(Box::new(CatalogRefusal::Revoked { id: id.to_string() }));
    }

    let artifact = resolve_artifact(entry, source)?;
    let bytes = std::fs::read(&artifact)
        .map_err(|err| format!("cannot read {}: {err}", artifact.display()))?;
    let actual = crate::domain::app_bundle::sha256_hex(&bytes);
    let expected = entry.digest_hex();
    if actual != expected {
        return Err(Box::new(CatalogRefusal::DigestMismatch { expected, actual }));
    }

    install_file(
        data_dir,
        apps_root,
        &artifact,
        host,
        accept_permissions,
        allow_downgrade,
    )
}

fn resolve_artifact(entry: &CatalogEntry, source: &CatalogSource) -> DynResult<PathBuf> {
    let artifact = entry.artifact.trim();
    if artifact.starts_with("http://") || artifact.starts_with("https://") {
        return Err(format!(
            "'{}' is a URL; remote artifact transport is P5 remainder (the digest check already exists)",
            entry.artifact
        )
        .into());
    }
    let candidate = match source {
        CatalogSource::File(path) => path
            .parent()
            .map(|dir| dir.join(artifact))
            .unwrap_or_else(|| PathBuf::from(artifact)),
        CatalogSource::Url(_) => PathBuf::from(artifact),
    };
    if !candidate.is_file() {
        return Err(Box::new(CatalogRefusal::NoArtifact {
            id: entry.id.clone(),
            artifact: entry.artifact.clone(),
        }));
    }
    Ok(candidate)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::application::app_sdk::{create_app, pack_dir, Template};
    use crate::domain::app_catalog::CatalogEntry;
    use crate::domain::app_compat::APP_API_LEVEL;

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
        fn catalog_path(&self) -> PathBuf {
            self.dir.path().join("catalog.json")
        }

        /// Packs an app beside the catalog and returns the entry that describes it.
        fn publish(&self, id: &str, version: &str) -> CatalogEntry {
            let app = self.dir.path().join(format!("src-{id}-{version}"));
            create_app(id, Template::Surface, &app).unwrap();
            let manifest_path = app.join("manifest.json");
            let mut manifest: serde_json::Value =
                serde_json::from_slice(&std::fs::read(&manifest_path).unwrap()).unwrap();
            manifest["version"] = serde_json::json!(version);
            std::fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest).unwrap()).unwrap();

            let packed = pack_dir(&app, Some(self.dir.path())).unwrap();
            let name = packed.path.file_name().unwrap().to_string_lossy().to_string();
            CatalogEntry {
                id: id.to_string(),
                version: version.to_string(),
                kernel_api: APP_API_LEVEL,
                min_quickshell: None,
                data_schema: Some(1),
                distribution: Some("store".to_string()),
                trust: Some("community".to_string()),
                permissions: Vec::new(),
                digest: packed.digest,
                artifact: name,
                size: std::fs::metadata(&packed.path).unwrap().len(),
                revoked: false,
            }
        }

        fn write_catalog(&self, entries: Vec<CatalogEntry>) -> CatalogSource {
            let catalog = Catalog {
                schema: 1,
                name: "Fixture".to_string(),
                publisher_key: None,
                apps: entries,
            };
            std::fs::write(self.catalog_path(), serde_json::to_vec_pretty(&catalog).unwrap()).unwrap();
            CatalogSource::File(self.catalog_path())
        }
    }

    fn host() -> HostApi {
        HostApi {
            level: APP_API_LEVEL,
            floor: APP_API_LEVEL,
            quickshell: None,
        }
    }

    #[test]
    fn install_by_id_resolves_verifies_and_installs() {
        let fixture = Fixture::new();
        let entry = fixture.publish("io.github.alice.clock", "1.0.0");
        let source = fixture.write_catalog(vec![entry]);
        let catalog = load(&source).unwrap();

        let installed = install_from_catalog(
            &catalog,
            &source,
            &fixture.data(),
            &fixture.apps(),
            "io.github.alice.clock",
            &host(),
            false,
            false,
        )
        .unwrap();

        assert_eq!(installed.outcome, "installed");
        assert!(installed.payload.join("shell.qml").is_file());
    }

    #[test]
    fn an_unknown_id_is_refused_by_name() {
        let fixture = Fixture::new();
        let source = fixture.write_catalog(vec![fixture.publish("io.github.alice.clock", "1.0.0")]);
        let catalog = load(&source).unwrap();
        let error = install_from_catalog(
            &catalog,
            &source,
            &fixture.data(),
            &fixture.apps(),
            "io.github.alice.ghost",
            &host(),
            false,
            false,
        )
        .unwrap_err();
        assert!(error.to_string().contains("io.github.alice.ghost"));
    }

    #[test]
    fn a_revoked_app_is_refused_with_a_reason() {
        let fixture = Fixture::new();
        let mut entry = fixture.publish("io.github.alice.clock", "1.0.0");
        entry.revoked = true;
        let source = fixture.write_catalog(vec![entry]);
        let catalog = load(&source).unwrap();
        let error = install_from_catalog(
            &catalog,
            &source,
            &fixture.data(),
            &fixture.apps(),
            "io.github.alice.clock",
            &host(),
            false,
            false,
        )
        .unwrap_err();
        assert!(error.to_string().contains("revoked"), "got: {error}");
    }

    #[test]
    fn an_artifact_that_does_not_match_the_digest_is_refused() {
        let fixture = Fixture::new();
        let mut entry = fixture.publish("io.github.alice.clock", "1.0.0");
        // The catalog vouches for different bytes than the artifact contains.
        entry.digest = "c".repeat(64);
        let source = fixture.write_catalog(vec![entry]);
        let catalog = load(&source).unwrap();

        let error = install_from_catalog(
            &catalog,
            &source,
            &fixture.data(),
            &fixture.apps(),
            "io.github.alice.clock",
            &host(),
            false,
            false,
        )
        .unwrap_err();
        assert!(error.to_string().contains("does not match the catalog"), "got: {error}");
        assert!(
            !fixture.apps().join("io.github.alice.clock").exists(),
            "nothing is written for a refused artifact"
        );
    }

    #[test]
    fn a_missing_artifact_file_names_what_it_looked_for() {
        let fixture = Fixture::new();
        let mut entry = fixture.publish("io.github.alice.clock", "1.0.0");
        entry.artifact = "not-there.astralapp".to_string();
        let source = fixture.write_catalog(vec![entry]);
        let catalog = load(&source).unwrap();
        let error = install_from_catalog(
            &catalog,
            &source,
            &fixture.data(),
            &fixture.apps(),
            "io.github.alice.clock",
            &host(),
            false,
            false,
        )
        .unwrap_err();
        assert!(error.to_string().contains("not-there.astralapp"), "got: {error}");
    }

    #[test]
    fn a_remote_catalog_is_refused_with_the_phase_it_needs() {
        let fixture = Fixture::new();
        let error = load(&CatalogSource::parse("https://example.invalid/catalog.json")).unwrap_err();
        assert!(error.to_string().contains("local catalog"), "got: {error}");
        assert!(!fixture.catalog_path().exists());
    }
}
