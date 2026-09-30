use serde::{Deserialize, Serialize};

/// Represents a single key-value entry in a KDE config file that was modified.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GranularShortcutSnapshot {
    pub group: String,
    pub key: String,
    /// None if the key was previously absent/unset in the configuration
    pub previous_value: Option<String>,
    /// The key codes KGlobalAccel was holding before the session touched the
    /// action. A config rewrite does not move the live registration, so the
    /// restore replays these (absent in journals written before they were
    /// captured).
    #[serde(default)]
    pub keys: Vec<i32>,
}

/// Represents an external shortcut that originally claimed the key combination (e.g. Meta+Space)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DisplacedShortcut {
    pub group: String,
    pub key: String,
    pub full_value: String,
    /// Pre-session key codes of the displaced action, replayed on release.
    #[serde(default)]
    pub keys: Vec<i32>,
}

/// An atomic session backup tracking ONLY keys modified by this shell
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AstralShortcutSessionBackup {
    pub timestamp: u64,
    pub affected_entries: Vec<GranularShortcutSnapshot>,
    pub previous_kwin_plugin_enabled: bool,
    pub displaced_action: Option<DisplacedShortcut>,
    #[serde(default)]
    pub displaced_actions: Vec<DisplacedShortcut>,
    /// Shortcut mode this session was claimed in (`meta-space`, `meta`,
    /// `alt-space`). Absent in journals written before the field existed, which
    /// reads as "claimed, mode unknown".
    #[serde(default)]
    pub mode: Option<String>,
}

/// Display label the KDE shortcuts editor shows for the launcher action.
///
/// This string is part of the *value* `scripts/bind_shortcuts.sh` writes, so it
/// has to match that script byte for byte - otherwise the claim check never
/// recognises its own work and every tick would re-bind. `test_shell_scripts`
/// pins the two sides together.
pub const LAUNCHER_BINDING_LABEL: &str = "Astral Plasma: Toggle Launcher";
/// Display label for the overview action, same contract as the launcher's.
pub const OVERVIEW_BINDING_LABEL: &str = "Astral Plasma: Active Apps Overview";

/// The `kglobalshortcutsrc` value the launcher action takes in a given mode.
///
/// Lives in the domain so the bind path, the reconciler and the tests all agree
/// on what "already claimed in this mode" means.
pub fn launcher_binding(mode: &str) -> String {
    let key = match mode {
        "meta" | "super" => "Meta",
        "alt-space" => "Alt+Space",
        _ => "Meta+Space",
    };
    format!("{key},none,{LAUNCHER_BINDING_LABEL}")
}

/// The overview action: bare Meta is the primary binding, except in `meta` mode
/// where the launcher owns Meta and the overview keeps Meta+W only.
pub fn overview_binding(mode: &str) -> String {
    let key = if matches!(mode, "meta" | "super") { "Meta+W" } else { "Meta\tMeta+W" };
    format!("{key},none,{OVERVIEW_BINDING_LABEL}")
}

/// Is the desktop already claimed in exactly the requested mode?
///
/// The journal records the claim and the live configuration proves it; both must
/// agree. A claim that is only half-present (journal there, keys overwritten by
/// Plasma) must be re-applied, and a claim for a *different* mode must be
/// re-applied rather than silently kept.
pub fn claim_is_current(
    journal_mode: Option<&str>,
    requested_mode: &str,
    launcher_value: Option<&str>,
    plugin_enabled: bool,
) -> bool {
    let expected = launcher_binding(requested_mode);
    journal_mode == Some(requested_mode)
        && plugin_enabled
        && launcher_value == Some(expected.as_str())
}

/// Merge freshly-read current entries into an EXISTING session backup.
///
/// The backup records pre-session state, and `snapshot` runs on every bind:
/// an already-recorded key must keep its ORIGINAL previous value even though
/// its current value has since been modified by an earlier bind. Only keys
/// the backup does not know yet - added to the monitored set after the
/// session started, e.g. the bare-Meta overview - are appended with their
/// pristine current value, so `restore` still reverts everything the project
/// manages. The first recorded displaced action wins; it fills in only when
/// absent. Returns the merged backup and whether anything changed.
pub fn merge_missing_entries(
    mut existing: AstralShortcutSessionBackup,
    fresh: Vec<GranularShortcutSnapshot>,
    fresh_displaced: Option<DisplacedShortcut>,
) -> (AstralShortcutSessionBackup, bool) {
    let mut changed = false;
    for entry in fresh {
        let known = existing
            .affected_entries
            .iter()
            .any(|e| e.group == entry.group && e.key == entry.key);
        if !known {
            existing.affected_entries.push(entry);
            changed = true;
        }
    }
    if existing.displaced_action.is_none() && fresh_displaced.is_some() {
        existing.displaced_action = fresh_displaced;
        changed = true;
    }
    (existing, changed)
}

/// Merge with multiple displaced actions support.
pub fn merge_missing_entries_multi(
    mut existing: AstralShortcutSessionBackup,
    fresh: Vec<GranularShortcutSnapshot>,
    fresh_displaced: Vec<DisplacedShortcut>,
) -> (AstralShortcutSessionBackup, bool) {
    let mut changed = false;
    for entry in fresh {
        let known = existing
            .affected_entries
            .iter()
            .any(|e| e.group == entry.group && e.key == entry.key);
        if !known {
            existing.affected_entries.push(entry);
            changed = true;
        }
    }
    for disp in fresh_displaced {
        let known = existing
            .displaced_actions
            .iter()
            .any(|d| d.group == disp.group && d.key == disp.key);
        if !known {
            if existing.displaced_action.is_none() {
                existing.displaced_action = Some(disp.clone());
            }
            existing.displaced_actions.push(disp);
            changed = true;
        }
    }
    (existing, changed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bindings_follow_the_mode() {
        assert!(launcher_binding("meta-space").starts_with("Meta+Space,none,"));
        assert!(launcher_binding("meta").starts_with("Meta,none,"));
        assert!(launcher_binding("super").starts_with("Meta,none,"));
        assert!(launcher_binding("alt-space").starts_with("Alt+Space,none,"));
        assert!(overview_binding("meta-space").starts_with("Meta\tMeta+W,none,"));
        assert!(overview_binding("meta").starts_with("Meta+W,none,"));
    }

    #[test]
    fn a_claim_is_only_current_when_journal_and_config_agree() {
        let launcher = launcher_binding("meta-space");
        assert!(claim_is_current(
            Some("meta-space"),
            "meta-space",
            Some(launcher.as_str()),
            true
        ));
        // A different mode, a half-restored configuration, a disabled plugin or
        // a legacy journal without a mode all mean the bind has to run again.
        assert!(!claim_is_current(Some("meta"), "meta-space", Some(launcher.as_str()), true));
        assert!(!claim_is_current(Some("meta-space"), "meta-space", None, true));
        assert!(!claim_is_current(
            Some("meta-space"),
            "meta-space",
            Some("Alt+F1,none,Activate Application Launcher"),
            true
        ));
        assert!(!claim_is_current(Some("meta-space"), "meta-space", Some(launcher.as_str()), false));
        assert!(!claim_is_current(None, "meta-space", Some(launcher.as_str()), true));
    }
}
