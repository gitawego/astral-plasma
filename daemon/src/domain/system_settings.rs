use serde::{Deserialize, Serialize};
use crate::domain::ports::DynResult;

// --- Network Domain ---
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WifiAccessPoint {
    pub ssid: String,
    pub bssid: String,
    pub signal: u8,
    pub security: String,
    pub is_connected: bool,
    pub frequency: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NetworkStatus {
    pub wifi_enabled: bool,
    pub active_ssid: Option<String>,
    pub ip_address: Option<String>,
    pub interface: String,
}

pub trait NetworkPort: Send + Sync {
    fn query_status(&self) -> DynResult<NetworkStatus>;
    fn scan_wifi(&self) -> DynResult<Vec<WifiAccessPoint>>;
    fn toggle_wifi(&self, enabled: bool) -> DynResult<()>;
    fn connect_wifi(&self, ssid: &str, password: Option<&str>) -> DynResult<()>;
}

// --- Bluetooth Domain ---
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BluetoothDevice {
    pub mac: String,
    pub name: String,
    pub connected: bool,
    pub paired: bool,
    pub battery_percent: Option<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BluetoothStatus {
    pub powered: bool,
    pub devices: Vec<BluetoothDevice>,
}

pub trait BluetoothPort: Send + Sync {
    fn query_status(&self) -> DynResult<BluetoothStatus>;
    fn toggle_power(&self, enabled: bool) -> DynResult<()>;
    fn connect_device(&self, mac: &str) -> DynResult<()>;
    fn disconnect_device(&self, mac: &str) -> DynResult<()>;
}

// --- Audio Domain ---
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioDevice {
    pub id: u32,
    pub name: String,
    pub description: String,
    pub volume: f32,
    pub is_muted: bool,
    pub is_default: bool,
    pub is_sink: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioAppStream {
    pub id: u32,
    pub app_name: String,
    pub volume: f32,
    pub is_muted: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioStatus {
    pub default_sink_volume: f32,
    pub default_sink_muted: bool,
    pub sinks: Vec<AudioDevice>,
    pub sources: Vec<AudioDevice>,
    pub apps: Vec<AudioAppStream>,
}

pub trait AudioPort: Send + Sync {
    fn query_status(&self) -> DynResult<AudioStatus>;
    fn set_master_volume(&self, volume: f32) -> DynResult<()>;
    fn toggle_master_mute(&self) -> DynResult<()>;
    fn set_app_volume(&self, app_id: u32, volume: f32) -> DynResult<()>;
    fn set_default_sink(&self, sink_id: u32) -> DynResult<()>;
}
