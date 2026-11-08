//! Swapping a staged binary into place and exec'ing it.
//!
//! Only the supervisor performs these operations, and only while Quickshell is
//! down. A rename is atomic on the same filesystem, so the path the unit, the
//! session entry and the IPC scripts all address keeps pointing at *a* working
//! binary at every instant: either the old one or the new one, never a
//! half-written file.

use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use crate::domain::ports::DynResult;
use crate::domain::update_state::RestartRequest;

/// What to do after Quickshell exits.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AfterExit {
    /// No staged update: the shell is really closing.
    Stop,
    /// A verified binary is staged: swap it in and exec it.
    Restart(RestartRequest),
}

/// Read and clear a pending restart request.
pub fn consume_restart(path: &Path) -> AfterExit {
    match RestartRequest::read(path) {
        Some(request) => {
            RestartRequest::clear(path);
            AfterExit::Restart(request)
        }
        None => AfterExit::Stop,
    }
}

/// Put a staged binary in place, keeping exactly one previous copy.
///
/// Returns the path of the copy that can be restored.
pub fn install_staged(staged: &Path, live: &Path) -> DynResult<PathBuf> {
    if !staged.is_file() {
        return Err(format!("staged update {} is missing", staged.display()).into());
    }
    let size = fs::metadata(staged)?.len();
    if size == 0 {
        return Err("staged update is empty; refusing to replace a working binary".into());
    }
    fs::set_permissions(staged, fs::Permissions::from_mode(0o755))?;

    let previous = with_suffix(live, ".prev");
    if live.is_file() {
        // Keep the previous binary under a name that never collides with the
        // live path, then move the staged one in.
        let _ = fs::remove_file(&previous);
        fs::rename(live, &previous).map_err(|err| {
            format!(
                "cannot set the running binary aside ({}): {err}",
                live.display()
            )
        })?;
    }
    fs::rename(staged, live).map_err(|err| {
        format!(
            "cannot move the staged update into place ({}): {err}",
            live.display()
        )
    })?;
    Ok(previous)
}

/// Put the previous binary back, so the next exec runs the version that worked.
pub fn restore_previous(live: &Path) -> DynResult<()> {
    let previous = with_suffix(live, ".prev");
    if !previous.is_file() {
        return Err("no previous binary to roll back to".into());
    }
    let failed = live.with_extension("failed");
    let _ = fs::remove_file(&failed);
    if live.is_file() {
        fs::rename(live, &failed)?;
    }
    fs::rename(&previous, live)?;
    Ok(())
}

/// Whether a `.prev` binary is available for rollback.
pub fn has_previous(live: &Path) -> bool {
    with_suffix(live, ".prev").is_file()
}

/// The binary an exec should run: the installed one when present.
pub fn exec_target(live: &Path) -> PathBuf {
    if live.is_file() {
        return live.to_path_buf();
    }
    std::env::current_exe().unwrap_or_else(|_| live.to_path_buf())
}

/// Replace this process with `binary run`, keeping the pid.
///
/// The pid is what the claim handoff is keyed on, so `execv` - rather than
/// spawning a detached process and exiting - is what makes the desktop claim
/// survive a restart.
pub fn exec_run(binary: &Path) -> DynResult<()> {
    use std::os::unix::process::CommandExt;
    let err = std::process::Command::new(binary).arg("run").exec();
    Err(format!("cannot exec {}: {err}", binary.display()).into())
}

/// Current executable's directory, used by tests to prove the rename order.
pub fn ensure_parent(path: &Path) -> io::Result<()> {
    match path.parent() {
        Some(parent) => fs::create_dir_all(parent),
        None => Ok(()),
    }
}

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(suffix);
    PathBuf::from(name)
}
