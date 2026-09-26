use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone)]
pub struct ProvisioningStatus {
    pub pi_executable: Option<PathBuf>,
    pub hermes_executable: Option<PathBuf>,
    pub has_mcp_adapter: bool,
    pub has_subagents: bool,
}

pub struct RuntimeProvisioner;

impl RuntimeProvisioner {
    /// Detects the best available `pi` binary on the system.
    pub fn locate_pi() -> Option<PathBuf> {
        // 1. Direct which lookup
        if let Ok(output) = Command::new("which").arg("pi").output() {
            if output.status.success() {
                let path_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path_str.is_empty() {
                    let p = PathBuf::from(path_str);
                    if p.exists() {
                        return Some(p);
                    }
                }
            }
        }

        // 2. Known local paths
        let home = std::env::var("HOME").unwrap_or_default();
        if !home.is_empty() {
            let home_p = Path::new(&home);

            // ~/.local/share/astral-plasma/bin/pi
            let astral_bin = home_p.join(".local/share/astral-plasma/bin/pi");
            if astral_bin.exists() {
                return Some(astral_bin);
            }

            // ~/.bun/bin/pi
            let bun_pi = home_p.join(".bun/bin/pi");
            if bun_pi.exists() {
                return Some(bun_pi);
            }

            // Look inside nvm directories
            let nvm_versions = home_p.join(".nvm/versions/node");
            if nvm_versions.is_dir() {
                if let Ok(entries) = std::fs::read_dir(nvm_versions) {
                    for entry in entries.flatten() {
                        let candidate = entry.path().join("bin/pi");
                        if candidate.exists() {
                            return Some(candidate);
                        }
                    }
                }
            }
        }

        None
    }

    /// Detects `hermes` agent executable if installed.
    pub fn locate_hermes() -> Option<PathBuf> {
        if let Ok(output) = Command::new("which").arg("hermes").output() {
            if output.status.success() {
                let path_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path_str.is_empty() {
                    let p = PathBuf::from(path_str);
                    if p.exists() {
                        return Some(p);
                    }
                }
            }
        }

        let home = std::env::var("HOME").unwrap_or_default();
        if !home.is_empty() {
            let home_p = Path::new(&home);
            let local_bin = home_p.join(".local/bin/hermes");
            if local_bin.exists() {
                return Some(local_bin);
            }
        }

        None
    }

    /// Checks if required packages (pi-mcp-adapter, pi-subagents) are configured in ~/.pi/agent/settings.json
    pub fn check_pi_packages() -> (bool, bool) {
        let home = std::env::var("HOME").unwrap_or_default();
        if home.is_empty() {
            return (false, false);
        }

        let settings_path = Path::new(&home).join(".pi/agent/settings.json");
        if !settings_path.exists() {
            return (false, false);
        }

        if let Ok(content) = std::fs::read_to_string(settings_path) {
            let has_mcp = content.contains("pi-mcp-adapter");
            let has_subagents = content.contains("pi-subagents");
            return (has_mcp, has_subagents);
        }

        (false, false)
    }

    /// Ensures that critical packages (pi-mcp-adapter and pi-subagents) are installed.
    pub fn ensure_critical_packages(pi_bin: &Path) -> Result<(), String> {
        let (has_mcp, has_subagents) = Self::check_pi_packages();

        if !has_mcp {
            let res = Command::new(pi_bin)
                .args(["install", "npm:pi-mcp-adapter"])
                .output()
                .map_err(|e| format!("Failed to install pi-mcp-adapter: {}", e))?;
            if !res.status.success() {
                eprintln!("[RuntimeProvisioner] Warning: failed to install pi-mcp-adapter");
            }
        }

        if !has_subagents {
            let res = Command::new(pi_bin)
                .args(["install", "npm:pi-subagents"])
                .output()
                .map_err(|e| format!("Failed to install pi-subagents: {}", e))?;
            if !res.status.success() {
                eprintln!("[RuntimeProvisioner] Warning: failed to install pi-subagents");
            }
        }

        Ok(())
    }

    /// Get total provisioning status
    pub fn get_status() -> ProvisioningStatus {
        let pi = Self::locate_pi();
        let hermes = Self::locate_hermes();
        let (has_mcp, has_subagents) = Self::check_pi_packages();

        ProvisioningStatus {
            pi_executable: pi,
            hermes_executable: hermes,
            has_mcp_adapter: has_mcp,
            has_subagents: has_subagents,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_locate_pi_or_fallback() {
        let status = RuntimeProvisioner::get_status();
        // On this test machine, pi is known to be installed in nvm
        assert!(status.pi_executable.is_some());
    }

    #[test]
    fn test_check_pi_packages() {
        let (mcp, subagents) = RuntimeProvisioner::check_pi_packages();
        assert!(mcp, "pi-mcp-adapter should be configured in settings.json");
        assert!(subagents, "pi-subagents should be configured in settings.json");
    }
}
