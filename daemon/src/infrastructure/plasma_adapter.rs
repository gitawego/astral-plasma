use crate::domain::branding;
use crate::domain::plasma::{PlasmaPanelInfo, PlasmaStatus};
use crate::domain::ports::{DynResult, PlasmaControlPort};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::thread;
use std::time::Duration;

/// PID file of the detached Plasma watchdog process.
pub fn watchdog_pid_file() -> PathBuf {
    branding::tmp_file("watchdog.pid")
}

#[derive(Clone, Default)]
pub struct PlasmaAdapter;

impl PlasmaAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn resolve_backup_dir(&self) -> PathBuf {
        if let Some(dir) = branding::dir_override(branding::ENV_PLASMA_BACKUP_DIR) {
            return dir;
        }
        branding::data_dir().join(branding::PLASMA_BACKUP_SUBDIR)
    }

    pub fn resolve_config_dir(&self) -> PathBuf {
        branding::config_home()
    }

    pub fn stop_watchdog(&self) {
        let pid_file = watchdog_pid_file();
        let pid_file = pid_file.as_path();
        let my_pid = std::process::id() as i32;
        if pid_file.exists() {
            if let Ok(content) = fs::read_to_string(pid_file) {
                if let Ok(pid) = content.trim().parse::<i32>() {
                    if pid != my_pid {
                        unsafe {
                            libc::kill(pid, libc::SIGTERM);
                        }
                    }
                }
            }
            if let Ok(content) = fs::read_to_string(pid_file) {
                if let Ok(pid) = content.trim().parse::<i32>() {
                    if pid != my_pid {
                        unsafe {
                            libc::kill(pid, libc::SIGKILL);
                        }
                    }
                }
            }
            if let Ok(content) = fs::read_to_string(pid_file) {
                if let Ok(pid) = content.trim().parse::<i32>() {
                    if pid != my_pid {
                        let _ = fs::remove_file(pid_file);
                    }
                } else {
                    let _ = fs::remove_file(pid_file);
                }
            }
        }

        if !branding::test_mode() {
            #[cfg(unix)]
            {
                if let Ok(output) = Command::new("pgrep")
                    .args(["-f", "astral-plasma plasma watchdog"])
                    .output()
                {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    for line in stdout.lines() {
                        if let Ok(pid) = line.trim().parse::<i32>() {
                            if pid != my_pid {
                                unsafe {
                                    libc::kill(pid, libc::SIGKILL);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

impl PlasmaControlPort for PlasmaAdapter {
    fn query_panels(&self) -> DynResult<Vec<PlasmaPanelInfo>> {
        if branding::test_mode() {
            return Ok(Vec::new());
        }

        let script = r#"
            var ps = panels();
            var res = [];
            for (var i = 0; i < ps.length; ++i) {
                res.push({
                    id: ps[i].id,
                    location: ps[i].location,
                    hiding: ps[i].hiding,
                    height: ps[i].height
                });
            }
            print(JSON.stringify(res));
        "#;

        let output = Command::new("qdbus6")
            .args(["org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script])
            .output()?;

        if !output.status.success() {
            return Ok(Vec::new());
        }

        let text = String::from_utf8_lossy(&output.stdout);
        // Find JSON array in stdout
        if let Some(start) = text.find('[') {
            if let Some(end) = text.rfind(']') {
                let json_slice = &text[start..=end];
                if let Ok(panels) = serde_json::from_str::<Vec<PlasmaPanelInfo>>(json_slice) {
                    return Ok(panels);
                }
            }
        }

        Ok(Vec::new())
    }

    fn backup_config(&self) -> DynResult<bool> {
        let backup_dir = self.resolve_backup_dir();
        fs::create_dir_all(&backup_dir)?;

        let session_flag = backup_dir.join("session_active");
        if session_flag.exists() {
            // Pristine backup already exists; preserve it
            return Ok(false);
        }

        let backed_appletsrc = backup_dir.join("plasma-org.kde.plasma.desktop-appletsrc");
        let current_panels = self.query_panels().unwrap_or_default();

        // Safety Guard: Never overwrite a good backup if current running state has 0 panels!
        if current_panels.is_empty() && backed_appletsrc.exists() {
            if let Ok(content) = fs::read_to_string(&backed_appletsrc) {
                if content.contains("[Containments][") {
                    fs::write(&session_flag, "")?;
                    return Ok(false);
                }
            }
        }

        let config_dir = self.resolve_config_dir();
        let appletsrc = config_dir.join("plasma-org.kde.plasma.desktop-appletsrc");
        let shellrc = config_dir.join("plasmashellrc");

        if appletsrc.exists() {
            fs::copy(&appletsrc, &backed_appletsrc)?;
        }
        if shellrc.exists() {
            fs::copy(&shellrc, backup_dir.join("plasmashellrc"))?;
        }

        // Dump current layout JS via DBus for 100% fidelity layout restoration
        if let Ok(output) = Command::new("qdbus6")
            .args(["org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.dumpCurrentLayoutJS"])
            .output()
        {
            if output.status.success() && !output.stdout.is_empty() {
                let _ = fs::write(backup_dir.join("layout.js"), &output.stdout);
            }
        }

        // Save metadata of panels
        if let Ok(panels_json) = serde_json::to_string_pretty(&current_panels) {
            let _ = fs::write(backup_dir.join("panels.json"), panels_json);
        }

        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs();
        fs::write(backup_dir.join("backup_timestamp"), ts.to_string())?;
        fs::write(session_flag, "")?;

        Ok(true)
    }

    fn disable_panels(&self, target: &str) -> DynResult<u32> {
        // Guarantee pristine backup before disabling
        self.backup_config()?;

        if branding::test_mode() {
            return Ok(0);
        }

        let target_sanitized = target.replace('\'', "");
        let script = format!(
            r#"
            var ps = panels();
            var count = 0;
            var target = '{target}';
            var targets = target.split(',');
            for (var i = ps.length - 1; i >= 0; --i) {{
                var loc = ps[i].location;
                if (target === 'all' || targets.indexOf(loc) !== -1) {{
                    ps[i].remove();
                    count++;
                }}
            }}
            print('REMOVED:' + count);
            "#,
            target = target_sanitized
        );

        let mut count = 0;
        for attempt in 0..10 {
            let output = Command::new("qdbus6")
                .args(["org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", &script])
                .output();

            if let Ok(out) = output {
                if out.status.success() {
                    let text = String::from_utf8_lossy(&out.stdout);
                    if let Some(pos) = text.find("REMOVED:") {
                        let num_str: String = text[pos + 8..].chars().take_while(|c| c.is_ascii_digit()).collect();
                        if let Ok(n) = num_str.parse::<u32>() {
                            count = n;
                            break;
                        }
                    }
                }
            }
            if attempt < 9 {
                thread::sleep(Duration::from_millis(150));
            }
        }

        Ok(count)
    }

    fn restore_config(&self) -> DynResult<bool> {
        let backup_dir = self.resolve_backup_dir();
        let restoring_lock = backup_dir.join(".restoring");

        // Prevent concurrent execution of restore_config
        if restoring_lock.exists() {
            if let Ok(metadata) = fs::metadata(&restoring_lock) {
                if let Ok(modified) = metadata.modified() {
                    if let Ok(elapsed) = modified.elapsed() {
                        if elapsed.as_secs() < 10 {
                            eprintln!("[astral-plasma] Restore already in progress by another process; skipping duplicate execution.");
                            return Ok(true);
                        }
                    }
                }
            }
        }
        let _ = fs::write(&restoring_lock, std::process::id().to_string());

        self.stop_watchdog();

        let backed_appletsrc = backup_dir.join("plasma-org.kde.plasma.desktop-appletsrc");
        let backed_shellrc = backup_dir.join("plasmashellrc");
        let backed_layout = backup_dir.join("layout.js");
        let session_flag = backup_dir.join("session_active");

        let has_backup = backed_appletsrc.exists() || backed_layout.exists();
        if !has_backup {
            let _ = fs::remove_file(&session_flag);
            let _ = fs::remove_file(&restoring_lock);
            return Ok(false);
        }

        let is_test = branding::test_mode();

        if !is_test {
            // Stop plasmashell cleanly so it cannot overwrite config upon exit
            let _ = Command::new("systemctl")
                .args(["--user", "stop", "plasma-plasmashell"])
                .status();
            let _ = Command::new("kquitapp6").arg("plasmashell").status();

            // Wait until any plasmashell process is completely gone from process table
            for _ in 0..40 {
                let any_alive = Command::new("pgrep")
                    .args(["-x", "plasmashell"])
                    .status()
                    .map(|s| s.success())
                    .unwrap_or(false);
                if !any_alive {
                    break;
                }
                thread::sleep(Duration::from_millis(100));
            }

            let _ = Command::new("pkill").args(["-9", "-x", "plasmashell"]).status();
            thread::sleep(Duration::from_millis(150));
        }

        // Restore files
        let config_dir = self.resolve_config_dir();
        fs::create_dir_all(&config_dir)?;

        if backed_appletsrc.exists() {
            fs::copy(&backed_appletsrc, config_dir.join("plasma-org.kde.plasma.desktop-appletsrc"))?;
        }
        if backed_shellrc.exists() {
            fs::copy(&backed_shellrc, config_dir.join("plasmashellrc"))?;
        }

        #[cfg(unix)]
        unsafe {
            libc::sync();
        }

        if !is_test {
            // Restart plasmashell cleanly via systemctl or direct spawn
            let started = Command::new("systemctl")
                .args(["--user", "start", "plasma-plasmashell"])
                .status()
                .map(|s| s.success())
                .unwrap_or(false);

            if !started {
                let _ = Command::new("nohup")
                    .args(["plasmashell", "--no-respawn"])
                    .spawn();
            }

            // Wait up to 5 seconds for plasmashell to appear on DBus
            let mut dbus_ready = false;
            for _ in 0..25 {
                if Command::new("qdbus6")
                    .args(["org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.color"])
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false)
                {
                    dbus_ready = true;
                    break;
                }
                thread::sleep(Duration::from_millis(200));
            }

            // Verification & Fallback: If DBus is ready, check if panels were restored
            if dbus_ready {
                let current_panels = self.query_panels().unwrap_or_default();
                // If panels are still 0 and we have a layout.js backup, execute it!
                if current_panels.is_empty() && backed_layout.exists() {
                    if let Ok(layout_script) = fs::read_to_string(&backed_layout) {
                        let _ = Command::new("qdbus6")
                            .args(["org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", &layout_script])
                            .output();
                    }
                }
            }
        }

        let _ = fs::remove_file(&session_flag);
        let _ = fs::remove_file(&restoring_lock);
        Ok(true)
    }

    fn get_status(&self) -> DynResult<PlasmaStatus> {
        let panels = self.query_panels().unwrap_or_default();
        let backup_dir = self.resolve_backup_dir();
        let session_active = backup_dir.join("session_active").exists();

        let mut watchdog_pid = None;
        let pid_file = watchdog_pid_file();
        if pid_file.exists() {
            if let Ok(content) = fs::read_to_string(&pid_file) {
                if let Ok(pid) = content.trim().parse::<u32>() {
                    let is_alive = unsafe { libc::kill(pid as i32, 0) == 0 };
                    if is_alive {
                        watchdog_pid = Some(pid);
                    }
                }
            }
        }

        Ok(PlasmaStatus {
            panels,
            backup_dir: backup_dir.to_string_lossy().to_string(),
            session_active,
            watchdog_pid,
        })
    }

    fn stop_watchdog(&self) {
        self.stop_watchdog();
    }
}
