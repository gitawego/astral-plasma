use astral_plasma::domain::ports::DynResult;
use astral_plasma::domain::system_settings::{
    AudioAppStream, AudioDevice, AudioPort, AudioStatus, BluetoothDevice, BluetoothPort,
    BluetoothStatus, NetworkPort, NetworkStatus, WifiAccessPoint,
};
use astral_plasma::application::settings_service::{
    AudioControlUseCase, BluetoothControlUseCase, NetworkControlUseCase,
};
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
struct MockNetworkPort {
    wifi_enabled: Arc<Mutex<bool>>,
    active_ssid: Arc<Mutex<Option<String>>>,
    networks: Vec<WifiAccessPoint>,
}

impl NetworkPort for MockNetworkPort {
    fn query_status(&self) -> DynResult<NetworkStatus> {
        let enabled = *self.wifi_enabled.lock().unwrap();
        let active = self.active_ssid.lock().unwrap().clone();
        Ok(NetworkStatus {
            wifi_enabled: enabled,
            active_ssid: active,
            ip_address: Some("192.168.1.50".to_string()),
            interface: "wlan0".to_string(),
        })
    }

    fn scan_wifi(&self) -> DynResult<Vec<WifiAccessPoint>> {
        Ok(self.networks.clone())
    }

    fn toggle_wifi(&self, enabled: bool) -> DynResult<()> {
        let mut lock = self.wifi_enabled.lock().unwrap();
        *lock = enabled;
        Ok(())
    }

    fn connect_wifi(&self, ssid: &str, _password: Option<&str>) -> DynResult<()> {
        let mut lock = self.active_ssid.lock().unwrap();
        *lock = Some(ssid.to_string());
        Ok(())
    }
}

#[derive(Clone, Default)]
struct MockBluetoothPort {
    powered: Arc<Mutex<bool>>,
    devices: Vec<BluetoothDevice>,
}

impl BluetoothPort for MockBluetoothPort {
    fn query_status(&self) -> DynResult<BluetoothStatus> {
        let p = *self.powered.lock().unwrap();
        Ok(BluetoothStatus {
            powered: p,
            devices: self.devices.clone(),
        })
    }

    fn toggle_power(&self, enabled: bool) -> DynResult<()> {
        let mut p = self.powered.lock().unwrap();
        *p = enabled;
        Ok(())
    }

    fn connect_device(&self, _mac: &str) -> DynResult<()> {
        Ok(())
    }

    fn disconnect_device(&self, _mac: &str) -> DynResult<()> {
        Ok(())
    }
}

#[derive(Clone, Default)]
struct MockAudioPort {
    master_vol: Arc<Mutex<f32>>,
    master_muted: Arc<Mutex<bool>>,
    sinks: Vec<AudioDevice>,
    apps: Vec<AudioAppStream>,
}

impl AudioPort for MockAudioPort {
    fn query_status(&self) -> DynResult<AudioStatus> {
        let vol = *self.master_vol.lock().unwrap();
        let muted = *self.master_muted.lock().unwrap();
        Ok(AudioStatus {
            default_sink_volume: vol,
            default_sink_muted: muted,
            sinks: self.sinks.clone(),
            sources: vec![],
            apps: self.apps.clone(),
        })
    }

    fn set_master_volume(&self, volume: f32) -> DynResult<()> {
        let mut v = self.master_vol.lock().unwrap();
        *v = volume.clamp(0.0, 1.5);
        Ok(())
    }

    fn toggle_master_mute(&self) -> DynResult<()> {
        let mut m = self.master_muted.lock().unwrap();
        *m = !*m;
        Ok(())
    }

    fn set_app_volume(&self, _app_id: u32, _volume: f32) -> DynResult<()> {
        Ok(())
    }

    fn set_default_sink(&self, _sink_id: u32) -> DynResult<()> {
        Ok(())
    }
}

#[test]
fn test_network_control_use_case() {
    let mock = MockNetworkPort {
        wifi_enabled: Arc::new(Mutex::new(true)),
        active_ssid: Arc::new(Mutex::new(Some("Home_5G".to_string()))),
        networks: vec![
            WifiAccessPoint {
                ssid: "Home_5G".to_string(),
                bssid: "00:11:22:33:44:55".to_string(),
                signal: 85,
                security: "WPA2".to_string(),
                is_connected: true,
                frequency: 5180,
            },
            WifiAccessPoint {
                ssid: "Cafe_Wifi".to_string(),
                bssid: "AA:BB:CC:DD:EE:FF".to_string(),
                signal: 45,
                security: "Open".to_string(),
                is_connected: false,
                frequency: 2412,
            },
        ],
    };

    let use_case = NetworkControlUseCase::new(Arc::new(mock.clone()));
    let status = use_case.get_status().unwrap();
    assert!(status.wifi_enabled);
    assert_eq!(status.active_ssid, Some("Home_5G".to_string()));

    let scan = use_case.scan_networks().unwrap();
    assert_eq!(scan.len(), 2);
    assert_eq!(scan[0].signal, 85);

    use_case.toggle_wifi(false).unwrap();
    let updated = use_case.get_status().unwrap();
    assert!(!updated.wifi_enabled);
}

#[test]
fn test_bluetooth_control_use_case() {
    let mock = MockBluetoothPort {
        powered: Arc::new(Mutex::new(false)),
        devices: vec![BluetoothDevice {
            mac: "11:22:33:44:55:66".to_string(),
            name: "Sony WH-1000XM4".to_string(),
            connected: false,
            paired: true,
            battery_percent: Some(90),
        }],
    };

    let use_case = BluetoothControlUseCase::new(Arc::new(mock.clone()));
    let status = use_case.get_status().unwrap();
    assert!(!status.powered);
    assert_eq!(status.devices.len(), 1);

    use_case.toggle_power(true).unwrap();
    let updated = use_case.get_status().unwrap();
    assert!(updated.powered);
}

#[test]
fn test_audio_control_use_case() {
    let mock = MockAudioPort {
        master_vol: Arc::new(Mutex::new(0.50)),
        master_muted: Arc::new(Mutex::new(false)),
        sinks: vec![AudioDevice {
            id: 42,
            name: "alsa_output.pci".to_string(),
            description: "Built-in Audio".to_string(),
            volume: 0.50,
            is_muted: false,
            is_default: true,
            is_sink: true,
        }],
        apps: vec![AudioAppStream {
            id: 101,
            app_name: "Spotify".to_string(),
            volume: 0.80,
            is_muted: false,
        }],
    };

    let use_case = AudioControlUseCase::new(Arc::new(mock.clone()));
    let status = use_case.get_status().unwrap();
    assert_eq!(status.default_sink_volume, 0.50);
    assert!(!status.default_sink_muted);
    assert_eq!(status.apps.len(), 1);

    use_case.set_volume(0.75).unwrap();
    let updated = use_case.get_status().unwrap();
    assert_eq!(updated.default_sink_volume, 0.75);

    use_case.toggle_mute().unwrap();
    let muted_st = use_case.get_status().unwrap();
    assert!(muted_st.default_sink_muted);
}
