use crate::domain::ports::{DynResult, WorkspacePort};
use serde_json::json;

pub struct WorkspaceControlUseCase<T: WorkspacePort> {
    port: T,
}

impl<T: WorkspacePort> WorkspaceControlUseCase<T> {
    pub fn new(port: T) -> Self {
        Self { port }
    }

    pub fn query_json(&self) -> DynResult<String> {
        let (current, count, items) = self.port.query_desktops()?;
        let val = json!({
            "current": current,
            "count": count,
            "items": items
        });
        Ok(val.to_string())
    }

    pub fn switch(&self, id: &str) -> DynResult<()> {
        self.port.switch_to(id)
    }

    pub fn ensure_and_switch(&self, index: u32) -> DynResult<()> {
        self.port.create_and_switch(index)
    }

    pub fn move_window(&self, window_id: &str, desktop_id: &str) -> DynResult<()> {
        self.port.move_window(window_id, desktop_id)
    }

    pub fn create_desktop(&self, name: Option<&str>) -> DynResult<()> {
        self.port.create_desktop(name)
    }

    pub fn remove_desktop(&self, id: &str) -> DynResult<()> {
        self.port.remove_desktop(id)
    }

    pub fn set_desktop_name(&self, id: &str, name: &str) -> DynResult<()> {
        self.port.set_desktop_name(id, name)
    }

    pub fn toggle_overview(&self) -> DynResult<()> {
        self.port.toggle_overview()
    }

    pub fn toggle_grid(&self) -> DynResult<()> {
        self.port.toggle_grid()
    }
}
