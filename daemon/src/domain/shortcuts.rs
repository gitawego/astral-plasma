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

/// An atomic session backup tracking ONLY keys modified by Astral/Caelestia
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AstralShortcutSessionBackup {
    pub timestamp: u64,
    pub affected_entries: Vec<GranularShortcutSnapshot>,
    pub previous_kwin_plugin_enabled: bool,
    pub displaced_action: Option<DisplacedShortcut>,
}
