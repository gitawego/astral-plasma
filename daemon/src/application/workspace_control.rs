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
}
