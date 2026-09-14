use crate::domain::model::{Desktop, SystemMetrics, TrayItem, Window};
use std::error::Error;

pub type DynResult<T> = Result<T, Box<dyn Error + Send + Sync>>;

pub trait WindowManagerPort: Send + Sync {
    fn query_windows(&self) -> DynResult<(Vec<Window>, Option<Window>)>;
    fn activate_window(&self, window_id: &str) -> DynResult<()>;
    fn close_window(&self, window_id: &str) -> DynResult<()>;
}

pub trait TrayPort: Send + Sync {
    fn query_tray(&self) -> DynResult<Vec<TrayItem>>;
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
