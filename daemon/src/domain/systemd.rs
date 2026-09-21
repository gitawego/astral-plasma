use crate::domain::branding;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServiceStatus {
    pub installed: bool,
    pub enabled: bool,
    pub active: bool,
    pub file: String,
}

pub fn generate_unit_file_content(quickshell_bin: &str, theme_dir: &str) -> String {
    format!(
r#"[Unit]
Description={}
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart={} -p {}
Restart=on-failure
RestartSec=2s
Environment=QT_QUICK_CONTROLS_STYLE=Basic

[Install]
WantedBy=graphical-session.target
"#,
        branding::SYSTEMD_DESCRIPTION, quickshell_bin, theme_dir
    )
}
