use crate::domain::branding;
use crate::domain::ports::{DynResult, ShortcutControlPort};
use crate::domain::shortcuts::{AstralShortcutSessionBackup, DisplacedShortcut, GranularShortcutSnapshot};
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub const BACKUP_FILENAME: &str = "shortcuts_backup.json";

pub struct KWinShortcutsAdapter;

impl KWinShortcutsAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn resolve_backup_dir(&self) -> PathBuf {
        if let Some(dir) = branding::dir_override(branding::ENV_SHORTCUTS_BACKUP_DIR) {
            return dir;
        }
        branding::data_dir().join(branding::SHORTCUTS_BACKUP_SUBDIR)
    }

    pub fn resolve_config_dir(&self) -> PathBuf {
        branding::config_home()
    }

    pub fn backup_file_path(&self) -> PathBuf {
        self.resolve_backup_dir().join(BACKUP_FILENAME)
    }
}

impl Default for KWinShortcutsAdapter {
    fn default() -> Self {
        Self::new()
    }
}

/// Lightweight parser for KDE INI files preserving existing groups and other keys
#[derive(Debug, Clone, Default)]
pub struct KdeIniFile {
    pub groups: BTreeMap<String, BTreeMap<String, String>>,
}

impl KdeIniFile {
    pub fn parse(content: &str) -> Self {
        let mut groups: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
        let mut current_group = String::new();

        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with('[') && trimmed.ends_with(']') {
                current_group = trimmed[1..trimmed.len() - 1].trim().to_string();
                groups.entry(current_group.clone()).or_default();
            } else if let Some(idx) = line.find('=') {
                if !current_group.is_empty() {
                    let key = line[..idx].trim().to_string();
                    let val = line[idx + 1..].trim().to_string();
                    groups.entry(current_group.clone()).or_default().insert(key, val);
                }
            }
        }

        Self { groups }
    }

    pub fn get(&self, group: &str, key: &str) -> Option<String> {
        self.groups.get(group)?.get(key).cloned()
    }

    pub fn set(&mut self, group: &str, key: &str, value: &str) {
        self.groups
            .entry(group.to_string())
            .or_default()
            .insert(key.to_string(), value.to_string());
    }

    pub fn remove(&mut self, group: &str, key: &str) -> Option<String> {
        if let Some(grp) = self.groups.get_mut(group) {
            let removed = grp.remove(key);
            if grp.is_empty() {
                self.groups.remove(group);
            }
            return removed;
        }
        None
    }

    pub fn serialize(&self) -> String {
        let mut out = String::new();
        for (group, keys) in &self.groups {
            out.push_str(&format!("[{}]\n", group));
            for (k, v) in keys {
                out.push_str(&format!("{}={}\n", k, v));
            }
            out.push('\n');
        }
        out
    }
}

impl ShortcutControlPort for KWinShortcutsAdapter {
    fn snapshot_relevant_shortcuts(&self, target_shortcut: &str) -> DynResult<AstralShortcutSessionBackup> {
        let backup_dir = self.resolve_backup_dir();
        fs::create_dir_all(&backup_dir)?;

        let backup_path = self.backup_file_path();
        if backup_path.exists() {
            // Already backed up; do not overwrite pristine state
            let content = fs::read_to_string(&backup_path)?;
            if let Ok(existing) = serde_json::from_str::<AstralShortcutSessionBackup>(&content) {
                return Ok(existing);
            }
        }

        let config_dir = self.resolve_config_dir();
        let kglobal_path = config_dir.join("kglobalshortcutsrc");
        let kwinrc_path = config_dir.join("kwinrc");

        let kglobal_content = if kglobal_path.exists() {
            fs::read_to_string(&kglobal_path).unwrap_or_default()
        } else {
            String::new()
        };

        let ini = KdeIniFile::parse(&kglobal_content);

        // Keys touched by Astral
        let mut affected = Vec::new();
        let monitored_keys = [
            ("kwin", branding::SHORTCUT_LAUNCHER_KEY),
            ("kwin", branding::SHORTCUT_WALLPAPER_KEY),
            ("services", "astral-launcher.desktop"),
            ("services", "astral-wallpaper.desktop"),
            ("plasmashell", "activate application launcher"),
        ];

        for (group, key) in monitored_keys {
            let prev = ini.get(group, key);
            affected.push(GranularShortcutSnapshot {
                group: group.to_string(),
                key: key.to_string(),
                previous_value: prev,
            });
        }

        // Scan if target_shortcut (e.g. Meta+Space) was previously claimed by another action
        let mut displaced: Option<DisplacedShortcut> = None;
        let target_lower = target_shortcut.to_lowercase();

        for (grp_name, keys) in &ini.groups {
            if grp_name == "kwin" || grp_name == "services" {
                // Skip Astral's own targets
                continue;
            }
            for (k, v) in keys {
                let first_part = v.split(',').next().unwrap_or("").trim().to_lowercase();
                if first_part == target_lower {
                    displaced = Some(DisplacedShortcut {
                        group: grp_name.clone(),
                        key: k.clone(),
                        full_value: v.clone(),
                    });
                    break;
                }
            }
            if displaced.is_some() {
                break;
            }
        }

        // Check kwinrc plugin state
        let kwinrc_content = if kwinrc_path.exists() {
            fs::read_to_string(&kwinrc_path).unwrap_or_default()
        } else {
            String::new()
        };
        let kwinrc_ini = KdeIniFile::parse(&kwinrc_content);
        let plugin_enabled = kwinrc_ini
            .get("Plugins", branding::KWIN_SHORTCUTS_ENABLED_KEY)
            .map(|v| v.to_lowercase() == "true")
            .unwrap_or(false);

        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let backup = AstralShortcutSessionBackup {
            timestamp,
            affected_entries: affected,
            previous_kwin_plugin_enabled: plugin_enabled,
            displaced_action: displaced,
        };

        fs::write(&backup_path, serde_json::to_string_pretty(&backup)?)?;
        Ok(backup)
    }

    fn restore_relevant_shortcuts(&self) -> DynResult<bool> {
        let backup_path = self.backup_file_path();
        if !backup_path.exists() {
            return Ok(false);
        }

        let content = fs::read_to_string(&backup_path)?;
        let backup: AstralShortcutSessionBackup = serde_json::from_str(&content)?;

        let config_dir = self.resolve_config_dir();
        let kglobal_path = config_dir.join("kglobalshortcutsrc");
        let kwinrc_path = config_dir.join("kwinrc");

        // 1. Revert ONLY affected keys in kglobalshortcutsrc
        if kglobal_path.exists() {
            let kglobal_content = fs::read_to_string(&kglobal_path).unwrap_or_default();
            let mut ini = KdeIniFile::parse(&kglobal_content);

            for entry in &backup.affected_entries {
                match &entry.previous_value {
                    Some(val) => {
                        ini.set(&entry.group, &entry.key, val);
                    }
                    None => {
                        ini.remove(&entry.group, &entry.key);
                    }
                }
            }

            // Restore displaced key if any
            if let Some(ref displaced) = backup.displaced_action {
                ini.set(&displaced.group, &displaced.key, &displaced.full_value);
            }

            fs::write(&kglobal_path, ini.serialize())?;
        }

        // 2. Revert kwinrc plugin state
        if kwinrc_path.exists() {
            let kwinrc_content = fs::read_to_string(&kwinrc_path).unwrap_or_default();
            let mut ini = KdeIniFile::parse(&kwinrc_content);
            if backup.previous_kwin_plugin_enabled {
                ini.set("Plugins", branding::KWIN_SHORTCUTS_ENABLED_KEY, "true");
            } else {
                ini.remove("Plugins", branding::KWIN_SHORTCUTS_ENABLED_KEY);
            }
            fs::write(&kwinrc_path, ini.serialize())?;
        }

        // 3. Live Compositor and DBus Cleanup (skipped in test mode)
        if !branding::test_mode() {
            let _ = Command::new("qdbus6")
                .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", branding::KWIN_SCRIPT_SHORTCUTS])
                .status();

            let _ = Command::new("qdbus6")
                .args(["org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"])
                .status();

            // Clear in-memory shortcuts over dbus python script
            let clear_py = format!(r#"
import dbus
try:
    bus = dbus.SessionBus()
    accel = dbus.Interface(bus.get_object('org.kde.kglobalaccel', '/kglobalaccel'), 'org.kde.KGlobalAccel')
    accel.setForeignShortcut(['kwin', '{launcher}', 'default', '{launcher_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['kwin', '{wallpaper}', 'default', '{wallpaper_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-launcher.desktop', '_launch', 'default', '{launcher_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-wallpaper.desktop', '_launch', 'default', '{wallpaper_label}'], [dbus.Int32(0)])
except Exception:
    pass
"#,
                launcher = branding::SHORTCUT_LAUNCHER_KEY,
                launcher_label = branding::SHORTCUT_LAUNCHER_LABEL,
                wallpaper = branding::SHORTCUT_WALLPAPER_KEY,
                wallpaper_label = branding::SHORTCUT_WALLPAPER_LABEL,
            );
            let _ = Command::new("python3").args(["-c", &clear_py]).status();
        }

        let _ = fs::remove_file(&backup_path);
        Ok(true)
    }

    fn bind_shortcuts(&self, mode: &str) -> DynResult<()> {
        if branding::test_mode() {
            // Test mode simulation: set the launcher shortcut in the mock config
            let config_dir = self.resolve_config_dir();
            let kglobal_path = config_dir.join("kglobalshortcutsrc");
            let kglobal_content = if kglobal_path.exists() {
                fs::read_to_string(&kglobal_path).unwrap_or_default()
            } else {
                String::new()
            };
            let mut ini = KdeIniFile::parse(&kglobal_content);
            ini.set(
                "kwin",
                branding::SHORTCUT_LAUNCHER_KEY,
                &format!("Meta+Space,none,{}", branding::SHORTCUT_LAUNCHER_LABEL),
            );
            ini.set(
                "kwin",
                branding::SHORTCUT_WALLPAPER_KEY,
                &format!("Meta+Shift+W,none,{}", branding::SHORTCUT_WALLPAPER_LABEL),
            );
            fs::write(&kglobal_path, ini.serialize())?;
            return Ok(());
        }

        // The binder ships with the repository, so resolve it relative to the
        // running executable (bin/astral-plasma -> <root>/scripts) and fall
        // back to the current directory for a bare `cargo run` session. A path
        // baked into $HOME would silently rot after the first move.
        let script = branding::repo_root_from_exe()
            .map(|root| root.join("scripts").join("bind_shortcuts.sh"))
            .filter(|path| path.exists())
            .unwrap_or_else(|| PathBuf::from("./scripts/bind_shortcuts.sh"));

        let _ = Command::new("bash")
            .arg(script)
            .arg(mode)
            .status();

        Ok(())
    }

    fn is_backup_active(&self) -> bool {
        self.backup_file_path().exists()
    }
}
