use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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
    #[serde(rename = "isMaximized", default)]
    pub is_maximized: bool,
    #[serde(rename = "isFullScreen", default)]
    pub is_fullscreen: bool,
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
    #[serde(rename = "itemIsMenu", default)]
    pub item_is_menu: bool,
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
    #[serde(rename = "activeId", default)]
    pub active_id: String,
    #[serde(rename = "hasMaximizedWindow", default)]
    pub has_maximized_window: bool,
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
    #[serde(rename = "hasMaximizedWindow", default)]
    pub has_maximized_window: bool,
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
    #[serde(rename = "activeId", default)]
    pub active_id: String,
    #[serde(rename = "hasMaximizedWindow", default)]
    pub has_maximized_window: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrayPayload {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub tray: Vec<TrayItem>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionConnectionState {
    Starting,
    Connected,
    Degraded,
    Disconnected,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OutputGeometry {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Output {
    pub id: String,
    pub name: String,
    pub geometry: OutputGeometry,
    pub scale: f64,
    #[serde(rename = "refreshRate")]
    pub refresh_rate: f64,
    pub focused: bool,
    pub primary: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub index: u32,
    #[serde(rename = "outputId", default, skip_serializing_if = "Option::is_none")]
    pub output_id: Option<String>,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Capability {
    pub available: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UserIntent {
    #[serde(rename = "requestId")]
    pub request_id: String,
    pub kind: String,
    #[serde(default)]
    pub target: serde_json::Value,
    #[serde(default)]
    pub parameters: serde_json::Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ActionStatus {
    Applied,
    Pending,
    Unsupported,
    PermissionDenied,
    Unavailable,
    Invalid,
    Stale,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionResult {
    #[serde(rename = "requestId")]
    pub request_id: String,
    pub status: ActionStatus,
    #[serde(rename = "messageKey")]
    pub message_key: String,
    #[serde(default)]
    pub details: serde_json::Value,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DesktopSessionSnapshot {
    #[serde(rename = "schemaVersion")]
    pub schema_version: u32,
    #[serde(rename = "sessionId")]
    pub session_id: String,
    pub revision: u64,
    pub connection: SessionConnectionState,
    pub profile: String,
    #[serde(rename = "focusedOutputId", default, skip_serializing_if = "Option::is_none")]
    pub focused_output_id: Option<String>,
    #[serde(default)]
    pub outputs: Vec<Output>,
    #[serde(default)]
    pub workspaces: Vec<Workspace>,
    #[serde(default)]
    pub windows: Vec<Window>,
    #[serde(default)]
    pub capabilities: HashMap<String, Capability>,
    #[serde(rename = "lastUpdated")]
    pub last_updated: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum DesktopEvent {
    SessionConnectionChanged { state: SessionConnectionState },
    WorkspaceActivated { id: String, output_id: Option<String> },
    WindowFocused { id: String },
    WindowListChanged { windows: Vec<Window> },
    OutputChanged { output: Output },
    ShellSurfaceVisibilityChanged { surface_id: String, visible: bool },
    CapabilityChanged { capabilities: HashMap<String, Capability> },
    ActionCompleted { result: ActionResult },
}

