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
/// This is the project release key (`packaging/keys/astral-plasma.pub`). It is
/// compiled in so a signed release verifies for every user without an
/// environment variable; `ASTRAL_PLASMA_MINISIGN_KEY` overrides it for mirrors
/// and tests. A signature with no key to check it against is refused rather than
/// compared with the user's own keyring.
pub const PINNED_MINISIGN_KEY: Option<&str> =
    Some("RWRZ7vlQFmz2R+Mk9rLAG2YZx1FR2KyCYrRPUYKPnUGYtOlk8GtFDiox");

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

    fn fetch_signature(&self, manifest_url: &str) -> DynResult<Option<String>> {
        let url = format!("{manifest_url}.minisig");
        let output = Command::new("curl")
            .arg("--silent")
            .arg("--show-error")
            .arg("--location")
            .arg("--proto")
            .arg(protocols_for(&url))
            .args(["--connect-timeout", &CONNECT_TIMEOUT_SECS.to_string()])
            .args(["--max-time", &MANIFEST_TIMEOUT_SECS.to_string()])
            .arg("--write-out")
            .arg("%{http_code}")
            .arg("--output")
            .arg(crate::domain::branding::tmp_file("update_sig"))
            .arg(&url)
            .output()
            .map_err(|err| format!("cannot run curl to fetch the release signature: {err}"))?;

        let path = crate::domain::branding::tmp_file("update_sig");
        let status = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let result: DynResult<Option<String>> = match status.as_str() {
            "200" => match fs::read_to_string(&path) {
                Ok(body) if !body.trim().is_empty() => Ok(Some(body)),
                _ => Err("the release signature asset is empty".into()),
            },
            // A release published before signing existed has no signature asset.
            "404" => Ok(None),
            other => Err(format!("release signature fetch answered HTTP {other}").into()),
        };
        let _ = fs::remove_file(&path);
        result
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

/// Verify a detached minisign signature over the manifest bytes.
///
/// Verification is done in-process with the `minisign-verify` crate rather than
/// by running the `minisign` binary: a user who installs a signed release has no
/// reason to have the signing tool on their machine, and a missing tool must not
/// turn every update into a refusal. Signing still uses the real tool in CI, and
/// the formats are identical.
///
/// Returns `Ok(false)` for an unsigned release, `Ok(true)` when a signature was
/// present and verified, and an error when it did not verify.
pub fn verify_signature(manifest: &[u8], signature: &str, public_key: &str) -> DynResult<bool> {
    let signature = signature.trim();
    if signature.is_empty() || signature == "null" {
        return Ok(false);
    }

    let key = minisign_verify::PublicKey::from_base64(public_key.trim()).map_err(|err| {
        format!("the pinned release key is not a usable minisign public key: {err}")
    })?;
    let signature = minisign_verify::Signature::decode(signature)
        .map_err(|err| format!("the release signature is malformed: {err}"))?;

    key.verify(manifest, &signature, false)
        .map_err(|err| format!("release signature verification failed: {err}"))?;
    Ok(true)
}
