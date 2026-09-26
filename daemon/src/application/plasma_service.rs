use crate::domain::branding;
use crate::domain::plasma::PlasmaStatus;
use crate::domain::ports::{DynResult, PlasmaControlPort, ShortcutControlPort};
use crate::infrastructure::plasma_adapter::watchdog_pid_file;
use std::env;
use std::fs;
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;

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
                self.port.stop_watchdog();
                spawn_watchdog(pid);
            }
        }

        Ok(count)
    }

    pub fn restore(&self) -> DynResult<bool> {
        self.port.restore_config()
    }
}

pub fn spawn_watchdog(target_pid: u32) {
    if target_pid == 0 || (!branding::test_mode() && unsafe { libc::kill(target_pid as i32, 0) != 0 }) {
        eprintln!("[astral-plasma] spawn_watchdog: target PID {} is not running, skipping watchdog.", target_pid);
        return;
    }

    let pid_file = watchdog_pid_file();
    if pid_file.exists() {
        if let Ok(content) = fs::read_to_string(&pid_file) {
            if let Ok(pid) = content.trim().parse::<i32>() {
                if pid > 0 {
                    unsafe { libc::kill(pid, libc::SIGTERM) };
                }
            }
        }
        let _ = fs::remove_file(&pid_file);
    }

    let current_exe = env::current_exe().unwrap_or_else(|_| "astral-plasma".into());

    let mut cmd = Command::new(&current_exe);
    cmd.args(["plasma", "watchdog", &target_pid.to_string()])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }

    let _ = cmd.spawn();
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
    let _ = fs::write(&pid_file, std::process::id().to_string());

    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut sigterm = signal(SignalKind::terminate())?;
        let mut sigint = signal(SignalKind::interrupt())?;

        let mut check_ticks = 0u32;

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

                    // Periodically ensure no built-in panels have respawned while Astral Plasma is active
                    check_ticks += 1;
                    if check_ticks % 4 == 0 && !branding::test_mode() {
                        if let Ok(panels) = plasma_port.query_panels() {
                            if !panels.is_empty() {
                                eprintln!("[astral-plasma watchdog] Detected {} respawned built-in panel(s); re-disabling...", panels.len());
                                let _ = plasma_port.disable_panels("all");
                            }
                        }
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

    // Quickshell has exited or watchdog was terminated; restore original Plasma panels and shortcuts!
    let _ = plasma_port.restore_config();
    let _ = shortcut_port.restore_relevant_shortcuts();

    let _ = fs::remove_file(pid_file);
    Ok(())
}
