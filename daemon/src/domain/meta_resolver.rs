//! Window identity resolution.
//!
//! A taskbar needs, for every window: a display name, an icon and a stable id.
//! There is exactly one trustworthy source for that - the desktop entry the
//! application installed - so resolution is:
//!
//!   1. The XDG desktop-entry index, matched on `StartupWMClass` or desktop id
//!      (see [`crate::domain::app_identity`]). This is the same lookup Plasma's
//!      own taskbar performs, so any installed application works without any
//!      code here knowing about it.
//!   2. Wine executables, which ship no usable entry, are named by their own
//!      executable (`cloudmusic.exe` -> "Cloudmusic").
//!   3. Everything else falls back to the window's own strings.
//!
//! There is deliberately no per-application table: adding one would mean every
//! new app needs a code change, and would override the data an app declares
//! about itself.

use crate::domain::app_identity::AppIdentityIndex;
use crate::domain::model::WindowMeta;

/// Identity of a Wine executable that has no desktop entry.
///
/// Wine reports the program's executable as the window class and offers no
/// desktop file. The executable's own name is therefore the only real identity
/// available - it is used verbatim, never mapped onto some *guess* at what the
/// program is.
fn wine_meta(cls: &str, krunner_icon: &str) -> Option<WindowMeta> {
    let stem = cls
        .len()
        .checked_sub(4)
        .filter(|_| cls.to_lowercase().ends_with(".exe"))
        .map(|len| &cls[..len])?;
    if stem.trim().is_empty() {
        return None;
    }
    let app_name = capitalize_truncate(stem, 14);
    Some(WindowMeta {
        app_name,
        icon_name: if krunner_icon.is_empty() {
            "wine".to_string()
        } else {
            krunner_icon.to_string()
        },
        material_icon: "window".to_string(),
        app_id: stem.to_lowercase(),
        desktop_file: stem.to_lowercase(),
    })
}

/// Generic fallback for windows that have neither a desktop entry nor a Wine
/// executable name (ad-hoc binaries, unusual toolkits).
fn generic_meta(title: &str, cls: &str, app: &str, krunner_icon: &str) -> WindowMeta {
    let icon_candidate = if !krunner_icon.is_empty() {
        krunner_icon
    } else if !app.is_empty() {
        app
    } else {
        cls
    };

    let app_name = if let Some(idx) = title.rfind(" — ") {
        title[idx + 4..].trim().chars().take(14).collect::<String>()
    } else if let Some(idx) = title.rfind(" - ") {
        title[idx + 3..].trim().chars().take(14).collect::<String>()
    } else if !cls.is_empty() {
        let last_part = cls.rsplit('.').next().unwrap_or(cls);
        capitalize_truncate(last_part, 14)
    } else if !title.is_empty() {
        title.chars().take(14).collect::<String>()
    } else {
        "Window".to_string()
    };

    let app_id = if !app.is_empty() {
        app.to_lowercase().replace(' ', "-")
    } else if !cls.is_empty() {
        cls.to_lowercase().replace(' ', "-")
    } else {
        app_name.to_lowercase().replace(' ', "-")
    };

    let desktop_file = if !app.is_empty() {
        app.to_string()
    } else if !cls.is_empty() {
        cls.to_string()
    } else {
        app_id.clone()
    };

    WindowMeta {
        app_name,
        icon_name: icon_candidate.to_string(),
        material_icon: "window".to_string(),
        app_id,
        desktop_file,
    }
}

/// Resolve a window's identity, preferring installed desktop entries.
///
/// Tier 1 is what makes this general: any installed application resolves from
/// its own desktop entry, with no per-app code and no substring ambiguity.
pub fn resolve_window_meta_with(
    index: Option<&AppIdentityIndex>,
    title: &str,
    cls: &str,
    app: &str,
    krunner_icon: &str,
) -> WindowMeta {
    if let Some(entry) = index.and_then(|i| i.resolve(cls, app)) {
        return WindowMeta {
            app_name: entry.name.clone(),
            // The desktop entry's Icon= is what the taskbar should draw.
            icon_name: if entry.icon.is_empty() {
                entry.desktop_id.clone()
            } else {
                entry.icon.clone()
            },
            material_icon: entry.material_icon.clone(),
            app_id: entry.desktop_id.clone(),
            desktop_file: entry.desktop_id.clone(),
        };
    }

    if let Some(meta) = wine_meta(cls, krunner_icon) {
        return meta;
    }

    generic_meta(title, cls, app, krunner_icon)
}

/// Resolve without consulting installed desktop entries.
///
/// Retained for callers that need a pure, filesystem-free function (and for
/// tests); production code uses [`resolve_window_meta_with`].
pub fn resolve_window_meta(title: &str, cls: &str, app: &str, krunner_icon: &str) -> WindowMeta {
    resolve_window_meta_with(None, title, cls, app, krunner_icon)
}

fn capitalize_truncate(s: &str, max_chars: usize) -> String {
    let mut c = s.chars();
    match c.next() {
        None => String::new(),
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
    }
    .chars()
    .take(max_chars)
    .collect()
}
