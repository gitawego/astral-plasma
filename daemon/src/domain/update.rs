//! Release discovery: what a published release looks like, and whether it is an
//! update for *this* install.
//!
//! The daemon reads exactly one document to decide. Everything here is pure: no
//! network, no filesystem, no clock - the caller supplies the manifest, the
//! running version and the channel, so every rule below is testable without a
//! live desktop.

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::BTreeMap;

use crate::domain::ports::DynResult;

/// Largest artifact this daemon will download. A release binary is ~22 MB; the
/// cap only has to be big enough for that and small enough that a hostile
/// manifest cannot ask for a disk-filling download.
pub const MAX_ARTIFACT_BYTES: u64 = 128 * 1024 * 1024;

/// Manifest schema this build understands.
pub const MANIFEST_SCHEMA: u32 = 1;

/// Channel an install follows.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Channel {
    Stable,
    Beta,
}

impl Channel {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Stable => "stable",
            Self::Beta => "beta",
        }
    }

    pub fn parse(value: &str) -> DynResult<Self> {
        match value.trim() {
            "stable" => Ok(Self::Stable),
            "beta" => Ok(Self::Beta),
            other => Err(format!("unknown channel '{other}' (expected stable or beta)").into()),
        }
    }

    /// Whether a release published on `release_channel` is offered to this one.
    /// A stable install never receives a beta; a beta install still receives
    /// stable releases, because stable is the newer of the two when beta testing
    /// ends.
    fn accepts(self, release: &str) -> bool {
        match self {
            Self::Beta => true,
            Self::Stable => release.trim().eq_ignore_ascii_case("stable"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Artifact {
    pub url: String,
    pub sha256: String,
    pub size: u64,
}

/// `latest.json`, published beside the release artifacts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReleaseManifest {
    pub schema: u32,
    pub version: String,
    #[serde(default = "default_channel")]
    pub channel: String,
    #[serde(default)]
    pub published_at: Option<String>,
    #[serde(default)]
    pub min_quickshell: Option<String>,
    #[serde(default)]
    pub highlights: Vec<String>,
    #[serde(default)]
    pub changelog: Option<String>,
    #[serde(default)]
    pub artifacts: BTreeMap<String, Artifact>,
    /// Reserved: detached signature over the manifest. Present but unverified
    /// signatures are refused; see `application::update_service`.
    #[serde(default)]
    pub signature: Option<String>,
}

fn default_channel() -> String {
    "stable".to_string()
}

impl ReleaseManifest {
    pub fn parse(bytes: &[u8]) -> DynResult<Self> {
        let manifest: Self = serde_json::from_slice(bytes)
            .map_err(|err| format!("release manifest is not valid JSON: {err}"))?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn validate(&self) -> DynResult<()> {
        if self.schema != MANIFEST_SCHEMA {
            return Err(format!(
                "release manifest schema {} is not supported by this build (expected {MANIFEST_SCHEMA})",
                self.schema
            )
            .into());
        }
        if !is_version(&self.version) {
            return Err(format!("release manifest has an invalid version '{}'", self.version).into());
        }
        if self.artifacts.is_empty() {
            return Err("release manifest lists no artifacts".into());
        }
        for (arch, artifact) in &self.artifacts {
            if artifact.url.trim().is_empty() {
                return Err(format!("artifact for {arch} has no url").into());
            }
            if artifact.sha256.len() != 64 || !artifact.sha256.chars().all(|c| c.is_ascii_hexdigit()) {
                return Err(format!(
                    "artifact for {arch} has no valid sha256 digest; an update without one \
                     cannot be verified and is not installable"
                )
                .into());
            }
            if artifact.size == 0 || artifact.size > MAX_ARTIFACT_BYTES {
                return Err(format!(
                    "artifact for {arch} declares {} bytes, outside the accepted range \
                     (1 ..= {MAX_ARTIFACT_BYTES})",
                    artifact.size
                )
                .into());
            }
        }
        Ok(())
    }

    pub fn artifact_for(&self, arch: &str) -> Option<&Artifact> {
        self.artifacts.get(arch)
    }
}

/// A release this install can actually install.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateCandidate {
    pub version: String,
    pub channel: String,
    pub highlights: Vec<String>,
    pub changelog: Option<String>,
    pub url: String,
    pub sha256: String,
    pub size: u64,
}

impl UpdateCandidate {
    /// The JSON shape the shell consumes; kept flat so the QML side has no
    /// nested-shape knowledge.
    pub fn view(&self) -> CandidateView {
        CandidateView {
            version: self.version.clone(),
            highlights: self.highlights.clone(),
            changelog: self.changelog.clone(),
            size: self.size,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CandidateView {
    pub version: String,
    pub highlights: Vec<String>,
    pub changelog: Option<String>,
    pub size: u64,
}

/// Result of comparing a manifest against this install.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Selection {
    /// Strictly newer and on an accepted channel, with an artifact for this
    /// architecture.
    Available(UpdateCandidate),
    /// The same or an older version.
    UpToDate,
    /// Newer, but not offered: channel, architecture, or runtime floor.
    Ignored(IgnoreReason),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IgnoreReason {
    Channel,
    Architecture { arch: String },
    RuntimeFloor { required: String, running: Option<String> },
}

/// Decide whether `manifest` is an update for a shell at `current_version`.
pub fn select(
    manifest: &ReleaseManifest,
    current_version: &str,
    channel: Channel,
    arch: &str,
    running_quickshell: Option<&str>,
) -> Selection {
    if !channel.accepts(&manifest.channel) {
        return Selection::Ignored(IgnoreReason::Channel);
    }

    if let Some(required) = manifest.min_quickshell.as_deref() {
        let satisfied = running_quickshell
            .map(|running| !version_gt(required, running))
            .unwrap_or(false);
        if !satisfied {
            return Selection::Ignored(IgnoreReason::RuntimeFloor {
                required: required.to_string(),
                running: running_quickshell.map(str::to_string),
            });
        }
    }

    let Some(artifact) = manifest.artifact_for(arch) else {
        return Selection::Ignored(IgnoreReason::Architecture {
            arch: arch.to_string(),
        });
    };

    if !version_gt(&manifest.version, current_version) {
        return Selection::UpToDate;
    }

    Selection::Available(UpdateCandidate {
        version: manifest.version.clone(),
        channel: manifest.channel.clone(),
        highlights: manifest.highlights.clone(),
        changelog: manifest.changelog.clone(),
        url: artifact.url.clone(),
        sha256: artifact.sha256.to_ascii_lowercase(),
        size: artifact.size,
    })
}

/// Architecture key used by the manifest (`x86_64`, `aarch64`).
pub fn host_arch() -> String {
    match std::env::consts::ARCH {
        "x86_64" => "x86_64".to_string(),
        "aarch64" => "aarch64".to_string(),
        other => other.to_string(),
    }
}

/// `a` is a valid `MAJOR.MINOR.PATCH[-prerelease]` version.
pub fn is_version(text: &str) -> bool {
    let text = text.trim();
    let (core, pre) = match text.split_once('-') {
        Some((core, pre)) => (core, Some(pre)),
        None => (text, None),
    };
    let parts: Vec<&str> = core.split('.').collect();
    if parts.len() != 3 || parts.iter().any(|p| p.is_empty() || !p.chars().all(|c| c.is_ascii_digit())) {
        return false;
    }
    match pre {
        None => true,
        Some(pre) => !pre.is_empty() && pre.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-'),
    }
}

/// Strictly greater version comparison.
///
/// A prerelease sorts below its release (`0.2.0-beta < 0.2.0`), which is what
/// keeps a beta install from refusing the stable release that supersedes it.
pub fn version_gt(a: &str, b: &str) -> bool {
    compare_versions(a, b) == Ordering::Greater
}

pub fn compare_versions(a: &str, b: &str) -> Ordering {
    let (a_core, a_pre) = split_version(a);
    let (b_core, b_pre) = split_version(b);
    for index in 0..a_core.len().max(b_core.len()) {
        let left = *a_core.get(index).unwrap_or(&0);
        let right = *b_core.get(index).unwrap_or(&0);
        if left != right {
            return left.cmp(&right);
        }
    }
    match (a_pre, b_pre) {
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Greater,
        (Some(_), None) => Ordering::Less,
        (Some(left), Some(right)) => left.cmp(&right),
    }
}

fn split_version(text: &str) -> (Vec<u32>, Option<String>) {
    let text = text.trim();
    let (core, pre) = match text.split_once('-') {
        Some((core, pre)) => (core, Some(pre.to_string())),
        None => (text, None),
    };
    let numbers = core
        .split('.')
        .map(|part| part.parse::<u32>().unwrap_or(0))
        .collect();
    (numbers, pre)
}

/// Result of fetching a manifest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManifestFetch {
    /// `true` when the server answered `304 Not Modified`.
    pub not_modified: bool,
    pub etag: Option<String>,
    pub body: Vec<u8>,
}

/// Network access, behind a port so the update rules never need a socket.
pub trait UpdateSourcePort {
    fn fetch_manifest(&self, url: &str, etag: Option<&str>) -> DynResult<ManifestFetch>;
    /// Download an artifact to `dest`, refusing to exceed `max_bytes`.
    /// Returns the number of bytes written.
    fn download(&self, url: &str, dest: &std::path::Path, max_bytes: u64) -> DynResult<u64>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_ordering_handles_prereleases() {
        assert!(version_gt("0.2.0", "0.1.3"));
        assert!(version_gt("0.2.0", "0.2.0-beta"));
        assert!(!version_gt("0.2.0-beta", "0.2.0"));
        assert!(!version_gt("0.1.3", "0.1.3"));
        assert!(version_gt("1.0.0", "0.99.99"));
    }
}
