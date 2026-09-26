//! Default calendar application launching.
//!
//! Resolution is the system's own XDG MIME database, in precedence order:
//!
//! 1. The explicit user override stored as `dashboard.calendarApp` in the
//!    live settings file (Settings > Dashboard & Widgets > Calendar App);
//!    empty/absent means "system default". The pick is trusted as-is - no
//!    declaration check - but dropped when its desktop file no longer exists,
//!    so an uninstalled app can never dead-end a date click.
//! 2. The MIME defaults for `text/calendar` (then `webcal`/`webcals`),
//!    **verified** against their installed desktop entries: the entry must
//!    declare `MimeType=text/calendar` or the freedesktop `Calendar`
//!    category. A bare association is not enough - on a system without a
//!    calendar app, opening a `.ics` can otherwise land in a text editor
//!    (observed: Kate), which is never a calendar application.
//! 3. Installed desktop entries declaring `MimeType=text/calendar` or the
//!    freedesktop `Calendar` category.
//! 4. Otherwise the platform Date & Time settings surface (`kcmshell6
//!    kcm_clock`, the same action the shell's clock popout already offers),
//!    and finally an honest failure.
//!
//! Nothing here names a third-party application: a calendar app is whatever
//! the system's own desktop-entry data says it is.

use crate::domain::calendar::{
    calendar_candidates, desktop_entry_name, desktop_entry_supports_calendar, is_valid_iso_date,
    normalize_desktop_id, parse_mimeapps_default, CalendarOpenResult, CALENDAR_MIME,
    CALENDAR_SCHEME_MIMES,
};
use crate::domain::ports::DynResult;
use serde::Serialize;
use std::path::PathBuf;
use std::process::Command;

/// Platform Date & Time settings surface, used only when no MIME handler
/// exists. This is the desktop environment's own date UI (the same action the
/// shell's clock popout already offers as "Date & Time Settings..."), never a
/// calendar application and never a hardcoded third-party app.
pub const FALLBACK_SETTINGS_COMMAND: &[&str] = &["kcmshell6", "kcm_clock"];

/// What opening the calendar resolves to, decided without side effects so it
/// stays unit-testable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpenPlan {
    /// Launch this MIME candidate (a real calendar application).
    Launch(String),
    /// No handler exists: open the platform Date & Time settings instead.
    DateTimeSettings,
    /// Nothing available at all.
    None,
}

pub fn open_plan(candidates: &[String], settings_available: bool) -> OpenPlan {
    for id in candidates {
        if !id.trim().is_empty() {
            return OpenPlan::Launch(id.clone());
        }
    }
    if settings_available {
        OpenPlan::DateTimeSettings
    } else {
        OpenPlan::None
    }
}

/// Is the platform Date & Time settings tool on PATH?
pub fn settings_tool_available() -> bool {
    let Some(binary) = FALLBACK_SETTINGS_COMMAND.first() else {
        return false;
    };
    std::env::var_os("PATH")
        .map(|paths| {
            std::env::split_paths(&paths).any(|dir| dir.join(binary).is_file())
        })
        .unwrap_or(false)
}

pub struct CalendarAdapter {
    user_override: Option<String>,
}

/// Picker row for the settings GUI: installed candidate plus its display name.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct CalendarOption {
    pub id: String,
    pub name: String,
}

/// The user's `dashboard.calendarApp` value from raw settings JSON.
///
/// `""` (the shipped default) means "system default", so blanks and missing
/// keys resolve to `None`; malformed JSON is treated the same way rather than
/// failing the launch.
pub fn calendar_app_from_settings(content: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(content).ok()?;
    let id = value.get("dashboard")?.get("calendarApp")?.as_str()?;
    let trimmed = id.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

/// The user's calendar override from the live settings file
/// (`$XDG_CONFIG_HOME/astral-plasma/settings.json` - the file `Config.qml`
/// writes), or `None` when absent/unreadable/blank.
pub fn settings_calendar_override() -> Option<String> {
    let path = crate::domain::branding::config_home()
        .join(crate::domain::branding::DATA_DIR)
        .join("settings.json");
    let content = std::fs::read_to_string(path).ok()?;
    calendar_app_from_settings(&content)
}

/// Picker options for `calendar resolve`: each candidate with the `Name=`
/// from its installed desktop entry, falling back to the id when the entry
/// or its name cannot be read.
pub fn calendar_options(candidates: &[String], dirs: &[PathBuf]) -> Vec<CalendarOption> {
    candidates
        .iter()
        .map(|id| {
            let name = find_desktop_file(id, dirs)
                .and_then(|path| std::fs::read_to_string(path).ok())
                .and_then(|content| desktop_entry_name(&content))
                .unwrap_or_else(|| id.clone());
            CalendarOption { id: id.clone(), name }
        })
        .collect()
}

impl CalendarAdapter {
    pub fn new() -> Self {
        Self { user_override: None }
    }

    pub fn with_override(override_id: &str) -> Self {
        let trimmed = override_id.trim();
        Self {
            user_override: if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            },
        }
    }

    /// Adapter honouring the user's `dashboard.calendarApp` setting, if any.
    pub fn from_settings() -> Self {
        match settings_calendar_override() {
            Some(id) => Self::with_override(&id),
            None => Self::new(),
        }
    }

    /// The configured user override, when set (for reporting in `resolve`).
    pub fn override_id(&self) -> Option<&str> {
        self.user_override.as_deref()
    }

    /// Desktop ids to try, highest precedence first.
    pub fn resolve(&self) -> Vec<String> {
        self.resolve_from(&self.mime_defaults(), &Self::search_dirs())
    }

    /// Resolve from injectable inputs (hermetic unit tests use temp dirs).
    pub fn resolve_from(&self, mime_defaults: &[String], dirs: &[PathBuf]) -> Vec<String> {
        let verified: Vec<String> = mime_defaults
            .iter()
            .filter(|id| desktop_id_declares_calendar(id, dirs))
            .cloned()
            .collect();
        let scan = scan_calendar_ids(dirs);
        // The user's pick wins, but only while its desktop entry exists:
        // a stale setting (app uninstalled) falls through to system order.
        let override_id = self
            .user_override
            .as_ref()
            .filter(|id| find_desktop_file(id, dirs).is_some());
        calendar_candidates(override_id.map(|s| s.as_str()), &verified, &scan)
    }

    /// MIME defaults in precedence order: `text/calendar` first, then the
    /// `webcal`/`webcals` scheme handlers a calendar app may claim instead.
    pub fn mime_defaults(&self) -> Vec<String> {
        let mut out = Vec::new();
        for mime in std::iter::once(CALENDAR_MIME).chain(CALENDAR_SCHEME_MIMES.iter().copied()) {
            if let Some(id) = query_mime_default(mime).or_else(|| read_mimeapps_default(mime)) {
                if !out.contains(&id) {
                    out.push(id);
                }
            }
        }
        out
    }

    /// Primary MIME default (`text/calendar`) without launching.
    /// Used by `calendar resolve`.
    pub fn mime_default(&self) -> Option<String> {
        self.mime_defaults().into_iter().next()
    }

    /// Launch the first resolvable candidate.
    ///
    /// `date` is the clicked day in `YYYY-MM-DD` form. It is validated and
    /// echoed back in the result for transparency; the launch itself opens
    /// the calendar application (which presents its own current view) rather
    /// than fabricating a calendar event for that day.
    pub fn open(&self, date: Option<&str>) -> DynResult<CalendarOpenResult> {
        let normalized_date = match date {
            Some(raw) => {
                let d = raw.trim().to_string();
                if d.is_empty() {
                    None
                } else if !is_valid_iso_date(&d) {
                    return Err(format!("invalid ISO date (expected YYYY-MM-DD): {raw}").into());
                } else {
                    Some(d)
                }
            }
            None => None,
        };

        let candidates = self.resolve();
        let settings_available = settings_tool_available();
        match open_plan(&candidates, settings_available) {
            OpenPlan::Launch(id) => {
                launch_desktop_id(&id);
                return Ok(CalendarOpenResult {
                    success: true,
                    date: normalized_date,
                    launched: Some(id),
                    candidates: candidates.clone(),
                    fallback: false,
                    reason: None,
                });
            }
            OpenPlan::DateTimeSettings => {
                if launch_settings_tool() {
                    return Ok(CalendarOpenResult {
                        success: true,
                        date: normalized_date,
                        launched: Some(FALLBACK_SETTINGS_COMMAND.join(" ")),
                        candidates,
                        fallback: true,
                        reason: None,
                    });
                }
            }
            OpenPlan::None => {}
        }

        Ok(CalendarOpenResult {
            success: false,
            date: normalized_date,
            launched: None,
            candidates,
            fallback: false,
            reason: Some("no-calendar-handler".to_string()),
        })
    }
}

impl crate::domain::ports::CalendarPort for CalendarAdapter {
    fn override_id(&self) -> Option<&str> {
        self.override_id()
    }
    fn resolve(&self) -> Vec<String> {
        self.resolve()
    }
    fn mime_defaults(&self) -> Vec<String> {
        self.mime_defaults()
    }
    fn mime_default(&self) -> Option<String> {
        self.mime_default()
    }
    fn fallback_available(&self) -> bool {
        settings_tool_available()
    }
    fn open(&self, date: Option<&str>) -> DynResult<CalendarOpenResult> {
        self.open(date)
    }
}

impl CalendarAdapter {

    /// Directories searched for `*.desktop` files, highest precedence first.
    /// Mirrors [`crate::domain::app_identity::AppIdentityIndex::search_dirs`]
    /// so both resolvers see the same installed applications.
    pub fn search_dirs() -> Vec<PathBuf> {
        crate::domain::app_identity::AppIdentityIndex::search_dirs()
    }

    /// `mimeapps.list` locations in decreasing precedence.
    pub fn mimeapps_files() -> Vec<PathBuf> {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/user".into());
        let config_home =
            std::env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{home}/.config"));
        let data_home =
            std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{home}/.local/share"));
        let mut files = vec![
            PathBuf::from(&config_home).join("mimeapps.list"),
            PathBuf::from(&data_home).join("applications/mimeapps.list"),
        ];
        let data_dirs =
            std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
        for d in data_dirs.split(':').filter(|d| !d.is_empty()) {
            files.push(PathBuf::from(d).join("applications/mimeapps.list"));
        }
        files
    }
}

impl Default for CalendarAdapter {
    fn default() -> Self {
        Self::new()
    }
}

/// The system's authoritative MIME default, via its own query tool.
fn query_mime_default(mime: &str) -> Option<String> {
    let out = Command::new("xdg-mime")
        .args(["query", "default", mime])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let id = String::from_utf8_lossy(&out.stdout);
    let id = normalize_desktop_id(&id);
    if id.is_empty() {
        None
    } else {
        Some(id)
    }
}

fn read_mimeapps_default(mime: &str) -> Option<String> {
    for path in CalendarAdapter::mimeapps_files() {
        let Ok(content) = std::fs::read_to_string(&path) else {
            continue;
        };
        if let Some(id) = parse_mimeapps_default(&content, mime) {
            let id = normalize_desktop_id(&id);
            if !id.is_empty() {
                return Some(id);
            }
        }
    }
    None
}

/// Locate an installed desktop entry for `id`, accepting both the bare id
/// and the `.desktop`-suffixed form.
pub fn find_desktop_file(id: &str, dirs: &[PathBuf]) -> Option<PathBuf> {
    let trimmed = id.trim();
    if trimmed.is_empty() {
        return None;
    }
    let bare = trimmed.strip_suffix(".desktop").unwrap_or(trimmed);
    for dir in dirs {
        let direct = dir.join(trimmed);
        if direct.is_file() {
            return Some(direct);
        }
        let suffixed = dir.join(format!("{bare}.desktop"));
        if suffixed.is_file() {
            return Some(suffixed);
        }
    }
    None
}

/// Does the installed entry for `id` declare itself calendar-capable?
/// Unverifiable ids (no file on disk) do not qualify: launching those blind
/// is how a date click ends up in a text editor.
pub fn desktop_id_declares_calendar(id: &str, dirs: &[PathBuf]) -> bool {
    let Some(path) = find_desktop_file(id, dirs) else {
        return false;
    };
    let Ok(content) = std::fs::read_to_string(&path) else {
        return false;
    };
    desktop_entry_supports_calendar(&content)
}

/// Installed desktop ids declaring calendar support, sorted for determinism.
fn scan_calendar_ids(dirs: &[PathBuf]) -> Vec<String> {
    let mut ids = Vec::new();
    for dir in dirs {
        scan_dir_calendar(dir, 0, &mut ids);
    }
    ids.sort();
    ids.dedup();
    ids
}

const MAX_SCAN_DEPTH: usize = 6;

fn scan_dir_calendar(dir: &PathBuf, depth: usize, out: &mut Vec<String>) {
    if depth > MAX_SCAN_DEPTH {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_symlink() {
            // Bounded: symlinked trees still count against the depth cap.
            let Ok(target) = std::fs::read_link(&path) else {
                continue;
            };
            let resolved = if target.is_absolute() {
                target
            } else {
                dir.join(target)
            };
            if resolved.is_dir() {
                scan_dir_calendar(&resolved, depth + 1, out);
            }
            continue;
        }
        if path.is_dir() {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with('.') {
                    continue;
                }
            }
            scan_dir_calendar(&path, depth + 1, out);
        } else if path.extension().and_then(|e| e.to_str()) == Some("desktop") {
            let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            let Ok(content) = std::fs::read_to_string(&path) else {
                continue;
            };
            if desktop_entry_supports_calendar(&content) {
                let id = format!("{stem}.desktop");
                if !out.contains(&id) {
                    out.push(id);
                }
            }
        }
    }
}

fn launch_settings_tool() -> bool {
    let mut parts = FALLBACK_SETTINGS_COMMAND.iter();
    let Some(binary) = parts.next() else {
        return false;
    };
    Command::new(binary)
        .args(parts.copied())
        .spawn()
        .is_ok()
}

fn launch_desktop_id(id: &str) {
    use crate::domain::ports::AppLauncherPort;
    use crate::infrastructure::launcher::DesktopLauncherAdapter;
    let launcher = DesktopLauncherAdapter::new();
    let _ = launcher.launch(id);
}
