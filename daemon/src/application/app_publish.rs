//! Publishing: turn a packed app into the catalog entry that distributes it.
//!
//! Publishing is an *authoring* step, so it deliberately lives outside the daemon's
//! runtime surface: the shell never needs a signing key, and `publish` never installs
//! anything. It produces the one thing a catalog needs — an entry whose digest matches the
//! artifact a user will actually download.

use std::path::{Path, PathBuf};

use serde_json::json;

use crate::application::app_sdk::lint_dir;
use crate::domain::app_bundle::sha256_hex;
use crate::application::app_catalog_service::CatalogSource;
use crate::domain::app_catalog::{Catalog, CatalogEntry};
use crate::domain::app_manifest::Manifest;
use crate::domain::ports::DynResult;

/// What `publish` produced: the entry, and where it was written when a catalog was given.
#[derive(Debug, Clone)]
pub struct Published {
    pub entry: CatalogEntry,
    pub catalog_path: Option<PathBuf>,
    /// True when this replaced an entry for the same id instead of adding one.
    pub replaced: bool,
}

/// Build an entry for `dir`, optionally merging it into an existing catalog file.
///
/// `artifact` is the catalog-relative name a user downloads; it defaults to the packed
/// file's name. The digest is computed from the artifact bytes, never taken from a
/// manifest, so the two cannot disagree.
pub fn publish(
    dir: &Path,
    artifact: Option<&Path>,
    catalog_path: Option<&Path>,
    url_base: Option<&str>,
) -> DynResult<Published> {
    let problems = lint_dir(dir)?;
    if !problems.is_empty() {
        return Err(format!(
            "refusing to publish an app that would fail to install:\n  {}",
            problems.join("\n  ")
        )
        .into());
    }

    let manifest = Manifest::parse(&std::fs::read(dir.join("manifest.json"))?)?;
    let artifact = match artifact {
        Some(path) => path.to_path_buf(),
        None => default_artifact(dir, &manifest)?,
    };
    let bytes = std::fs::read(&artifact)
        .map_err(|error| format!("cannot read {}: {error}", artifact.display()))?;
    let digest = format!("sha256:{}", sha256_hex(&bytes));
    let file_name = artifact
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| format!("{}-{}.astralapp", manifest.id, manifest.version));

    // A URL artifact is absolute; a local one stays relative to the catalog so the pair can
    // be moved together.
    let artifact_ref = match url_base {
        Some(base) => format!("{}/{}", base.trim_end_matches('/'), file_name),
        None => file_name.clone(),
    };

    let entry = CatalogEntry {
        id: manifest.id.clone(),
        version: manifest.version.clone(),
        kernel_api: manifest.kernel_api,
        min_quickshell: manifest.min_quickshell.clone(),
        data_schema: manifest.data_schema,
        distribution: manifest.distribution.clone(),
        trust: Some(manifest.trust.clone()),
        permissions: manifest.permissions.clone(),
        digest: digest.clone(),
        artifact: artifact_ref,
        size: bytes.len() as u64,
        revoked: false,
    };

    let (catalog_path, replaced) = match catalog_path {
        Some(path) => {
            let (catalog, replaced) = merge(path, entry.clone())?;
            write_catalog(path, &catalog)?;
            (Some(path.to_path_buf()), replaced)
        }
        None => (None, false),
    };

    Ok(Published {
        entry,
        catalog_path,
        replaced,
    })
}

/// The entry as a submission would carry it (one line, stable order).
pub fn entry_json(entry: &CatalogEntry) -> serde_json::Value {
    json!({
        "id": entry.id,
        "version": entry.version,
        "kernelApi": entry.kernel_api,
        "minQuickshell": entry.min_quickshell,
        "dataSchema": entry.data_schema,
        "distribution": entry.distribution,
        "trust": entry.trust,
        "permissions": entry.permissions,
        "digest": entry.digest,
        "artifact": entry.artifact,
        "size": entry.size,
    })
}

fn default_artifact(dir: &Path, manifest: &Manifest) -> DynResult<PathBuf> {
    let expected = format!("{}-{}.astralapp", manifest.id, manifest.version);
    // `app pack` writes beside the app or into the working directory, so look where it
    // actually leaves the file before asking the author to repeat themselves.
    let candidates = [
        dir.join(&expected),
        dir.parent().unwrap_or(dir).join(&expected),
        std::env::current_dir()?.join(&expected),
    ];
    for candidate in candidates {
        if candidate.is_file() {
            return Ok(candidate);
        }
    }
    let parent = dir.parent().unwrap_or(dir);
    Err(format!(
        "no {} beside the app; run `astral app pack {} --out {}` first or pass --artifact <file>",
        expected,
        dir.display(),
        parent.display()
    )
    .into())
}

/// Merge an entry into a catalog, replacing the same id (a version bump supersedes).
fn merge(path: &Path, entry: CatalogEntry) -> DynResult<(Catalog, bool)> {
    let mut catalog = if path.is_file() {
        crate::application::app_catalog_service::load(&CatalogSource::File(path.to_path_buf()))?
    } else {
        Catalog {
            schema: 1,
            name: path
                .file_stem()
                .map(|stem| stem.to_string_lossy().into_owned())
                .unwrap_or_else(|| "catalog".to_string()),
            publisher_key: None,
            apps: Vec::new(),
        }
    };

    let existing = catalog.apps.iter().position(|candidate| candidate.id == entry.id);
    match existing {
        Some(index) => {
            catalog.apps[index] = entry;
            Ok((catalog, true))
        }
        None => {
            catalog.apps.push(entry);
            catalog.apps.sort_by(|a, b| a.id.cmp(&b.id));
            Ok((catalog, false))
        }
    }
}

fn write_catalog(path: &Path, catalog: &Catalog) -> DynResult<()> {
    let text = serde_json::to_string_pretty(catalog)? + "\n";
    // Write beside then rename: a half-written catalog is a list of wrong digests.
    let temporary = path.with_extension("json.tmp");
    std::fs::write(&temporary, text)?;
    std::fs::rename(&temporary, path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::application::app_sdk::{create_app, pack_dir, Template};

    fn packed(id: &str) -> (tempfile::TempDir, PathBuf, PathBuf) {
        let workspace = tempfile::tempdir().unwrap();
        let app = workspace.path().join("src");
        create_app(id, Template::Surface, &app).unwrap();
        let packed = pack_dir(&app, Some(workspace.path())).unwrap();
        (workspace, app, packed.path)
    }

    #[test]
    fn an_entry_carries_the_artifact_digest_and_trust() {
        let (_workspace, app, artifact) = packed("io.github.alice.clock");
        let published = publish(&app, Some(&artifact), None, None).unwrap();
        let expected = format!("sha256:{}", sha256_hex(&std::fs::read(&artifact).unwrap()));
        assert_eq!(published.entry.digest, expected);
        assert_eq!(published.entry.trust.as_deref(), Some("community"));
        assert_eq!(published.entry.version, "0.1.0");
        assert!(published.entry.size > 0);
        assert!(published.catalog_path.is_none());
    }

    #[test]
    fn publishing_into_a_catalog_replaces_the_same_app_and_keeps_others() {
        let (_workspace, app, artifact) = packed("io.github.alice.clock");
        let (other_workspace, other_app, other_artifact) = packed("io.github.alice.timer");
        let catalog = other_workspace.path().join("catalog.json");

        publish(&other_app, Some(&other_artifact), Some(&catalog), None).unwrap();
        let first = publish(&app, Some(&artifact), Some(&catalog), None).unwrap();
        assert!(!first.replaced, "a new id is added");
        let second = publish(&app, Some(&artifact), Some(&catalog), None).unwrap();
        assert!(second.replaced, "the same id is replaced, not duplicated");

        let written = crate::application::app_catalog_service::load(&CatalogSource::File(
            catalog.clone(),
        ))
        .unwrap();
        assert_eq!(written.apps.len(), 2, "one entry per app");
        assert!(written.apps.iter().any(|entry| entry.id == "io.github.alice.clock"));
        assert!(written.apps.iter().any(|entry| entry.id == "io.github.alice.timer"));
    }

    #[test]
    fn a_url_base_makes_the_artifact_absolute() {
        let (_workspace, app, artifact) = packed("io.github.alice.clock");
        let published = publish(&app, Some(&artifact), None, Some("https://example.org/apps/"))
            .unwrap();
        assert!(published.entry.artifact.starts_with("https://example.org/apps/"));
        assert!(published.entry.artifact.ends_with(".astralapp"));
    }

    #[test]
    fn an_app_that_would_fail_to_install_is_not_published() {
        let (_workspace, app, artifact) = packed("io.github.alice.clock");
        std::fs::write(app.join("bad.qml"), "import Astral.Kernel 1.0\nItem { }\n").unwrap();
        let error = publish(&app, Some(&artifact), None, None).unwrap_err();
        assert!(error.to_string().contains("would fail to install"), "got: {error}");
    }

    #[test]
    fn a_missing_artifact_names_the_pack_command() {
        let workspace = tempfile::tempdir().unwrap();
        let app = workspace.path().join("src");
        create_app("io.github.alice.clock", Template::Surface, &app).unwrap();
        let error = publish(&app, None, None, None).unwrap_err();
        assert!(error.to_string().contains("astral app pack"), "got: {error}");
    }
}
