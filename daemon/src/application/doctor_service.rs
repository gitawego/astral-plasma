use crate::domain::doctor::{is_version_compatible, CheckStatus, DependencyCheck, DoctorReport};
use std::env;
use std::process::Command;

pub struct DoctorService;

impl DoctorService {
    pub fn new() -> Self {
        Self
    }

    pub fn run_diagnostics(&self) -> DoctorReport {
        let mut checks = Vec::new();

        // 1. Quickshell
        checks.push(check_quickshell());

        // 2. Qt6 Framework
        checks.push(check_qt6());

        // 3. Desktop & Window Manager
        checks.push(check_desktop_environment());

        // 4. DBus CLI
        checks.push(check_qdbus());

        // 5. PipeWire Audio Subsystem
        checks.push(check_pipewire());

        // 6. Matugen (Wallpaper color generation)
        checks.push(check_matugen());

        // 7. Power Profiles Daemon
        checks.push(check_powerprofiles());

        // 8. Fcitx5 IME
        checks.push(check_fcitx5());

        // 9. Spectacle
        checks.push(check_spectacle());

        DoctorReport::new(checks)
    }
}

fn check_quickshell() -> DependencyCheck {
    let path = which("quickshell");
    if let Some(ref bin_path) = path {
        if let Ok(output) = Command::new(bin_path).arg("--version").output() {
            let out_str = String::from_utf8_lossy(&output.stdout);
            let version_opt = extract_version(&out_str);
            let req = "0.3.0";
            if let Some(ref ver) = version_opt {
                if is_version_compatible(ver, req) {
                    return DependencyCheck {
                        name: "Quickshell".to_string(),
                        category: "Core Display Engine".to_string(),
                        required: true,
                        status: CheckStatus::Pass,
                        installed: true,
                        detected_version: Some(ver.clone()),
                        required_version: Some(req.to_string()),
                        binary_path: Some(bin_path.clone()),
                        message: "Compatible Quickshell runtime installed and detected".to_string(),
                        recommendation: None,
                    };
                } else {
                    return DependencyCheck {
                        name: "Quickshell".to_string(),
                        category: "Core Display Engine".to_string(),
                        required: true,
                        status: CheckStatus::Fail,
                        installed: true,
                        detected_version: Some(ver.clone()),
                        required_version: Some(req.to_string()),
                        binary_path: Some(bin_path.clone()),
                        message: format!("Installed Quickshell {} is older than minimum required version {}", ver, req),
                        recommendation: Some("Upgrade quickshell: sudo pacman -Syu quickshell (or yay -S quickshell-git)".to_string()),
                    };
                }
            }
        }
        DependencyCheck {
            name: "Quickshell".to_string(),
            category: "Core Display Engine".to_string(),
            required: true,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: None,
            required_version: Some("0.3.0".to_string()),
            binary_path: Some(bin_path.clone()),
            message: "Quickshell binary detected in PATH".to_string(),
            recommendation: None,
        }
    } else {
        DependencyCheck {
            name: "Quickshell".to_string(),
            category: "Core Display Engine".to_string(),
            required: true,
            status: CheckStatus::Fail,
            installed: false,
            detected_version: None,
            required_version: Some("0.3.0".to_string()),
            binary_path: None,
            message: "Quickshell binary not found in PATH".to_string(),
            recommendation: Some("Install Quickshell: sudo pacman -S quickshell (or yay -S quickshell-git)".to_string()),
        }
    }
}

fn check_qt6() -> DependencyCheck {
    // Try pacman first on Arch/CachyOS
    if let Ok(output) = Command::new("pacman").args(["-Q", "qt6-base"]).output() {
        if output.status.success() {
            let out = String::from_utf8_lossy(&output.stdout);
            let ver = extract_version(&out);
            return DependencyCheck {
                name: "Qt 6 Framework".to_string(),
                category: "Core Display Engine".to_string(),
                required: true,
                status: CheckStatus::Pass,
                installed: true,
                detected_version: ver,
                required_version: Some("6.6.0".to_string()),
                binary_path: Some("/usr/lib/qt6".to_string()),
                message: "Qt 6 runtime and QML engine installed".to_string(),
                recommendation: None,
            };
        }
    }

    // Try qmake6 fallback
    if let Some(path) = which("qmake6") {
        if let Ok(output) = Command::new(&path).arg("-v").output() {
            let out = String::from_utf8_lossy(&output.stdout);
            let ver = extract_version(&out);
            return DependencyCheck {
                name: "Qt 6 Framework".to_string(),
                category: "Core Display Engine".to_string(),
                required: true,
                status: CheckStatus::Pass,
                installed: true,
                detected_version: ver,
                required_version: Some("6.6.0".to_string()),
                binary_path: Some(path),
                message: "Qt 6 runtime detected via qmake6".to_string(),
                recommendation: None,
            };
        }
    }

    DependencyCheck {
        name: "Qt 6 Framework".to_string(),
        category: "Core Display Engine".to_string(),
        required: true,
        status: CheckStatus::Warning,
        installed: false,
        detected_version: None,
        required_version: Some("6.6.0".to_string()),
        binary_path: None,
        message: "Could not query Qt 6 version directly via pacman or qmake6".to_string(),
        recommendation: Some("Ensure Qt 6 modules are installed: sudo pacman -S qt6-base qt6-declarative qt6-svg qt6-wayland".to_string()),
    }
}

fn check_desktop_environment() -> DependencyCheck {
    let session = env::var("XDG_SESSION_TYPE").unwrap_or_else(|_| "unknown".to_string());
    let is_wayland = session.to_lowercase() == "wayland";

    // 1. Check Hyprland / Omarchy
    if crate::infrastructure::desktop_factory::detect_compositor() == crate::infrastructure::desktop_factory::CompositorKind::Hyprland
        || env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok()
        || which("Hyprland").is_some() && env::var("XDG_CURRENT_DESKTOP").map(|d| d.to_lowercase().contains("hyprland")).unwrap_or(false)
    {
        let hypr_path = which("Hyprland");
        let hypr_ver = hypr_path.as_ref().and_then(|p| {
            Command::new(p).arg("--version").output().ok().and_then(|o| {
                extract_version(&String::from_utf8_lossy(&o.stdout))
            })
        });

        let profile = crate::infrastructure::desktop_factory::detect_profile();
        let env_label = match profile {
            crate::infrastructure::desktop_factory::EnvironmentProfile::Omarchy => "Omarchy (Hosted on Hyprland)",
            _ => "Hyprland",
        };

        return DependencyCheck {
            name: format!("{env_label} Compositor"),
            category: "Desktop & Window Manager".to_string(),
            required: true,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: hypr_ver,
            required_version: Some("0.50.0".to_string()),
            binary_path: hypr_path,
            message: format!("{env_label} Wayland session active ({session})"),
            recommendation: None,
        };
    }

    // 2. Check KDE Plasma / KWin
    let kwin_path = which("kwin_wayland").or_else(|| which("kwin_x11"));
    let plasma_ver = if let Ok(output) = Command::new("plasmashell").arg("--version").output() {
        if output.status.success() {
            extract_version(&String::from_utf8_lossy(&output.stdout))
        } else {
            None
        }
    } else {
        None
    };

    if kwin_path.is_some() || plasma_ver.is_some() {
        let msg = if is_wayland {
            format!("KDE Plasma & KWin Wayland session active ({})", session)
        } else {
            format!("KDE Plasma & KWin active under {} (Wayland recommended for native liquid glass blur)", session)
        };

        let status = if is_wayland { CheckStatus::Pass } else { CheckStatus::Warning };

        DependencyCheck {
            name: "KDE Plasma & KWin".to_string(),
            category: "Desktop & Window Manager".to_string(),
            required: true,
            status,
            installed: true,
            detected_version: plasma_ver,
            required_version: Some("6.0.0".to_string()),
            binary_path: kwin_path,
            message: msg,
            recommendation: if !is_wayland {
                Some("Log in via a Wayland session for optimal hardware blur and gesture support".to_string())
            } else {
                None
            },
        }
    } else {
        DependencyCheck {
            name: "Desktop & Window Manager".to_string(),
            category: "Desktop & Window Manager".to_string(),
            required: false,
            status: CheckStatus::Warning,
            installed: false,
            detected_version: None,
            required_version: Some("6.0.0".to_string()),
            binary_path: None,
            message: format!("Session type: {}. Neither KWin, plasmashell, nor Hyprland was detected", session),
            recommendation: Some("Astral Plasma supports KDE Plasma 6 (KWin) and Hyprland / Omarchy".to_string()),
        }
    }
}

fn check_qdbus() -> DependencyCheck {
    let is_hyprland = crate::infrastructure::desktop_factory::detect_compositor() == crate::infrastructure::desktop_factory::CompositorKind::Hyprland;
    let path = which("qdbus6").or_else(|| which("qdbus"));
    if let Some(p) = path {
        DependencyCheck {
            name: "DBus Utility (qdbus6)".to_string(),
            category: "IPC & Audio Subsystem".to_string(),
            required: !is_hyprland,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: None,
            required_version: None,
            binary_path: Some(p),
            message: "qdbus6 binary available for session and window management".to_string(),
            recommendation: None,
        }
    } else {
        DependencyCheck {
            name: "DBus Utility (qdbus6)".to_string(),
            category: "IPC & Audio Subsystem".to_string(),
            required: !is_hyprland,
            status: if is_hyprland { CheckStatus::Pass } else { CheckStatus::Fail },
            installed: false,
            detected_version: None,
            required_version: None,
            binary_path: None,
            message: if is_hyprland {
                "qdbus6 not found (optional on Hyprland: native UNIX domain socket IPC is active)".to_string()
            } else {
                "Neither qdbus6 nor qdbus was found in PATH".to_string()
            },
            recommendation: if is_hyprland { None } else { Some("Install Qt6 DBus tools: sudo pacman -S qt6-tools".to_string()) },
        }
    }
}

fn check_pipewire() -> DependencyCheck {
    let path = which("pw-record").or_else(|| which("pipewire"));
    if let Some(ref p) = path {
        let mut ver = None;
        if let Ok(output) = Command::new(p).arg("--version").output() {
            let out = String::from_utf8_lossy(&output.stdout);
            ver = extract_version(&out);
        }
        DependencyCheck {
            name: "PipeWire Audio Subsystem".to_string(),
            category: "IPC & Audio Subsystem".to_string(),
            required: false,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: ver,
            required_version: Some("1.0.0".to_string()),
            binary_path: Some(p.clone()),
            message: "PipeWire audio capture available for real-time visualizer spectrum".to_string(),
            recommendation: None,
        }
    } else {
        DependencyCheck {
            name: "PipeWire Audio Subsystem".to_string(),
            category: "IPC & Audio Subsystem".to_string(),
            required: false,
            status: CheckStatus::Warning,
            installed: false,
            detected_version: None,
            required_version: Some("1.0.0".to_string()),
            binary_path: None,
            message: "pw-record not found (audio visualizer will remain dormant)".to_string(),
            recommendation: Some("Install pipewire-audio-tools: sudo pacman -S pipewire".to_string()),
        }
    }
}

fn check_matugen() -> DependencyCheck {
    let path = which("matugen");
    if let Some(ref p) = path {
        let mut ver = None;
        if let Ok(output) = Command::new(p).arg("--version").output() {
            let out = String::from_utf8_lossy(&output.stdout);
            ver = extract_version(&out);
        }
        DependencyCheck {
            name: "Matugen (Dynamic Palettes)".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: ver,
            required_version: Some("2.0.0".to_string()),
            binary_path: Some(p.clone()),
            message: "matugen available for automatic Material You wallpaper palette generation".to_string(),
            recommendation: None,
        }
    } else {
        DependencyCheck {
            name: "Matugen (Dynamic Palettes)".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Warning,
            installed: false,
            detected_version: None,
            required_version: Some("2.0.0".to_string()),
            binary_path: None,
            message: "matugen not found (theme falls back gracefully to embedded palettes)".to_string(),
            recommendation: Some("Install matugen for dynamic wallpaper colors: cargo install matugen (or sudo pacman -S matugen)".to_string()),
        }
    }
}

fn check_powerprofiles() -> DependencyCheck {
    let path = which("powerprofilesctl");
    if let Some(p) = path {
        DependencyCheck {
            name: "Power Profiles Daemon".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: None,
            required_version: None,
            binary_path: Some(p),
            message: "powerprofilesctl available for switching performance/saver battery profiles".to_string(),
            recommendation: None,
        }
    } else {
        DependencyCheck {
            name: "Power Profiles Daemon".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Warning,
            installed: false,
            detected_version: None,
            required_version: None,
            binary_path: None,
            message: "powerprofilesctl not found (battery popout will display static profile)".to_string(),
            recommendation: Some("Install power-profiles-daemon: sudo pacman -S power-profiles-daemon".to_string()),
        }
    }
}

fn check_fcitx5() -> DependencyCheck {
    let path = which("fcitx5-remote");
    if let Some(p) = path {
        DependencyCheck {
            name: "Fcitx5 Input Method".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: None,
            required_version: None,
            binary_path: Some(p),
            message: "fcitx5-remote available for active IME state management (Rime / English)".to_string(),
            recommendation: None,
        }
    } else {
        DependencyCheck {
            name: "Fcitx5 Input Method".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Warning,
            installed: false,
            detected_version: None,
            required_version: None,
            binary_path: None,
            message: "fcitx5-remote not found (only relevant if using Fcitx5 / Rime IME)".to_string(),
            recommendation: None,
        }
    }
}

fn check_spectacle() -> DependencyCheck {
    let path = which("spectacle");
    if let Some(ref p) = path {
        let mut ver = None;
        if let Ok(output) = Command::new(p).arg("--version").output() {
            let out = String::from_utf8_lossy(&output.stdout);
            ver = extract_version(&out);
        }
        DependencyCheck {
            name: "Spectacle Screenshot Utility".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Pass,
            installed: true,
            detected_version: ver,
            required_version: None,
            binary_path: Some(p.clone()),
            message: "spectacle available for screenshot capture and diagnostic auditing".to_string(),
            recommendation: None,
        }
    } else {
        DependencyCheck {
            name: "Spectacle Screenshot Utility".to_string(),
            category: "Optional Enhancements".to_string(),
            required: false,
            status: CheckStatus::Warning,
            installed: false,
            detected_version: None,
            required_version: None,
            binary_path: None,
            message: "spectacle not found (useful for visual troubleshooting)".to_string(),
            recommendation: Some("Install spectacle: sudo pacman -S spectacle".to_string()),
        }
    }
}

fn which(bin: &str) -> Option<String> {
    let output = Command::new("which").arg(bin).output().ok()?;
    if output.status.success() {
        let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !path.is_empty() {
            return Some(path);
        }
    }
    None
}

fn extract_version(text: &str) -> Option<String> {
    let re = regex::Regex::new(r"([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9a-zA-Z\.]+)*)").ok()?;
    re.captures(text).and_then(|c| c.get(1)).map(|m| m.as_str().to_string())
}
