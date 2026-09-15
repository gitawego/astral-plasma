use include_dir::{include_dir, Dir};
use std::fs;
use std::path::{Path, PathBuf};
use crate::domain::ports::DynResult;

pub static SHELL_QML: &str = include_str!("../../../shell.qml");
pub static DOCK_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../dock");
pub static COMPONENTS_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../components");
pub static THEME_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../theme");
pub static CONFIG_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../config");
pub static DASHBOARD_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../dashboard");
pub static NOTIFICATIONS_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../notifications");
pub static SERVICES_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../services");
pub static SETTINGS_GUI_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../settings_gui");
pub static SHELL_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../shell");
pub static SHORTCUTS_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../shortcuts");
pub static TOPBAR_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../topbar");

pub fn get_default_package_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("CAELESTIA_PACKAGE_DIR") {
        if !dir.trim().is_empty() {
            return PathBuf::from(dir);
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".local").join("share").join("caelestia").join("package")
}

pub fn extract_embedded_theme(target_dir: &Path) -> DynResult<()> {
    fs::create_dir_all(target_dir)?;
    fs::write(target_dir.join("shell.qml"), SHELL_QML)?;

    let dirs = [
        ("dock", &DOCK_DIR),
        ("components", &COMPONENTS_DIR),
        ("theme", &THEME_DIR),
        ("config", &CONFIG_DIR),
        ("dashboard", &DASHBOARD_DIR),
        ("notifications", &NOTIFICATIONS_DIR),
        ("services", &SERVICES_DIR),
        ("settings_gui", &SETTINGS_GUI_DIR),
        ("shell", &SHELL_DIR),
        ("shortcuts", &SHORTCUTS_DIR),
        ("topbar", &TOPBAR_DIR),
    ];

    for (name, d) in dirs {
        let dest = target_dir.join(name);
        fs::create_dir_all(&dest)?;
        d.extract(&dest)?;
    }

    Ok(())
}
