//! Check for, stage and apply a release.
//!
//! The rules live in [`crate::domain::update`]; this module supplies the
//! environment (paths, clock, network source, session lock) and performs the two
//! side effects an update has: placing a verified binary beside the live one,
//! and asking the running shell to exit. The supervisor does the swap and the
//! restart, because only it survives the exit.

use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::domain::branding;
use crate::domain::install_record::{self, InstallMethod, InstallRecord};
use crate::domain::ports::DynResult;
use crate::domain::update::{
    host_arch, select, CandidateView, Channel, IgnoreReason, ReleaseManifest, Selection,
    UpdateCandidate, UpdateSourcePort, MAX_ARTIFACT_BYTES,
};
use crate::domain::update_state::{RestartRequest, RollbackInfo, UpdateState, STATE_SCHEMA};

/// Free space kept beyond the artifact itself, so a download cannot fill the
/// filesystem the desktop is running on.
const FREE_SPACE_MARGIN: u64 = 64 * 1024 * 1024;

/// Environment override for the pinned signing key (see `docs/UPDATES.md`).
pub const ENV_MINISIGN_KEY: &str = "ASTRAL_PLASMA_MINISIGN_KEY";
/// `1` refuses unsigned releases. Turn on once the release key exists.
pub const ENV_REQUIRE_SIGNATURE: &str = "ASTRAL_PLASMA_REQUIRE_SIGNATURE";

#[derive(Debug, Clone)]
pub struct UpdatePaths {
    pub state_path: PathBuf,
    pub record_path: PathBuf,
    pub data_dir: PathBuf,
    pub live_binary: PathBuf,
    pub staged_binary: PathBuf,
    pub prev_binary: PathBuf,
    pub download_dir: PathBuf,
    pub restart_path: PathBuf,
    pub manifest_cache: PathBuf,
    pub signature_cache: PathBuf,
    pub lock_path: PathBuf,
}

impl UpdatePaths {
    pub fn for_user() -> Self {
        let data_dir = branding::data_dir();
        let live_binary = branding::bin_path();
        let state_path = UpdateState::path();
        Self {
            staged_binary: live_binary.with_extension("next"),
            prev_binary: with_suffix(&live_binary, branding::PREV_SUFFIX),
            record_path: branding::install_record_path(),
            restart_path: RestartRequest::path(),
            manifest_cache: branding::state_dir().join("manifest.json"),
            signature_cache: branding::state_dir().join("manifest.json.minisig"),
            lock_path: branding::state_dir().join("update.lock"),
            download_dir: branding::cache_dir().join("update"),
            data_dir,
            live_binary,
            state_path,
        }
    }

    pub fn rooted_at(root: &Path) -> Self {
        let data_dir = root.join("data").join(branding::DATA_DIR);
        let live_binary = data_dir.join(branding::BIN_SUBDIR).join(branding::BIN_FILE);
        let state_dir = root.join("state").join(branding::STATE_DIR);
        Self {
            state_path: state_dir.join("update.json"),
            record_path: data_dir.join(branding::INSTALL_RECORD_FILE),
            staged_binary: live_binary.with_extension("next"),
            prev_binary: with_suffix(&live_binary, branding::PREV_SUFFIX),
            download_dir: root.join("cache").join(branding::CACHE_DIR).join("update"),
            restart_path: state_dir.join("restart-requested.json"),
            manifest_cache: state_dir.join("manifest.json"),
            signature_cache: state_dir.join("manifest.json.minisig"),
            lock_path: state_dir.join("update.lock"),
            data_dir,
            live_binary,
        }
    }
}

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(suffix);
    PathBuf::from(name)
}

/// What the shell and the CLI report.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateStatus {
    pub current_version: String,
    pub channel: String,
    pub install_method: String,
    pub arch: String,
    pub can_apply: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub refuse_reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate: Option<CandidateView>,
    pub last_check_unix: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rollback: Option<RollbackInfo>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_seen_version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub restart_pending: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApplyOutcome {
    pub version: String,
    /// True when the shell was asked to exit and the supervisor will restart it.
    pub restart_requested: bool,
    pub staged_binary: String,
    pub verified_sha256: String,
}

pub struct UpdateService {
    pub paths: UpdatePaths,
    pub source: Box<dyn UpdateSourcePort>,
    pub manifest_url: String,
    pub quickshell_version: Option<String>,
    pub current_version: String,
    /// Refuse releases that carry no signature (see `ENV_REQUIRE_SIGNATURE`).
    pub require_signature: bool,
    /// Skip the interactive guards (session lock). Set only by tests.
    pub ignore_session_lock: bool,
}

impl UpdateService {
    pub fn for_user() -> Self {
        Self {
            paths: UpdatePaths::for_user(),
            source: Box::new(crate::infrastructure::update_source::CurlUpdateSource::new()),
            manifest_url: crate::infrastructure::update_source::manifest_url(),
            quickshell_version: running_quickshell_version(),
            current_version: env!("CARGO_PKG_VERSION").to_string(),
            require_signature: branding::env_value(ENV_REQUIRE_SIGNATURE)
                .map(|value| value == "1")
                .unwrap_or(false),
            ignore_session_lock: branding::test_mode(),
        }
    }

    pub fn with_paths(paths: UpdatePaths, source: Box<dyn UpdateSourcePort>) -> Self {
        Self {
            paths,
            source,
            manifest_url: "https://example.invalid/latest.json".to_string(),
            quickshell_version: Some("0.3.2".to_string()),
            current_version: env!("CARGO_PKG_VERSION").to_string(),
            require_signature: false,
            ignore_session_lock: true,
        }
    }

    pub fn record(&self) -> DynResult<Option<InstallRecord>> {
        InstallRecord::read(&self.paths.record_path)
    }

    /// Method recorded for this install. No record means an old checkout, which
    /// this daemon must not update.
    ///
    /// `pacman` ownership wins over the record: a package can adopt a path after
    /// the record was written, and writing a package manager's files is the
    /// two-owners failure this whole design exists to avoid.
    pub fn install_method(&self) -> DynResult<InstallMethod> {
        let recorded = self.record()?.map(|record| record.method);
        if recorded == Some(InstallMethod::Package) {
            return Ok(InstallMethod::Package);
        }
        if package_owner(&self.paths.live_binary).is_some() {
            return Ok(InstallMethod::Package);
        }
        Ok(recorded.unwrap_or(InstallMethod::Checkout))
    }

    pub fn channel(&self) -> DynResult<Channel> {
        let channel = self
            .record()?
            .map(|record| record.channel)
            .unwrap_or_else(|| "stable".to_string());
        Channel::parse(&channel)
    }

    pub fn status(&self) -> DynResult<UpdateStatus> {
        let state = UpdateState::load(&self.paths.state_path);
        let method = self.install_method()?;
        let channel = self.channel()?;
        let candidate = state.candidate.clone();
        let refusal = refusal(method, candidate.is_some(), state.last_check_unix, &self.paths);
        Ok(UpdateStatus {
            current_version: self.current_version.clone(),
            channel: channel.as_str().to_string(),
            install_method: method.as_str().to_string(),
            arch: host_arch(),
            // Applying needs something to apply *and* no reason to refuse:
            // "checked, nothing available" is not a refusal.
            can_apply: refusal.is_none() && candidate.is_some(),
            refuse_reason: refusal,
            candidate: candidate.as_ref().map(UpdateCandidate::view),
            last_check_unix: state.last_check_unix,
            last_error: state.last_error,
            rollback: state.rollback,
            last_seen_version: state.last_seen_version,
            restart_pending: RestartRequest::read(&self.paths.restart_path)
                .map(|request| request.target_version),
        })
    }

    /// Fetch the manifest and record what it means for this install.
    pub fn check(&self, force: bool) -> DynResult<UpdateStatus> {
        let mut state = UpdateState::load(&self.paths.state_path);
        let channel = self.channel()?;
        let method = self.install_method()?;

        // A package-managed install still learns what is available - it just
        // cannot apply it, and never downloads.
        let etag = if force { None } else { state.etag.clone() };
        let fetched = match self.source.fetch_manifest(&self.manifest_url, etag.as_deref()) {
            Ok(fetched) => fetched,
            Err(err) => {
                state.record_error(err.to_string());
                state.save(&self.paths.state_path)?;
                return Err(err);
            }
        };

        if fetched.not_modified {
            state.last_check_unix = install_record::now_unix();
            state.last_error = None;
            state.save(&self.paths.state_path)?;
            return self.status();
        }

        let manifest = ReleaseManifest::parse(&fetched.body)?;

        // The signature is a sibling asset, verified over the exact bytes that
        // were fetched. A signed release with no key to check it against is
        // refused rather than silently trusted.
        let signature = self.source.fetch_signature(&self.manifest_url)?;
        match &signature {
            Some(signature) => {
                // A verification failure is a *result* the user must be able to
                // read, not just a non-zero exit: record it before returning.
                let outcome = self.signing_key().and_then(|key| {
                    crate::infrastructure::update_source::verify_signature(
                        &fetched.body,
                        signature,
                        &key,
                    )
                });
                if let Err(err) = outcome {
                    state.record_error(err.to_string());
                    state.save(&self.paths.state_path)?;
                    return Err(err);
                }
                self.cache_signature(signature)?;
            }
            None => {
                if self.require_signature {
                    let message = "this build only installs signed releases, and the published release is unsigned";
                    state.record_error(message);
                    state.save(&self.paths.state_path)?;
                    return Err(message.into());
                }
                self.clear_signature_cache();
            }
        }


        self.cache_manifest(&fetched.body)?;

        let selection = select(
            &manifest,
            &self.current_version,
            channel,
            &host_arch(),
            self.quickshell_version.as_deref(),
        );

        match selection {
            Selection::Available(candidate) => {
                state.record_check(fetched.etag, Some(candidate));
                state.save(&self.paths.state_path)?;
            }
            Selection::UpToDate => {
                state.record_check(fetched.etag, None);
                state.save(&self.paths.state_path)?;
            }
            Selection::Ignored(reason) => {
                state.record_check(fetched.etag, None);
                state.last_error = Some(describe_ignore(&reason));
                state.save(&self.paths.state_path)?;
            }
        }
        let _ = method; // ownership is reported by `status`, not by the check
        self.status()
    }

    fn cache_manifest(&self, body: &[u8]) -> DynResult<()> {
        if let Some(parent) = self.paths.manifest_cache.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&self.paths.manifest_cache, body)?;
        Ok(())
    }

    /// Download, verify and stage the candidate; then ask the shell to exit.
    ///
    /// `quit` returns whether a running shell answered. A false answer is not an
    /// error: the staged request is picked up by the next `astral-plasma run`.
    pub fn apply(&self, quit: impl FnOnce() -> bool) -> DynResult<ApplyOutcome> {
        let mut state = UpdateState::load(&self.paths.state_path);
        let method = self.install_method()?;
        if !method.is_self_updatable() {
            return Err(format!(
                "this install is owned by {} ({}). Use your package manager or git to update it.",
                method.as_str(),
                self.paths.record_path.display()
            )
            .into());
        }

        let candidate = state.candidate.clone().ok_or(
            "no update has been checked yet; run `astral-plasma update check` first",
        )?;

        if !self.ignore_session_lock && session_locked() {
            return Err("the session is locked; the update will apply once it is unlocked".into());
        }

        let _lock = UpdateLock::acquire(&self.paths.lock_path)?;

        let required = candidate.size + FREE_SPACE_MARGIN;
        let available = free_bytes(&self.paths.data_dir);
        if let Some(available) = available {
            if available < required {
                return Err(format!(
                    "not enough free space: the update needs {} MiB, {} MiB are free",
                    required / (1024 * 1024),
                    available / (1024 * 1024)
                )
                .into());
            }
        }

        fs::create_dir_all(&self.paths.download_dir)?;
        let download = self.paths.download_dir.join("astral-plasma.next");
        let written = self
            .source
            .download(&candidate.url, &download, MAX_ARTIFACT_BYTES)?;
        if written != candidate.size {
            let _ = fs::remove_file(&download);
            return Err(format!(
                "downloaded {} bytes but the release declares {}; refusing to install",
                written, candidate.size
            )
            .into());
        }

        let digest = crate::infrastructure::update_source::sha256_file(&download)?;
        if digest != candidate.sha256 {
            let _ = fs::remove_file(&download);
            return Err(format!(
                "checksum mismatch for {}: expected {}, got {digest}",
                candidate.version, candidate.sha256
            )
            .into());
        }

        self.verify_signature()?;

        // Place the verified binary beside the live one. The supervisor renames
        // it into place only after the shell is down, so a running shell never
        // execs a half-written file.
        if let Some(parent) = self.paths.staged_binary.parent() {
            fs::create_dir_all(parent)?;
        }
        let _ = fs::remove_file(&self.paths.staged_binary);
        fs::rename(&download, &self.paths.staged_binary)?;
        set_executable(&self.paths.staged_binary)?;

        RestartRequest {
            schema: STATE_SCHEMA,
            target_version: candidate.version.clone(),
            staged_binary: self.paths.staged_binary.to_string_lossy().to_string(),
            at_unix: install_record::now_unix(),
            already_in_place: false,
        }
        .write(&self.paths.restart_path)?;

        state.last_error = None;
        state.save(&self.paths.state_path)?;

        let restart_requested = quit();
        Ok(ApplyOutcome {
            version: candidate.version,
            restart_requested,
            staged_binary: self.paths.staged_binary.to_string_lossy().to_string(),
            verified_sha256: digest,
        })
    }

    /// Re-verify the cached manifest against the cached signature.
    ///
    /// Check already verified it, but the artifact is installed minutes later and
    /// from disk: the bytes that were signed are the bytes that must be staged.
    fn verify_signature(&self) -> DynResult<()> {
        let manifest = fs::read(&self.paths.manifest_cache).map_err(|_| {
            "the release manifest is no longer cached; check again before applying"
        })?;
        let signature = fs::read_to_string(&self.paths.signature_cache).ok();

        match signature {
            Some(signature) if !signature.trim().is_empty() => {
                let key = self.signing_key()?;
                crate::infrastructure::update_source::verify_signature(
                    &manifest,
                    &signature,
                    &key,
                )?;
                Ok(())
            }
            _ if self.require_signature => Err(
                "this build only installs signed releases, and this one is unsigned".into(),
            ),
            _ => Ok(()),
        }
    }

    /// The key a signature is checked against: the pinned project key, or the
    /// documented override for a mirror or a test.
    fn signing_key(&self) -> DynResult<String> {
        branding::env_value(ENV_MINISIGN_KEY)
            .or_else(|| {
                crate::infrastructure::update_source::PINNED_MINISIGN_KEY.map(str::to_string)
            })
            .ok_or_else(|| {
                "this release is signed, but no publisher key is pinned in this build; \
                 set ASTRAL_PLASMA_MINISIGN_KEY to the published key"
                    .into()
            })
    }

    fn cache_signature(&self, signature: &str) -> DynResult<()> {
        if let Some(parent) = self.paths.signature_cache.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&self.paths.signature_cache, signature)?;
        Ok(())
    }

    fn clear_signature_cache(&self) {
        let _ = fs::remove_file(&self.paths.signature_cache);
    }

    /// Put the previous release back and restart into it.
    ///
    /// The swap happens here because there is exactly one previous copy; the
    /// request then only asks the supervisor to exec what is already live.
    pub fn revert(&self, quit: impl FnOnce() -> bool) -> DynResult<ApplyOutcome> {
        if !self.install_method()?.is_self_updatable() {
            return Err("only a managed install can be reverted from here".into());
        }
        if !crate::application::restart::has_previous(&self.paths.live_binary) {
            return Err("there is no previous version to go back to".into());
        }

        let previous_record = InstallRecord::read(&self.paths.record_path.with_extension("json.prev"))?;
        let previous_version = previous_record
            .as_ref()
            .map(|record| record.version.clone())
            .unwrap_or_else(|| "the previous release".to_string());

        crate::application::restart::restore_previous(&self.paths.live_binary)?;
        let _ = install_record::record_version(&previous_version, install_record::now_unix());

        RestartRequest {
            schema: STATE_SCHEMA,
            target_version: previous_version.clone(),
            staged_binary: self.paths.live_binary.to_string_lossy().to_string(),
            at_unix: install_record::now_unix(),
            already_in_place: true,
        }
        .write(&self.paths.restart_path)?;

        let restart_requested = quit();
        Ok(ApplyOutcome {
            version: previous_version,
            restart_requested,
            staged_binary: self.paths.live_binary.to_string_lossy().to_string(),
            verified_sha256: String::new(),
        })
    }

    /// Record that the user has seen this version's notes.
    pub fn mark_seen(&self, version: &str) -> DynResult<()> {
        let mut state = UpdateState::load(&self.paths.state_path);
        state.last_seen_version = Some(version.to_string());
        state.save(&self.paths.state_path)
    }
}

/// Why this install cannot apply an update right now.
///
/// `None` means "nothing stands in the way" - which is *not* the same as "there
/// is an update": an install that was checked and is current has no refusal and
/// no candidate. Conflating the two made the page tell a checked, up-to-date
/// install that it had never been checked.
fn refusal(
    method: InstallMethod,
    has_candidate: bool,
    last_check_unix: u64,
    paths: &UpdatePaths,
) -> Option<String> {
    match method {
        InstallMethod::Package => Some(
            "Your package manager owns this install; update it with pacman.".to_string(),
        ),
        InstallMethod::Checkout => Some(
            "This is a git checkout; update it with `git pull`.".to_string(),
        ),
        InstallMethod::Managed => {
            if !has_candidate && last_check_unix == 0 {
                Some("No update has been checked yet.".to_string())
            } else if has_candidate && RestartRequest::read(&paths.restart_path).is_some() {
                Some("An update is already staged and waiting for a restart.".to_string())
            } else {
                None
            }
        }
    }
}

fn describe_ignore(reason: &IgnoreReason) -> String {
    match reason {
        IgnoreReason::Channel => "The newer release is on another channel.".to_string(),
        IgnoreReason::Architecture { arch } => {
            format!("The newer release has no build for {arch}.")
        }
        IgnoreReason::RuntimeFloor { required, running } => format!(
            "The newer release needs Quickshell {required}, this session runs {}.",
            running.as_deref().unwrap_or("an unknown version")
        ),
    }
}

/// Exclusive lock so two applies cannot interleave their renames.
struct UpdateLock {
    path: PathBuf,
}

impl UpdateLock {
    fn acquire(path: &Path) -> DynResult<Self> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        for attempt in 0..2 {
            match fs::OpenOptions::new().create_new(true).write(true).open(path) {
                Ok(mut file) => {
                    let _ = writeln!(file, "{}", std::process::id());
                    return Ok(Self {
                        path: path.to_path_buf(),
                    });
                }
                Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => {
                    if attempt == 0 && lock_is_stale(path) {
                        let _ = fs::remove_file(path);
                        continue;
                    }
                    return Err("another update is already running".into());
                }
                Err(err) => return Err(Box::new(err)),
            }
        }
        Err("could not acquire the update lock".into())
    }
}

impl Drop for UpdateLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn lock_is_stale(path: &Path) -> bool {
    let Ok(meta) = fs::metadata(path) else {
        return false;
    };
    let Ok(modified) = meta.modified() else {
        return false;
    };
    modified
        .elapsed()
        .map(|age| age.as_secs() > 3_600)
        .unwrap_or(false)
}

/// Whether KDE's screen locker currently holds the session.
///
/// An unknowable answer is `false`: blocking updates because a DBus probe is
/// unavailable would strand every non-KDE session.
fn session_locked() -> bool {
    if branding::test_mode() {
        return false;
    }
    let output = std::process::Command::new("qdbus6")
        .args([
            "org.kde.ScreenSaver",
            "/ScreenSaver",
            "org.freedesktop.ScreenSaver.GetActive",
        ])
        .output();
    match output {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).trim() == "true"
        }
        _ => false,
    }
}

/// Free bytes on the filesystem holding `path`, when it can be determined.
fn free_bytes(path: &Path) -> Option<u64> {
    use std::ffi::CString;
    let c_path = CString::new(path.to_string_lossy().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    let result = unsafe { libc::statvfs(c_path.as_ptr(), &mut stat) };
    if result != 0 {
        return None;
    }
    Some(stat.f_bavail as u64 * stat.f_frsize as u64)
}

fn set_executable(path: &Path) -> DynResult<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o755))?;
    Ok(())
}


/// Package that owns `exe`, when the system package manager says so.
///
/// Returns `None` on any other distro, for a user-owned path, or when pacman is
/// absent - every one of those is "not a package install" as far as updates are
/// concerned.
pub fn package_owner(exe: &Path) -> Option<String> {
    if branding::test_mode() {
        // Tests drive `parse_pacman_owner` directly; probing the live package
        // database from a suite would describe the machine, not the fixture.
        return None;
    }
    let output = std::process::Command::new("pacman")
        .arg("-Qo")
        .arg(exe)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    parse_pacman_owner(&String::from_utf8_lossy(&output.stdout))
}

/// Parse `pacman -Qo`: `usr/bin/astral-plasma is owned by astral-plasma-bin 0.1.3-1`.
pub fn parse_pacman_owner(text: &str) -> Option<String> {
    let (_, rest) = text.split_once(" is owned by ")?;
    let package = rest.split_whitespace().next()?;
    (!package.is_empty()).then(|| package.to_string())
}

/// Version of the Quickshell binary on this machine, if it answers.
pub fn running_quickshell_version() -> Option<String> {
    let output = std::process::Command::new("quickshell").arg("--version").output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    text.split_whitespace().find(|token| {
        token.chars().next().is_some_and(|c| c.is_ascii_digit()) && token.contains('.')
    })
    .map(|token| token.trim_end_matches(',').to_string())
}
