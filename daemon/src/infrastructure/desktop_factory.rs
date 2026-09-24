use crate::domain::ports::{DesktopSessionPort, WindowManagerPort, WorkspacePort};
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

pub fn detect_compositor() -> CompositorKind {
    if std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok() {
        CompositorKind::Hyprland
    } else {
        CompositorKind::KWin
    }
}

pub fn detect_profile() -> EnvironmentProfile {
    if std::env::var("OMARCHY_SESSION_ID").is_ok() || std::env::var("OMARCHY_DIR").is_ok() {
        EnvironmentProfile::Omarchy
    } else if std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok() {
        EnvironmentProfile::Hyprland
    } else {
        EnvironmentProfile::Kde
    }
}

pub fn create_desktop_session_port() -> Arc<dyn DesktopSessionPort> {
    match detect_compositor() {
        CompositorKind::KWin => Arc::new(KWinAdapter::new()),
        CompositorKind::Hyprland => Arc::new(KWinAdapter::new()),
    }
}

pub fn create_window_manager_port() -> Arc<dyn WindowManagerPort> {
    match detect_compositor() {
        CompositorKind::KWin => Arc::new(KWinAdapter::new()),
        CompositorKind::Hyprland => Arc::new(KWinAdapter::new()),
    }
}

pub fn create_workspace_port() -> Arc<dyn WorkspacePort> {
    match detect_compositor() {
        CompositorKind::KWin => Arc::new(KWinAdapter::new()),
        CompositorKind::Hyprland => Arc::new(KWinAdapter::new()),
    }
}
