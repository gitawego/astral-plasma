use crate::domain::branding;
use crate::domain::plasma::PlasmaStatus;
use crate::domain::ports::{DynResult, PlasmaControlPort, ShortcutControlPort};
use crate::infrastructure::plasma_adapter::{is_watchdog_process, watchdog_pid_file};
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::Arc;
use std::time::{Duration, Instant};

/// How long the incoming session waits for an outgoing watchdog's hand-back.
pub const RESTORE_HANDOVER_TIMEOUT: Duration = Duration::from_secs(15);

/// Waits for an in-progress hand-back to finish.
///
/// A theme restart starts the incoming session while the outgoing watchdog may
/// still be restoring panels and shortcuts (it holds `plasma-backup/.restoring`
/// for the duration). Killing it mid-restore, or claiming the desktop while it
/// runs, interleaves two claims: the shortcuts are left half-restored and the
/// incoming `bind_shortcuts` skips its work because the journal still looks
/// current. The incoming session therefore waits for the lock to clear first.
/// The wait is bounded, so startup can never hang on a stale lock left by a
/// crashed restore - the restore path itself treats a >10 s lock as stale.
pub fn wait_for_restore_to_finish(backup_dir: &Path, timeout: Duration) {
    let lock = backup_dir.join(".restoring");
    let deadline = Instant::now() + timeout;
    while lock.exists() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(200));
    }
}

/// Async form of [`wait_for_restore_to_finish`].
///
/// The daemon runs on a tokio runtime whose I/O and timer drivers are polled by
/// the worker threads: a `std::thread::sleep` loop on one of them parks the
/// thread for up to `RESTORE_HANDOVER_TIMEOUT` and can leave the drivers
/// unpolled, which freezes every D-Bus reply, timer and shortcut in the process.
/// Async callers therefore use this form, which yields to the runtime.
pub async fn wait_for_restore_to_finish_async(backup_dir: &Path, timeout: Duration) {
    let lock = backup_dir.join(".restoring");
    let deadline = Instant::now() + timeout;
    while lock.exists() && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(200)).await;
    }
}

#[derive(Clone)]
pub struct PlasmaControlUseCase<P: PlasmaControlPort> {
    port: P,
}

impl<P: PlasmaControlPort> PlasmaControlUseCase<P> {
    pub fn new(port: P) -> Self {
        Self { port }
    }

    pub fn get_status(&self) -> DynResult<PlasmaStatus> {
        self.port.get_status()
    }

    pub fn backup_and_disable(&self, target: &str, monitor_pid: Option<u32>) -> DynResult<u32> {
        let count = self.port.disable_panels(target)?;

        if let Some(pid) = monitor_pid {
            if pid > 0 && !branding::test_mode() {
                // The stop and the spawn are one hand-over: two processes perform
                // it at session start (this daemon's startup and the `plasma
                // disable` the shell runs from QML), and an unserialized `stop`
                // that lands after the last `spawn` leaves the session with no
                // watchdog at all - the shell then exits without handing the
                // panels back.
                with_watchdog_lock(|| {
                    self.port.stop_watchdog();
                    spawn_watchdog(pid);
                });
            }
        }

        Ok(count)
    }

    pub fn restore(&self) -> DynResult<bool> {
        self.port.restore_config()
    }
}

/// Claims the watchdog pid file for `self_pid`.
///
/// The file names the watchdog that supervises this session. A second watchdog
/// must not overwrite it: the session would lose track of its watchdog (so a
/// later `stop_watchdog` could not release it) and be left with two - or, once
/// the extra one exits and removes the file, with none at all, which is how the
/// panels end up never being handed back. A stale file (no live owner) is
/// replaced; a live owner keeps its claim.
pub fn claim_watchdog_pid_file(pid_file: &Path, self_pid: u32) -> bool {
    with_watchdog_lock(|| {
        if let Ok(content) = fs::read_to_string(pid_file) {
            if let Ok(existing) = content.trim().parse::<i32>() {
                let self_pid = self_pid as i32;
                if existing > 0
                    && existing != self_pid
                    && unsafe { libc::kill(existing, 0) } == 0
                    && crate::infrastructure::plasma_adapter::is_watchdog_process(existing)
                {
                    return false;
                }
            }
        }
        fs::write(pid_file, self_pid.to_string()).is_ok()
    })
}

/// Runs `f` with the watchdog hand-over lock held.
///
/// Two processes stop-and-spawn the watchdog when a session starts: the daemon's
/// own startup and the `plasma disable` call the shell runs from its QML. Their
/// `stop`/`spawn` pairs must not interleave - a `stop` that lands after the last
/// `spawn` leaves the session with no watchdog, and the shell can then exit
/// without handing the panels back. The critical section is short and every
/// caller already runs on the blocking pool, so a plain `flock` is enough; a
/// missing lock file degrades to the previous behaviour rather than failing the
/// hand-over.
pub fn with_watchdog_lock<T>(f: impl FnOnce() -> T) -> T {
    use std::os::fd::AsRawFd;

    let lock_path = watchdog_pid_file().with_file_name("watchdog.lock");
    let file = fs::OpenOptions::new()
        .create(true)
        .write(true)
        .open(&lock_path)
        .ok();
    let fd = file.as_ref().map(|file| file.as_raw_fd());
    if let Some(fd) = fd {
        unsafe { libc::flock(fd, libc::LOCK_EX) };
    }

    let result = f();

    if let Some(fd) = fd {
        unsafe { libc::flock(fd, libc::LOCK_UN) };
    }
    result
}

/// Spawns `command` and reaps it when it exits.
///
/// A killed watchdog whose parent never waits stays a zombie for the life of the
/// process; the daemon spawns its watchdog once per session and must not leak it.
pub fn spawn_reaped(command: &mut Command) -> std::io::Result<()> {
    let mut child = command.spawn()?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}

pub fn spawn_watchdog(target_pid: u32) {
    if target_pid == 0 || (!branding::test_mode() && unsafe { libc::kill(target_pid as i32, 0) != 0 }) {
        eprintln!("[astral-plasma] spawn_watchdog: target PID {} is not running, skipping watchdog.", target_pid);
        return;
    }

    // Never signal an outgoing watchdog that is mid-hand-back: the restore has
    // to finish before this session takes over, or the two claims interleave.
    let backup_dir = crate::infrastructure::plasma_adapter::PlasmaAdapter::new().resolve_backup_dir();
    wait_for_restore_to_finish(&backup_dir, RESTORE_HANDOVER_TIMEOUT);

    let pid_file = watchdog_pid_file();
    if pid_file.exists() {
        // Only signal a process that really is a watchdog: the file lives in
        // `/tmp` and its pid can outlive the watchdog and be recycled by an
        // unrelated process (see `is_watchdog_process`).
        let previous = fs::read_to_string(&pid_file)
            .ok()
            .and_then(|content| content.trim().parse::<i32>().ok())
            .filter(|pid| is_watchdog_process(*pid));
        if let Some(pid) = previous {
            unsafe { libc::kill(pid, libc::SIGTERM) };
        }
        let _ = fs::remove_file(&pid_file);
    }

    let current_exe = env::current_exe().unwrap_or_else(|_| "astral-plasma".into());

    // The watchdog is detached and outlives this process, so its output must go
    // somewhere durable: with `Stdio::null()` its exit reason is invisible, and
    // a watchdog that died before the shell did is exactly what leaves the
    // panels unrestored with nothing to look at.
    let log_path = watchdog_pid_file().with_file_name("astral_plasma_watchdog.log");
    let log = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .ok();

    let mut cmd = Command::new(&current_exe);
    cmd.args(["plasma", "watchdog", &target_pid.to_string()])
        .stdin(std::process::Stdio::null());
    match &log {
        Some(file) => {
            let Ok(stdout) = file.try_clone() else {
                eprintln!("[astral-plasma] spawn_watchdog: cannot clone the watchdog log handle");
                return;
            };
            let Ok(stderr) = file.try_clone() else {
                eprintln!("[astral-plasma] spawn_watchdog: cannot clone the watchdog log handle");
                return;
            };
            cmd.stdout(std::process::Stdio::from(stdout))
                .stderr(std::process::Stdio::from(stderr));
        }
        None => {
            cmd.stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null());
        }
    }

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }

    if let Err(error) = spawn_reaped(&mut cmd) {
        eprintln!("[astral-plasma] spawn_watchdog: cannot start the watchdog: {error}");
    }
}

pub async fn run_watchdog_loop(target_pid: u32) -> DynResult<()> {
    let plasma_port = Arc::new(crate::infrastructure::plasma_adapter::PlasmaAdapter::new());
    let shortcut_port = Arc::new(crate::infrastructure::kwin_shortcuts::KWinShortcutsAdapter::new());
    run_watchdog_loop_with_ports(target_pid, plasma_port, shortcut_port).await
}

pub async fn run_watchdog_loop_with_ports(
    target_pid: u32,
    plasma_port: Arc<dyn PlasmaControlPort>,
    shortcut_port: Arc<dyn ShortcutControlPort>,
) -> DynResult<()> {
    if target_pid == 0 {
        return Ok(());
    }

    // Safety check: verify target process was actually running at the start
    if !branding::test_mode() {
        if unsafe { libc::kill(target_pid as i32, 0) != 0 } {
            eprintln!("[astral-plasma watchdog] Target PID {} is not active on startup, aborting without restore.", target_pid);
            return Ok(());
        }
    }

    let pid_file = watchdog_pid_file();
    if !claim_watchdog_pid_file(&pid_file, std::process::id()) {
        eprintln!(
            "[astral-plasma watchdog] another watchdog already supervises pid {}; exiting without restoring.",
            target_pid
        );
        return Ok(());
    }

    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut sigterm = signal(SignalKind::terminate())?;
        let mut sigint = signal(SignalKind::interrupt())?;

        loop {
            tokio::select! {
                _ = sigterm.recv() => {
                    eprintln!("[astral-plasma watchdog] Received SIGTERM signal, exiting cleanly without restoring.");
                    let _ = fs::remove_file(pid_file);
                    return Ok(());
                }
                _ = sigint.recv() => {
                    eprintln!("[astral-plasma watchdog] Received SIGINT signal, exiting cleanly without restoring.");
                    let _ = fs::remove_file(pid_file);
                    return Ok(());
                }
                _ = tokio::time::sleep(Duration::from_millis(500)) => {
                    let alive = unsafe { libc::kill(target_pid as i32, 0) == 0 };
                    if !alive {
                        eprintln!("[astral-plasma watchdog] Monitored PID {} has terminated, restoring original Plasma state...", target_pid);
                        break;
                    }

                }
            }
        }
    }

    #[cfg(not(unix))]
    {
        while unsafe { libc::kill(target_pid as i32, 0) == 0 } {
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    }

    // The supervised shell is gone: hand the desktop back - unless the user
    // asked to keep the shell's desktop state after quitting.
    if crate::domain::desktop_integration::restore_on_exit(shell_auto_restore_setting()) {
        let _ = plasma_port.restore_config();
        let _ = shortcut_port.restore_relevant_shortcuts();
        // The shell tunes KWin's blur for its glass; hand it back with the rest
        // of the desktop state instead of leaving the override behind.
        if !branding::test_mode() {
            let _ = crate::infrastructure::kwin_blur::KWinBlurAdapter::new().restore();
        }
    } else {
        eprintln!(
            "[astral-plasma watchdog] plasma.autoRestoreOnExit is off; keeping the shell's desktop state."
        );
    }

    let _ = crate::infrastructure::plasma_adapter::remove_pid_file_owned_by(
        &pid_file,
        std::process::id(),
    );
    Ok(())
}

/// `plasma.autoRestoreOnExit` from the shell's settings file, when readable.
fn shell_auto_restore_setting() -> Option<bool> {
    let path = branding::config_home()
        .join(branding::APP_ID)
        .join("settings.json");
    let content = fs::read_to_string(path).ok()?;
    crate::domain::desktop_integration::auto_restore_from_settings(&content)
}
