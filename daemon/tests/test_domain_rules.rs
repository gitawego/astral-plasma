use caelestia_daemon::domain::meta_resolver::resolve_window_meta;
use caelestia_daemon::domain::model::*;
use caelestia_daemon::domain::sys_parser::*;

#[test]
fn test_antigravity_resolution() {
    let meta = resolve_window_meta("Antigravity Editor", "antigravity", "ai.opencode.desktop", "");
    assert_eq!(meta.app_name, "Antigravity");
    assert_eq!(meta.icon_name, "antigravity");
    assert_eq!(meta.material_icon, "smart_toy");
    assert_eq!(meta.app_id, "antigravity");
    assert_eq!(meta.desktop_file, "ai.opencode.desktop");
}

#[test]
fn test_cloudmusic_resolution() {
    let meta = resolve_window_meta("网易云音乐", "netease-cloud-music", "cloudmusic", "");
    assert_eq!(meta.app_name, "CloudMusic");
    assert_eq!(meta.icon_name, "netease-cloud-music");
    assert_eq!(meta.material_icon, "music_note");
    assert_eq!(meta.desktop_file, "lutris:rungame/netease-cloud-music");
}

#[test]
fn test_ghostty_terminal_resolution() {
    let meta = resolve_window_meta("ghostty", "com.mitchellh.ghostty", "ghostty", "");
    assert_eq!(meta.app_name, "Terminal");
    assert_eq!(meta.icon_name, "com.mitchellh.ghostty");
    assert_eq!(meta.material_icon, "terminal");
    assert_eq!(meta.app_id, "ghostty");
}

#[test]
fn test_wine_executable_resolution() {
    let meta = resolve_window_meta("Notepad Application", "notepad.exe", "", "");
    assert_eq!(meta.app_name, "Notepad");
    assert_eq!(meta.icon_name, "wine");
    assert_eq!(meta.material_icon, "window");
    assert_eq!(meta.app_id, "notepad");
}

#[test]
fn test_wine_cloudmusic_resolution() {
    let meta = resolve_window_meta("CloudMusic Win", "cloudmusic.exe", "", "");
    assert_eq!(meta.app_name, "CloudMusic");
    assert_eq!(meta.icon_name, "netease-cloud-music");
    assert_eq!(meta.material_icon, "music_note");
}

#[test]
fn test_title_fallback_splitting() {
    let meta = resolve_window_meta("Project Overview — Obsidian", "", "", "");
    assert_eq!(meta.app_name, "Obsidian");
    assert_eq!(meta.material_icon, "window");
}

#[test]
fn test_uptime_parser() {
    let uptime_str = parse_uptime_content("3665.20 12345.67\n");
    assert_eq!(uptime_str, "up 1 hour, 1 minute");

    let uptime_short = parse_uptime_content("125.0 200.0\n");
    assert_eq!(uptime_short, "up 2 minutes");

    let uptime_multi = parse_uptime_content("7325.0 200.0\n");
    assert_eq!(uptime_multi, "up 2 hours, 2 minutes");
}

#[test]
fn test_meminfo_parser() {
    let meminfo = r#"
MemTotal:       32000000 kB
MemFree:         8000000 kB
MemAvailable:   16000000 kB
Buffers:          500000 kB
Cached:          7000000 kB
"#;
    let ram_pct = parse_meminfo_content(meminfo);
    assert!((ram_pct - 0.50).abs() < 0.001);
}

#[test]
fn test_workspace_regex_parser() {
    let kwin_legacy = r#"[Argument: a(uss) {(0, "uuid-one", "Desktop 1"), (1, "uuid-two", "Desktop 2")}]"#;
    let desktops = parse_kwin_desktops(kwin_legacy, "uuid-one");
    assert_eq!(desktops.len(), 2);
    assert_eq!(desktops[0].index, 0);
    assert_eq!(desktops[0].id, "uuid-one");
    assert_eq!(desktops[0].name, "Desktop 1");
    assert!(desktops[0].active);
    assert!(!desktops[1].active);

    // KDE Plasma 6 qdbus6 --literal format with [Argument: (uss) ...]
    let kwin_plasma6 = r#"[Variant: [Argument: a(uss) {[Argument: (uss) 0, "aa1e4fae-42a5-461e-89bf-dd373921543d", "Desktop 1"], [Argument: (uss) 1, "1e3d2f1f-854c-4595-9932-be41778c318c", "Desktop 2"], [Argument: (uss) 2, "06acc857-1a7d-4c98-9558-aef15e21d7a3", "Desktop 3"], [Argument: (uss) 3, "a1417742-e493-4a6c-b824-c14f97c91b67", "Desktop 4"]}]]"#;
    let p6_desktops = parse_kwin_desktops(kwin_plasma6, "1e3d2f1f-854c-4595-9932-be41778c318c");
    assert_eq!(p6_desktops.len(), 4);
    assert_eq!(p6_desktops[0].index, 0);
    assert_eq!(p6_desktops[0].id, "aa1e4fae-42a5-461e-89bf-dd373921543d");
    assert_eq!(p6_desktops[0].name, "Desktop 1");
    assert!(!p6_desktops[0].active);

    assert_eq!(p6_desktops[1].index, 1);
    assert_eq!(p6_desktops[1].id, "1e3d2f1f-854c-4595-9932-be41778c318c");
    assert_eq!(p6_desktops[1].name, "Desktop 2");
    assert!(p6_desktops[1].active);

    assert_eq!(p6_desktops[2].index, 2);
    assert_eq!(p6_desktops[2].id, "06acc857-1a7d-4c98-9558-aef15e21d7a3");
    assert_eq!(p6_desktops[2].name, "Desktop 3");

    assert_eq!(p6_desktops[3].index, 3);
    assert_eq!(p6_desktops[3].id, "a1417742-e493-4a6c-b824-c14f97c91b67");
    assert_eq!(p6_desktops[3].name, "Desktop 4");
}

#[test]
fn test_json_event_serialization() {
    let win = Window {
        id: "test-uuid-1".to_string(),
        title: "Test Window".to_string(),
        app_name: "TestApp".to_string(),
        icon_name: "test-icon".to_string(),
        material_icon: "window".to_string(),
        app_id: "testapp".to_string(),
        desktop_file: "testapp.desktop".to_string(),
        is_active: true,
    };

    let serialized = serde_json::to_string(&win).unwrap();
    assert!(serialized.contains(r#""appName":"TestApp""#));
    assert!(serialized.contains(r#""iconName":"test-icon""#));
    assert!(serialized.contains(r#""isActive":true"#));
}

#[test]
fn test_tray_error_filtering_rules() {
    fn is_valid_sni(item_id: &str, item_icon: &str, item_title: &str) -> bool {
        if item_id.is_empty() && item_title.is_empty() && item_icon.is_empty() {
            return false;
        }
        if item_id.starts_with("Error:") || item_title.starts_with("Error:") || item_icon.starts_with("Error:") {
            return false;
        }
        if item_id.chars().all(|c| c.is_ascii_digit()) && item_icon.is_empty() && item_title.is_empty() {
            return false;
        }
        true
    }

    // DBus error string from ghost service must be rejected
    assert!(!is_valid_sni(
        "Error: org.freedesktop.DBus.Error.UnknownMethod",
        "Error: org.freedesktop.DBus.Error.UnknownMethod",
        "Error: org.freedesktop.DBus.Error.UnknownMethod"
    ));

    // Empty numeric proxy must be rejected
    assert!(!is_valid_sni("31457293", "", ""));

    // Completely empty item must be rejected
    assert!(!is_valid_sni("", "", ""));

    // Valid real items must be accepted
    assert!(is_valid_sni("Fcitx", "input-keyboard", "Input Method"));
    assert!(is_valid_sni("Cachy-Update", "cachy-update-blue", "Cachy-Update"));
    assert!(is_valid_sni("trayid62821", "dev.lizardbyte.app.Sunshine-tray", "sunshine"));
    assert!(is_valid_sni("dropbox-client-7074", "dropboxstatus-idle", "dropbox"));
}

#[test]
fn test_kwin_watcher_dbus_casing() {
    let script = caelestia_daemon::application::watch_events::get_kwin_watcher_script();
    // Must call WindowActivated with capital W to match zbus default CamelCase
    assert!(script.contains(r#""WindowActivated""#), "Script must call WindowActivated (capital W)");
    assert!(!script.contains(r#""windowActivated""#), "Script must NOT call windowActivated (lowercase w)");

    // Must call UpdateWindowList with capital U to match zbus default CamelCase
    assert!(script.contains(r#""UpdateWindowList""#), "Script must call UpdateWindowList (capital U)");
    assert!(!script.contains(r#""updateWindowList""#), "Script must NOT call updateWindowList (lowercase u)");
}

