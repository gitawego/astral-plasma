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
use crate::domain::app_catalog::{CatalogBinding, load_local, Catalog, CatalogEntry};
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

/// Fetch a URL over HTTP(S). `curl` is the transport because it is already a session
/// dependency (the wallpaper engine uses it) and it handles TLS, proxies and redirects
/// without vendoring a second TLS stack into a shell.
pub fn fetch(url: &str, limit: usize) -> DynResult<Vec<u8>> {
    let output = std::process::Command::new("curl")
        .args([
            "--fail",
            "--silent",
            "--show-error",
            "--location",
            "--proto",
            "=https,http",
            "--max-time",
            "60",
            "--max-filesize",
            &limit.to_string(),
            "--output",
            "-",
            url,
        ])
        .output()
        .map_err(|error| format!("cannot run curl for {url}: {error}"))?;
    if !output.status.success() {
        let reason = String::from_utf8_lossy(&output.stderr);
        return Err(format!("cannot fetch {url}: {}", reason.trim()).into());
    }
    if output.stdout.len() > limit {
        return Err(format!("{url} is larger than the {limit}-byte limit").into());
    }
    Ok(output.stdout)
}

/// The largest artifact the transport will accept (compressed bytes).
pub const ARTIFACT_LIMIT: usize = 64 * 1024 * 1024;
/// The largest catalog the transport will accept.
pub const CATALOG_LIMIT: usize = 4 * 1024 * 1024;

pub fn load(source: &CatalogSource) -> DynResult<Catalog> {
    Ok(load_binding(source)?.catalog)
}

/// Load a catalog and report whether its signature was verified.
pub fn load_binding(source: &CatalogSource) -> DynResult<CatalogBinding> {
    match source {
        CatalogSource::File(path) => load_local(path),
        CatalogSource::Url(url) => {
            let bytes = fetch(url, CATALOG_LIMIT)?;
            // The signature lives beside the catalog, the way a local one does.
            let signature = fetch(&format!("{url}.minisig"), 64 * 1024).ok();
            crate::domain::app_catalog::load_remote(
                &bytes,
                signature.as_deref().map(|bytes| String::from_utf8_lossy(bytes).into_owned()).as_deref(),
            )
        }
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

    let bytes = artifact_bytes(entry, source)?;
    let actual = crate::domain::app_bundle::sha256_hex(&bytes);
    let expected = entry.digest_hex();
    if actual != expected {
        return Err(Box::new(CatalogRefusal::DigestMismatch { expected, actual }));
    }

    // `install_file` reads a path, so a fetched artifact is staged inside the app root
    // (same filesystem, removed immediately) rather than in a shared temp directory.
    std::fs::create_dir_all(apps_root)?;
    let staged = apps_root.join(format!(".download-{}.astralapp", entry.id));
    std::fs::write(&staged, &bytes)?;
    let outcome = install_file(
        data_dir,
        apps_root,
        &staged,
        host,
        accept_permissions,
        allow_downgrade,
    );
    let _ = std::fs::remove_file(&staged);
    outcome
}

/// The artifact's bytes: from disk when it is a path, over the network when it is a URL.
///
/// A remote artifact is verified by digest *before* it is written anywhere, so a tampered
/// download never reaches the installer's staging directory.
fn artifact_bytes(entry: &CatalogEntry, source: &CatalogSource) -> DynResult<Vec<u8>> {
    let artifact = entry.artifact.trim();
    if artifact.starts_with("http://") || artifact.starts_with("https://") {
        let bytes = fetch(artifact, ARTIFACT_LIMIT)?;
        let actual = crate::domain::app_bundle::sha256_hex(&bytes);
        let expected = entry.digest_hex();
        if actual != expected {
            return Err(Box::new(CatalogRefusal::DigestMismatch { expected, actual }));
        }
        return Ok(bytes);
    }
    let path = resolve_artifact(entry, source)?;
    Ok(std::fs::read(&path).map_err(|err| format!("cannot read {}: {err}", path.display()))?)
}

fn resolve_artifact(entry: &CatalogEntry, source: &CatalogSource) -> DynResult<PathBuf> {
    let artifact = entry.artifact.trim();
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
    fn a_remote_catalog_without_a_publisher_key_is_refused() {
        let catalog = br#"{"schema":1,"apps":[]}"#;
        let error = crate::domain::app_catalog::load_remote(catalog, Some("sig")).unwrap_err();
        assert!(error.to_string().contains("publisherKey"), "got: {error}");
    }

    #[test]
    fn a_remote_catalog_without_a_signature_is_refused() {
        // A key alone proves nothing: without the detached signature anyone could serve
        // their own catalog, digests included.
        let catalog = br#"{"schema":1,"publisherKey":"RWQplaceholderKeyForTheExampleOnly","apps":[]}"#;
        let error = crate::domain::app_catalog::load_remote(catalog, None).unwrap_err();
        assert!(error.to_string().contains("minisig"), "got: {error}");
    }

    #[test]
    fn a_bad_remote_signature_is_refused_rather_than_trusted() {
        let catalog = br#"{"schema":1,"publisherKey":"RWQplaceholderKeyForTheExampleOnly","apps":[]}"#;
        let error =
            crate::domain::app_catalog::load_remote(catalog, Some("untrusted comment: nope\n"))
                .unwrap_err();
        assert!(!error.to_string().is_empty());
    }

    #[test]
    fn a_url_catalog_goes_to_the_transport() {
        // `.invalid` never resolves, so this exercises the transport without depending on
        // the network: whatever the failure mode (DNS, TLS, missing curl), it names the URL
        // and not "use a local catalog".
        let error = load(&CatalogSource::parse("https://example.invalid/catalog.json")).unwrap_err();
        let text = error.to_string();
        assert!(text.contains("example.invalid"), "got: {text}");
        assert!(!text.contains("local catalog"), "got: {text}");
    }
}
