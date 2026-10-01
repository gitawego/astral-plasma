use serde::{Deserialize, Serialize};

/// Status of desktop-level entries installed into the user's profile.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DesktopIntegrationStatus {
    pub installed: bool,
    pub session_installed: bool,
    pub shortcuts_installed: bool,
    pub session_file: String,
    pub shortcuts_dir: String,
}
