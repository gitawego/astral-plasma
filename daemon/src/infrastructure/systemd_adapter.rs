use crate::domain::ports::{DynResult, SystemdControlPort};
use crate::domain::systemd::{generate_unit_file_content, ServiceStatus};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Clone, Default)]
pub struct SystemdAdapter;

impl SystemdAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn resolve_systemd_dir(&self) -> PathBuf {
        if let Ok(dir) = env::var("CAELESTIA_SYSTEMD_DIR") {
            if !dir.trim().is_empty() {
                return PathBuf::from(dir);
            }
        }
        let home = env::var("HOME").unwrap_or_else(|_| ".".to_string());
        let config_home = env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{}/.config", home));
        PathBuf::from(config_home).join("systemd").join("user")
    }

    pub fn resolve_theme_dir(&self) -> PathBuf {
        if let Ok(dir) = env::var("CAELESTIA_THEME_DIR") {
            if !dir.trim().is_empty() {
                return PathBuf::from(dir);
            }
        }
        if let Ok(exe) = env::current_exe() {
            if let Some(parent) = exe.parent() {
                if let Some(root) = parent.parent() {
                    return root.to_path_buf();
                }
            }
        }
        PathBuf::from(".")
    }
}

impl SystemdControlPort for SystemdAdapter {
    fn query_status(&self) -> DynResult<ServiceStatus> {
        let dir = self.resolve_systemd_dir();
        let service_file = dir.join("caelestia.service");
        let installed = service_file.exists();

        let mut enabled = false;
        let mut active = false;

        let is_test = env::var("CAELESTIA_TEST_MODE").unwrap_or_default() == "1";
        if installed && !is_test {
            enabled = Command::new("systemctl")
                .args(["--user", "is-enabled", "--quiet", "caelestia.service"])
                .status()
                .map(|s| s.success())
                .unwrap_or(false);

            active = Command::new("systemctl")
                .args(["--user", "is-active", "--quiet", "caelestia.service"])
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
        }

        Ok(ServiceStatus {
            installed,
            enabled,
            active,
            file: service_file.to_string_lossy().to_string(),
        })
    }

    fn install_service(&self) -> DynResult<ServiceStatus> {
        let dir = self.resolve_systemd_dir();
        fs::create_dir_all(&dir)?;

        let service_file = dir.join("caelestia.service");
        let quickshell_bin = which_quickshell();
        let theme_dir = self.resolve_theme_dir();

        let content = generate_unit_file_content(&quickshell_bin, &theme_dir.to_string_lossy());
        fs::write(&service_file, content)?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&service_file, fs::Permissions::from_mode(0o644));
        }

        let is_test = env::var("CAELESTIA_TEST_MODE").unwrap_or_default() == "1";
        if !is_test {
            let _ = Command::new("systemctl").args(["--user", "daemon-reload"]).status();
            let _ = Command::new("systemctl").args(["--user", "enable", "caelestia.service"]).status();
        }

        self.query_status()
    }

    fn remove_service(&self) -> DynResult<ServiceStatus> {
        let dir = self.resolve_systemd_dir();
        let service_file = dir.join("caelestia.service");

        let is_test = env::var("CAELESTIA_TEST_MODE").unwrap_or_default() == "1";
        if !is_test {
            let _ = Command::new("systemctl")
                .args(["--user", "disable", "--now", "caelestia.service"])
                .status();
        }

        if service_file.exists() {
            let _ = fs::remove_file(&service_file);
        }

        if !is_test {
            let _ = Command::new("systemctl").args(["--user", "daemon-reload"]).status();
        }

        self.query_status()
    }
}

fn which_quickshell() -> String {
    if let Ok(path) = Command::new("which").arg("quickshell").output() {
        if path.status.success() {
            let s = String::from_utf8_lossy(&path.stdout).trim().to_string();
            if !s.is_empty() {
                return s;
            }
        }
    }
    "/usr/bin/quickshell".to_string()
}
