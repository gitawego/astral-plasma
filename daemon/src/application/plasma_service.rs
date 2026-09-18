use crate::domain::plasma::PlasmaStatus;
use crate::domain::ports::{DynResult, PlasmaControlPort};
use crate::infrastructure::plasma_adapter::{DEFAULT_WATCHDOG_PID_FILE, PlasmaAdapter};
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;
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
            if pid > 0 && env::var("CAELESTIA_TEST_MODE").unwrap_or_default() != "1" {
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
    let adapter = PlasmaAdapter::new();
    adapter.stop_watchdog();

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
    let pid_file = Path::new(DEFAULT_WATCHDOG_PID_FILE);
    let _ = fs::write(pid_file, std::process::id().to_string());

    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut sigterm = signal(SignalKind::terminate())?;
        let mut sigint = signal(SignalKind::interrupt())?;

        loop {
            tokio::select! {
                _ = sigterm.recv() => {
                    eprintln!("[astral-plasma watchdog] Received SIGTERM signal, restoring original Plasma state...");
                    break;
                }
                _ = sigint.recv() => {
                    eprintln!("[astral-plasma watchdog] Received SIGINT signal, restoring original Plasma state...");
                    break;
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

    // Quickshell has exited or watchdog was terminated; restore original Plasma panels and shortcuts!
    let adapter = PlasmaAdapter::new();
    let _ = adapter.restore_config();

    let shortcut_adapter = crate::infrastructure::kwin_shortcuts::KWinShortcutsAdapter::new();
    let shortcut_use_case = crate::application::shortcut_service::ShortcutControlUseCase::new(shortcut_adapter);
    let _ = shortcut_use_case.restore();

    let _ = fs::remove_file(pid_file);
    Ok(())
}
