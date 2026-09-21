//! Application identity resolution from XDG desktop entries.
//!
//! Window managers report a window's identity as a class/app-id string, and the
//! mapping from that string to a human name and icon is what a taskbar needs.
//! Doing it with a hand-curated table of substring tests is structurally unsafe:
//! `cls.contains("code")` also matches `zcode`, `opencode`, `claude-code` and
//! `minimax-code`, so any app whose name merely *contains* a curated keyword is
//! misidentified (a ZCode window renders as a second VS Code icon).
//!
//! The desktop-entry standard already carries this mapping: `StartupWMClass`
//! declares the window class an application reports, and `Name`/`Icon` give the
//! display identity. This module reads those entries directly, so resolution is
//! data-driven and exact-matched - no per-app code, and no substring ambiguity.
//!
//! Matching is deliberately exact (case-insensitive, `.desktop` stripped). A
//! near-miss falls through to the caller's heuristics rather than guessing.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock, RwLock};

/// A single application identity read from a desktop entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DesktopApp {
    /// File stem of the desktop entry, e.g. `zcode` for `zcode.desktop`.
    pub desktop_id: String,
    /// `Name=` - the human-readable application name.
    pub name: String,
    /// `Icon=` - theme icon name (may be empty).
    pub icon: String,
    /// `StartupWMClass=` - the window class the app reports, if declared.
    pub wm_class: Option<String>,
    /// Material Symbols name derived from `Categories=`.
    pub material_icon: String,
    /// `Comment=` - a short description, used by launchers.
    pub comment: String,
    /// `Exec=` - the command line the entry declares.
    pub exec: String,
}

/// Map a desktop entry's `Categories=` to a Material Symbols icon name.
///
/// Categories are a freedesktop standard, so this stays data-driven: an app
/// declares what it is and gets a sensible glyph without a curated entry.
fn material_icon_for_categories(categories: &str) -> String {
    let has = |want: &str| {
        categories
            .split(';')
            .any(|c| c.trim().eq_ignore_ascii_case(want))
    };

    if has("Development") || has("IDE") {
        "code".to_string()
    } else if has("AudioVideo") || has("Audio") || has("Player") || has("Music") {
        "music_note".to_string()
    } else if has("Game") {
        "sports_esports".to_string()
    } else if has("Network") || has("WebBrowser") || has("Email") {
        "language".to_string()
    } else if has("Graphics") {
        "palette".to_string()
    } else if has("Office") || has("TextEditor") {
        "description".to_string()
    } else if has("TerminalEmulator") {
        "terminal".to_string()
    } else if has("System") || has("Settings") {
        "settings".to_string()
    } else if has("FileManager") || has("Filesystem") {
        "folder".to_string()
    } else if has("Utility") || has("Calculator") {
        "build".to_string()
    } else if categories.trim().is_empty() {
        "window".to_string()
    } else {
        "window".to_string()
    }
}

/// Window classes belonging to the shell's own surfaces.
///
/// Shared by the Rust filter and the generated KWin scripts, so a rename can
/// never make the two disagree about which windows are the shell's own.
pub const SHELL_WINDOW_CLASSES: [&str; 4] = [
    "quickshell",
    "org.quickshell",
    crate::domain::branding::WINDOW_CLASS_SETTINGS,
    crate::domain::branding::WINDOW_CLASS,
];

/// The class list as a JavaScript array literal for the KWin scripts.
pub fn shell_classes_js() -> String {
    let quoted: Vec<String> = SHELL_WINDOW_CLASSES
        .iter()
        .map(|class| format!("\"{class}\""))
        .collect();
    format!("[{}]", quoted.join(", "))
}

/// Is this window one of the shell's OWN surfaces rather than a user application?
///
/// The shell creates real KWin windows: the unified desktop surface, popout
/// drawers, the notification layer, and the settings window. They set
/// `skipTaskbar`, but a hover or a focus grab can still make one the "active
/// window" - and an unfiltered active-window path then reports a bogus entry,
/// so the dock shows a shell surface as if it were the program the user is
/// working in.
///
/// Matched on the window CLASS and app id only, never the title: editing
/// `UnifiedShell.qml` in VS Code must not make VS Code look like a shell surface.
pub fn is_shell_owned_surface(cls: &str, app: &str, _title: &str) -> bool {
    for candidate in [cls, app] {
        let key = normalize_identity(candidate);
        if key.is_empty() {
            continue;
        }
        for want in SHELL_WINDOW_CLASSES {
            if key == want || key.starts_with(&format!("{want}.")) || key.starts_with(&format!("{want}-")) {
                return true;
            }
        }
    }
    false
}

/// EWMH `skipTaskbar`: the window asked not to appear in a taskbar.
///
/// Honouring it in the ACTIVE-window path is what keeps shell surfaces and other
/// helper windows out of the dock's active-app display. KWin reports this as
/// `skipTaskbar` on every window.
pub fn should_skip_taskbar(skip_flag: bool, cls: &str, app: &str, title: &str) -> bool {
    skip_flag || is_shell_owned_surface(cls, app, title)
}

/// Normalize an identity string for comparison: strip any path, drop a
/// `.desktop` suffix, lowercase. `ZCode` -> `zcode`,
/// `kde4/foo.desktop` -> `foo`.
pub fn normalize_identity(raw: &str) -> String {
    let s = raw.trim();
    let s = s.strip_suffix(".desktop").unwrap_or(s);
    let s = s.rsplit('/').next().unwrap_or(s);
    s.to_lowercase()
}

/// Every key an identity may legitimately match under, most specific first.
///
/// The only naming rule here is Wine's: a Windows executable reports its class
/// as `foo.exe`, while the desktop entry describing it may be named `foo` or
/// declare `StartupWMClass=foo` (and vice versa). Treating `.exe` as an
/// optional suffix is a property of the data format, not knowledge about any
/// particular application.
fn identity_keys(raw: &str) -> Vec<String> {
    let base = normalize_identity(raw);
    if base.is_empty() {
        return Vec::new();
    }
    let mut keys = vec![base.clone()];
    match base.strip_suffix(".exe") {
        Some(stem) if !stem.is_empty() => keys.push(stem.to_string()),
        Some(_) => {}
        None => keys.push(format!("{base}.exe")),
    }
    keys
}

/// Parse one desktop file's `[Desktop Entry]` group.
///
/// Only the FIRST `[Desktop Entry]` group is read: several upstream entries
/// (notably VS Code) ship additional `[Desktop Entry]` groups for secondary
/// launchers, and reading a later group would pick up the wrong `Name`/`Icon`.
/// Localized keys (`Name[de]`) are ignored in favour of the plain key.
/// Returns `None` for non-application or `NoDisplay` entries.
pub fn parse_desktop_entry(content: &str, desktop_id: &str) -> Option<DesktopApp> {
    let mut in_entry = false;
    let mut seen_entry = false;

    let mut name: Option<String> = None;
    let mut icon: Option<String> = None;
    let mut wm_class: Option<String> = None;
    let mut comment = String::new();
    let mut exec = String::new();
    let mut categories = String::new();
    let mut type_app = false;
    let mut no_display = false;

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            if line.starts_with("[Desktop Entry]") {
                if seen_entry {
                    // A second [Desktop Entry] group: stop, the first one wins.
                    break;
                }
                seen_entry = true;
                in_entry = true;
                continue;
            }
            if in_entry {
                // Left the group we care about.
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
        let value = value.trim();
        // Skip localized variants such as `Name[zh_CN]`.
        if key.contains('[') {
            continue;
        }

        match key {
            "Name" => {
                if name.is_none() {
                    name = Some(value.to_string());
                }
            }
            "Icon" => {
                if icon.is_none() {
                    icon = Some(value.to_string());
                }
            }
            "StartupWMClass" => {
                if wm_class.is_none() && !value.is_empty() {
                    wm_class = Some(value.to_string());
                }
            }
            "Comment" => {
                if comment.is_empty() {
                    comment = value.to_string();
                }
            }
            "Exec" => {
                if exec.is_empty() {
                    exec = value.to_string();
                }
            }
            "Categories" => categories = value.to_string(),
            "Type" => type_app = value.eq_ignore_ascii_case("Application"),
            "NoDisplay" => no_display = value.eq_ignore_ascii_case("true"),
            _ => {}
        }
    }

    if !type_app || no_display {
        return None;
    }
    let name = name?;

    Some(DesktopApp {
        desktop_id: desktop_id.to_string(),
        name,
        icon: icon.unwrap_or_else(|| desktop_id.to_string()),
        wm_class,
        material_icon: material_icon_for_categories(&categories),
        comment,
        exec,
    })
}

/// An exact-match index of installed applications.
#[derive(Debug, Default)]
pub struct AppIdentityIndex {
    by_wm_class: HashMap<String, DesktopApp>,
    by_desktop_id: HashMap<String, DesktopApp>,
}

impl AppIdentityIndex {
    /// Build an index from already-parsed entries. Used by tests, and by
    /// [`Self::load`] after scanning.
    pub fn from_entries(entries: Vec<DesktopApp>) -> Self {
        let mut idx = Self::default();
        for app in entries {
            idx.insert(app);
        }
        idx
    }

    /// Add one entry. Earlier insertions win, so callers must feed directories
    /// in descending precedence order (user entries before system ones).
    pub fn insert(&mut self, app: DesktopApp) {
        if let Some(wm) = app.wm_class.as_deref() {
            let key = normalize_identity(wm);
            if !key.is_empty() {
                self.by_wm_class.entry(key).or_insert_with(|| app.clone());
            }
        }
        let id = normalize_identity(&app.desktop_id);
        if !id.is_empty() {
            self.by_desktop_id.entry(id).or_insert(app);
        }
    }

    /// Resolve a window's identity from the class and app-id KWin reported.
    ///
    /// Order matters: `StartupWMClass` is the app's own declaration of the class
    /// it reports, so it is the strongest signal. Desktop-entry ids are exact
    /// too, and cover apps that never set `StartupWMClass`.
    pub fn resolve(&self, cls: &str, app: &str) -> Option<&DesktopApp> {
        for candidate in [cls, app] {
            for key in identity_keys(candidate) {
                if let Some(found) = self.by_wm_class.get(&key) {
                    return Some(found);
                }
            }
        }
        for candidate in [app, cls] {
            for key in identity_keys(candidate) {
                if let Some(found) = self.by_desktop_id.get(&key) {
                    return Some(found);
                }
            }
        }
        None
    }

    pub fn len(&self) -> usize {
        self.by_desktop_id.len()
    }

    /// Every indexed application, one per desktop id.
    pub fn entries(&self) -> Vec<&DesktopApp> {
        self.by_desktop_id.values().collect()
    }

    pub fn is_empty(&self) -> bool {
        self.by_desktop_id.is_empty()
    }

    /// Directories searched for `*.desktop` files, highest precedence first.
    pub fn search_dirs() -> Vec<PathBuf> {
        let mut dirs: Vec<PathBuf> = Vec::new();
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/user".into());

        let data_home = std::env::var("XDG_DATA_HOME")
            .unwrap_or_else(|_| format!("{}/.local/share", home));
        dirs.push(PathBuf::from(&data_home).join("applications"));

        // Flatpak per-user exports.
        dirs.push(PathBuf::from(&data_home).join("flatpak/exports/share/applications"));

        let data_dirs = std::env::var("XDG_DATA_DIRS")
            .unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
        for d in data_dirs.split(':').filter(|d| !d.is_empty()) {
            dirs.push(PathBuf::from(d).join("applications"));
        }

        // Flatpak and Snap system exports.
        dirs.push(PathBuf::from("/var/lib/flatpak/exports/share/applications"));
        dirs.push(PathBuf::from("/var/lib/snapd/desktop/applications"));

        dirs
    }

    /// Scan the XDG application directories. Best-effort: unreadable files and
    /// directories are skipped rather than failing, because a shell must still
    /// start on a partially broken system.
    pub fn load() -> Self {
        Self::load_from(&Self::search_dirs())
    }

    /// Build an index from explicit directories, scanning each recursively.
    ///
    /// Recursion is not optional: Wine installs its entries several levels deep
    /// (`applications/wine/Programs/<app>/<name>.desktop`), and Plasma's own
    /// indexer walks the same tree. Hidden directories are ignored; symlinks
    /// are followed, bounded by [`MAX_SCAN_DEPTH`].
    pub fn load_from(dirs: &[PathBuf]) -> Self {
        let mut entries = Vec::new();
        for dir in dirs {
            scan_dir(dir, 0, &mut entries);
        }
        Self::from_entries(entries)
    }
}

/// Depth cap for the recursive scan. Wine nests entries three levels below
/// `applications/`; anything deeper is not part of the specification, and the
/// cap keeps a symlink cycle from becoming an infinite walk.
const MAX_SCAN_DEPTH: usize = 6;

fn scan_dir(dir: &Path, depth: usize, out: &mut Vec<DesktopApp>) {
    if depth > MAX_SCAN_DEPTH {
        return;
    }
    let Ok(read) = fs::read_dir(dir) else {
        return;
    };
    for item in read.flatten() {
        let path = item.path();
        let name = item.file_name();
        if name.to_string_lossy().starts_with('.') {
            continue;
        }
        if path.is_dir() {
            scan_dir(&path, depth + 1, out);
            continue;
        }
        if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
            continue;
        }
        let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };
        let Ok(content) = fs::read_to_string(&path) else {
            continue;
        };
        if let Some(app) = parse_desktop_entry(&content, stem) {
            out.push(app);
        }
    }
}

static SHARED_INDEX: OnceLock<RwLock<Arc<AppIdentityIndex>>> = OnceLock::new();

fn shared_slot() -> &'static RwLock<Arc<AppIdentityIndex>> {
    SHARED_INDEX.get_or_init(|| RwLock::new(Arc::new(AppIdentityIndex::load())))
}

/// The process-wide index. Cheap to call: clones an `Arc`.
pub fn shared_index() -> Arc<AppIdentityIndex> {
    shared_slot()
        .read()
        .map(|g| Arc::clone(&g))
        .unwrap_or_else(|e| Arc::clone(&e.into_inner()))
}

/// Re-scan the XDG directories, for when the user installs an application while
/// the shell is running.
pub fn refresh_shared_index() -> Arc<AppIdentityIndex> {
    let fresh = Arc::new(AppIdentityIndex::load());
    if let Ok(mut g) = shared_slot().write() {
        *g = Arc::clone(&fresh);
    }
    fresh
}
