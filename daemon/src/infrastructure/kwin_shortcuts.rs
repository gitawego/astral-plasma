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

    /// Is the KWin script that owns the shortcut actions loaded right now?
    ///
    /// KWin loads enabled script packages at startup, so this only goes false
    /// after the script was unloaded or KWin restarted without the plugin -
    /// both leave the keys bound to actions that no longer exist.
    pub fn shortcut_script_loaded(&self) -> bool {
        if branding::test_mode() {
            return true;
        }
        Command::new("qdbus6")
            .args([
                "org.kde.KWin",
                "/Scripting",
                "org.kde.kwin.Scripting.isScriptLoaded",
                branding::KWIN_SCRIPT_SHORTCUTS,
            ])
            .output()
            .map(|out| String::from_utf8_lossy(&out.stdout).trim() == "true")
            .unwrap_or(false)
    }

    /// Load the shortcut script package into the running compositor.
    ///
    /// Used by the reconciler when the actions went missing. The normal claim
    /// path loads the script from `scripts/bind_shortcuts.sh` together with the
    /// keys; this is the repair for "script gone, keys still bound".
    pub fn load_shortcut_script(&self) {
        if branding::test_mode() {
            return;
        }
        let installed = branding::data_dir()
            .join("kwin")
            .join("scripts")
            .join(branding::KWIN_SCRIPT_SHORTCUTS)
            .join("contents/code/main.js");
        let script = if installed.exists() {
            Some(installed)
        } else {
            branding::repo_root_from_exe()
                .map(|root| {
                    root.join("kwin")
                        .join(branding::KWIN_SCRIPT_SHORTCUTS)
                        .join("contents/code/main.js")
                })
                .filter(|path| path.exists())
        };
        let Some(script) = script else {
            // The package was never installed: fall back to the full bind, which
            // installs it first.
            let _ = self.bind_shortcuts(crate::domain::desktop_integration::DEFAULT_SHORTCUT_MODE);
            return;
        };

        let _ = Command::new("qdbus6")
            .args([
                "org.kde.KWin",
                "/Scripting",
                "org.kde.kwin.Scripting.unloadScript",
                branding::KWIN_SCRIPT_SHORTCUTS,
            ])
            .output();
        let _ = Command::new("qdbus6")
            .args([
                "org.kde.KWin",
                "/Scripting",
                "org.kde.kwin.Scripting.loadScript",
                &script.to_string_lossy(),
                branding::KWIN_SCRIPT_SHORTCUTS,
            ])
            .output();
        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start"])
            .output();
    }

    /// The mode the session journal recorded, when a session is claimed.
    ///
    /// This is what a restart resumes: the user's choice survives a shell reload
    /// instead of being reset to the default mode.
    pub fn journal_mode(&self) -> Option<String> {
        fs::read_to_string(self.backup_file_path())
            .ok()
            .and_then(|content| serde_json::from_str::<AstralShortcutSessionBackup>(&content).ok())
            .and_then(|backup| backup.mode)
    }

    /// Is the session already claimed in exactly this mode?
    ///
    /// Reads the session journal plus the live KDE configuration - never the
    /// process state - so both the bind path and the reconciler decide from the
    /// same evidence.
    pub fn shortcut_claim_is_current(&self, mode: &str) -> bool {
        let journal_mode = self.journal_mode();
        let config_dir = self.resolve_config_dir();
        let launcher = fs::read_to_string(config_dir.join("kglobalshortcutsrc"))
            .ok()
            .map(|content| KdeIniFile::parse(&content))
            .and_then(|ini| ini.get("kwin", branding::SHORTCUT_LAUNCHER_KEY));
        let plugin_enabled = fs::read_to_string(config_dir.join("kwinrc"))
            .ok()
            .map(|content| KdeIniFile::parse(&content))
            .and_then(|ini| ini.get("Plugins", branding::KWIN_SHORTCUTS_ENABLED_KEY))
            .map(|value| value == "true")
            .unwrap_or(false);
        crate::domain::shortcuts::claim_is_current(
            journal_mode.as_deref(),
            mode,
            launcher.as_deref(),
            plugin_enabled,
        )
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

fn is_astral_action(group: &str, key: &str) -> bool {
    let g = group.to_lowercase();
    let k = key.to_lowercase();
    if g == "services" && k.starts_with("astral-") {
        return true;
    }
    if g == "kwin" && k.starts_with("astral") {
        return true;
    }
    false
}

fn parse_kde_shortcuts(v: &str) -> (String, String) {
    let normalized = v.replace("+,,", "+__COMMA__,").replace("\\,", "__COMMA__");
    let parts: Vec<&str> = normalized.split(',').collect();
    let primary = parts
        .first()
        .unwrap_or(&"")
        .replace("__COMMA__", ",")
        .trim()
        .to_lowercase();
    let alt = parts
        .get(1)
        .unwrap_or(&"")
        .replace("__COMMA__", ",")
        .trim()
        .to_lowercase();
    (primary, alt)
}

impl ShortcutControlPort for KWinShortcutsAdapter {
    fn snapshot_relevant_shortcuts(
        &self,
        target_shortcut: &str,
        mode: &str,
    ) -> DynResult<AstralShortcutSessionBackup> {
        let backup_dir = self.resolve_backup_dir();
        fs::create_dir_all(&backup_dir)?;

        let backup_path = self.backup_file_path();
        let existing: Option<AstralShortcutSessionBackup> = if backup_path.exists() {
            // A session backup already exists: never overwrite recorded
            // originals. Keys managed only after it was written (the
            // bare-Meta overview) are merged in before returning.
            let content = fs::read_to_string(&backup_path)?;
            serde_json::from_str::<AstralShortcutSessionBackup>(&content).ok()
        } else {
            None
        };

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
            ("kwin", branding::SHORTCUT_OVERVIEW_KEY),
            ("kwin", branding::SHORTCUT_ASSISTANT_KEY),
            ("kwin", branding::SHORTCUT_DASHBOARD_KEY),
            ("kwin", branding::SHORTCUT_SETTINGS_KEY),
            ("services", "astral-launcher.desktop"),
            ("services", "astral-wallpaper.desktop"),
            ("services", "astral-assistant.desktop"),
            ("services", "astral-dashboard.desktop"),
            ("services", "astral-settings.desktop"),
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

        // Scan if any target shortcuts were previously claimed by another action
        let mut displaced_actions: Vec<DisplacedShortcut> = Vec::new();
        let target_launcher_clean = match target_shortcut.to_lowercase().as_str() {
            "meta" | "super" => "alt+f1",
            "alt-space" => "alt+space",
            _ => "meta+space",
        };
        let target_keys = [
            target_launcher_clean,
            "meta+shift+w",
            "meta+w",
            "meta+c",
            "meta+d",
            "meta+,",
        ];

        for (grp_name, keys) in &ini.groups {
            for (k, v) in keys {
                if is_astral_action(grp_name, k) {
                    continue;
                }
                let (primary_sc, alt_scs) = parse_kde_shortcuts(v);

                let matches_any = target_keys.iter().any(|&tk| {
                    primary_sc == tk || alt_scs.split('\t').any(|alt| alt.trim() == tk)
                });

                if matches_any {
                    displaced_actions.push(DisplacedShortcut {
                        group: grp_name.clone(),
                        key: k.clone(),
                        full_value: v.clone(),
                    });
                }
            }
        }
        let displaced = displaced_actions.first().cloned();

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

        // Existing backup: merge in only the keys it never recorded (added to
        // `monitored_keys` after the session started), keep every recorded
        // original untouched, and rewrite only when something was appended.
        if let Some(existing) = existing {
            let (mut merged, changed) =
                crate::domain::shortcuts::merge_missing_entries_multi(existing, affected, displaced_actions);
            // A journal written before the mode was recorded still vouches for
            // the session; filling the mode in is what lets a restart resume the
            // user's choice instead of resetting it.
            let mode_filled = merged.mode.is_none();
            if mode_filled {
                merged.mode = Some(mode.to_string());
            }
            if changed || mode_filled {
                fs::write(&backup_path, serde_json::to_string_pretty(&merged)?)?;
            }
            return Ok(merged);
        }

        let backup = AstralShortcutSessionBackup {
            timestamp,
            affected_entries: affected,
            previous_kwin_plugin_enabled: plugin_enabled,
            displaced_action: displaced,
            displaced_actions,
            // The journal records the *mode*, not the key sequence: it is what a
            // restart resumes and what the reconciler re-claims.
            mode: Some(mode.to_string()),
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

            // Restore displaced keys if any
            for displaced in &backup.displaced_actions {
                ini.set(&displaced.group, &displaced.key, &displaced.full_value);
            }
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
    accel.setForeignShortcut(['kwin', '{overview}', 'default', '{overview_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['kwin', '{assistant}', 'default', '{assistant_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['kwin', '{dashboard}', 'default', '{dashboard_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['kwin', '{settings}', 'default', '{settings_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-launcher.desktop', '_launch', 'default', '{launcher_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-wallpaper.desktop', '_launch', 'default', '{wallpaper_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-assistant.desktop', '_launch', 'default', '{assistant_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-dashboard.desktop', '_launch', 'default', '{dashboard_label}'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-settings.desktop', '_launch', 'default', '{settings_label}'], [dbus.Int32(0)])
except Exception:
    pass
"#,
                launcher = branding::SHORTCUT_LAUNCHER_KEY,
                launcher_label = branding::SHORTCUT_LAUNCHER_LABEL,
                wallpaper = branding::SHORTCUT_WALLPAPER_KEY,
                wallpaper_label = branding::SHORTCUT_WALLPAPER_LABEL,
                overview = branding::SHORTCUT_OVERVIEW_KEY,
                overview_label = branding::SHORTCUT_OVERVIEW_LABEL,
                assistant = branding::SHORTCUT_ASSISTANT_KEY,
                assistant_label = branding::SHORTCUT_ASSISTANT_LABEL,
                dashboard = branding::SHORTCUT_DASHBOARD_KEY,
                dashboard_label = branding::SHORTCUT_DASHBOARD_LABEL,
                settings = branding::SHORTCUT_SETTINGS_KEY,
                settings_label = branding::SHORTCUT_SETTINGS_LABEL,
            );
            let _ = Command::new("python3").args(["-c", &clear_py]).status();
        }

        let _ = fs::remove_file(&backup_path);
        Ok(true)
    }

    fn bind_shortcuts(&self, mode: &str) -> DynResult<()> {
        // Claiming twice is a no-op: the journal records the mode and the live
        // KDE configuration proves it. Without this guard every startup would
        // reload KWin's scripting service for nothing - which is exactly what
        // wedged the daemon's D-Bus service during a restart race.
        if !branding::test_mode() && self.shortcut_claim_is_current(mode) {
            return Ok(());
        }

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

            // Clear displaced actions from the backup in the mock config
            if let Ok(content) = fs::read_to_string(self.backup_file_path()) {
                if let Ok(backup) = serde_json::from_str::<AstralShortcutSessionBackup>(&content) {
                    for disp in &backup.displaced_actions {
                        ini.set(&disp.group, &disp.key, "none,none");
                    }
                    if let Some(ref disp) = backup.displaced_action {
                        ini.set(&disp.group, &disp.key, "none,none");
                    }
                }
            }

            ini.set(
                "kwin",
                branding::SHORTCUT_LAUNCHER_KEY,
                &crate::domain::shortcuts::launcher_binding(mode),
            );
            ini.set(
                "kwin",
                branding::SHORTCUT_WALLPAPER_KEY,
                &format!("Meta+Shift+W,none,{}", branding::SHORTCUT_WALLPAPER_LABEL),
            );
            ini.set(
                "kwin",
                branding::SHORTCUT_OVERVIEW_KEY,
                &crate::domain::shortcuts::overview_binding(mode),
            );
            ini.set(
                "kwin",
                branding::SHORTCUT_ASSISTANT_KEY,
                &format!("Meta+C,none,{}", branding::SHORTCUT_ASSISTANT_LABEL),
            );
            ini.set(
                "kwin",
                branding::SHORTCUT_DASHBOARD_KEY,
                &format!("Meta+D,none,{}", branding::SHORTCUT_DASHBOARD_LABEL),
            );
            ini.set(
                "kwin",
                branding::SHORTCUT_SETTINGS_KEY,
                &format!("Meta+,,none,{}", branding::SHORTCUT_SETTINGS_LABEL),
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
