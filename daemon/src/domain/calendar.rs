//! Default calendar handler resolution.
//!
//! Clicking a date in the dashboard calendar must open the user's own
//! calendar application. The handler is resolved entirely from the system's
//! XDG MIME database - `mimeapps.list` defaults plus desktop-entry
//! `MimeType=` / `Categories=` declarations - so no application name is ever
//! hardcoded here.

use serde::{Deserialize, Serialize};

/// MIME type whose default handler is the user's calendar application.
pub const CALENDAR_MIME: &str = "text/calendar";

/// Scheme-handler registrations a calendar app may claim instead of (or in
/// addition to) `text/calendar`, e.g. webcal feed handlers. Standards, not apps.
pub const CALENDAR_SCHEME_MIMES: &[&str] = &["x-scheme-handler/webcal", "x-scheme-handler/webcals"];

/// Result of opening (or resolving) the default calendar application.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CalendarOpenResult {
    pub success: bool,
    pub date: Option<String>,
    pub launched: Option<String>,
    pub candidates: Vec<String>,
    /// True when no MIME handler existed and the platform's Date & Time
    /// settings surface was opened instead (graceful degradation, not a
    /// calendar application).
    #[serde(default)]
    pub fallback: bool,
    pub reason: Option<String>,
}

/// Return the first desktop id listed for `mime` in a `mimeapps.list` file.
///
/// Only the `[Default Applications]` section is honoured, per the XDG MIME
/// specification. Matching is exact on the MIME name; surrounding whitespace
/// around the key, `=`, and list items is ignored.
pub fn parse_mimeapps_default(content: &str, mime: &str) -> Option<String> {
    let mut in_defaults = false;
    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_defaults = line.eq_ignore_ascii_case("[Default Applications]");
            continue;
        }
        if !in_defaults {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if key.trim() != mime {
            continue;
        }
        for entry in value.split(';') {
            let entry = entry.trim();
            if !entry.is_empty() {
                return Some(entry.to_string());
            }
        }
        return None;
    }
    None
}

/// Does this desktop-entry file declare itself calendar-capable?
///
/// True when the first `[Desktop Entry]` group lists `text/calendar` in
/// `MimeType=` or the freedesktop `Calendar` category in `Categories=`.
/// Category comparison is an exact token match (case-insensitive), so
/// `Calculator` never qualifies.
pub fn desktop_entry_supports_calendar(content: &str) -> bool {
    let mut in_entry = false;
    let mut seen_entry = false;
    let mut mime_field = String::new();
    let mut categories_field = String::new();

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
            "MimeType" if mime_field.is_empty() => mime_field = value.trim().to_string(),
            "Categories" if categories_field.is_empty() => {
                categories_field = value.trim().to_string()
            }
            _ => {}
        }
    }

    let mime_hit = mime_field.split(';').any(|m| {
        let m = m.trim();
        !m.is_empty() && m.eq_ignore_ascii_case(CALENDAR_MIME)
    });
    if mime_hit {
        return true;
    }
    categories_field.split(';').any(|c| {
        let c = c.trim();
        !c.is_empty() && c.eq_ignore_ascii_case("Calendar")
    })
}

/// Human-readable `Name=` of a desktop entry, for picker labels.
///
/// Only the first `[Desktop Entry]` group is read: comments, localized keys
/// (`Name[de]=`), and names in other groups (e.g. `[Desktop Action ...]`) are
/// ignored. `None` when the group has no non-empty `Name`.
pub fn desktop_entry_name(content: &str) -> Option<String> {
    let mut in_entry = false;
    let mut seen_entry = false;
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
        if key == "Name" {
            let name = value.trim();
            if !name.is_empty() {
                return Some(name.to_string());
            }
        }
    }
    None
}

/// Order the desktop ids to try, highest precedence first.
///
/// `user_override` is an explicit user configuration, `mime_defaults` are the
/// system's MIME defaults in precedence order (`text/calendar` first, then
/// the `webcal`/`webcals` scheme handlers), and `calendar_ids` are installed
/// entries that declare calendar support. Empty strings are dropped and
/// duplicates keep their first position. With all inputs empty the result is
/// empty: there is no hardcoded fallback application.
pub fn calendar_candidates(
    user_override: Option<&str>,
    mime_defaults: &[String],
    calendar_ids: &[String],
) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut push = |raw: &str| {
        let id = raw.trim();
        if id.is_empty() {
            return;
        }
        if !out.iter().any(|e| e == id) {
            out.push(id.to_string());
        }
    };
    if let Some(u) = user_override {
        push(u);
    }
    for m in mime_defaults {
        push(m);
    }
    let mut sorted = calendar_ids.to_vec();
    sorted.sort();
    sorted.dedup();
    for id in &sorted {
        push(id);
    }
    out
}

/// Trimmed desktop id, or empty when blank. Launching accepts both the bare
/// id and the `.desktop`-suffixed form, so the value is passed through as-is.
pub fn normalize_desktop_id(raw: &str) -> String {
    raw.trim().to_string()
}

/// Is `s` a real calendar date in `YYYY-MM-DD` form?
///
/// Besides shape (`\d{4}-\d{2}-\d{2}`) the month must be 01-12 and the day
/// must exist in that month, including February 29 only on leap years.
pub fn is_valid_iso_date(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return false;
    }
    for (i, c) in b.iter().enumerate() {
        if i == 4 || i == 7 {
            continue;
        }
        if !c.is_ascii_digit() {
            return false;
        }
    }
    let num = |range: std::ops::Range<usize>| -> Option<u32> {
        s[range].parse::<u32>().ok()
    };
    let (Some(y), Some(m), Some(d)) = (num(0..4), num(5..7), num(8..10)) else {
        return false;
    };
    if !(1..=12).contains(&m) || d < 1 {
        return false;
    }
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let max_day = match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap => 29,
        2 => 28,
        _ => return false,
    };
    d <= max_day
}
