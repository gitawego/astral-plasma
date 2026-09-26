use crate::domain::ai_activity::AiActivityState;
use crate::domain::ports::AiActivityPort;
use crate::infrastructure::ai_activity_monitor::AiActivityMonitor;
use std::sync::Arc;

/// Application use case coordinating AI agent model activity tracking and state queries.
pub struct AiActivityUseCase {
    monitor: Arc<dyn AiActivityPort>,
}

impl Default for AiActivityUseCase {
    fn default() -> Self {
        Self {
            monitor: Arc::new(AiActivityMonitor::new()),
        }
    }
}

impl AiActivityUseCase {
    pub fn new(monitor: Arc<dyn AiActivityPort>) -> Self {
        Self { monitor }
    }

    /// Queries the instantaneous state of AI agent activity.
    pub fn get_state(&self) -> AiActivityState {
        self.monitor.get_state_sync()
    }

    /// Synchronously executes a full scan across active session files and external stores.
    pub fn query_current_state(&self) -> AiActivityState {
        self.monitor.query_active_state_sync()
    }

    /// Records a new request event for the specified model and tool source.
    pub fn record_activity(&self, raw_model: &str, tool_source: &str, tokens: Option<u64>, is_completed: bool) {
        self.monitor.record_activity_sync(raw_model, tool_source, tokens, is_completed);
    }

    /// Ticks decay and prunes inactive agents.
    pub fn tick_decay(&self) -> bool {
        self.monitor.tick_decay_sync()
    }
}
