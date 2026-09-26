use crate::domain::model::{
    ActionResult, Capability, Desktop, DesktopEvent, DesktopSessionSnapshot, Output, SystemMetrics,
    TrayItem, UserIntent, Window,
};
use crate::domain::plasma::{PlasmaPanelInfo, PlasmaStatus};
use crate::domain::systemd::ServiceStatus;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::error::Error;
use std::path::{Path, PathBuf};

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

impl<T: ?Sized + TrayPort> TrayPort for std::sync::Arc<T> {
    fn query_tray(&self) -> DynResult<Vec<TrayItem>> {
        (**self).query_tray()
    }
    fn fetch_menu(&self, service: &str, menu_path: &str) -> DynResult<Vec<crate::domain::model::TrayMenuItem>> {
        (**self).fetch_menu(service, menu_path)
    }
    fn click_item(&self, service: &str, menu_path: &str, item_id: i32) -> DynResult<()> {
        (**self).click_item(service, menu_path, item_id)
    }
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
    fn stop_watchdog(&self);
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

/// Parsed session result representing instantaneous model activity from an agent file or data store.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionParseResult {
    pub model_id: String,
    pub tool_source: String,
    pub tokens: Option<u64>,
    pub is_turn_completed: bool,
    pub timestamp_ms: Option<u64>,
}

/// Metadata describing an active agent session file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActiveSessionDescriptor {
    pub path: PathBuf,
    pub mtime: u64,
    pub size: u64,
}

/// Adapter trait for scanning, identifying, and parsing active AI agent sessions across diverse tooling.
pub trait AgentSessionAdapter: Send + Sync {
    /// Canonical tool identifier (e.g., "antigravity", "claude", "codex", "zcode", "opencode", "pi", "omp", "dsh", "cursor", "windsurf").
    fn tool_id(&self) -> &'static str;

    /// Directories to register with the file watcher.
    fn watch_directories(&self, home: &Path) -> Vec<PathBuf>;

    /// Tests if this adapter handles the specified file path.
    fn can_handle_file(&self, path: &Path) -> bool;

    /// Parses an active session file given its path, optional tail string, and optional head string.
    fn parse_session_file(&self, path: &Path, tail: Option<&str>, head: Option<&str>) -> Option<SessionParseResult>;

    /// Scans candidate active session files within the retention window.
    fn scan_active_files(&self, home: &Path, max_age_ms: u64, sink: &mut Vec<ActiveSessionDescriptor>);

    /// Discovers candidate session files for finding the latest activity.
    fn find_candidate_session_files(&self, home: &Path, sink: &mut Vec<PathBuf>);

    /// Queries an external database or store if applicable (e.g., SQLite for OpenCode / ZCode).
    fn query_external_store(&self, _home: &Path) -> Option<SessionParseResult> {
        None
    }

    /// Reads default model and provider configured in tool settings if available.
    fn read_default_settings(&self, _home: &Path) -> Option<(String, String)> {
        None
    }

    /// Tests whether the latest activity indicates turn completion.
    fn check_turn_completed(&self, _tail: &str, _path: &Path) -> bool {
        true
    }
}

/// Domain Port for real-time AI activity tracking and state queries.
pub trait AiActivityPort: Send + Sync {
    fn get_state_sync(&self) -> crate::domain::ai_activity::AiActivityState;
    fn record_activity_sync(&self, raw_model: &str, tool_source: &str, tokens: Option<u64>, is_completed: bool);
    fn tick_decay_sync(&self) -> bool;
    fn query_active_state_sync(&self) -> crate::domain::ai_activity::AiActivityState;
    fn start_background_watcher(&self);
}

impl<T: ?Sized + AiActivityPort> AiActivityPort for std::sync::Arc<T> {
    fn get_state_sync(&self) -> crate::domain::ai_activity::AiActivityState {
        (**self).get_state_sync()
    }
    fn record_activity_sync(&self, raw_model: &str, tool_source: &str, tokens: Option<u64>, is_completed: bool) {
        (**self).record_activity_sync(raw_model, tool_source, tokens, is_completed)
    }
    fn tick_decay_sync(&self) -> bool {
        (**self).tick_decay_sync()
    }
    fn query_active_state_sync(&self) -> crate::domain::ai_activity::AiActivityState {
        (**self).query_active_state_sync()
    }
    fn start_background_watcher(&self) {
        (**self).start_background_watcher()
    }
}

/// Domain Port for Calendar application resolution and launching.
pub trait CalendarPort: Send + Sync {
    fn override_id(&self) -> Option<&str>;
    fn resolve(&self) -> Vec<String>;
    fn mime_defaults(&self) -> Vec<String>;
    fn mime_default(&self) -> Option<String>;
    fn fallback_available(&self) -> bool;
    fn open(&self, date: Option<&str>) -> DynResult<crate::domain::calendar::CalendarOpenResult>;
}

/// Domain Port for AI Quotas tracking, OAuth, and account management.
pub trait AiQuotaPort: Send + Sync {
    fn get_snapshot(&self, warning_thr: f64, critical_thr: f64, force_refresh: bool) -> crate::domain::ai_quota::AiQuotaSnapshot;
    fn switch_gemini_account(&self, target_id_or_email: &str) -> Result<String, String>;
    fn login_gemini_oauth(&self, email_hint: Option<&str>) -> Result<String, String>;
    fn remove_account(&self, provider_id: &str, target_id_or_email: &str) -> Result<String, String>;
    fn add_account(&self, provider_id: &str, credential: &str, label: Option<&str>, is_session: bool) -> Result<String, String>;
    fn list_accounts(&self, provider_id: Option<&str>) -> Result<serde_json::Value, String>;
}



