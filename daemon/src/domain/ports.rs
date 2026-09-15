use crate::domain::model::{Desktop, SystemMetrics, TrayItem, Window};
use crate::domain::plasma::{PlasmaPanelInfo, PlasmaStatus};
use crate::domain::systemd::ServiceStatus;
use std::error::Error;

pub type DynResult<T> = Result<T, Box<dyn Error + Send + Sync>>;

pub trait WindowManagerPort: Send + Sync {
    fn query_windows(&self) -> DynResult<(Vec<Window>, Option<Window>)>;
    fn activate_window(&self, window_id: &str) -> DynResult<()>;
    fn close_window(&self, window_id: &str) -> DynResult<()>;
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

pub trait MetricsPort: Send + Sync {
    fn get_metrics(&self) -> DynResult<SystemMetrics>;
}

pub trait AppLauncherPort: Send + Sync {
    fn launch(&self, target: &str) -> DynResult<()>;
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
