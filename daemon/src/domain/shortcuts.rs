use serde::{Deserialize, Serialize};

/// Represents a single key-value entry in a KDE config file that was modified.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GranularShortcutSnapshot {
    pub group: String,
    pub key: String,
    /// None if the key was previously absent/unset in the configuration
    pub previous_value: Option<String>,
}

/// Represents an external shortcut that originally claimed the key combination (e.g. Meta+Space)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DisplacedShortcut {
    pub group: String,
    pub key: String,
    pub full_value: String,
}

/// An atomic session backup tracking ONLY keys modified by this shell
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AstralShortcutSessionBackup {
    pub timestamp: u64,
    pub affected_entries: Vec<GranularShortcutSnapshot>,
    pub previous_kwin_plugin_enabled: bool,
    pub displaced_action: Option<DisplacedShortcut>,
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
