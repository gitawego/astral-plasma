use crate::domain::ports::{DesktopSessionPort, WindowManagerPort, WorkspacePort};
use crate::infrastructure::hyprland_adapter::HyprlandAdapter;
use crate::infrastructure::kwin_adapter::KWinAdapter;
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompositorKind {
    KWin,
    Hyprland,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnvironmentProfile {
    Kde,
    Hyprland,
    Omarchy,
}

fn get_configured_session() -> (Option<String>, Option<String>) {
    let candidate_paths = [
        crate::domain::branding::config_home().join("astral-plasma").join("settings.json"),
        std::path::PathBuf::from("config/settings.json"),
    ];

    for path in &candidate_paths {
        if let Ok(content) = std::fs::read_to_string(path) {
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(session) = val.get("session") {
                    let comp = session
                        .get("compositor")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_lowercase())
                        .filter(|s| s != "auto");
                    let env = session
                        .get("environment")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_lowercase())
                        .filter(|s| s != "auto");
                    return (comp, env);
                }
            }
        }
    }
    (None, None)
}

pub fn detect_compositor() -> CompositorKind {
    let (comp_cfg, _) = get_configured_session();
    match comp_cfg.as_deref() {
        Some("hyprland") => CompositorKind::Hyprland,
        Some("kwin") => CompositorKind::KWin,
        _ => {
            if std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok() {
                CompositorKind::Hyprland
            } else {
                CompositorKind::KWin
            }
        }
    }
}

pub fn detect_profile() -> EnvironmentProfile {
    let (_, env_cfg) = get_configured_session();
    match env_cfg.as_deref() {
        Some("omarchy") | Some("omarchyhosted") => EnvironmentProfile::Omarchy,
        Some("hyprland") | Some("hyprlandstandaloneexperimental") => EnvironmentProfile::Hyprland,
        Some("kde") | Some("plasma") => EnvironmentProfile::Kde,
        _ => {
            if std::env::var("OMARCHY_SESSION_ID").is_ok()
                || std::env::var("OMARCHY_DIR").is_ok()
                || std::env::var("OMARCHY_SESSION").is_ok()
                || std::env::var("OMARCHY_VERSION").is_ok()
            {
                EnvironmentProfile::Omarchy
            } else if std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok() {
                EnvironmentProfile::Hyprland
            } else {
                EnvironmentProfile::Kde
            }
        }
    }
}

pub fn create_desktop_session_port() -> Arc<dyn DesktopSessionPort> {
    match detect_compositor() {
        CompositorKind::KWin => Arc::new(KWinAdapter::new()),
        CompositorKind::Hyprland => Arc::new(HyprlandAdapter::new()),
    }
}

pub fn create_window_manager_port() -> Arc<dyn WindowManagerPort> {
    match detect_compositor() {
        CompositorKind::KWin => Arc::new(KWinAdapter::new()),
        CompositorKind::Hyprland => Arc::new(HyprlandAdapter::new()),
    }
}

pub fn create_workspace_port() -> Arc<dyn WorkspacePort> {
    match detect_compositor() {
        CompositorKind::KWin => Arc::new(KWinAdapter::new()),
        CompositorKind::Hyprland => Arc::new(HyprlandAdapter::new()),
    }
}
