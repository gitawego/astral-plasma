use crate::domain::ports::DynResult;
use crate::domain::system_settings::{
    AudioPort, AudioStatus, BluetoothPort, BluetoothStatus, NetworkPort,
    NetworkStatus, WifiAccessPoint,
};
use std::sync::Arc;

pub struct NetworkControlUseCase {
    port: Arc<dyn NetworkPort>,
}

impl NetworkControlUseCase {
    pub fn new(port: Arc<dyn NetworkPort>) -> Self {
        Self { port }
    }

    pub fn get_status(&self) -> DynResult<NetworkStatus> {
        self.port.query_status()
    }

    pub fn scan_networks(&self) -> DynResult<Vec<WifiAccessPoint>> {
        self.port.scan_wifi()
    }

    pub fn toggle_wifi(&self, enabled: bool) -> DynResult<()> {
        self.port.toggle_wifi(enabled)
    }

    pub fn connect_wifi(&self, ssid: &str, password: Option<&str>) -> DynResult<()> {
        self.port.connect_wifi(ssid, password)
    }
}

pub struct BluetoothControlUseCase {
    port: Arc<dyn BluetoothPort>,
}

impl BluetoothControlUseCase {
    pub fn new(port: Arc<dyn BluetoothPort>) -> Self {
        Self { port }
    }

    pub fn get_status(&self) -> DynResult<BluetoothStatus> {
        self.port.query_status()
    }

    pub fn toggle_power(&self, enabled: bool) -> DynResult<()> {
        self.port.toggle_power(enabled)
    }

    pub fn connect(&self, mac: &str) -> DynResult<()> {
        self.port.connect_device(mac)
    }

    pub fn disconnect(&self, mac: &str) -> DynResult<()> {
        self.port.disconnect_device(mac)
    }
}

pub struct AudioControlUseCase {
    port: Arc<dyn AudioPort>,
}

impl AudioControlUseCase {
    pub fn new(port: Arc<dyn AudioPort>) -> Self {
        Self { port }
    }

    pub fn get_status(&self) -> DynResult<AudioStatus> {
        self.port.query_status()
    }

    pub fn set_volume(&self, volume: f32) -> DynResult<()> {
        self.port.set_master_volume(volume)
    }

    pub fn toggle_mute(&self) -> DynResult<()> {
        self.port.toggle_master_mute()
    }

    pub fn set_app_volume(&self, app_id: u32, volume: f32) -> DynResult<()> {
        self.port.set_app_volume(app_id, volume)
    }

    pub fn set_default_sink(&self, sink_id: u32) -> DynResult<()> {
        self.port.set_default_sink(sink_id)
    }
}
