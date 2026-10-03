//! Infrastructure adapter for resolving and opening system monitor applications.

use crate::domain::app_identity::AppIdentityIndex;
use crate::domain::ports::{DynResult, SystemMonitorPort};
use crate::domain::system_monitor::{
    desktop_entry_supports_system_monitor, parse_exec_command, system_monitor_app_from_settings,
    system_monitor_candidates, SystemMonitorOpenResult, WELL_KNOWN_MONITORS,
};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct SystemMonitorAdapter {
    user_override: Option<String>,
}

impl SystemMonitorAdapter {
    pub fn new() -> Self {
        Self { user_override: None }
    }

    pub fn with_override(override_id: &str) -> Self {
        let trimmed = override_id.trim();
        Self {
            user_override: if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            },
        }
    }

    pub fn from_settings() -> Self {
        let path = Self::settings_path();
        let content = fs::read_to_string(&path).unwrap_or_default();
        let ov = system_monitor_app_from_settings(&content);
        Self { user_override: ov }
    }

    pub fn search_dirs() -> Vec<PathBuf> {
        AppIdentityIndex::search_dirs()
    }

    fn settings_path() -> PathBuf {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/user".into());
        let config_home = std::env::var("XDG_CONFIG_HOME")
            .unwrap_or_else(|_| format!("{}/.config", home));
        let user_settings = PathBuf::from(&config_home).join("astral-plasma/settings.json");
        if user_settings.exists() {
            return user_settings;
        }
        PathBuf::from("config/settings.json")
    }

    /// Check if a binary exists on PATH.
    pub fn is_binary_on_path(binary: &str) -> bool {
        let clean = binary.trim();
        if clean.is_empty() {
            return false;
        }
        if clean.contains('/') {
            return Path::new(clean).is_file();
        }
        if let Some(paths) = std::env::var_os("PATH") {
            for dir in std::env::split_paths(&paths) {
                if dir.join(clean).is_file() {
                    return true;
                }
            }
        }
        false
    }

    /// Find an installed terminal emulator for console monitors.
    pub fn find_terminal_emulator() -> Option<String> {
        let terms = ["ghostty", "alacritty", "konsole", "kitty", "foot", "wezterm", "xterm"];
        for t in terms {
            if Self::is_binary_on_path(t) {
                return Some(t.to_string());
            }
        }
        None
    }
}

impl Default for SystemMonitorAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemMonitorPort for SystemMonitorAdapter {
    fn override_id(&self) -> Option<&str> {
        self.user_override.as_deref()
    }

    fn resolve(&self) -> Vec<String> {
        let mut installed_ids: Vec<String> = Vec::new();
        let dirs = Self::search_dirs();

        for dir in &dirs {
            let Ok(entries) = fs::read_dir(dir) else {
                continue;
            };
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
                    continue;
                }
                let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or_default();
                let Ok(content) = fs::read_to_string(&path) else {
                    continue;
                };
                if desktop_entry_supports_system_monitor(&content, stem) {
                    if !installed_ids.contains(&stem.to_string()) {
                        installed_ids.push(stem.to_string());
                    }
                }
            }
        }

        let mut fallback_bins: Vec<String> = Vec::new();
        for m in WELL_KNOWN_MONITORS {
            if !m.contains('.') && Self::is_binary_on_path(m) {
                fallback_bins.push(m.to_string());
            }
        }

        system_monitor_candidates(
            self.user_override.as_deref(),
            &installed_ids,
            &fallback_bins,
        )
    }

    fn open(&self) -> DynResult<SystemMonitorOpenResult> {
        let candidates = self.resolve();
        if candidates.is_empty() {
            return Ok(SystemMonitorOpenResult {
                success: false,
                launched: None,
                candidates: Vec::new(),
                reason: Some("No system monitor application found or installed on PATH".into()),
            });
        }

        let dirs = Self::search_dirs();

        for candidate in &candidates {
            let bare = candidate.strip_suffix(".desktop").unwrap_or(candidate);
            let with_suffix = format!("{bare}.desktop");

            // 1. Try finding matching desktop entry
            let mut found_desktop: Option<(PathBuf, String)> = None;
            for dir in &dirs {
                let candidate_path = dir.join(&with_suffix);
                if candidate_path.is_file() {
                    if let Ok(content) = fs::read_to_string(&candidate_path) {
                        found_desktop = Some((candidate_path, content));
                        break;
                    }
                }
            }

            if let Some((desktop_path, content)) = found_desktop {
                let mut is_terminal = false;
                let mut exec_line = String::new();

                for line in content.lines() {
                    let trimmed = line.trim();
                    if trimmed.starts_with("Terminal=") {
                        is_terminal = trimmed.eq_ignore_ascii_case("Terminal=true");
                    } else if trimmed.starts_with("Exec=") && exec_line.is_empty() {
                        exec_line = trimmed.strip_prefix("Exec=").unwrap_or("").trim().to_string();
                    }
                }

                // If it is a terminal application (like btop), launch in terminal
                if is_terminal {
                    if let Some((prog, args)) = parse_exec_command(&exec_line) {
                        if let Some(term) = Self::find_terminal_emulator() {
                            let mut term_args = vec!["-e".to_string(), prog];
                            term_args.extend(args);
                            if Command::new(&term).args(&term_args).spawn().is_ok() {
                                return Ok(SystemMonitorOpenResult {
                                    success: true,
                                    launched: Some(candidate.clone()),
                                    candidates,
                                    reason: None,
                                });
                            }
                        }
                    }
                }

                // Try KDE KIO client if available
                if Self::is_binary_on_path("kioclient") {
                    if Command::new("kioclient")
                        .args(["exec", &desktop_path.to_string_lossy()])
                        .spawn()
                        .is_ok()
                    {
                        return Ok(SystemMonitorOpenResult {
                            success: true,
                            launched: Some(candidate.clone()),
                            candidates,
                            reason: None,
                        });
                    }
                }

                // Try direct execution of parsed Exec command
                if let Some((prog, args)) = parse_exec_command(&exec_line) {
                    if Command::new(&prog).args(&args).spawn().is_ok() {
                        return Ok(SystemMonitorOpenResult {
                            success: true,
                            launched: Some(candidate.clone()),
                            candidates,
                            reason: None,
                        });
                    }
                }
            }

            // 2. Direct binary on PATH
            if Self::is_binary_on_path(bare) {
                if bare == "btop" || bare == "htop" {
                    if let Some(term) = Self::find_terminal_emulator() {
                        if Command::new(&term).args(["-e", bare]).spawn().is_ok() {
                            return Ok(SystemMonitorOpenResult {
                                success: true,
                                launched: Some(bare.to_string()),
                                candidates,
                                reason: None,
                            });
                        }
                    }
                } else if Command::new(bare).spawn().is_ok() {
                    return Ok(SystemMonitorOpenResult {
                        success: true,
                        launched: Some(bare.to_string()),
                        candidates,
                        reason: None,
                    });
                }
            }

            // 3. Fallback gtk-launch
            if let Ok(mut child) = Command::new("gtk-launch").arg(candidate).spawn() {
                if let Ok(st) = child.wait() {
                    if st.success() {
                        return Ok(SystemMonitorOpenResult {
                            success: true,
                            launched: Some(candidate.clone()),
                            candidates,
                            reason: None,
                        });
                    }
                }
            }
        }

        Ok(SystemMonitorOpenResult {
            success: false,
            launched: None,
            candidates,
            reason: Some("Failed to spawn any candidate system monitor".into()),
        })
    }
}
