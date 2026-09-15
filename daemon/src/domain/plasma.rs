use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PlasmaPanelInfo {
    #[serde(default)]
    pub id: u64,
    #[serde(default)]
    pub location: String,
    #[serde(default)]
    pub hiding: String,
    #[serde(default)]
    pub height: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PlasmaStatus {
    pub panels: Vec<PlasmaPanelInfo>,
    pub backup_dir: String,
    pub session_active: bool,
    pub watchdog_pid: Option<u32>,
}

pub fn is_panel_target_match(target: &str, location: &str) -> bool {
    let t = target.trim().to_lowercase();
    if t == "all" || t.is_empty() {
        return true;
    }
    let loc = location.trim().to_lowercase();
    t.split(',').any(|part| part.trim().to_lowercase() == loc)
}
