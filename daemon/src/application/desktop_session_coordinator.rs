use crate::domain::model::{ActionResult, Capability, DesktopSessionSnapshot, UserIntent};
use crate::domain::ports::{DesktopSessionPort, DynResult};
use std::collections::HashMap;
use std::sync::Arc;

/// DesktopSessionCoordinator (Application Service)
///
/// Orchestrates canonical desktop session snapshot queries, capability resolution,
/// and user intent execution across active compositor backends.
pub struct DesktopSessionCoordinator {
    port: Arc<dyn DesktopSessionPort>,
}

impl DesktopSessionCoordinator {
    pub fn new(port: Arc<dyn DesktopSessionPort>) -> Self {
        Self { port }
    }

    pub fn get_snapshot(&self) -> DynResult<DesktopSessionSnapshot> {
        self.port.get_snapshot()
    }

    pub fn get_snapshot_json(&self) -> DynResult<String> {
        let snap = self.get_snapshot()?;
        Ok(serde_json::to_string(&snap)?)
    }

    pub fn get_capabilities(&self) -> DynResult<HashMap<String, Capability>> {
        self.port.get_capabilities()
    }

    pub fn get_capabilities_json(&self) -> DynResult<String> {
        let caps = self.get_capabilities()?;
        Ok(serde_json::to_string(&caps)?)
    }

    pub fn execute_intent(&self, intent: UserIntent) -> DynResult<ActionResult> {
        self.port.execute_intent(intent)
    }

    pub fn execute_intent_json(&self, intent: UserIntent) -> DynResult<String> {
        let res = self.execute_intent(intent)?;
        Ok(serde_json::to_string(&res)?)
    }
}
