//! Desktop identity + window geometry for the DSH web app window.
//!
//! Two browser behaviours on native Wayland need correcting:
//!
//! * Chrome/Chromium/Edge app windows set their Wayland `app_id` to
//!   `<browser>-<host>__-<profile>` (e.g. `msedge-127.0.0.1__-Default`) and
//!   ignore `--class`, so a desktop entry with `StartupWMClass=astral-dsh-web`
//!   never matches and the window shows the browser's icon. We therefore also
//!   install an entry named exactly the app_id, carrying DeepSeek's mark.
//! * When the browser is already running, the new app window restores its saved
//!   bounds and ignores `--window-size`. A KWin rule forces a landscape size for
//!   those app_ids; KWin then centres the window.
//!
//! Both are announced with a desktop notification and are removable from
//! Settings or with `astral-plasma dsh-web desktop remove`.

use crate::domain::branding;
use crate::infrastructure::kwin_shortcuts::KdeIniFile;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// WM_CLASS / X11 app class, used when the browser runs under XWayland.
pub const APP_CLASS: &str = "astral-dsh-web";
/// Base name of the installed icon. The `-symbolic` suffix is the freedesktop
/// convention for a monochrome template: KWin's titlebar and the shell's
/// ThemedIcon both recolour it to the current theme, so the mark never keeps a
/// hard-coded brand colour.
pub const ICON_NAME: &str = "astral-dsh-web-symbolic";
/// Earlier releases installed the icon without the symbolic suffix; remove it.
pub const LEGACY_ICON_NAME: &str = "astral-dsh-web";
pub const DESKTOP_FILE: &str = "astral-dsh-web.desktop";
/// Description prefix for the KWin size rules this module owns.
pub const KWIN_RULE_PREFIX: &str = "Astral Plasma: DSH web app window";
/// KWin rule disposition for the size: 3 = "Remember" (apply the default, then
/// keep the user's resize/maximise). 2 = "Force" would pin it, which is what
/// made the window impossible to resize.
pub const SIZE_RULE: &str = "3";

/// DeepSeek's mark, embedded so the entry installs without the checkout.
pub const DEEPSEEK_SVG: &str = include_str!("../../../theme/assets/icons/deepseek.svg");

pub fn icon_path() -> PathBuf {
    branding::data_home()
        .join("icons/hicolor/scalable/apps")
        .join(format!("{ICON_NAME}.svg"))
}

pub fn desktop_path() -> PathBuf {
    branding::applications_dir().join(DESKTOP_FILE)
}

pub fn kwinrules_path() -> PathBuf {
    branding::config_home().join("kwinrulesrc")
}

/// Chrome/Chromium/Edge derive the Wayland app_id as `<browser>-<host>__-<profile>`.
pub fn wayland_app_ids(host: &str) -> Vec<String> {
    let infix = format!("{}__", host);
    vec![
        format!("chrome-{infix}-Default"),
        format!("chrome-{infix}-default"),
        format!("chromium-{infix}-Default"),
        format!("chromium-{infix}-default"),
        format!("msedge-{infix}-Default"),
        format!("msedge-{infix}-default"),
    ]
}

fn icon_display() -> String {
    icon_path().display().to_string()
}

/// The desktop entry matched through `StartupWMClass` (X11/XWayland `--class`).
pub fn desktop_entry_content() -> String {
    format!(
        "[Desktop Entry]\n\
         Version=1.0\n\
         Type=Application\n\
         NoDisplay=true\n\
         Name=DeepSeek Harness\n\
         Comment=DeepSeek Harness Web UI\n\
         Exec=xdg-open %u\n\
         Icon={}\n\
         StartupWMClass={}\n\
         StartupNotify=false\n\
         Categories=Utility;Development;\n",
        icon_display(),
        APP_CLASS
    )
}

/// A desktop entry named exactly the Wayland app id, so KDE associates the
/// window with DeepSeek's mark despite Chromium ignoring `--class`.
pub fn wayland_entry_content(app_id: &str) -> String {
    format!(
        "[Desktop Entry]\n\
         Version=1.0\n\
         Type=Application\n\
         NoDisplay=true\n\
         Name=DeepSeek Harness\n\
         Comment=DeepSeek Harness Web UI\n\
         Exec=xdg-open %u\n\
         Icon={}\n\
         StartupWMClass={app_id}\n\
         StartupNotify=false\n\
         Categories=Utility;Development;\n",
        icon_display()
    )
}

/// Whether the icon and the primary desktop entry are present.
pub fn is_installed() -> bool {
    icon_path().is_file() && desktop_path().is_file()
}

/// Install (or refresh) the icon, the desktop entries and the KWin size rules.
///
/// Returns true when something changed, so the caller can tell the user once.
pub fn ensure(host: &str, width: u32, height: u32) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    let icon = icon_path();
    if let Some(parent) = icon.parent() {
        fs::create_dir_all(parent)?;
    }
    let icon_changed = fs::read_to_string(&icon).map(|t| t != DEEPSEEK_SVG).unwrap_or(true);
    let mut changed = icon_changed;
    if icon_changed {
        fs::write(&icon, DEEPSEEK_SVG)?;
    }

    // Drop the icon a previous release installed under the non-symbolic name.
    let legacy = icon_path().with_file_name(format!("{LEGACY_ICON_NAME}.svg"));
    if legacy.is_file() {
        let _ = fs::remove_file(&legacy);
        changed = true;
    }

    changed |= write_if_changed(&desktop_path(), &desktop_entry_content())?;
    for app_id in wayland_app_ids(host) {
        let path = branding::applications_dir().join(format!("{app_id}.desktop"));
        changed |= write_if_changed(&path, &wayland_entry_content(&app_id))?;
    }

    changed |= apply_kwin_size_rules(host, width, height)?;

    if changed {
        refresh_caches();
        notify(
            "DeepSeek app icon enabled",
            "Astral Plasma registered a DeepSeek icon and a landscape window size for the DSH web app. Remove them in Settings > AI.",
            Some(&icon),
        );
    }
    Ok(changed)
}

/// Remove the icon, the desktop entries and the KWin size rules.
pub fn remove() -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    let mut changed = false;
    let legacy = icon_path().with_file_name(format!("{LEGACY_ICON_NAME}.svg"));
    for path in [icon_path(), legacy, desktop_path()] {
        if path.is_file() {
            fs::remove_file(&path)?;
            changed = true;
        }
    }
    if let Ok(entries) = fs::read_dir(branding::applications_dir()) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("chrome-") || name.starts_with("chromium-") || name.starts_with("msedge-") {
                if name.ends_with("-Default.desktop") {
                    let _ = fs::remove_file(entry.path());
                    changed = true;
                }
            }
        }
    }
    changed |= remove_kwin_size_rules()?;

    if changed {
        refresh_caches();
        notify(
            "DeepSeek app icon disabled",
            "Astral Plasma removed the DSH web app desktop entries and window rule; the window uses the browser's icon again.",
            None,
        );
    }
    Ok(changed)
}

fn write_if_changed(path: &Path, content: &str) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    if fs::read_to_string(path).map(|t| t == content).unwrap_or(false) {
        return Ok(false);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, content)?;
    Ok(true)
}

/// Pure rendering of the DSH size rules into `existing` `kwinrulesrc` text.
fn render_size_rules(existing: &str, host: &str, width: u32, height: u32) -> String {
    let mut ini = KdeIniFile::parse(existing);

    // Drop any rules we previously wrote (the description carries the prefix).
    let stale: Vec<String> = ini.groups.iter()
        .filter(|(group, keys)| is_numeric_group(group)
            && keys.get("Description").map(|d| d.starts_with(KWIN_RULE_PREFIX)).unwrap_or(false))
        .map(|(group, _)| group.clone())
        .collect();
    for group in stale {
        ini.groups.remove(&group);
    }

    for app_id in wayland_app_ids(host) {
        let id: u64 = ini.groups.keys().filter_map(|g| g.parse::<u64>().ok()).max().unwrap_or(0) + 1;
        let group = id.to_string();
        ini.set(&group, "Description", &format!("{KWIN_RULE_PREFIX} ({app_id})"));
        ini.set(&group, "wmclass", &app_id);
        ini.set(&group, "wmclassmatch", "1");
        ini.set(&group, "wmclasscomplete", "false");
        ini.set(&group, "size", &format!("{width},{height}"));
        ini.set(&group, "sizerule", SIZE_RULE);
    }

    let mut ids: Vec<u64> = ini.groups.keys().filter_map(|g| g.parse::<u64>().ok()).collect();
    ids.sort_unstable();
    let ids: Vec<String> = ids.into_iter().map(|i| i.to_string()).collect();
    ini.set("General", "count", &ids.len().to_string());
    ini.set("General", "rules", &ids.join(","));

    ini.serialize()
}

fn apply_kwin_size_rules(host: &str, width: u32, height: u32) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    let path = kwinrules_path();
    let existing = fs::read_to_string(&path).unwrap_or_default();
    let rendered = render_size_rules(&existing, host, width, height);
    if rendered == existing {
        return Ok(false);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, rendered)?;
    reconfigure_kwin();
    Ok(true)
}

fn remove_kwin_size_rules() -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    let path = kwinrules_path();
    let Ok(existing) = fs::read_to_string(&path) else {
        return Ok(false);
    };
    let mut ini = KdeIniFile::parse(&existing);
    let stale: Vec<String> = ini.groups.iter()
        .filter(|(group, keys)| is_numeric_group(group)
            && keys.get("Description").map(|d| d.starts_with(KWIN_RULE_PREFIX)).unwrap_or(false))
        .map(|(group, _)| group.clone())
        .collect();
    if stale.is_empty() {
        return Ok(false);
    }
    for group in stale {
        ini.groups.remove(&group);
    }
    let mut ids: Vec<u64> = ini.groups.keys().filter_map(|g| g.parse::<u64>().ok()).collect();
    ids.sort_unstable();
    let ids: Vec<String> = ids.into_iter().map(|i| i.to_string()).collect();
    ini.set("General", "count", &ids.len().to_string());
    ini.set("General", "rules", &ids.join(","));
    fs::write(&path, ini.serialize())?;
    reconfigure_kwin();
    Ok(true)
}

fn is_numeric_group(group: &str) -> bool {
    !group.is_empty() && group.bytes().all(|b| b.is_ascii_digit())
}

fn reconfigure_kwin() {
    let _ = Command::new("qdbus6")
        .args(["org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn refresh_caches() {
    let _ = Command::new("kbuildsycoca6")
        .arg("--noincremental")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = Command::new("update-desktop-database")
        .arg(branding::applications_dir())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// Tell the user what changed. Skipped during tests and in test mode.
fn notify(summary: &str, body: &str, icon: Option<&Path>) {
    if cfg!(test) || branding::test_mode() {
        return;
    }
    let mut cmd = Command::new("notify-send");
    cmd.args(["-a", "Astral Plasma"]);
    match icon {
        Some(path) => cmd.arg("-i").arg(path),
        None => cmd.arg("-i").arg("dialog-information"),
    };
    cmd.arg(summary)
        .arg(body)
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let _ = cmd.spawn();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_ids_follow_the_wayland_scheme() {
        let ids = wayland_app_ids("127.0.0.1");
        assert!(ids.contains(&"chrome-127.0.0.1__-Default".to_string()));
        assert!(ids.contains(&"chrome-127.0.0.1__-default".to_string()));
        assert!(ids.contains(&"chromium-127.0.0.1__-Default".to_string()));
        assert!(ids.contains(&"chromium-127.0.0.1__-default".to_string()));
        assert!(ids.contains(&"msedge-127.0.0.1__-Default".to_string()));
        assert!(ids.contains(&"msedge-127.0.0.1__-default".to_string()));
    }

    #[test]
    fn wayland_entry_binds_the_app_id_to_the_deepseek_icon() {
        let content = wayland_entry_content("msedge-127.0.0.1__-Default");
        assert!(content.contains("StartupWMClass=msedge-127.0.0.1__-Default"));
        assert!(content.contains(&format!("Icon={}", icon_path().display())));
    }

    #[test]
    fn size_rule_is_remembered_not_forced() {
        // "Force" pins the window size and makes it impossible to resize or
        // maximise, which is the bug this guard prevents.
        let rendered = render_size_rules("", "127.0.0.1", 1536, 968);
        assert!(rendered.contains("size=1536,968"));
        assert!(rendered.contains(&format!("sizerule={SIZE_RULE}")));
        assert!(rendered.contains("wmclasscomplete=false"));
        assert_eq!(SIZE_RULE, "3", "Remember: apply the default, keep user resizes");
        assert!(!rendered.contains("sizerule=2"));
    }

    #[test]
    fn xwayland_entry_keeps_the_app_class() {
        let content = desktop_entry_content();
        assert!(content.contains("StartupWMClass=astral-dsh-web"));
    }

    #[test]
    fn embedded_svg_is_the_deepseek_mark() {
        assert!(DEEPSEEK_SVG.contains("<svg"));
        assert!(DEEPSEEK_SVG.contains("DeepSeek"));
    }
}
