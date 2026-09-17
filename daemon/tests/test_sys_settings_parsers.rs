use astral_plasma::infrastructure::sys_settings::{
    parse_audio_volume_output, parse_bluetooth_show_output, parse_nmcli_wifi_list,
};

#[test]
fn test_parse_nmcli_wifi_list() {
    let output = "*:00\\:11\\:22\\:33\\:44\\:55:MyHomeWifi:85:WPA2:5180\n :AA\\:BB\\:CC\\:DD\\:EE\\:FF:PublicSpot:42:Open:2412\n";
    let aps = parse_nmcli_wifi_list(output);
    assert_eq!(aps.len(), 2);
    assert_eq!(aps[0].ssid, "MyHomeWifi");
    assert!(aps[0].is_connected);
    assert_eq!(aps[0].signal, 85);
    assert_eq!(aps[0].security, "WPA2");
    assert_eq!(aps[0].frequency, 5180);

    assert_eq!(aps[1].ssid, "PublicSpot");
    assert!(!aps[1].is_connected);
    assert_eq!(aps[1].signal, 42);
}

#[test]
fn test_parse_bluetooth_show_output() {
    let output = "Controller 00:11:22:33:44:55\n\tName: ArchPC\n\tPowered: yes\n\tDiscoverable: no\n";
    let powered = parse_bluetooth_show_output(output);
    assert!(powered);

    let output_off = "Controller 00:11:22:33:44:55\n\tPowered: no\n";
    assert!(!parse_bluetooth_show_output(output_off));
}

#[test]
fn test_parse_audio_volume_output() {
    let normal = "Volume: 0.65\n";
    let (vol, muted) = parse_audio_volume_output(normal);
    assert!((vol - 0.65).abs() < 0.001);
    assert!(!muted);

    let muted_str = "Volume: 0.40 [MUTED]\n";
    let (vol_m, muted_m) = parse_audio_volume_output(muted_str);
    assert!((vol_m - 0.40).abs() < 0.001);
    assert!(muted_m);
}
