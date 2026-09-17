use crate::domain::ports::DynResult;
use crate::domain::system_settings::{
    AudioAppStream, AudioDevice, AudioPort, AudioStatus, BluetoothDevice, BluetoothPort,
    BluetoothStatus, NetworkPort, NetworkStatus, WifiAccessPoint,
};
use std::process::Command;

// ==========================================
// Parsing Utilities (Pure functions for TDD)
// ==========================================

pub fn parse_nmcli_wifi_list(output: &str) -> Vec<WifiAccessPoint> {
    let mut list = Vec::new();
    for line in output.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        // Format: IN-USE:BSSID:SSID:SIGNAL:SECURITY:FREQ
        // Colons can be escaped in BSSID as "\:"
        let unescaped = line.replace("\\:", "__COLON__");
        let parts: Vec<&str> = unescaped.split(':').collect();
        if parts.len() >= 5 {
            let in_use = parts[0].trim() == "*";
            let bssid = parts[1].replace("__COLON__", ":");
            let ssid = parts[2].trim().to_string();
            let signal: u8 = parts[3].trim().parse().unwrap_or(0);
            let security = parts[4].trim().to_string();
            let frequency: u32 = if parts.len() >= 6 {
                parts[5].trim().parse().unwrap_or(0)
            } else {
                0
            };

            if !ssid.is_empty() {
                list.push(WifiAccessPoint {
                    ssid,
                    bssid,
                    signal,
                    security: if security.is_empty() { "Open".to_string() } else { security },
                    is_connected: in_use,
                    frequency,
                });
            }
        }
    }
    list
}

pub fn parse_bluetooth_show_output(output: &str) -> bool {
    for line in output.lines() {
        let line = line.trim();
        if line.starts_with("Powered:") {
            return line.contains("yes");
        }
    }
    false
}

pub fn parse_audio_volume_output(output: &str) -> (f32, bool) {
    let muted = output.contains("[MUTED]");
    // Find "Volume: X.XX"
    let vol = if let Some(idx) = output.find("Volume:") {
        let rest = output[idx + 7..].trim_start();
        let num_str: String = rest
            .chars()
            .take_while(|c| c.is_ascii_digit() || *c == '.')
            .collect();
        num_str.parse::<f32>().unwrap_or(0.0)
    } else {
        0.0
    };
    (vol, muted)
}

// ==========================================
// Adapters implementing Domain Ports
// ==========================================

pub struct SystemNetworkAdapter;

impl Default for SystemNetworkAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemNetworkAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl NetworkPort for SystemNetworkAdapter {
    fn query_status(&self) -> DynResult<NetworkStatus> {
        let wifi_out = Command::new("nmcli")
            .args(["-t", "-f", "WIFI,STATE", "g"])
            .output();

        let mut wifi_enabled = true;
        if let Ok(out) = wifi_out {
            let s = String::from_utf8_lossy(&out.stdout);
            if s.contains("disabled") {
                wifi_enabled = false;
            }
        }

        // Active connection
        let conn_out = Command::new("nmcli")
            .args(["-t", "-f", "IN-USE,SSID", "dev", "wifi"])
            .output();

        let mut active_ssid = None;
        if let Ok(out) = conn_out {
            let s = String::from_utf8_lossy(&out.stdout);
            for line in s.lines() {
                if line.starts_with('*') {
                    let parts: Vec<&str> = line.split(':').collect();
                    if parts.len() >= 2 && !parts[1].is_empty() {
                        active_ssid = Some(parts[1].trim().to_string());
                        break;
                    }
                }
            }
        }

        // IP address
        let ip_out = Command::new("hostname").arg("-I").output();
        let ip_address = if let Ok(out) = ip_out {
            let s = String::from_utf8_lossy(&out.stdout);
            s.split_whitespace().next().map(|s| s.to_string())
        } else {
            None
        };

        Ok(NetworkStatus {
            wifi_enabled,
            active_ssid,
            ip_address,
            interface: "wlan0".to_string(),
        })
    }

    fn scan_wifi(&self) -> DynResult<Vec<WifiAccessPoint>> {
        let out = Command::new("nmcli")
            .args(["-t", "-f", "IN-USE,BSSID,SSID,SIGNAL,SECURITY,FREQ", "dev", "wifi", "list"])
            .output()?;

        let s = String::from_utf8_lossy(&out.stdout);
        let mut list = parse_nmcli_wifi_list(&s);
        // Sort by signal strength descending
        list.sort_by(|a, b| b.signal.cmp(&a.signal));
        Ok(list)
    }

    fn toggle_wifi(&self, enabled: bool) -> DynResult<()> {
        let arg = if enabled { "on" } else { "off" };
        Command::new("nmcli").args(["radio", "wifi", arg]).output()?;
        Ok(())
    }

    fn connect_wifi(&self, ssid: &str, password: Option<&str>) -> DynResult<()> {
        let mut cmd = Command::new("nmcli");
        cmd.args(["dev", "wifi", "connect", ssid]);
        if let Some(pass) = password {
            cmd.args(["password", pass]);
        }
        cmd.output()?;
        Ok(())
    }
}

pub struct SystemBluetoothAdapter;

impl Default for SystemBluetoothAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemBluetoothAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl BluetoothPort for SystemBluetoothAdapter {
    fn query_status(&self) -> DynResult<BluetoothStatus> {
        let show_out = Command::new("bluetoothctl").arg("show").output();
        let powered = if let Ok(out) = show_out {
            let s = String::from_utf8_lossy(&out.stdout);
            parse_bluetooth_show_output(&s)
        } else {
            false
        };

        let mut devices = Vec::new();
        if powered {
            let dev_out = Command::new("bluetoothctl").arg("devices").output();
            if let Ok(out) = dev_out {
                let s = String::from_utf8_lossy(&out.stdout);
                for line in s.lines() {
                    // Line format: Device MAC Name
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 3 && parts[0] == "Device" {
                        let mac = parts[1].to_string();
                        let name = parts[2..].join(" ");
                        // Query info for this device
                        let info_out = Command::new("bluetoothctl").args(["info", &mac]).output();
                        let mut connected = false;
                        let mut paired = true;
                        let mut battery = None;

                        if let Ok(info) = info_out {
                            let info_str = String::from_utf8_lossy(&info.stdout);
                            connected = info_str.contains("Connected: yes");
                            paired = info_str.contains("Paired: yes");
                            if let Some(idx) = info_str.find("Battery Percentage:") {
                                let rest = &info_str[idx + 19..];
                                if let Some(first_num) = rest.split_whitespace().next() {
                                    let clean: String = first_num.chars().filter(|c| c.is_ascii_digit()).collect();
                                    battery = clean.parse::<u8>().ok();
                                }
                            }
                        }

                        devices.push(BluetoothDevice {
                            mac,
                            name,
                            connected,
                            paired,
                            battery_percent: battery,
                        });
                    }
                }
            }
        }

        Ok(BluetoothStatus { powered, devices })
    }

    fn toggle_power(&self, enabled: bool) -> DynResult<()> {
        let arg = if enabled { "on" } else { "off" };
        Command::new("bluetoothctl").args(["power", arg]).output()?;
        Ok(())
    }

    fn connect_device(&self, mac: &str) -> DynResult<()> {
        Command::new("bluetoothctl").args(["connect", mac]).output()?;
        Ok(())
    }

    fn disconnect_device(&self, mac: &str) -> DynResult<()> {
        Command::new("bluetoothctl").args(["disconnect", mac]).output()?;
        Ok(())
    }
}

pub struct SystemAudioAdapter;

impl Default for SystemAudioAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemAudioAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AudioPort for SystemAudioAdapter {
    fn query_status(&self) -> DynResult<AudioStatus> {
        let out = Command::new("wpctl")
            .args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
            .output()?;

        let (vol, muted) = parse_audio_volume_output(&String::from_utf8_lossy(&out.stdout));

        // Get app streams using pactl list sink-inputs if available
        let mut apps = Vec::new();
        let pactl_out = Command::new("pactl").args(["list", "sink-inputs"]).output();
        if let Ok(p_out) = pactl_out {
            let s = String::from_utf8_lossy(&p_out.stdout);
            let mut current_id = 0;
            let mut app_name = String::new();
            let mut app_vol = 1.0;
            let mut app_muted = false;

            for line in s.lines() {
                let line = line.trim();
                if line.starts_with("Sink Input #") {
                    if current_id != 0 && !app_name.is_empty() {
                        apps.push(AudioAppStream {
                            id: current_id,
                            app_name: app_name.clone(),
                            volume: app_vol,
                            is_muted: app_muted,
                        });
                    }
                    current_id = line[12..].parse().unwrap_or(0);
                    app_name.clear();
                    app_vol = 1.0;
                    app_muted = false;
                } else if line.starts_with("application.name =") {
                    app_name = line[18..].trim().trim_matches('"').trim().to_string();
                } else if line.starts_with("Mute:") {
                    app_muted = line.contains("yes");
                } else if line.starts_with("Volume:") {
                    // e.g. "Volume: front-left: 65536 / 100% / 0.00 dB"
                    if let Some(pct_idx) = line.find('%') {
                        let prefix = &line[..pct_idx];
                        if let Some(last_space) = prefix.rfind(' ') {
                            let pct_str = &prefix[last_space + 1..];
                            if let Ok(pct) = pct_str.parse::<f32>() {
                                app_vol = pct / 100.0;
                            }
                        }
                    }
                }
            }
            if current_id != 0 && !app_name.is_empty() {
                apps.push(AudioAppStream {
                    id: current_id,
                    app_name,
                    volume: app_vol,
                    is_muted: app_muted,
                });
            }
        }

        Ok(AudioStatus {
            default_sink_volume: vol,
            default_sink_muted: muted,
            sinks: vec![AudioDevice {
                id: 1,
                name: "@DEFAULT_AUDIO_SINK@".to_string(),
                description: "Default Output".to_string(),
                volume: vol,
                is_muted: muted,
                is_default: true,
                is_sink: true,
            }],
            sources: vec![],
            apps,
        })
    }

    fn set_master_volume(&self, volume: f32) -> DynResult<()> {
        let v = format!("{:.2}", volume.clamp(0.0, 1.5));
        Command::new("wpctl")
            .args(["set-volume", "@DEFAULT_AUDIO_SINK@", &v])
            .output()?;
        Ok(())
    }

    fn toggle_master_mute(&self) -> DynResult<()> {
        Command::new("wpctl")
            .args(["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
            .output()?;
        Ok(())
    }

    fn set_app_volume(&self, app_id: u32, volume: f32) -> DynResult<()> {
        let pct = format!("{}%", (volume * 100.0).round() as u32);
        Command::new("pactl")
            .args(["set-sink-input-volume", &app_id.to_string(), &pct])
            .output()?;
        Ok(())
    }

    fn set_default_sink(&self, sink_id: u32) -> DynResult<()> {
        Command::new("wpctl")
            .args(["set-default", &sink_id.to_string()])
            .output()?;
        Ok(())
    }
}
