use crate::domain::plasma::PlasmaStatus;
use crate::domain::ports::{DynResult, PlasmaControlPort};
use crate::infrastructure::plasma_adapter::{DEFAULT_WATCHDOG_PID_FILE, PlasmaAdapter};
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::thread;
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
    let current_exe = env::current_exe().unwrap_or_else(|_| "caelestia-daemon".into());

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

pub fn run_watchdog_loop(target_pid: u32) -> DynResult<()> {
    let pid_file = Path::new(DEFAULT_WATCHDOG_PID_FILE);
    fs::write(pid_file, std::process::id().to_string())?;

    while unsafe { libc::kill(target_pid as i32, 0) == 0 } {
        thread::sleep(Duration::from_millis(500));
    }

    // Quickshell has exited or was killed; restore original Plasma panels!
    let adapter = PlasmaAdapter::new();
    let _ = adapter.restore_config();

    let _ = fs::remove_file(pid_file);
    Ok(())
}
