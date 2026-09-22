use crate::domain::calendar::CalendarOpenResult;
use crate::domain::ports::DynResult;
use crate::infrastructure::calendar::CalendarAdapter;

pub struct OpenCalendarUseCase {
    adapter: CalendarAdapter,
}

impl OpenCalendarUseCase {
    /// Resolves with the user's `dashboard.calendarApp` setting applied when
    /// set; otherwise the system's XDG MIME default (no hardcoded app).
    pub fn new() -> Self {
        Self {
            adapter: CalendarAdapter::from_settings(),
        }
    }

    pub fn with_override(override_id: &str) -> Self {
        Self {
            adapter: CalendarAdapter::with_override(override_id),
        }
    }

    /// The configured user override, when set.
    pub fn override_id(&self) -> Option<&str> {
        self.adapter.override_id()
    }

    pub fn resolve(&self) -> Vec<String> {
        self.adapter.resolve()
    }

    pub fn mime_defaults(&self) -> Vec<String> {
        self.adapter.mime_defaults()
    }

    pub fn fallback_available(&self) -> bool {
        crate::infrastructure::calendar::settings_tool_available()
    }

    pub fn mime_default(&self) -> Option<String> {
        self.adapter.mime_default()
    }

    pub fn execute(&self, date: Option<&str>) -> DynResult<CalendarOpenResult> {
        self.adapter.open(date)
    }
}

impl Default for OpenCalendarUseCase {
    fn default() -> Self {
        Self::new()
    }
}
