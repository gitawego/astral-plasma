use crate::domain::branding;
use crate::domain::plasma::{PlasmaPanelInfo, PlasmaStatus};
use crate::domain::ports::{DynResult, PlasmaControlPort};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

/// Removes a watchdog pid file only when it still names `owner_pid`.
///
/// A restart runs two watchdogs for a moment: the outgoing one is handing the
/// desktop back while the incoming one is already monitoring the new shell.
/// The outgoing cleanup must not delete the incoming process's record - that is
/// how a session ended up with a live watchdog and `watchdog_pid: null`.
pub fn remove_pid_file_owned_by(path: &Path, owner_pid: u32) -> bool {
    let Ok(content) = fs::read_to_string(path) else {
        return false;
    };
    let Ok(pid) = content.trim().parse::<u32>() else {
        return false;
    };
    if pid != owner_pid {
        return false;
    }
    fs::remove_file(path).is_ok()
}

/// PID file of the detached Plasma watchdog process.
pub fn watchdog_pid_file() -> PathBuf {
    branding::tmp_file("watchdog.pid")
}

/// Whether `pid` is one of our Plasma watchdog processes.
///
/// The pid file is a plain file in `/tmp`: it can outlive its watchdog (a
/// `SIGKILL`ed watchdog leaves it behind) and the recorded pid can then be
/// recycled by an unrelated process. Signalling a pid from that file without
/// checking what it is has already killed the wrong process, so every signal
/// path verifies the target first - the watchdog's argv is
/// `<exe> plasma watchdog <pid>`, which nothing else in the session has.
pub fn is_watchdog_process(pid: i32) -> bool {
    if pid <= 0 {
        return false;
    }
    let Ok(cmdline) = fs::read(format!("/proc/{pid}/cmdline")) else {
        return false;
    };
    let args: Vec<String> = cmdline
        .split(|byte| *byte == 0)
        .filter(|arg| !arg.is_empty())
        .map(|arg| String::from_utf8_lossy(arg).to_string())
        .collect();
    is_watchdog_argv(&args)
}

/// Whether a process's argv is `<exe> plasma watchdog <pid>`.
///
/// Matching the argv *shape* rather than the text is deliberate: a path such as
/// `.../test_watchdog_handover` contains both words and would otherwise be
/// mistaken for a watchdog - and then signalled.
pub fn is_watchdog_argv(args: &[String]) -> bool {
    args.len() >= 3 && args[1] == "plasma" && args[2] == "watchdog"
}

/// Whether the dumped layout must be replayed after a restore.
///
/// A file-perfect restore can still leave plasmashell with no panels: it comes
/// back from its in-memory layout and then saves that empty layout over the
/// restored file. Replaying the dumped layout is the only repair that does not
/// need another restart, so it is worth attempting whenever the backup carries
/// one and the running shell reports nothing.
pub fn should_replay_layout(panel_count: usize, has_layout_backup: bool) -> bool {
    panel_count == 0 && has_layout_backup
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
            let target = fs::read_to_string(pid_file)
                .ok()
                .and_then(|content| content.trim().parse::<i32>().ok())
                .filter(|pid| *pid != my_pid && is_watchdog_process(*pid));
            if let Some(pid) = target {
                unsafe {
                    libc::kill(pid, libc::SIGTERM);
                }
                unsafe {
                    libc::kill(pid, libc::SIGKILL);
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
    /// Stops the running plasmashell so it cannot re-save its in-memory layout.
    ///
    /// Plasma 6 provides plasmashell through the `plasma-plasmashell` user unit.
    /// `kquitapp6 plasmashell` is not an option: it resolves the application
    /// through the legacy KApplication interface and fails with "Application
    /// plasmashell could not be found using service org.kde.plasmashell and path
    /// /MainApplication", leaving plasmashell running with the very layout we
    /// are about to replace.
    fn stop_plasmashell() {
        let _ = Command::new("systemctl")
            .args(["--user", "stop", "plasma-plasmashell"])
            .status();

        for _ in 0..40 {
            if !Self::plasmashell_alive() {
                return;
            }
            thread::sleep(Duration::from_millis(100));
        }

        let _ = Command::new("pkill").args(["-9", "-x", "plasmashell"]).status();
        thread::sleep(Duration::from_millis(150));
    }

    fn plasmashell_alive() -> bool {
        Command::new("pgrep")
            .args(["-x", "plasmashell"])
            .status()
            .map(|status| status.success())
            .unwrap_or(false)
    }

    /// Starts plasmashell again and waits for its D-Bus interface.
    fn start_plasmashell() -> bool {
        let started = Command::new("systemctl")
            .args(["--user", "start", "plasma-plasmashell"])
            .status()
            .map(|status| status.success())
            .unwrap_or(false);

        if !started {
            let _ = Command::new("nohup")
                .args(["plasmashell", "--no-respawn"])
                .spawn();
        }

        for _ in 0..25 {
            if Self::plasmashell_dbus_ready() {
                return true;
            }
            thread::sleep(Duration::from_millis(200));
        }
        false
    }

    fn plasmashell_dbus_ready() -> bool {
        Command::new("qdbus6")
            .args(["org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.color"])
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }

    /// Restores the panels and proves it.
    ///
    /// Copying the config back is not enough: a plasmashell that restarts from a
    /// stale in-memory layout comes back with no panels and then saves that
    /// empty layout over the restored file. When the running shell reports no
    /// panels and the backup carries a dumped layout, that layout is replayed
    /// (bounded retries) and the result is verified instead of assumed.
    fn restore_panels(&self, layout_path: &Path) -> usize {
        let has_layout = layout_path.exists();
        let mut panels = self.query_panels().unwrap_or_default().len();

        for attempt in 0..3 {
            if !should_replay_layout(panels, has_layout) {
                break;
            }
            if let Ok(layout_script) = fs::read_to_string(layout_path) {
                let _ = Command::new("qdbus6")
                    .args([
                        "org.kde.plasmashell",
                        "/PlasmaShell",
                        "org.kde.PlasmaShell.evaluateScript",
                        &layout_script,
                    ])
                    .output();
            }
            thread::sleep(Duration::from_millis(if attempt == 0 { 400 } else { 800 }));
            panels = self.query_panels().unwrap_or_default().len();
        }

        panels
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
        if target_sanitized == "all" || target_sanitized.is_empty() {
            let count = self.query_panels().map(|p| p.len() as u32).unwrap_or(0);
            // Non-destructive: stop plasma-plasmashell cleanly via systemd rather
            // than deleting containments from the user's desktop configuration.
            Self::stop_plasmashell();
            return Ok(count);
        }

        // Targeted hiding for specific panel positions:
        // Use non-destructive hiding ('windowscover') instead of permanently deleting containments!
        let script = format!(
            r#"
            var ps = panels();
            var count = 0;
            var target = '{target}';
            var targets = target.split(',');
            for (var i = ps.length - 1; i >= 0; --i) {{
                var loc = ps[i].location;
                if (targets.indexOf(loc) !== -1) {{
                    ps[i].hiding = "windowscover";
                    count++;
                }}
            }}
            print('HIDDEN:' + count);
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
                    if let Some(pos) = text.find("HIDDEN:") {
                        let num_str: String = text[pos + 7..].chars().take_while(|c| c.is_ascii_digit()).collect();
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
            Self::stop_plasmashell();
        }

        // Restore files
        let config_dir = self.resolve_config_dir();
        fs::create_dir_all(&config_dir)?;

        let current_appletsrc = config_dir.join("plasma-org.kde.plasma.desktop-appletsrc");
        let active_has_containments = current_appletsrc.exists()
            && fs::read_to_string(&current_appletsrc)
                .map(|c| c.contains("[Containments][") && c.contains("plugin=org.kde.panel"))
                .unwrap_or(false);

        // Preserve current active config if it already has intact panel containments;
        // only copy backup if active config was wiped or missing containments, or in test mode.
        if (!active_has_containments || is_test) && backed_appletsrc.exists() {
            fs::copy(&backed_appletsrc, &current_appletsrc)?;
        }
        if (!active_has_containments || is_test) && backed_shellrc.exists() {
            fs::copy(&backed_shellrc, config_dir.join("plasmashellrc"))?;
        }

        #[cfg(unix)]
        unsafe {
            libc::sync();
        }

        if !is_test {
            // Keep the lock fresh: stopping, starting and verifying plasmashell
            // can outlive the staleness window a concurrent restore uses to
            // decide the previous one died.
            let _ = fs::write(&restoring_lock, std::process::id().to_string());

            if Self::start_plasmashell() {
                // If any panels were set to 'windowscover', restore them to 'none'
                let unhide_script = r#"
                    var ps = panels();
                    for (var i = 0; i < ps.length; ++i) {
                        if (ps[i].hiding === "windowscover") {
                            ps[i].hiding = "none";
                        }
                    }
                "#;
                let _ = Command::new("qdbus6")
                    .args(["org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", unhide_script])
                    .output();

                let panels = self.restore_panels(&backed_layout);
                if panels == 0 {
                    eprintln!(
                        "[astral-plasma] plasma restore: plasmashell is running with 0 panels and the dumped layout could not be replayed; backup kept at {}",
                        backup_dir.display()
                    );
                }
            } else {
                eprintln!(
                    "[astral-plasma] plasma restore: plasmashell did not answer on D-Bus after the restart"
                );
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
