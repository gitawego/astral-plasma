use crate::domain::branding;
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

    /// Path of the user unit this shell owns.
    pub fn unit_path(&self) -> PathBuf {
        self.resolve_systemd_dir().join(branding::SYSTEMD_UNIT)
    }

    pub fn resolve_systemd_dir(&self) -> PathBuf {
        if let Some(dir) = branding::dir_override(branding::ENV_SYSTEMD_DIR) {
            return dir;
        }
        branding::config_home().join("systemd").join("user")
    }

    pub fn resolve_theme_dir(&self) -> PathBuf {
        if let Some(dir) = branding::dir_override(branding::ENV_THEME_DIR) {
            return dir;
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
        let service_file = self.unit_path();
        let installed = service_file.exists();

        let mut enabled = false;
        let mut active = false;

        let is_test = branding::test_mode();
        if installed && !is_test {
            enabled = Command::new("systemctl")
                .args(["--user", "is-enabled", "--quiet", branding::SYSTEMD_UNIT])
                .status()
                .map(|s| s.success())
                .unwrap_or(false);

            active = Command::new("systemctl")
                .args(["--user", "is-active", "--quiet", branding::SYSTEMD_UNIT])
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

        let service_file = self.unit_path();
        let quickshell_bin = which_quickshell();
        let theme_dir = self.resolve_theme_dir();

        let content = generate_unit_file_content(&quickshell_bin, &theme_dir.to_string_lossy());
        fs::write(&service_file, content)?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&service_file, fs::Permissions::from_mode(0o644));
        }

        let is_test = branding::test_mode();
        if !is_test {
            let _ = Command::new("systemctl").args(["--user", "daemon-reload"]).status();
            let _ = Command::new("systemctl").args(["--user", "enable", branding::SYSTEMD_UNIT]).status();
        }

        self.query_status()
    }

    fn remove_service(&self) -> DynResult<ServiceStatus> {
        let service_file = self.unit_path();

        let is_test = branding::test_mode();
        if !is_test {
            let _ = Command::new("systemctl")
                .args(["--user", "disable", "--now", branding::SYSTEMD_UNIT])
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
