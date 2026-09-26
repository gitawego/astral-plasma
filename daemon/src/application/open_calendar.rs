use crate::domain::calendar::CalendarOpenResult;
use crate::domain::ports::{CalendarPort, DynResult};
use crate::infrastructure::calendar::CalendarAdapter;
use std::sync::Arc;

pub struct OpenCalendarUseCase {
    port: Arc<dyn CalendarPort>,
}

impl OpenCalendarUseCase {
    /// Constructs a use case backed by any implementation of the CalendarPort domain trait.
    pub fn new_with_port(port: Arc<dyn CalendarPort>) -> Self {
        Self { port }
    }

    /// Resolves with the user's `dashboard.calendarApp` setting applied when
    /// set; otherwise the system's XDG MIME default (no hardcoded app).
    pub fn new() -> Self {
        Self {
            port: Arc::new(CalendarAdapter::from_settings()),
        }
    }

    pub fn with_override(override_id: &str) -> Self {
        Self {
            port: Arc::new(CalendarAdapter::with_override(override_id)),
        }
    }

    /// The configured user override, when set.
    pub fn override_id(&self) -> Option<&str> {
        self.port.override_id()
    }

    pub fn resolve(&self) -> Vec<String> {
        self.port.resolve()
    }

    pub fn mime_defaults(&self) -> Vec<String> {
        self.port.mime_defaults()
    }

    pub fn fallback_available(&self) -> bool {
        self.port.fallback_available()
    }

    pub fn mime_default(&self) -> Option<String> {
        self.port.mime_default()
    }

    pub fn execute(&self, date: Option<&str>) -> DynResult<CalendarOpenResult> {
        self.port.open(date)
    }
}

impl Default for OpenCalendarUseCase {
    fn default() -> Self {
        Self::new()
    }
}
