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
}
