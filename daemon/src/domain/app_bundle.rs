//! `.astralapp`: the archive an author produces and the installer consumes.
//!
//! Deliberately dependency-free: the daemon has no archive crate, and a platform
//! that cannot pack an app offline is not a platform. So this is a **POSIX ustar
//! writer and reader** over UTF-8 files (the platform allows QML/JS only, which is
//! exactly why text is a safe assumption here).
//!
//! Compression and signing are P5: `zstd` needs a codec dependency, and signing
//! needs a private key the daemon must never own. Until then a bundle is
//! `ustar` + a printed SHA-256 the installer can verify against a catalog entry.
//!
//! The format rules live in [`Bundle::validate`] so a malformed archive is refused
//! with a reason instead of half-extracting:
//!
//! * every path is relative, normalised, and stays inside the bundle;
//! * no symlinks, no native libraries (`.so`, `.dylib`, `.dll`);
//! * the manifest is present at the root and parses as a legal manifest.

use std::collections::BTreeMap;
use std::error::Error;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::domain::app_manifest::Manifest;
use crate::domain::ports::DynResult;

const RECORD: usize = 512;
const MAX_NAME: usize = 100;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bundle {
    /// Path inside the archive -> file contents (UTF-8).
    pub files: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BundleError {
    Empty,
    NoManifest,
    Manifest(String),
    AbsolutePath { path: String },
    EscapingPath { path: String },
    Symlink { path: String },
    NativeLibrary { path: String },
    MissingEntry { root: String },
    NotUtf8 { path: String },
    TooLong { path: String },
    Malformed(String),
}

impl std::fmt::Display for BundleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => write!(f, "the bundle has no files"),
            Self::NoManifest => write!(f, "the bundle has no manifest.json at its root"),
            Self::Manifest(reason) => write!(f, "manifest.json is not valid: {reason}"),
            Self::AbsolutePath { path } => write!(f, "'{path}' is an absolute path"),
            Self::EscapingPath { path } => write!(f, "'{path}' escapes the bundle"),
            Self::Symlink { path } => write!(f, "'{path}' is a symlink; a bundle is files only"),
            Self::NativeLibrary { path } => {
                write!(f, "'{path}' is a native library; the platform is QML/JS only")
            }
            Self::MissingEntry { root } => write!(
                f,
                "the manifest's entry.root '{root}' is not in the bundle"
            ),
            Self::NotUtf8 { path } => write!(f, "'{path}' is not UTF-8"),
            Self::TooLong { path } => write!(
                f,
                "'{path}' is longer than {MAX_NAME} bytes, which ustar cannot store here"
            ),
            Self::Malformed(reason) => write!(f, "archive is malformed: {reason}"),
        }
    }
}

impl Error for BundleError {}

impl Bundle {
    /// Files in a directory tree, keyed by their path relative to `root`.
    ///
    /// Skips dot-entries (`.git`, `.astral`) and `tests/`: a bundle ships what runs,
    /// not what verifies it.
    pub fn from_dir(root: &Path) -> DynResult<Self> {
        let mut files = BTreeMap::new();
        collect(root, root, &mut files)?;
        Ok(Self { files })
    }

    pub fn validate(&self) -> Result<Manifest, BundleError> {
        if self.files.is_empty() {
            return Err(BundleError::Empty);
        }
        for path in self.files.keys() {
            validate_path(path)?;
            let lower = path.to_ascii_lowercase();
            if lower.ends_with(".so") || lower.ends_with(".dylib") || lower.ends_with(".dll") {
                return Err(BundleError::NativeLibrary { path: path.clone() });
            }
        }
        let raw = self
            .files
            .get("manifest.json")
            .ok_or(BundleError::NoManifest)?;
        let manifest =
            Manifest::parse(raw.as_bytes()).map_err(|err| BundleError::Manifest(err.to_string()))?;
        // A bundle that does not contain what it says it starts is not installable,
        // and finding that out at launch instead of at install is worse.
        if !self.files.contains_key(&manifest.entry.root) {
            return Err(BundleError::MissingEntry {
                root: manifest.entry.root.clone(),
            });
        }
        Ok(manifest)
    }

    /// Serialise to a POSIX ustar archive.
    pub fn to_ustar(&self) -> DynResult<Vec<u8>> {
        self.validate()?;
        let mut out = Vec::new();
        for (path, contents) in &self.files {
            out.extend_from_slice(&header(path, contents.len())?);
            out.extend_from_slice(contents.as_bytes());
            let padding = (RECORD - (contents.len() % RECORD)) % RECORD;
            out.extend(std::iter::repeat_n(0u8, padding));
        }
        out.extend(std::iter::repeat_n(0u8, RECORD * 2));
        Ok(out)
    }

    pub fn from_ustar(bytes: &[u8]) -> Result<Self, BundleError> {
        let mut files = BTreeMap::new();
        let mut offset = 0usize;
        loop {
            if offset + RECORD > bytes.len() {
                break;
            }
            let block = &bytes[offset..offset + RECORD];
            if block.iter().all(|byte| *byte == 0) {
                break;
            }
            let name = field(block, 0, MAX_NAME);
            let size = octal(block, 124, 12)?;
            let typeflag = block[156];
            let prefix = field(block, 345, 155);
            let path = if prefix.is_empty() {
                name
            } else {
                format!("{prefix}/{name}")
            };

            if typeflag == b'5' {
                // Directory entry: the files below it carry their own paths.
                offset += RECORD;
                continue;
            }
            if typeflag == b'2' {
                return Err(BundleError::Symlink { path });
            }
            if typeflag != b'0' && typeflag != 0 && typeflag != b'\0' {
                return Err(BundleError::Malformed(format!(
                    "unsupported entry type '{}' for {path}",
                    typeflag as char
                )));
            }

            offset += RECORD;
            if offset + size > bytes.len() {
                return Err(BundleError::Malformed(format!("{path} is truncated")));
            }
            let raw = &bytes[offset..offset + size];
            let text = String::from_utf8(raw.to_vec())
                .map_err(|_| BundleError::NotUtf8 { path: path.clone() })?;
            files.insert(path, text);
            offset += size + ((RECORD - (size % RECORD)) % RECORD);
        }
        let bundle = Self { files };
        bundle.validate()?;
        Ok(bundle)
    }

    /// SHA-256 of the archive bytes, as the catalog records it.
    pub fn digest(&self) -> DynResult<String> {
        let bytes = self.to_ustar()?;
        Ok(sha256_hex(&bytes))
    }
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

fn validate_path(path: &str) -> Result<(), BundleError> {
    if path.starts_with('/') {
        return Err(BundleError::AbsolutePath {
            path: path.to_string(),
        });
    }
    if path.split('/').any(|segment| segment == ".." || segment == ".") {
        return Err(BundleError::EscapingPath {
            path: path.to_string(),
        });
    }
    if path.len() > MAX_NAME {
        return Err(BundleError::TooLong {
            path: path.to_string(),
        });
    }
    Ok(())
}

fn collect(root: &Path, dir: &Path, files: &mut BTreeMap<String, String>) -> DynResult<()> {
    let mut entries: Vec<PathBuf> = std::fs::read_dir(dir)?
        .flatten()
        .map(|entry| entry.path())
        .collect();
    entries.sort();
    for path in entries {
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if name.starts_with('.') {
            continue;
        }
        let metadata = std::fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() {
            let relative = path.strip_prefix(root).unwrap_or(&path).display().to_string();
            return Err(Box::new(BundleError::Symlink { path: relative }));
        }
        if metadata.is_dir() {
            if name == "tests" || name == "target" {
                continue;
            }
            collect(root, &path, files)?;
            continue;
        }
        let relative = path
            .strip_prefix(root)
            .map_err(|_| format!("{} is not under {}", path.display(), root.display()))?
            .to_string_lossy()
            .replace('\\', "/");
        let contents = std::fs::read_to_string(&path)
            .map_err(|_| BundleError::NotUtf8 { path: relative.clone() })?;
        files.insert(relative, contents);
    }
    Ok(())
}

fn header(path: &str, size: usize) -> DynResult<[u8; RECORD]> {
    let mut block = [0u8; RECORD];
    let name_bytes = path.as_bytes();
    block[..name_bytes.len()].copy_from_slice(name_bytes);
    write_octal(&mut block, 100, 8, 0o644); // mode
    write_octal(&mut block, 108, 8, 0); // uid
    write_octal(&mut block, 116, 8, 0); // gid
    write_octal(&mut block, 124, 12, size as u64);
    write_octal(&mut block, 136, 12, 0); // mtime: reproducible bundles
    block[148..156].fill(b' '); // checksum placeholder
    block[156] = b'0';
    block[257..263].copy_from_slice(b"ustar\0");
    block[263..265].copy_from_slice(b"00");
    let checksum: u32 = block.iter().map(|byte| u32::from(*byte)).sum();
    let text = format!("{checksum:06o}\0 ");
    block[148..156].copy_from_slice(text.as_bytes());
    Ok(block)
}

fn write_octal(block: &mut [u8; RECORD], offset: usize, length: usize, value: u64) {
    let text = format!("{:0width$o}", value, width = length - 1);
    block[offset..offset + length - 1].copy_from_slice(text.as_bytes());
    block[offset + length - 1] = 0;
}

fn field(block: &[u8], offset: usize, length: usize) -> String {
    let slice = &block[offset..offset + length];
    let end = slice.iter().position(|byte| *byte == 0).unwrap_or(slice.len());
    String::from_utf8_lossy(&slice[..end]).trim().to_string()
}

fn octal(block: &[u8], offset: usize, length: usize) -> Result<usize, BundleError> {
    let text = field(block, offset, length);
    usize::from_str_radix(text.trim(), 8)
        .map_err(|_| BundleError::Malformed(format!("'{text}' is not an octal size")))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest_json() -> String {
        r#"{
  "schema": 1,
  "id": "io.github.alice.clock",
  "name": "Clock",
  "version": "0.1.0",
  "kernelApi": 1,
  "trust": "community",
  "runtime": "hosted",
  "publisher": { "name": "Alice" },
  "entry": { "root": "shell.qml" },
  "permissions": []
}"#
        .to_string()
    }

    fn bundle() -> Bundle {
        let mut files = BTreeMap::new();
        files.insert("manifest.json".to_string(), manifest_json());
        files.insert(
            "shell.qml".to_string(),
            "import QtQuick\nItem {}\n".to_string(),
        );
        Bundle { files }
    }

    #[test]
    fn an_archive_round_trips() {
        let original = bundle();
        let bytes = original.to_ustar().unwrap();
        let parsed = Bundle::from_ustar(&bytes).unwrap();
        assert_eq!(parsed, original);
    }

    #[test]
    fn the_digest_is_stable_and_content_addressed() {
        let first = bundle().digest().unwrap();
        let second = bundle().digest().unwrap();
        assert_eq!(first, second, "packing the same content twice must agree");
        assert_eq!(first.len(), 64);
        assert!(first.chars().all(|c| c.is_ascii_hexdigit()));

        let mut changed = bundle();
        changed
            .files
            .insert("shell.qml".to_string(), "import QtQuick\nItem { }\n".to_string());
        assert_ne!(changed.digest().unwrap(), first, "content changes the digest");
    }

    #[test]
    fn mtimes_do_not_change_the_digest() {
        // The header writes mtime=0 so two packs of the same source agree.
        let mut first = bundle();
        let mut second = bundle();
        first.files.insert("a.qml".to_string(), "x".to_string());
        second.files.insert("a.qml".to_string(), "x".to_string());
        assert_eq!(first.digest().unwrap(), second.digest().unwrap());
    }

    #[test]
    fn a_missing_manifest_is_refused() {
        let mut files = BTreeMap::new();
        files.insert("shell.qml".to_string(), "Item {}".to_string());
        assert_eq!(
            Bundle { files }.validate().unwrap_err(),
            BundleError::NoManifest
        );
    }

    #[test]
    fn an_invalid_manifest_is_refused_with_the_reason() {
        let mut broken = bundle();
        broken.files.insert(
            "manifest.json".to_string(),
            manifest_json().replace("\"0.1.0\"", "\"0.1\""),
        );
        let error = broken.validate().unwrap_err();
        assert!(error.to_string().contains("version"), "got: {error}");
    }

    #[test]
    fn paths_may_not_escape_the_bundle() {
        for path in ["../evil.qml", "/etc/passwd", "a/../../b.qml"] {
            let mut files = bundle().files.clone();
            files.insert(path.to_string(), String::new());
            assert!(
                matches!(
                    Bundle { files }.validate().unwrap_err(),
                    BundleError::EscapingPath { .. } | BundleError::AbsolutePath { .. }
                ),
                "{path} must be refused"
            );
        }
    }

    #[test]
    fn native_libraries_are_refused() {
        let mut files = bundle().files.clone();
        files.insert("payload/libhelper.so".to_string(), "ELF".to_string());
        assert!(matches!(
            Bundle { files }.validate().unwrap_err(),
            BundleError::NativeLibrary { .. }
        ));
    }

    #[test]
    fn a_truncated_archive_loses_its_entry_and_is_refused() {
        let mut bytes = bundle().to_ustar().unwrap();
        // Keep the manifest, drop everything after it: the manifest is legal, but
        // the entry component it names is gone.
        bytes.truncate(RECORD * 2);
        let error = Bundle::from_ustar(&bytes).unwrap_err();
        assert!(
            matches!(error, BundleError::MissingEntry { .. }),
            "got: {error}"
        );
    }

    #[test]
    fn a_bundle_without_its_entry_component_is_refused() {
        let mut files = bundle().files.clone();
        files.remove("shell.qml");
        let error = Bundle { files }.validate().unwrap_err();
        assert!(
            matches!(error, BundleError::MissingEntry { .. }),
            "got: {error}"
        );
    }

    #[test]
    fn a_symlink_entry_is_refused() {
        let mut bytes = bundle().to_ustar().unwrap();
        // Rewrite the typeflag of the first entry to "symlink".
        bytes[156] = b'2';
        let checksum: u32 = bytes[..RECORD].iter().map(|b| u32::from(*b)).sum();
        let text = format!("{checksum:06o}\0 ");
        bytes[148..156].copy_from_slice(text.as_bytes());
        assert!(matches!(
            Bundle::from_ustar(&bytes).unwrap_err(),
            BundleError::Symlink { .. }
        ));
    }
}
