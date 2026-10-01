use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone)]
pub struct ProvisioningStatus {
    pub pi_executable: Option<PathBuf>,
    pub hermes_executable: Option<PathBuf>,
    /// pi's built-in MCP support (`pi mcp`, pi >= 0.99). MCP is no longer a
    /// companion package: the legacy `pi-mcp-adapter` shadows the built-in
    /// implementation, so provisioning neither requires nor installs it.
    pub has_mcp_support: bool,
    pub has_subagents: bool,
}

/// Companion packages Astral Plasma provisions for the pi harness.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PiPackages {
    pub subagents: bool,
}

impl PiPackages {
    /// Reads the `packages` list written by `pi install` and reports which
    /// companion packages are configured. Matching is exact: `npm:pi-subagents`
    /// counts, a lookalike name such as `npm:pi-subagents-extra` does not.
    pub fn from_settings(settings_path: &Path) -> Self {
        let packages = Self::configured_packages(settings_path);
        Self {
            subagents: packages
                .iter()
                .any(|entry| Self::entry_matches(entry, "pi-subagents")),
        }
    }

    /// Every package entry configured in a pi settings file.
    pub fn configured_packages(settings_path: &Path) -> Vec<String> {
        let Ok(content) = std::fs::read_to_string(settings_path) else {
            return Vec::new();
        };
        let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) else {
            return Vec::new();
        };
        json.get("packages")
            .and_then(|value| value.as_array())
            .map(|entries| {
                entries
                    .iter()
                    .filter_map(|entry| entry.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default()
    }

    fn entry_matches(entry: &str, name: &str) -> bool {
        entry == name || entry.strip_prefix("npm:").is_some_and(|rest| rest == name)
    }
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

    /// Path of the user-level pi settings file (`~/.pi/agent/settings.json`).
    pub fn pi_settings_path() -> Option<PathBuf> {
        let home = std::env::var("HOME").ok()?;
        if home.is_empty() {
            return None;
        }
        Some(Path::new(&home).join(".pi/agent/settings.json"))
    }

    /// Companion packages configured for pi. Only `pi-subagents` remains
    /// critical; MCP is built into pi and must not be required as a package.
    pub fn check_pi_packages() -> PiPackages {
        match Self::pi_settings_path() {
            Some(path) => PiPackages::from_settings(&path),
            None => PiPackages::default(),
        }
    }

    /// Whether pi's built-in MCP support is available.
    ///
    /// MCP ships with pi; probing the built-in `pi mcp` command reports what the
    /// installed binary can actually do instead of trusting a package list.
    pub fn pi_supports_mcp(pi_bin: Option<&Path>) -> bool {
        let Some(bin) = pi_bin else {
            return false;
        };
        Command::new(bin)
            .args(["mcp", "--help"])
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }

    /// Ensures the companion packages Astral Plasma relies on are installed.
    /// MCP is built in and must never be installed as a separate package: the
    /// legacy `pi-mcp-adapter` shadows the built-in implementation.
    pub fn ensure_critical_packages(pi_bin: &Path) -> Result<(), String> {
        let packages = Self::check_pi_packages();

        if !packages.subagents {
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
        let packages = Self::check_pi_packages();

        ProvisioningStatus {
            has_mcp_support: Self::pi_supports_mcp(pi.as_deref()),
            pi_executable: pi,
            hermes_executable: hermes,
            has_subagents: packages.subagents,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_settings(name: &str, contents: &str) -> PathBuf {
        let path = std::env::temp_dir()
            .join(format!("astral-pi-settings-{}-{}.json", std::process::id(), name));
        std::fs::write(&path, contents).expect("write temp settings");
        path
    }

    #[test]
    fn test_locate_pi_or_fallback() {
        let status = RuntimeProvisioner::get_status();
        assert_eq!(status.pi_executable, RuntimeProvisioner::locate_pi());
        if let Some(ref pi) = status.pi_executable {
            assert!(pi.exists(), "Located pi executable must exist on disk");
        }
    }

    #[test]
    fn test_pi_package_matching_is_exact() {
        let exact = temp_settings("exact", r#"{"packages":["npm:pi-web-access","npm:pi-subagents"]}"#);
        assert!(PiPackages::from_settings(&exact).subagents,
            "npm:pi-subagents must be recognised");
        std::fs::remove_file(&exact).ok();

        let trap = temp_settings("trap", r#"{"packages":["npm:pi-subagents-extra","not-a-package"]}"#);
        assert!(!PiPackages::from_settings(&trap).subagents,
            "a lookalike package name must not satisfy the pi-subagents requirement");
        std::fs::remove_file(&trap).ok();

        let broken = temp_settings("broken", "{not json");
        assert!(!PiPackages::from_settings(&broken).subagents,
            "malformed settings must not panic or report packages");
        std::fs::remove_file(&broken).ok();

        assert!(!PiPackages::from_settings(Path::new("/nonexistent/settings.json")).subagents,
            "missing settings file must not panic");
    }

    #[test]
    fn test_check_pi_packages_only_requires_subagents() {
        // MCP is built into pi; the provisioner must not require an adapter package.
        let packages = RuntimeProvisioner::check_pi_packages();
        if let Some(settings_path) = RuntimeProvisioner::pi_settings_path() {
            if settings_path.exists() {
                assert_eq!(
                    packages,
                    PiPackages::from_settings(&settings_path),
                    "check_pi_packages must reflect live settings.json when present"
                );
            } else {
                assert!(!packages.subagents, "Missing settings must report no packages configured");
            }
        }
    }

    #[test]
    fn test_pi_supports_mcp_probes_builtin_cli() {
        assert!(!RuntimeProvisioner::pi_supports_mcp(None),
            "no pi binary means no MCP support");
        assert!(!RuntimeProvisioner::pi_supports_mcp(Some(Path::new("/nonexistent/pi"))),
            "a missing binary must report no MCP support");
        let pi = RuntimeProvisioner::locate_pi();
        if let Some(ref pi_path) = pi {
            assert!(RuntimeProvisioner::pi_supports_mcp(Some(pi_path.as_path())),
                "pi ships built-in MCP: `pi mcp --help` must succeed when pi is installed");
        }
    }
}
