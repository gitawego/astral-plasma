//! A catalog: the signed index that turns `install <id>` into a bundle.
//!
//! The catalog is data, not code: an index of what exists, what it costs (size,
//! permissions), what it was signed with, and where the artifact lives. Install
//! refuses anything the index does not vouch for, and a `revoked` entry is a refusal
//! rather than a silent removal — a desktop that quietly loses an app is worse than
//! one that explains why.
//!
//! Signature policy: a catalog that declares a `publisher_key` must carry a detached
//! `.minisig` beside it, verified with the same `minisign` path the release manifest
//! uses. A local (file) catalog without a key is accepted and reported as unsigned,
//! because that is what an author's own dev catalog is.

use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::domain::app_manifest::is_app_id;
use crate::domain::ports::DynResult;
use crate::domain::update::is_version;

pub const CATALOG_SCHEMA: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CatalogEntry {
    pub id: String,
    pub version: String,
    #[serde(rename = "kernelApi")]
    pub kernel_api: u32,
    #[serde(default, rename = "minQuickshell")]
    pub min_quickshell: Option<String>,
    #[serde(default, rename = "dataSchema")]
    pub data_schema: Option<u32>,
    /// `preinstalled` or `store`.
    #[serde(default)]
    pub distribution: Option<String>,
    /// `official`, `verified`, or `community`.
    #[serde(default)]
    pub trust: Option<String>,
    #[serde(default)]
    pub permissions: Vec<String>,
    /// SHA-256 of the artifact, hex; a `sha256:` prefix is tolerated.
    pub digest: String,
    /// URL, or a path relative to the catalog file for a local catalog.
    pub artifact: String,
    #[serde(default)]
    pub size: u64,
    /// Present and true means: do not offer it, and say why.
    #[serde(default)]
    pub revoked: bool,
}

impl CatalogEntry {
    pub fn digest_hex(&self) -> String {
        self.digest
            .trim()
            .trim_start_matches("sha256:")
            .to_ascii_lowercase()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Catalog {
    pub schema: u32,
    #[serde(default)]
    pub name: String,
    /// minisign public key (base64). When present, the catalog must be signed.
    #[serde(default, rename = "publisherKey")]
    pub publisher_key: Option<String>,
    #[serde(default)]
    pub apps: Vec<CatalogEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CatalogBinding {
    pub catalog: Catalog,
    /// True when a signature was verified, false for an unsigned local catalog.
    pub signed: bool,
}

impl Catalog {
    pub fn parse(bytes: &[u8]) -> DynResult<Self> {
        let catalog: Self = serde_json::from_slice(bytes)
            .map_err(|err| format!("catalog is not valid JSON: {err}"))?;
        catalog.validate()?;
        Ok(catalog)
    }

    pub fn validate(&self) -> DynResult<()> {
        if self.schema != CATALOG_SCHEMA {
            return Err(format!(
                "catalog schema {} is not supported by this build (expected {CATALOG_SCHEMA})",
                self.schema
            )
            .into());
        }
        let mut seen: Vec<&str> = Vec::new();
        for entry in &self.apps {
            if !is_app_id(&entry.id) {
                return Err(format!("catalog contains an invalid app id '{}'", entry.id).into());
            }
            if !is_version(&entry.version) {
                return Err(format!(
                    "catalog entry '{}' has an invalid version '{}'",
                    entry.id, entry.version
                )
                .into());
            }
            if entry.kernel_api == 0 {
                return Err(format!("catalog entry '{}' declares no kernelApi", entry.id).into());
            }
            let digest = entry.digest_hex();
            if digest.len() != 64 || !digest.chars().all(|c| c.is_ascii_hexdigit()) {
                return Err(format!(
                    "catalog entry '{}' has no usable sha256 digest ('{}')",
                    entry.id, entry.digest
                )
                .into());
            }
            if entry.artifact.trim().is_empty() {
                return Err(format!("catalog entry '{}' has no artifact", entry.id).into());
            }
            if seen.contains(&entry.id.as_str()) {
                return Err(format!("catalog lists '{}' more than once", entry.id).into());
            }
            seen.push(&entry.id);
        }
        Ok(())
    }

    pub fn resolve(&self, id: &str) -> Option<&CatalogEntry> {
        self.apps.iter().find(|entry| entry.id == id)
    }

    /// Entries that may be offered right now.
    pub fn offerable(&self) -> impl Iterator<Item = &CatalogEntry> {
        self.apps.iter().filter(|entry| !entry.revoked)
    }
}

/// Read a catalog from disk (and verify its detached signature when it declares a key).
pub fn load_local(path: &Path) -> DynResult<CatalogBinding> {
    let bytes = std::fs::read(path)?;
    let catalog = Catalog::parse(&bytes)?;

    let signature_path = path.with_extension("minisig");
    match (&catalog.publisher_key, signature_path.is_file()) {
        (Some(key), true) => {
            let signature = std::fs::read_to_string(&signature_path)?;
            if !crate::infrastructure::update_source::verify_signature(&bytes, &signature, key)? {
                return Err(format!("catalog signature did not verify: {}", path.display()).into());
            }
            Ok(CatalogBinding {
                catalog,
                signed: true,
            })
        }
        (Some(_), false) => Err(format!(
            "catalog {} declares a publisher key but has no {}",
            path.display(),
            signature_path.display()
        )
        .into()),
        (None, _) => Ok(CatalogBinding {
            catalog,
            signed: false,
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str) -> CatalogEntry {
        CatalogEntry {
            id: id.to_string(),
            version: "1.0.0".to_string(),
            kernel_api: 1,
            min_quickshell: None,
            data_schema: Some(1),
            distribution: Some("store".to_string()),
            trust: Some("community".to_string()),
            permissions: Vec::new(),
            digest: "a".repeat(64),
            artifact: format!("{id}-1.0.0.astralapp"),
            size: 5120,
            revoked: false,
        }
    }

    fn catalog() -> Catalog {
        Catalog {
            schema: 1,
            name: "Test".to_string(),
            publisher_key: None,
            apps: vec![entry("io.github.alice.clock")],
        }
    }

    #[test]
    fn a_valid_catalog_parses() {
        let json = serde_json::to_vec(&catalog()).unwrap();
        assert_eq!(Catalog::parse(&json).unwrap(), catalog());
    }

    #[test]
    fn duplicate_ids_are_refused() {
        let mut duplicate = catalog();
        duplicate.apps.push(entry("io.github.alice.clock"));
        assert!(duplicate
            .validate()
            .unwrap_err()
            .to_string()
            .contains("more than once"));
    }

    #[test]
    fn a_digest_must_be_a_sha256() {
        let mut broken = catalog();
        broken.apps[0].digest = "abc".to_string();
        assert!(broken
            .validate()
            .unwrap_err()
            .to_string()
            .contains("sha256"));
    }

    #[test]
    fn a_sha256_prefix_is_tolerated() {
        let mut prefixed = catalog();
        prefixed.apps[0].digest = format!("sha256:{}", "b".repeat(64));
        prefixed.validate().unwrap();
        assert_eq!(prefixed.apps[0].digest_hex(), "b".repeat(64));
    }

    #[test]
    fn revoked_entries_are_not_offered_but_still_resolve() {
        let mut with_revoked = catalog();
        with_revoked.apps[0].revoked = true;
        assert_eq!(with_revoked.offerable().count(), 0);
        assert!(
            with_revoked.resolve("io.github.alice.clock").is_some(),
            "resolve must still answer, so install can explain the revocation"
        );
    }

    #[test]
    fn a_catalog_declaring_a_key_without_a_signature_is_refused() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("catalog.json");
        let mut signed = catalog();
        signed.publisher_key = Some("RWSkey".to_string());
        std::fs::write(&path, serde_json::to_vec(&signed).unwrap()).unwrap();

        let error = load_local(&path).unwrap_err();
        assert!(error.to_string().contains("no"), "got: {error}");
    }

    #[test]
    fn a_local_catalog_without_a_key_loads_as_unsigned() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("catalog.json");
        std::fs::write(&path, serde_json::to_vec(&catalog()).unwrap()).unwrap();
        let binding = load_local(&path).unwrap();
        assert!(!binding.signed, "no key means unsigned");
        assert_eq!(binding.catalog.apps.len(), 1);
    }
}
