//! Release manifest and artifact transport over `curl`.
//!
//! The daemon deliberately does not link a TLS/HTTP stack: the binary is already
//! ~22 MB, `curl` is present on every Arch install and is what the installer
//! itself uses, and it gives us redirect handling, protocol pinning and ETags
//! for free.
//!
//! Two rules are enforced here rather than trusted from the caller:
//! * the scheme decides the allowed protocols, so an `https` manifest can never
//!   be redirected to plain `http`;
//! * a download that exceeds the declared size is stopped by byte limit, not by
//!   hoping the server tells the truth.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::domain::ports::DynResult;
use crate::domain::update::{ManifestFetch, UpdateSourcePort};

/// Default manifest location: the newest published release.
pub const DEFAULT_MANIFEST_URL: &str =
    "https://github.com/gitawego/astral-plasma/releases/latest/download/latest.json";

/// Environment override, used by mirrors and by the test suite.
pub const ENV_MANIFEST_URL: &str = "ASTRAL_PLASMA_UPDATE_URL";

/// Public key this build trusts for release signatures.
///
/// `None` until the project key is published (see `scripts/astral-sign.sh`).
/// Filling this in is what makes a signature check meaningful to a user who has
/// not set an environment variable; until then a signed release is verified only
/// when `ASTRAL_PLASMA_MINISIGN_KEY` provides the key, and a signature without a
/// key is refused rather than checked against the user's own keyring.
pub const PINNED_MINISIGN_KEY: Option<&str> = None;

const CONNECT_TIMEOUT_SECS: u32 = 15;
const MANIFEST_TIMEOUT_SECS: u32 = 30;
const ARTIFACT_TIMEOUT_SECS: u32 = 600;

/// Manifest URL this process should use.
pub fn manifest_url() -> String {
    crate::domain::branding::env_value(ENV_MANIFEST_URL).unwrap_or_else(|| DEFAULT_MANIFEST_URL.to_string())
}

#[derive(Debug, Clone, Default)]
pub struct CurlUpdateSource;

impl CurlUpdateSource {
    pub fn new() -> Self {
        Self
    }
}

impl UpdateSourcePort for CurlUpdateSource {
    fn fetch_manifest(&self, url: &str, etag: Option<&str>) -> DynResult<ManifestFetch> {
        let work = temp_path("manifest");
        let headers = temp_path("headers");
        let _ = fs::remove_file(&work);

        let mut command = Command::new("curl");
        command
            .arg("--silent")
            .arg("--show-error")
            .arg("--location")
            .arg("--fail")
            .args(["--connect-timeout", &CONNECT_TIMEOUT_SECS.to_string()])
            .args(["--max-time", &MANIFEST_TIMEOUT_SECS.to_string()])
            .arg("--proto")
            .arg(protocols_for(url))
            .arg("--dump-header")
            .arg(&headers)
            .arg("--output")
            .arg(&work)
            .arg("--write-out")
            .arg("%{http_code}");
        if let Some(etag) = etag.filter(|value| !value.trim().is_empty()) {
            command.arg("--header").arg(format!("If-None-Match: {etag}"));
        }
        command.arg(url);

        let output = command.output().map_err(|err| {
            format!("cannot run curl to reach the release manifest: {err} (install curl or set a mirror)")
        })?;

        let status = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !output.status.success() {
            let reason = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let _ = fs::remove_file(&work);
            return Err(format!("release manifest fetch failed ({status}): {reason}").into());
        }

        if status == "304" {
            let _ = fs::remove_file(&work);
            return Ok(ManifestFetch {
                not_modified: true,
                etag: etag.map(str::to_string),
                body: Vec::new(),
            });
        }
        if status != "200" {
            let _ = fs::remove_file(&work);
            return Err(format!("release manifest answered HTTP {status}").into());
        }

        let etag = read_etag(&headers);
        let body = fs::read(&work).map_err(|err| format!("cannot read fetched manifest: {err}"))?;
        let _ = fs::remove_file(&work);
        let _ = fs::remove_file(&headers);
        Ok(ManifestFetch {
            not_modified: false,
            etag,
            body,
        })
    }

    fn download(&self, url: &str, dest: &Path, max_bytes: u64) -> DynResult<u64> {
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)?;
        }
        let partial = dest.with_extension("part");
        let _ = fs::remove_file(&partial);

        let status = Command::new("curl")
            .arg("--silent")
            .arg("--show-error")
            .arg("--location")
            .arg("--fail")
            .args(["--connect-timeout", &CONNECT_TIMEOUT_SECS.to_string()])
            .args(["--max-time", &ARTIFACT_TIMEOUT_SECS.to_string()])
            .args(["--max-filesize", &max_bytes.to_string()])
            .arg("--proto")
            .arg(protocols_for(url))
            .arg("--output")
            .arg(&partial)
            .arg(url)
            .status()
            .map_err(|err| format!("cannot run curl to download the update: {err}"))?;

        if !status.success() {
            let _ = fs::remove_file(&partial);
            return Err("update download failed or exceeded the size limit".into());
        }

        let written = fs::metadata(&partial)
            .map_err(|err| format!("downloaded update is unreadable: {err}"))?
            .len();
        if written == 0 || written > max_bytes {
            let _ = fs::remove_file(&partial);
            return Err(format!("downloaded update has an unacceptable size ({written} bytes)").into());
        }
        fs::rename(&partial, dest)?;
        Ok(written)
    }
}

/// `https` only, or `http` only when the caller explicitly asked for an `http`
/// URL (a local mirror or the test server). This is what stops a redirect from
/// silently downgrading transport.
fn protocols_for(url: &str) -> &'static str {
    if url.trim_start().to_ascii_lowercase().starts_with("http://") {
        "=http"
    } else {
        "=https"
    }
}

fn read_etag(path: &Path) -> Option<String> {
    let text = fs::read_to_string(path).ok()?;
    text.lines()
        .filter_map(|line| line.split_once(':').map(|(name, value)| (name.trim(), value.trim())))
        .find(|(name, _)| name.eq_ignore_ascii_case("etag"))
        .map(|(_, value)| value.trim_matches('"').to_string())
}

fn temp_path(prefix: &str) -> PathBuf {
    crate::domain::branding::tmp_file(&format!("update_{prefix}_{}", std::process::id()))
}

/// `sha256` of a file, streamed so a large artifact is never held in memory.
pub fn sha256_file(path: &Path) -> DynResult<String> {
    use sha2::{Digest, Sha256};
    use std::io::Read;

    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

/// Verify a detached minisign signature when the release carries one.
///
/// Returns `Ok(true)` when a signature was present and verified, `Ok(false)`
/// when the release is unsigned, and an error when verification fails or the
/// tool is missing while a signature was claimed.
pub fn verify_minisign(signed_file: &Path, signature: &str, public_key: Option<&str>) -> DynResult<bool> {
    let signature = signature.trim();
    if signature.is_empty() || signature == "null" {
        return Ok(false);
    }
    let signature_path = signed_file.with_extension("minisig");
    fs::write(&signature_path, signature)?;

    let mut command = Command::new("minisign");
    command.arg("-Vm").arg(signed_file).arg("-x").arg(&signature_path);
    if let Some(key) = public_key.filter(|k| !k.trim().is_empty()) {
        command.arg("-P").arg(key);
    }
    let output = command
        .output()
        .map_err(|err| format!("minisign is required to verify this release: {err}"))?;
    let _ = fs::remove_file(&signature_path);
    if !output.status.success() {
        return Err(format!(
            "release signature verification failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )
        .into());
    }
    Ok(true)
}
