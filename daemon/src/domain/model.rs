use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WindowMeta {
    pub app_name: String,
    pub icon_name: String,
    pub material_icon: String,
    pub app_id: String,
    pub desktop_file: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Window {
    pub id: String,
    pub title: String,
    #[serde(rename = "appName")]
    pub app_name: String,
    #[serde(rename = "iconName")]
    pub icon_name: String,
    #[serde(rename = "materialIcon")]
    pub material_icon: String,
    #[serde(rename = "appId")]
    pub app_id: String,
    #[serde(rename = "desktopFile")]
    pub desktop_file: String,
    #[serde(rename = "isActive")]
    pub is_active: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrayItem {
    pub service: String,
    pub path: String,
    pub id: String,
    pub title: String,
    #[serde(rename = "materialIcon")]
    pub material_icon: String,
    #[serde(rename = "rawIcon")]
    pub raw_icon: String,
    #[serde(rename = "imBadge")]
    pub im_badge: String,
    #[serde(rename = "menuPath")]
    pub menu_path: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrayMenuItem {
    pub id: i32,
    pub label: String,
    #[serde(rename = "isSeparator")]
    pub is_separator: bool,
    pub enabled: bool,
    pub icon: String,
    #[serde(rename = "hasSubmenu", default)]
    pub has_submenu: bool,
    #[serde(rename = "toggleType", default)]
    pub toggle_type: String,
    #[serde(rename = "toggleState", default)]
    pub toggle_state: i32,
    #[serde(default)]
    pub disposition: String,
    #[serde(default)]
    pub children: Vec<TrayMenuItem>,
}


#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Desktop {
    pub index: u32,
    pub id: String,
    pub name: String,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SystemMetrics {
    pub uptime: String,
    pub ram: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FullStatePayload {
    pub windows: Vec<Window>,
    pub tray: Vec<TrayItem>,
    #[serde(rename = "activeTitle")]
    pub active_title: String,
    #[serde(rename = "activeMaterialIcon")]
    pub active_material_icon: String,
    #[serde(rename = "activeIconName")]
    pub active_icon_name: String,
    #[serde(rename = "activeAppId")]
    pub active_app_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActiveWindowPayload {
    #[serde(rename = "type")]
    pub msg_type: String,
    #[serde(rename = "activeTitle")]
    pub active_title: String,
    #[serde(rename = "activeMaterialIcon")]
    pub active_material_icon: String,
    #[serde(rename = "activeIconName")]
    pub active_icon_name: String,
    #[serde(rename = "activeAppId")]
    pub active_app_id: String,
    #[serde(rename = "activeId")]
    pub active_id: String,
    pub windows: Vec<Window>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowsListPayload {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub windows: Vec<Window>,
    #[serde(rename = "activeTitle")]
    pub active_title: String,
    #[serde(rename = "activeMaterialIcon")]
    pub active_material_icon: String,
    #[serde(rename = "activeIconName")]
    pub active_icon_name: String,
    #[serde(rename = "activeAppId")]
    pub active_app_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrayPayload {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub tray: Vec<TrayItem>,
}
