//! System monitor application resolution and launching.
//!
//! Clicking the "System Monitor" button in the performance tab opens
//! the user's preferred or system-default monitor application.
//! The handler is resolved dynamically from:
//! 1. User override in settings (`dashboard.systemMonitorApp` or `system.monitorApp`).
//! 2. Installed desktop entries supporting system monitoring (`org.kde.plasma-systemmonitor`,
//!    `io.missioncenter.MissionCenter`, `org.gnome.SystemMonitor`, `ksysguard`, `btop`, etc.).
//! 3. System PATH fallback for well-known binaries.

use serde::{Deserialize, Serialize};

/// Result of opening (or resolving) the system monitor application.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SystemMonitorOpenResult {
    pub success: bool,
    pub launched: Option<String>,
    pub candidates: Vec<String>,
    pub reason: Option<String>,
}

/// Known well-known system monitor desktop IDs and binaries in precedence order.
pub const WELL_KNOWN_MONITORS: &[&str] = &[
    "org.kde.plasma-systemmonitor",
    "plasma-systemmonitor",
    "io.missioncenter.MissionCenter",
    "mission-center",
    "org.gnome.SystemMonitor",
    "gnome-system-monitor",
    "org.kde.ksysguard",
    "ksysguard",
    "btop",
    "htop",
];

/// Does this desktop-entry file declare itself as a system monitor?
pub fn desktop_entry_supports_system_monitor(content: &str, desktop_id: &str) -> bool {
    let clean_id = desktop_id.strip_suffix(".desktop").unwrap_or(desktop_id);
    for known in WELL_KNOWN_MONITORS {
        if clean_id.eq_ignore_ascii_case(known) {
            return true;
        }
    }

    let mut in_entry = false;
    let mut seen_entry = false;
    let mut categories_field = String::new();
    let mut keywords_field = String::new();
    let mut name_field = String::new();
    let mut generic_name_field = String::new();

    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            if line.starts_with("[Desktop Entry]") {
                if seen_entry {
                    break;
                }
                seen_entry = true;
                in_entry = true;
                continue;
            }
            if in_entry {
                break;
            }
            continue;
        }
        if !in_entry {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if key.contains('[') {
            continue;
        }
        match key {
            "Categories" if categories_field.is_empty() => categories_field = value.trim().to_string(),
            "Keywords" if keywords_field.is_empty() => keywords_field = value.trim().to_string(),
            "Name" if name_field.is_empty() => name_field = value.trim().to_string(),
            "GenericName" if generic_name_field.is_empty() => generic_name_field = value.trim().to_string(),
            _ => {}
        }
    }

    let categories: Vec<&str> = categories_field
        .split(';')
        .map(|c| c.trim())
        .filter(|c| !c.is_empty())
        .collect();
    let has_category = |name: &str| categories.iter().any(|c| c.eq_ignore_ascii_case(name));

    // freedesktop Monitor + System category (GNOME System Monitor, Mission Center, KSysGuard, btop)
    if has_category("Monitor") && (has_category("System") || has_category("Utility") || has_category("Settings")) {
        return true;
    }

    // Name or GenericName is "System Monitor" / "Resource Monitor" / "Task Manager"
    let is_monitor_name = |s: &str| {
        let lower = s.to_ascii_lowercase();
        lower == "system monitor"
            || lower == "task manager"
            || lower == "resource monitor"
            || lower.contains("system monitor")
            || lower.contains("task manager")
    };

    if (is_monitor_name(&name_field) || is_monitor_name(&generic_name_field))
        && (has_category("System") || has_category("Utility") || has_category("Qt") || has_category("KDE") || categories.is_empty())
    {
        return true;
    }

    // Keywords check: e.g. plasma-systemmonitor has Keywords=task;manager;process;cpu;memory;
    let keywords_lower = keywords_field.to_ascii_lowercase();
    if (keywords_lower.contains("task") || keywords_lower.contains("process") || keywords_lower.contains("manager"))
        && (keywords_lower.contains("cpu") || keywords_lower.contains("memory") || keywords_lower.contains("monitor"))
        && has_category("System")
    {
        return true;
    }

    false
}

/// Order the candidates to try, highest precedence first.
pub fn system_monitor_candidates(
    user_override: Option<&str>,
    installed_ids: &[String],
    fallback_binaries: &[String],
) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut push = |raw: &str| {
        let id = raw.trim();
        if id.is_empty() {
            return;
        }
        if !out.iter().any(|e| e.eq_ignore_ascii_case(id)) {
            out.push(id.to_string());
        }
    };

    if let Some(u) = user_override {
        push(u);
    }

    // Prioritize well-known system monitors among installed entries
    for pref in WELL_KNOWN_MONITORS {
        if installed_ids.iter().any(|id| {
            id.eq_ignore_ascii_case(pref)
                || id.eq_ignore_ascii_case(&format!("{pref}.desktop"))
                || pref.eq_ignore_ascii_case(id.strip_suffix(".desktop").unwrap_or(id))
        }) {
            push(pref);
        }
    }

    for id in installed_ids {
        push(id);
    }

    for bin in fallback_binaries {
        push(bin);
    }

    out
}

/// Parse an `Exec=` string into binary and arguments, removing freedesktop field codes (`%u`, `%f`, etc.).
pub fn parse_exec_command(exec: &str) -> Option<(String, Vec<String>)> {
    let mut parts: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut quote_char = ' ';

    for ch in exec.chars() {
        if in_quotes {
            if ch == quote_char {
                in_quotes = false;
            } else {
                current.push(ch);
            }
        } else if ch == '"' || ch == '\'' {
            in_quotes = true;
            quote_char = ch;
        } else if ch.is_whitespace() {
            if !current.is_empty() {
                parts.push(current);
                current = String::new();
            }
        } else {
            current.push(ch);
        }
    }
    if !current.is_empty() {
        parts.push(current);
    }

    let filtered: Vec<String> = parts
        .into_iter()
        .filter(|p| !p.starts_with('%'))
        .collect();

    if filtered.is_empty() {
        return None;
    }

    let program = filtered[0].clone();
    let args = filtered[1..].to_vec();
    Some((program, args))
}

/// The user's system monitor override from settings JSON.
pub fn system_monitor_app_from_settings(content: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(content).ok()?;
    if let Some(id) = value
        .get("dashboard")
        .and_then(|d| d.get("systemMonitorApp"))
        .and_then(|v| v.as_str())
    {
        let trimmed = id.trim();
        if !trimmed.is_empty() {
            return Some(trimmed.to_string());
        }
    }
    if let Some(id) = value
        .get("system")
        .and_then(|s| s.get("monitorApp"))
        .and_then(|v| v.as_str())
    {
        let trimmed = id.trim();
        if !trimmed.is_empty() {
            return Some(trimmed.to_string());
        }
    }
    None
}
