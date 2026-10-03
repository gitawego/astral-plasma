use crate::domain::ports::{DynResult, SystemMonitorPort};
use crate::domain::system_monitor::SystemMonitorOpenResult;
use crate::infrastructure::system_monitor::SystemMonitorAdapter;
use std::sync::Arc;

pub struct OpenSystemMonitorUseCase {
    port: Arc<dyn SystemMonitorPort>,
}

impl OpenSystemMonitorUseCase {
    pub fn new() -> Self {
        Self {
            port: Arc::new(SystemMonitorAdapter::from_settings()),
        }
    }

    pub fn with_port(port: Arc<dyn SystemMonitorPort>) -> Self {
        Self { port }
    }

    pub fn with_override(override_id: &str) -> Self {
        Self {
            port: Arc::new(SystemMonitorAdapter::with_override(override_id)),
        }
    }

    pub fn override_id(&self) -> Option<&str> {
        self.port.override_id()
    }

    pub fn resolve(&self) -> Vec<String> {
        self.port.resolve()
    }

    pub fn execute(&self) -> DynResult<SystemMonitorOpenResult> {
        self.port.open()
    }
}

impl Default for OpenSystemMonitorUseCase {
    fn default() -> Self {
        Self::new()
    }
}
