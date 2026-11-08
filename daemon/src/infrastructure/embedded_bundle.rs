use crate::domain::branding;
use include_dir::{include_dir, Dir};
use std::fs;
use std::path::{Path, PathBuf};
use crate::domain::ports::DynResult;

pub static SHELL_QML: &str = include_str!("../../../shell.qml");
/// The kernel, AppKit and the bundled apps: one tree, because they are one module
/// namespace (`Astral.Kernel`, `Astral.AppKit`, `Astral.Apps.*`). The package
/// layout therefore mirrors the repository instead of flattening it.
pub static MODULES_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../modules");
pub static DOCK_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../dock");
pub static DASHBOARD_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../dashboard");
pub static NOTIFICATIONS_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../notifications");
pub static SETTINGS_GUI_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../settings_gui");
pub static SHELL_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../shell");
pub static SHORTCUTS_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../shortcuts");
pub static TOPBAR_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../topbar");
pub static OMARCHY_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../omarchy");

pub fn get_default_package_dir() -> PathBuf {
    branding::default_package_dir()
}

pub fn extract_embedded_theme(target_dir: &Path) -> DynResult<()> {
    fs::create_dir_all(target_dir)?;
    fs::write(target_dir.join("shell.qml"), SHELL_QML)?;

    let dirs = [
        ("dock", &DOCK_DIR),
        ("modules", &MODULES_DIR),
        ("dashboard", &DASHBOARD_DIR),
        ("notifications", &NOTIFICATIONS_DIR),
        ("settings_gui", &SETTINGS_GUI_DIR),
        ("shell", &SHELL_DIR),
        ("shortcuts", &SHORTCUTS_DIR),
        ("topbar", &TOPBAR_DIR),
        ("omarchy", &OMARCHY_DIR),
    ];

    for (name, d) in dirs {
        let dest = target_dir.join(name);
        fs::create_dir_all(&dest)?;
        d.extract(&dest)?;
    }

    Ok(())
}
