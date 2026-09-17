use crate::domain::ports::{AppLauncherPort, DynResult};
use std::process::Command;

pub struct DesktopLauncherAdapter;

impl DesktopLauncherAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl Default for DesktopLauncherAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl AppLauncherPort for DesktopLauncherAdapter {
    fn launch(&self, target: &str) -> DynResult<()> {
        let trimmed = target.trim();
        if trimmed.is_empty() {
            return Ok(());
        }

        // 1. Lutris
        if trimmed.starts_with("lutris:") || trimmed == "cloudmusic" || trimmed == "netease-cloud-music" {
            let game_id = trimmed
                .replace("lutris:rungame/", "")
                .replace("lutris:", "");
            let final_id = if game_id == "cloudmusic" { "netease-cloud-music" } else { &game_id };
            let _ = Command::new("lutris")
                .arg(format!("lutris:rungame/{}", final_id))
                .spawn();
            return Ok(());
        }

        // 2. Flatpak
        if trimmed.starts_with("be.alexandervanhee.gradia") || trimmed == "gradia" {
            let _ = Command::new("flatpak")
                .args(["run", "be.alexandervanhee.gradia"])
                .spawn();
            return Ok(());
        }

        // 3. Antigravity special handling
        if trimmed == "antigravity" || trimmed == "ai.opencode.desktop" {
            for cand in ["ai.opencode.desktop", "opencode-desktop", "antigravity"] {
                if let Ok(mut child) = Command::new("gtk-launch").arg(cand).spawn() {
                    if let Ok(status) = child.wait() {
                        if status.success() {
                            return Ok(());
                        }
                    }
                }
            }
        }

        // 4. General gtk-launch
        let desktop = if trimmed.ends_with(".desktop") {
            &trimmed[..trimmed.len() - 8]
        } else {
            trimmed
        };

        if let Ok(mut child) = Command::new("gtk-launch").arg(desktop).spawn() {
            if let Ok(status) = child.wait() {
                if status.success() {
                    return Ok(());
                }
            }
        }

        // 5. Direct execution fallback
        for cmd in [trimmed, &trimmed.to_lowercase()] {
            if Command::new(cmd).spawn().is_ok() {
                return Ok(());
            }
        }

        Ok(())
    }

    fn list_apps(&self) -> DynResult<Vec<crate::domain::ports::AppInfo>> {
        use std::collections::HashSet;
        use std::fs;
        use std::path::PathBuf;

        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/user".to_string());
        let app_dirs = [
            PathBuf::from(&home).join(".local/share/applications"),
            PathBuf::from("/usr/share/applications"),
        ];

        let mut seen = HashSet::new();
        let mut apps = Vec::new();

        for dir in &app_dirs {
            if !dir.exists() {
                continue;
            }
            if let Ok(entries) = fs::read_dir(dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() && path.extension().and_then(|s| s.to_str()) == Some("desktop") {
                        let filename = match path.file_name().and_then(|s| s.to_str()) {
                            Some(n) => n.to_string(),
                            None => continue,
                        };

                        if seen.contains(&filename) {
                            continue;
                        }

                        if let Ok(content) = fs::read_to_string(&path) {
                            let mut in_desktop_entry = false;
                            let mut name = String::new();
                            let mut icon = String::new();
                            let mut comment = String::new();
                            let mut exec = String::new();
                            let mut no_display = false;
                            let mut is_app = false;

                            for line in content.lines() {
                                let trimmed = line.trim();
                                if trimmed == "[Desktop Entry]" {
                                    in_desktop_entry = true;
                                    continue;
                                } else if trimmed.starts_with('[') {
                                    in_desktop_entry = false;
                                }

                                if in_desktop_entry {
                                    if trimmed == "Type=Application" {
                                        is_app = true;
                                    } else if trimmed == "NoDisplay=true" {
                                        no_display = true;
                                    } else if trimmed.starts_with("Name=") && name.is_empty() {
                                        name = trimmed[5..].trim().to_string();
                                    } else if trimmed.starts_with("Icon=") && icon.is_empty() {
                                        icon = trimmed[5..].trim().to_string();
                                    } else if trimmed.starts_with("Comment=") && comment.is_empty() {
                                        comment = trimmed[8..].trim().to_string();
                                    } else if trimmed.starts_with("Exec=") && exec.is_empty() {
                                        exec = trimmed[5..].trim().to_string();
                                    }
                                }
                            }

                            if (is_app || !name.is_empty()) && !no_display {
                                seen.insert(filename.clone());
                                apps.push(crate::domain::ports::AppInfo {
                                    name,
                                    desktop_file: filename,
                                    icon,
                                    comment,
                                    exec,
                                });
                            }
                        }
                    }
                }
            }
        }

        apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        Ok(apps)
    }
}
