use crate::domain::model::{
    ActionResult, Capability, Desktop, DesktopEvent, DesktopSessionSnapshot, Output, SystemMetrics,
    TrayItem, UserIntent, Window,
};
use crate::domain::plasma::{PlasmaPanelInfo, PlasmaStatus};
use crate::domain::systemd::ServiceStatus;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::error::Error;

pub type DynError = Box<dyn Error + Send + Sync>;
pub type DynResult<T> = Result<T, DynError>;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AppInfo {
    pub name: String,
    pub desktop_file: String,
    pub icon: String,
    pub comment: String,
    pub exec: String,
}

pub trait WindowManagerPort: Send + Sync {
    fn query_windows(&self) -> DynResult<(Vec<Window>, Option<Window>)>;
    fn activate_window(&self, window_id: &str) -> DynResult<()>;
    fn close_window(&self, window_id: &str) -> DynResult<()>;
}

impl<T: ?Sized + WindowManagerPort> WindowManagerPort for std::sync::Arc<T> {
    fn query_windows(&self) -> DynResult<(Vec<Window>, Option<Window>)> {
        (**self).query_windows()
    }
    fn activate_window(&self, window_id: &str) -> DynResult<()> {
        (**self).activate_window(window_id)
    }
    fn close_window(&self, window_id: &str) -> DynResult<()> {
        (**self).close_window(window_id)
    }
}

pub trait TrayPort: Send + Sync {
    fn query_tray(&self) -> DynResult<Vec<TrayItem>>;
    fn fetch_menu(&self, service: &str, menu_path: &str) -> DynResult<Vec<crate::domain::model::TrayMenuItem>>;
    fn click_item(&self, service: &str, menu_path: &str, item_id: i32) -> DynResult<()>;
}

pub trait WorkspacePort: Send + Sync {
    fn query_desktops(&self) -> DynResult<(String, u32, Vec<Desktop>)>;
    fn switch_to(&self, id: &str) -> DynResult<()>;
    fn create_and_switch(&self, index: u32) -> DynResult<()>;
}

impl<T: ?Sized + WorkspacePort> WorkspacePort for std::sync::Arc<T> {
    fn query_desktops(&self) -> DynResult<(String, u32, Vec<Desktop>)> {
        (**self).query_desktops()
    }
    fn switch_to(&self, id: &str) -> DynResult<()> {
        (**self).switch_to(id)
    }
    fn create_and_switch(&self, index: u32) -> DynResult<()> {
        (**self).create_and_switch(index)
    }
}


pub trait MetricsPort: Send + Sync {
    fn get_metrics(&self) -> DynResult<SystemMetrics>;
}

pub trait AppLauncherPort: Send + Sync {
    fn launch(&self, target: &str) -> DynResult<()>;
    fn list_apps(&self) -> DynResult<Vec<AppInfo>>;
}

pub trait PlasmaControlPort: Send + Sync {
    fn query_panels(&self) -> DynResult<Vec<PlasmaPanelInfo>>;
    fn disable_panels(&self, target: &str) -> DynResult<u32>;
    fn backup_config(&self) -> DynResult<bool>;
    fn restore_config(&self) -> DynResult<bool>;
    fn get_status(&self) -> DynResult<PlasmaStatus>;
}

pub trait SystemdControlPort: Send + Sync {
    fn query_status(&self) -> DynResult<ServiceStatus>;
    fn install_service(&self) -> DynResult<ServiceStatus>;
    fn remove_service(&self) -> DynResult<ServiceStatus>;
}

pub trait ShortcutControlPort: Send + Sync {
    fn snapshot_relevant_shortcuts(&self, target_shortcut: &str) -> DynResult<crate::domain::shortcuts::AstralShortcutSessionBackup>;
    fn restore_relevant_shortcuts(&self) -> DynResult<bool>;
    fn bind_shortcuts(&self, mode: &str) -> DynResult<()>;
    fn is_backup_active(&self) -> bool;
}

pub trait DesktopSessionPort: Send + Sync {
    fn get_snapshot(&self) -> DynResult<DesktopSessionSnapshot>;
    fn get_capabilities(&self) -> DynResult<HashMap<String, Capability>>;
    fn execute_intent(&self, intent: UserIntent) -> DynResult<ActionResult>;
}

pub trait DesktopHostPort: Send + Sync {
    fn detect_host(&self) -> DynResult<Option<String>>;
    fn is_hosted(&self) -> bool;
}

pub trait OutputPort: Send + Sync {
    fn query_outputs(&self) -> DynResult<Vec<Output>>;
    fn focused_output(&self) -> DynResult<Option<Output>>;
}

pub trait FocusPort: Send + Sync {
    fn restore_focus(&self) -> DynResult<()>;
    fn can_restore_focus(&self) -> bool;
}

pub trait DesktopLifecyclePort: Send + Sync {
    fn on_startup(&self) -> DynResult<()>;
    fn on_shutdown(&self) -> DynResult<()>;
}

pub trait DesktopEventSource: Send + Sync {
    fn poll_events(&self) -> DynResult<Vec<DesktopEvent>>;
}

pub trait PreviewPort: Send + Sync {
    fn capture_preview(&self, window_id: &str) -> DynResult<Vec<u8>>;
}

pub trait CompositorEffectsPort: Send + Sync {
    fn is_blur_supported(&self) -> bool;
    fn blur_mode(&self) -> String;
}


