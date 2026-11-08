//! What the updater remembers between runs.
//!
//! This file is a cache and a journal, never a source of truth about the
//! install: deleting it must cost a check and nothing else. It therefore loads
//! as a default when missing *or* unreadable, and is always written atomically.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

use crate::domain::branding;
use crate::domain::install_record::now_unix;
use crate::domain::ports::DynResult;
use crate::domain::update::UpdateCandidate;

pub const STATE_SCHEMA: u32 = 1;

/// A rollback that already happened, kept so the UI can explain it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RollbackInfo {
    pub version: String,
    pub reason: String,
    pub at_unix: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateState {
    pub schema: u32,
    #[serde(default)]
    pub last_check_unix: u64,
    #[serde(default)]
    pub etag: Option<String>,
    #[serde(default)]
    pub candidate: Option<UpdateCandidate>,
    #[serde(default)]
    pub last_error: Option<String>,
    #[serde(default)]
    pub rollback: Option<RollbackInfo>,
    /// Consecutive restarts that did not come up. Two trigger a rollback.
    #[serde(default)]
    pub failed_starts: u32,
    /// Version whose changelog the user has already been shown.
    #[serde(default)]
    pub last_seen_version: Option<String>,
}

impl Default for UpdateState {
    fn default() -> Self {
        Self {
            schema: STATE_SCHEMA,
            last_check_unix: 0,
            etag: None,
            candidate: None,
            last_error: None,
            rollback: None,
            failed_starts: 0,
            last_seen_version: None,
        }
    }
}

impl UpdateState {
    /// Path of the live state file.
    pub fn path() -> PathBuf {
        branding::state_dir().join("update.json")
    }

    /// Load, treating a missing or unreadable file as "nothing known yet".
    ///
    /// A corrupt cache must never block updating: the worst outcome of taking the
    /// default is one extra check.
    pub fn load(path: &Path) -> Self {
        let Ok(text) = fs::read_to_string(path) else {
            return Self::default();
        };
        let Ok(mut state) = serde_json::from_str::<Self>(&text) else {
            return Self::default();
        };
        if state.schema != STATE_SCHEMA {
            return Self::default();
        }
        // A candidate whose digest was tampered with in the cache is not a
        // candidate: it would install an unverified artifact.
        if let Some(candidate) = &state.candidate {
            if candidate.sha256.len() != 64 || candidate.url.trim().is_empty() {
                state.candidate = None;
            }
        }
        state
    }

    pub fn save(&self, path: &Path) -> DynResult<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, format!("{}\n", serde_json::to_string_pretty(self)?))?;
        fs::rename(&tmp, path)?;
        Ok(())
    }

    /// Record a completed check: clear the previous error, keep the rest.
    pub fn record_check(&mut self, etag: Option<String>, candidate: Option<UpdateCandidate>) {
        self.last_check_unix = now_unix();
        self.etag = etag;
        self.candidate = candidate;
        self.last_error = None;
    }

    pub fn record_error(&mut self, error: impl Into<String>) {
        self.last_check_unix = now_unix();
        self.last_error = Some(error.into());
    }
}

/// A pending restart written by `update apply` and consumed by the supervisor.
///
/// The supervisor reads it after Quickshell exits; the new binary is already
/// verified and staged beside the live one, so the swap is a rename.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RestartRequest {
    pub schema: u32,
    pub target_version: String,
    /// Staged executable (`bin/astral-plasma.next`).
    pub staged_binary: String,
    pub at_unix: u64,
    /// Set by a manual revert: the binary at `staged_binary` is already the live
    /// one, so the supervisor must exec it without swapping again.
    #[serde(default)]
    pub already_in_place: bool,
}

impl RestartRequest {
    pub fn path() -> PathBuf {
        branding::state_dir().join("restart-requested.json")
    }

    pub fn read(path: &Path) -> Option<Self> {
        let text = fs::read_to_string(path).ok()?;
        let request: Self = serde_json::from_str(&text).ok()?;
        (request.schema == STATE_SCHEMA && !request.staged_binary.is_empty()).then_some(request)
    }

    pub fn write(&self, path: &Path) -> DynResult<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, format!("{}\n", serde_json::to_string_pretty(self)?))?;
        fs::rename(&tmp, path)?;
        Ok(())
    }

    pub fn clear(path: &Path) {
        let _ = fs::remove_file(path);
    }
}

/// The marker proving the Plasma claim is already held by this session.
///
/// Written once when the supervisor takes the claim, inherited across the
/// `execv` that installs an update. Without it the restarted shell would take a
/// second claim on a desktop that is still claimed, and hand back the user's
/// panels twice.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClaimHandoff {
    pub schema: u32,
    pub boot_id: Option<String>,
    pub supervisor_pid: u32,
    pub at_unix: u64,
}

impl ClaimHandoff {
    pub fn path() -> PathBuf {
        branding::state_dir().join("claim-handoff.json")
    }

    pub fn read(path: &Path) -> Option<Self> {
        let text = fs::read_to_string(path).ok()?;
        let handoff: Self = serde_json::from_str(&text).ok()?;
        (handoff.schema == STATE_SCHEMA).then_some(handoff)
    }

    pub fn write(&self, path: &Path) -> DynResult<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, format!("{}\n", serde_json::to_string_pretty(self)?))?;
        fs::rename(&tmp, path)?;
        Ok(())
    }

    pub fn clear(path: &Path) {
        let _ = fs::remove_file(path);
    }

    /// Whether a restarted shell may skip taking a claim.
    ///
    /// Both halves matter: the marker must belong to *this* boot (a stale marker
    /// from a machine that crashed mid-update would otherwise make the shell
    /// believe a claim it never took) and to the process that is starting now.
    pub fn covers(&self, boot_id: Option<&str>, supervisor_pid: u32) -> bool {
        let boot_matches = match (&self.boot_id, boot_id) {
            (Some(marked), Some(current)) => marked == current,
            _ => false,
        };
        boot_matches && self.supervisor_pid == supervisor_pid
    }
}
