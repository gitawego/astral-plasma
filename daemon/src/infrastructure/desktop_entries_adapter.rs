use crate::domain::branding;
use crate::domain::desktop_entries::DesktopIntegrationStatus;
use crate::domain::ports::{DesktopIntegrationPort, DynResult};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Clone, Default)]
pub struct DesktopEntriesAdapter;

impl DesktopEntriesAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn resolve_applications_dir(&self) -> PathBuf {
        if let Some(dir) = branding::dir_override(branding::ENV_APPLICATIONS_DIR) {
            return dir;
        }
        branding::data_home().join("applications")
    }

    pub fn resolve_wayland_sessions_dir(&self) -> PathBuf {
        if let Some(dir) = branding::dir_override(branding::ENV_WAYLAND_SESSIONS_DIR) {
            return dir;
        }
        branding::data_home().join("wayland-sessions")
    }

    pub fn resolve_bin_dir(&self) -> PathBuf {
        branding::home_dir().join(".local").join("bin")
    }

    pub fn resolve_theme_dir(&self) -> PathBuf {
        if let Some(dir) = branding::dir_override(branding::ENV_THEME_DIR) {
            return dir;
        }
        if std::path::Path::new("shell.qml").exists() {
            if let Ok(cwd) = env::current_dir() {
                return cwd;
            }
        }
        if let Ok(exe) = env::current_exe() {
            let mut curr = exe.parent();
            while let Some(dir) = curr {
                if dir.join("shell.qml").exists() {
                    return dir.to_path_buf();
                }
                curr = dir.parent();
            }
            if let Some(parent) = exe.parent() {
                if let Some(root) = parent.parent() {
                    return root.to_path_buf();
                }
            }
        }
        PathBuf::from(".")
    }
}

impl DesktopIntegrationPort for DesktopEntriesAdapter {
    fn query_status(&self) -> DynResult<DesktopIntegrationStatus> {
        let sessions_dir = self.resolve_wayland_sessions_dir();
        let plasma_session = sessions_dir.join("astral-plasma.desktop").exists();
        let hypr_session = sessions_dir.join("astral-hyprland.desktop").exists();
        let session_installed = plasma_session || hypr_session;

        let app_dir = self.resolve_applications_dir();
        let shortcuts_installed = app_dir.join("astral-launcher.desktop").exists()
            || app_dir.join("astral-dashboard.desktop").exists();

        let installed = session_installed && shortcuts_installed;

        Ok(DesktopIntegrationStatus {
            installed,
            session_installed,
            shortcuts_installed,
            session_file: sessions_dir.to_string_lossy().to_string(),
            shortcuts_dir: app_dir.to_string_lossy().to_string(),
        })
    }

    fn install_desktop_entries(&self) -> DynResult<DesktopIntegrationStatus> {
        let theme_dir = self.resolve_theme_dir();

        // 1. Install Wayland session desktop entries (both KWin and Hyprland)
        let sessions_dir = self.resolve_wayland_sessions_dir();
        fs::create_dir_all(&sessions_dir)?;
        for name in &["astral-plasma.desktop", "astral-hyprland.desktop"] {
            let src = theme_dir.join("sessions").join(name);
            if src.exists() {
                let _ = fs::copy(&src, sessions_dir.join(name));
            }
        }

        // 2. Install session launcher scripts into ~/.local/bin
        let bin_dir = self.resolve_bin_dir();
        let _ = fs::create_dir_all(&bin_dir);
        for name in &["astral-plasma-session", "astral-hyprland-session"] {
            let src = theme_dir.join("sessions").join(name);
            let dst = bin_dir.join(name);
            if src.exists() {
                #[cfg(unix)]
                {
                    let _ = fs::remove_file(&dst);
                    let _ = std::os::unix::fs::symlink(&src, &dst);
                }
            }
        }

        // 3. Install shortcuts into ~/.local/share/applications
        let app_dir = self.resolve_applications_dir();
        fs::create_dir_all(&app_dir)?;
        let src_shortcuts = theme_dir.join("shortcuts");
        if let Ok(entries) = fs::read_dir(&src_shortcuts) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) == Some("desktop") {
                    if let Some(name) = path.file_name() {
                        let _ = fs::copy(&path, app_dir.join(name));
                    }
                }
            }
        }

        // 4. Install KWin authorization entry
        let _ = crate::infrastructure::preview_capture::install_desktop_entry_with_notification(Some(&app_dir), None);

        // 5. Update databases if not in test mode
        if !branding::test_mode() {
            let _ = Command::new("update-desktop-database")
                .arg(&app_dir)
                .status();
            let _ = Command::new("kbuildsycoca6").status();
        }

        self.query_status()
    }

    fn remove_desktop_entries(&self) -> DynResult<DesktopIntegrationStatus> {
        // 1. Remove Wayland session entries
        let sessions_dir = self.resolve_wayland_sessions_dir();
        for name in &["astral-plasma.desktop", "astral-hyprland.desktop"] {
            let path = sessions_dir.join(name);
            if path.exists() {
                let _ = fs::remove_file(&path);
            }
        }

        // 2. Remove session binary symlinks
        let bin_dir = self.resolve_bin_dir();
        for name in &["astral-plasma-session", "astral-hyprland-session"] {
            let path = bin_dir.join(name);
            if path.exists() {
                let _ = fs::remove_file(&path);
            }
        }

        // 3. Remove application shortcuts
        let app_dir = self.resolve_applications_dir();
        for item in &[
            "astral-launcher.desktop",
            "astral-dashboard.desktop",
            "astral-wallpaper.desktop",
            "astral-settings.desktop",
            "astral-assistant.desktop",
            "astral-plasma.desktop",
        ] {
            let path = app_dir.join(item);
            if path.exists() {
                let _ = fs::remove_file(&path);
            }
        }

        // 4. Update databases if not in test mode
        if !branding::test_mode() {
            let _ = Command::new("update-desktop-database")
                .arg(&app_dir)
                .status();
            let _ = Command::new("kbuildsycoca6").status();
        }

        self.query_status()
    }
}
