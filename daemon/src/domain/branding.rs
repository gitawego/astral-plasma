//! Canonical product identity: one place that names the shell.
//!
//! Every user-visible identifier the shell owns - XDG directories, systemd
//! units, D-Bus names, KWin script names, KDE shortcut keys, environment
//! variables, temporary files - is defined here exactly once. Code must never
//! inline one of these strings: a rename then becomes a one-file change
//! instead of a repo-wide find-and-replace that silently misses a cache path.

use std::env;
use std::path::PathBuf;

/// Reverse-DNS / desktop application id.
pub const APP_ID: &str = "astral-plasma";
/// Human-readable product name.
pub const APP_NAME: &str = "Astral Plasma";
/// D-Bus namespace root.
pub const DBUS_PREFIX: &str = "org.astralplasma";
/// Window class reported by the shell's own surfaces.
pub const WINDOW_CLASS: &str = "astral-plasma";
/// Window class reported by the settings surface.
pub const WINDOW_CLASS_SETTINGS: &str = "astral-plasma-settings";

// --- XDG directories ---------------------------------------------------------

/// Directory name under `XDG_DATA_HOME` (`~/.local/share/astral-plasma`).
pub const DATA_DIR: &str = "astral-plasma";
/// Directory name under `XDG_CACHE_HOME` (`~/.cache/astral-plasma`).
pub const CACHE_DIR: &str = "astral-plasma";
/// Directory name under `XDG_STATE_HOME` (`~/.local/state/astral-plasma`).
pub const STATE_DIR: &str = "astral-plasma";
/// Subdirectory holding the extracted QML package.
pub const PACKAGE_SUBDIR: &str = "package";
/// Subdirectory holding the KDE Plasma panel backup.
pub const PLASMA_BACKUP_SUBDIR: &str = "plasma-backup";
/// Subdirectory holding the KDE global-shortcut backup.
pub const SHORTCUTS_BACKUP_SUBDIR: &str = "shortcuts-backup";

// --- systemd -----------------------------------------------------------------

/// User unit file name.
pub const SYSTEMD_UNIT: &str = "astral-plasma.service";
/// `Description=` line of the generated unit.
pub const SYSTEMD_DESCRIPTION: &str = "Astral Plasma Desktop Shell for KDE Plasma";

// --- D-Bus -------------------------------------------------------------------

/// Object path of the window watcher.
pub const DBUS_WATCHER_PATH: &str = "/Watcher";
/// Bus name of the window watcher.
pub const DBUS_WATCHER_NAME: &str = "org.astralplasma.WindowWatcher";

// --- KWin scripts ------------------------------------------------------------

/// KWin script package that owns the launcher/wallpaper global shortcuts.
pub const KWIN_SCRIPT_SHORTCUTS: &str = "astral-plasma-shortcuts";
/// `kwinrc` key toggling the shortcut script.
pub const KWIN_SHORTCUTS_ENABLED_KEY: &str = "astral-plasma-shortcutsEnabled";
/// KWin script that streams window/workspace events to the daemon.
pub const KWIN_SCRIPT_WATCHER: &str = "astral-plasma-watcher";

// --- KDE global shortcuts (visible in Plasma System Settings) ----------------

/// KWin global shortcut key for the command launcher.
pub const SHORTCUT_LAUNCHER_KEY: &str = "AstralLauncher";
/// KWin global shortcut key for the wallpaper picker.
pub const SHORTCUT_WALLPAPER_KEY: &str = "AstralWallpaper";
/// Display label of the launcher shortcut.
pub const SHORTCUT_LAUNCHER_LABEL: &str = "Astral Plasma Launcher";
/// Display label of the wallpaper picker shortcut.
pub const SHORTCUT_WALLPAPER_LABEL: &str = "Astral Plasma Wallpaper Picker";
/// KWin global shortcut key for the active-apps overview (bare Meta).
pub const SHORTCUT_OVERVIEW_KEY: &str = "AstralOverview";
/// Display label of the active-apps overview shortcut.
pub const SHORTCUT_OVERVIEW_LABEL: &str = "Astral Plasma: Active Apps Overview";

// --- Wayland -----------------------------------------------------------------

/// `WlrLayershell` namespace for the wallpaper layer.
pub const LAYER_NAMESPACE_WALLPAPER: &str = "astral-plasma-wallpaper";

// --- Environment variables ---------------------------------------------------

/// `1` disables every external side effect (systemctl, qdbus, plasma...).
pub const ENV_TEST_MODE: &str = "ASTRAL_PLASMA_TEST_MODE";
/// Overrides the extracted QML package directory.
pub const ENV_PACKAGE_DIR: &str = "ASTRAL_PLASMA_PACKAGE_DIR";
/// Overrides the theme (repo) directory used by the systemd unit.
pub const ENV_THEME_DIR: &str = "ASTRAL_PLASMA_THEME_DIR";
/// Overrides the systemd user unit directory.
pub const ENV_SYSTEMD_DIR: &str = "ASTRAL_PLASMA_SYSTEMD_DIR";
/// Overrides the Plasma panel backup directory.
pub const ENV_PLASMA_BACKUP_DIR: &str = "ASTRAL_PLASMA_BACKUP_DIR";
/// Overrides the shortcut backup directory.
pub const ENV_SHORTCUTS_BACKUP_DIR: &str = "ASTRAL_PLASMA_SHORTCUTS_BACKUP_DIR";
/// Launcher open-on-start flag read by the QML side.
pub const ENV_LAUNCHER_OPEN: &str = "ASTRAL_PLASMA_LAUNCHER_OPEN";
/// Launcher mode (`apps` / `wallpaper`) read by the QML side.
pub const ENV_LAUNCHER_MODE: &str = "ASTRAL_PLASMA_LAUNCHER_MODE";
/// Dashboard open-on-start flag read by the QML side.
pub const ENV_DASHBOARD_OPEN: &str = "ASTRAL_PLASMA_DASHBOARD_OPEN";
/// Settings open-on-start flag read by the QML side.
pub const ENV_SETTINGS_OPEN: &str = "ASTRAL_PLASMA_SETTINGS_OPEN";
/// Settings page to focus on start, read by the QML side.
pub const ENV_SETTINGS_PAGE: &str = "ASTRAL_PLASMA_SETTINGS_PAGE";

/// Read a variable, treating whitespace-only values as unset.
pub fn env_value(name: &str) -> Option<String> {
    env::var(name)
        .ok()
        .filter(|value| !value.trim().is_empty())
}

/// `ASTRAL_PLASMA_TEST_MODE=1`.
pub fn test_mode() -> bool {
    env_value(ENV_TEST_MODE).map(|v| v == "1").unwrap_or(false)
}

/// Value of a directory-override variable, when set.
pub fn dir_override(name: &str) -> Option<PathBuf> {
    env_value(name).map(PathBuf::from)
}

/// Resolve `$XDG_<kind>_HOME`, defaulting to the conventional dot-directory.
fn xdg_dir(kind: &str, fallback: &str) -> PathBuf {
    let key = format!("XDG_{}_HOME", kind.to_uppercase());
    if let Some(dir) = env_value(&key) {
        return PathBuf::from(dir);
    }
    home_dir().join(fallback)
}

/// Home directory of the user running the shell.
pub fn home_dir() -> PathBuf {
    env::var("HOME").unwrap_or_else(|_| "/home/user".to_string()).into()
}

/// `~/.local/share` (honours `XDG_DATA_HOME`).
pub fn data_home() -> PathBuf {
    xdg_dir("data", ".local/share")
}

/// `~/.cache` (honours `XDG_CACHE_HOME`).
pub fn cache_home() -> PathBuf {
    xdg_dir("cache", ".cache")
}

/// `~/.local/state` (honours `XDG_STATE_HOME`).
pub fn state_home() -> PathBuf {
    xdg_dir("state", ".local/state")
}

/// `~/.config` (honours `XDG_CONFIG_HOME`).
pub fn config_home() -> PathBuf {
    xdg_dir("config", ".config")
}

/// Current data directory: `$XDG_DATA_HOME/astral-plasma`.
pub fn data_dir() -> PathBuf {
    data_home().join(DATA_DIR)
}

/// Current cache directory: `$XDG_CACHE_HOME/astral-plasma`.
pub fn cache_dir() -> PathBuf {
    cache_home().join(CACHE_DIR)
}

/// Current state directory: `$XDG_STATE_HOME/astral-plasma`.
pub fn state_dir() -> PathBuf {
    state_home().join(STATE_DIR)
}

/// Default directory the embedded QML package is extracted into.
pub fn default_package_dir() -> PathBuf {
    if let Some(dir) = dir_override(ENV_PACKAGE_DIR) {
        return dir;
    }
    data_dir().join(PACKAGE_SUBDIR)
}

/// Directory holding temporary runtime artifacts for this app.
pub fn tmp_dir() -> PathBuf {
    env::temp_dir()
}

/// Prefix of every shell-owned temporary file, e.g. `astral_plasma_kwin_query.js`.
pub const TMP_PREFIX: &str = "astral_plasma_";

/// Path of a shell-owned temporary file, e.g. `astral_plasma_kwin_query.js`.
pub fn tmp_file(name: &str) -> PathBuf {
    tmp_dir().join(format!("{}{}", TMP_PREFIX, name))
}

/// Shared cache for extracted media artwork.
pub fn art_cache_dir() -> PathBuf {
    tmp_dir().join(format!("{}art_cache", TMP_PREFIX))
}

/// Directory of per-user desktop entries.
pub fn applications_dir() -> PathBuf {
    data_home().join("applications")
}

/// Repository root inferred from the running executable.
///
/// Layout is `<root>/bin/astral-plasma`, so the parent of the executable's
/// directory is the checkout that ships `scripts/`. Returns `None` for an
/// installed package or a `cargo run` build, where callers fall back to a
/// relative path - never to a `$HOME` path baked in at build time.
pub fn repo_root_from_exe() -> Option<PathBuf> {
    let exe = env::current_exe().ok()?;
    exe.parent()?.parent().map(std::path::Path::to_path_buf)
}
