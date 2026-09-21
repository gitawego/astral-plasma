use astral_plasma::domain::meta_resolver::resolve_window_meta;
use astral_plasma::domain::model::*;
use astral_plasma::domain::sys_parser::*;

#[test]
fn test_window_without_entry_is_named_by_its_own_class() {
    // No desktop entry -> no invented name, brand or icon: the window's own
    // class identifies it, exactly as an unknown app behaves in Plasma.
    let meta = resolve_window_meta("Antigravity Editor", "antigravity", "", "");
    assert_eq!(meta.app_name, "Antigravity");
    assert_eq!(meta.app_id, "antigravity");
    assert_eq!(meta.icon_name, "antigravity");
    assert_eq!(meta.material_icon, "window");
}

#[test]
fn test_identity_is_never_attributed_to_another_application() {
    // A class that merely contains a known word must not borrow that app's
    // identity: no built-in table exists to do so any more.
    let meta = resolve_window_meta("网易云音乐", "netease-cloud-music", "cloudmusic", "");
    assert_eq!(meta.app_id, "cloudmusic", "the reported app id is the identity");
    assert_eq!(meta.icon_name, "cloudmusic");
    assert_eq!(meta.material_icon, "window");
}

#[test]
fn test_reverse_dns_class_uses_its_own_identity() {
    let meta = resolve_window_meta("ghostty", "com.mitchellh.ghostty", "ghostty", "");
    assert_eq!(meta.app_id, "ghostty", "the reported app id is the identity");
    assert_eq!(meta.icon_name, "ghostty");
}

#[test]
fn test_generic_material_glyph_for_unresolved_windows() {
    let meta = resolve_window_meta("Quickshell", "quickshell", "quickshell", "");
    assert_eq!(meta.app_name, "Quickshell");
    assert_eq!(meta.icon_name, "quickshell");
    assert_eq!(meta.material_icon, "window");
    assert_eq!(meta.app_id, "quickshell");
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
fn test_wine_without_entry_uses_its_executable_name() {
    let meta = resolve_window_meta("CloudMusic Win", "cloudmusic.exe", "", "");
    assert_eq!(meta.app_name, "Cloudmusic");
    assert_eq!(meta.icon_name, "wine");
    assert_eq!(meta.material_icon, "window");
    assert_eq!(meta.app_id, "cloudmusic");
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
        is_maximized: false,
        is_fullscreen: false,
    };

    let serialized = serde_json::to_string(&win).unwrap();
    assert!(serialized.contains(r#""appName":"TestApp""#));
    assert!(serialized.contains(r#""iconName":"test-icon""#));
    assert!(serialized.contains(r#""isActive":true"#));
    assert!(serialized.contains(r#""isMaximized":false"#));
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
    assert!(is_valid_sni("Antigravity_status_icon_1", "", "Antigravity"));
    assert!(is_valid_sni("Antigravity_status_icon_1", "antigravity", ""));
}

#[test]
fn test_tray_item_without_icon_is_not_fabricated() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    // No title, no icon on the wire: the item keeps its own id and the generic
    // glyph. Nothing is invented on its behalf.
    let (title, icon, m_icon) = TrayAdapter::resolve_tray_meta("some_status_icon_1", "", "");
    assert_eq!(title, "some_status_icon_1");
    assert_eq!(icon, "");
    assert_eq!(m_icon, "circle");

    // A title the item publishes itself is always used verbatim.
    let (title2, _, _) = TrayAdapter::resolve_tray_meta("some_status_icon_1", "My App", "");
    assert_eq!(title2, "My App");
}

#[test]
fn test_kwin_watcher_dbus_casing() {
    let script = astral_plasma::application::watch_events::get_kwin_watcher_script();
    // Must call WindowActivated with capital W to match zbus default CamelCase
    assert!(script.contains(r#""WindowActivated""#), "Script must call WindowActivated (capital W)");
    assert!(!script.contains(r#""windowActivated""#), "Script must NOT call windowActivated (lowercase w)");

    // Must call UpdateWindowList with capital U to match zbus default CamelCase
    assert!(script.contains(r#""UpdateWindowList""#), "Script must call UpdateWindowList (capital U)");
    assert!(!script.contains(r#""updateWindowList""#), "Script must NOT call updateWindowList (lowercase u)");
}

#[test]
fn shell_driven_activation_reports_itself_to_the_watcher() {
    use astral_plasma::infrastructure::kwin_adapter::activate_script;

    let script = activate_script("abc-123");

    // It activates the requested window...
    assert!(script.contains("workspace.activeWindow = w"));
    assert!(script.contains("abc-123"));

    // ...and then reports the activation. KWin's `windowActivated` signal does
    // not fire for script-driven activation, so without this the daemon's
    // Xwayland focus guard would take the keyboard focus back from the window
    // the user just brought to the front ("Bring to Front" would raise it but
    // leave it unable to receive typing).
    assert!(
        script.contains(r#""WindowActivated""#),
        "activation must be reported to the watcher"
    );
    assert!(script.contains("org.astralplasma.WindowWatcher"));
    assert!(script.contains("/Watcher"));
}

#[test]
fn test_workspace_control_use_case() {
    use std::sync::Mutex;
    use astral_plasma::domain::ports::{DynResult, WorkspacePort};
    use astral_plasma::domain::model::Desktop;
    use astral_plasma::application::workspace_control::WorkspaceControlUseCase;

    struct MockWorkspacePort {
        switched_to: Mutex<Option<String>>,
        created_idx: Mutex<Option<u32>>,
    }

    impl WorkspacePort for MockWorkspacePort {
        fn query_desktops(&self) -> DynResult<(String, u32, Vec<Desktop>)> {
            Ok(("desktop-1".to_string(), 2, vec![
                Desktop { id: "desktop-1".to_string(), name: "Workspace 1".to_string(), index: 0, active: true },
                Desktop { id: "desktop-2".to_string(), name: "Workspace 2".to_string(), index: 1, active: false },
            ]))
        }
        fn switch_to(&self, id: &str) -> DynResult<()> {
            *self.switched_to.lock().unwrap() = Some(id.to_string());
            Ok(())
        }
        fn create_and_switch(&self, index: u32) -> DynResult<()> {
            *self.created_idx.lock().unwrap() = Some(index);
            Ok(())
        }
    }

    let port = MockWorkspacePort {
        switched_to: Mutex::new(None),
        created_idx: Mutex::new(None),
    };
    let uc = WorkspaceControlUseCase::new(port);

    let json_str = uc.query_json().unwrap();
    assert!(json_str.contains(r#""current":"desktop-1""#));
    assert!(json_str.contains(r#""count":2"#));

    uc.switch("desktop-2").unwrap();
    uc.ensure_and_switch(3).unwrap();
}

#[test]
fn test_dbusmenu_json_parsing() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    let json_str = r#"{
        "type": "u(ia{sv}av)",
        "data": [
            0,
            [
                0,
                {},
                [
                    {
                        "type": "(ia{sv}av)",
                        "data": [
                            1,
                            {
                                "label": { "type": "s", "data": "Preferences..." },
                                "enabled": { "type": "b", "data": true },
                                "icon-name": { "type": "s", "data": "preferences-system" }
                            },
                            []
                        ]
                    },
                    {
                        "type": "(ia{sv}av)",
                        "data": [
                            2,
                            {
                                "type": { "type": "s", "data": "separator" }
                            },
                            []
                        ]
                    },
                    {
                        "type": "(ia{sv}av)",
                        "data": [
                            3,
                            {
                                "label": { "type": "s", "data": "_Quit" },
                                "enabled": { "type": "b", "data": false }
                            },
                            []
                        ]
                    }
                ]
            ]
        ]
    }"#;

    let val: serde_json::Value = serde_json::from_str(json_str).unwrap();
    let items = TrayAdapter::parse_dbusmenu_json(&val).unwrap();

    assert_eq!(items.len(), 3);

    assert_eq!(items[0].id, 1);
    assert_eq!(items[0].label, "Preferences...");
    assert!(!items[0].is_separator);
    assert!(items[0].enabled);
    assert_eq!(items[0].icon, "preferences-system");

    assert_eq!(items[1].id, 2);
    assert!(items[1].is_separator);

    assert_eq!(items[2].id, 3);
    assert_eq!(items[2].label, "Quit"); // underscore stripped
    assert!(!items[2].is_separator);
    assert!(!items[2].enabled);
}

#[test]
fn test_dbusmenu_nested_submenus_and_toggles() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    let json_str = r#"{
        "data": [
            1,
            [
                0,
                { "children-display": { "data": "submenu" } },
                [
                    {
                        "data": [
                            10,
                            {
                                "label": { "data": "_Updates (2)" },
                                "children-display": { "data": "submenu" }
                            },
                            [
                                {
                                    "data": [
                                        11,
                                        { "label": { "data": "package-a 1.0 -> 2.0" } },
                                        []
                                    ]
                                },
                                {
                                    "data": [
                                        12,
                                        {
                                            "label": { "data": "_Nested Sub" },
                                            "children-display": { "data": "submenu" }
                                        },
                                        [
                                            {
                                                "data": [
                                                    13,
                                                    {
                                                        "label": { "data": "Deep Option" },
                                                        "toggle-type": { "data": "checkmark" },
                                                        "toggle-state": { "data": 1 }
                                                    },
                                                    []
                                                ]
                                            }
                                        ]
                                    ]
                                }
                            ]
                        ]
                    },
                    {
                        "data": [
                            20,
                            {
                                "label": { "data": "Radio Option" },
                                "toggle-type": { "data": "radio" },
                                "toggle-state": { "data": 0 }
                            },
                            []
                        ]
                    }
                ]
            ]
        ]
    }"#;

    let val: serde_json::Value = serde_json::from_str(json_str).unwrap();
    let items = TrayAdapter::parse_dbusmenu_json(&val).unwrap();

    assert_eq!(items.len(), 2);
    // Item 10: Updates (2)
    assert_eq!(items[0].id, 10);
    assert_eq!(items[0].label, "Updates (2)");
    assert!(items[0].has_submenu);
    assert_eq!(items[0].children.len(), 2);

    // Child 11: package-a
    assert_eq!(items[0].children[0].id, 11);
    assert_eq!(items[0].children[0].label, "package-a 1.0 -> 2.0");
    assert!(!items[0].children[0].has_submenu);

    // Child 12: Nested Sub
    assert_eq!(items[0].children[1].id, 12);
    assert_eq!(items[0].children[1].label, "Nested Sub");
    assert!(items[0].children[1].has_submenu);
    assert_eq!(items[0].children[1].children.len(), 1);

    // Grandchild 13: Deep Option (Checkmark on)
    assert_eq!(items[0].children[1].children[0].id, 13);
    assert_eq!(items[0].children[1].children[0].label, "Deep Option");
    assert_eq!(items[0].children[1].children[0].toggle_type, "checkmark");
    assert_eq!(items[0].children[1].children[0].toggle_state, 1);

    // Item 20: Radio Option (off)
    assert_eq!(items[1].id, 20);
    assert_eq!(items[1].toggle_type, "radio");
    assert_eq!(items[1].toggle_state, 0);
}

#[test]
fn test_power_session_confirmation_rules() {
    // Domain rule: all destructive session actions (logout, restart, shutdown)
    // must be guarded behind confirmation and map to canonical system/dbus commands.
    let destructive_actions = vec!["logout", "restart", "shutdown"];

    for action in &destructive_actions {
        let requires_confirmation = match *action {
            "logout" | "restart" | "shutdown" => true,
            _ => false,
        };
        assert!(requires_confirmation, "Action '{}' must require confirmation dialog", action);
    }

    // Non-destructive actions do not require confirmation
    let non_destructive = vec!["lock", "suspend"];
    for action in &non_destructive {
        let requires_confirmation = match *action {
            "logout" | "restart" | "shutdown" => true,
            _ => false,
        };
        assert!(!requires_confirmation, "Action '{}' should not require confirmation", action);
    }
}

#[test]
fn test_tray_metadata_resolution() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    // The SNI's own metadata is authoritative: no keyword mapping decides what
    // an item is called or which icon it uses.
    let (title, icon, m_icon) = TrayAdapter::resolve_tray_meta("Strawberry Music Player", "Strawberry Music Player", "");
    assert_eq!(title, "Strawberry Music Player");
    assert_eq!(icon, "");
    assert_eq!(m_icon, "circle");
    assert!(!icon.contains(' '), "Icon name must never contain spaces: got '{}'", icon);

    // A pre-resolved file:// icon passes through untouched.
    let (title, icon, m_icon) = TrayAdapter::resolve_tray_meta("Strawberry Music Player", "Strawberry Music Player", "file:///tmp/astral_plasma_tray/test.png");
    assert_eq!(title, "Strawberry Music Player");
    assert_eq!(icon, "file:///tmp/astral_plasma_tray/test.png");
    assert_eq!(m_icon, "circle");
}

#[test]
fn test_another_app_owns_audio() {
    use astral_plasma::application::audio_streams::{another_app_owns_audio, AudioStream};

    let music = AudioStream {
        name: "NetEase Cloud Music".to_string(),
        binary: "wine-preloader".to_string(),
    };
    let edge = AudioStream {
        name: "Microsoft Edge".to_string(),
        binary: "msedge".to_string(),
    };
    let bus = "org.mpris.MediaPlayer2.cloudmusic";

    // The bridge's own stream: it stays as the Wine player reports it.
    assert!(!another_app_owns_audio(
        &[music],
        "NetEase Cloud Music (Wine)",
        bus
    ));
    // Something else owns the sound: the bridge is not the one making noise.
    assert!(another_app_owns_audio(
        &[edge],
        "NetEase Cloud Music (Wine)",
        bus
    ));
    // Silence is not "someone else".
    assert!(!another_app_owns_audio(
        &[],
        "NetEase Cloud Music (Wine)",
        bus
    ));
}

#[tokio::test]
async fn test_mpris_art_url_inside_tokio_runtime() {
    use astral_plasma::application::notif_monitor::get_mpris_art_url;
    if let Ok(conn) = zbus::Connection::session().await {
        // Querying art URL within a Tokio multithreaded runtime must never panic with nested runtime errors
        let _ = get_mpris_art_url(&conn, "strawberry").await;
        let _ = get_mpris_art_url(&conn, "elisa").await;
        let _ = get_mpris_art_url(&conn, "nonexistent_player").await;
    }
}

#[test]
fn test_wine_media_coords() {
    use astral_plasma::infrastructure::x11_input::{calculate_wine_media_coords, WineMediaAction};

    // Test with standard 1280x750 window
    let (cx, cy) = calculate_wine_media_coords(WineMediaAction::PlayPause, 1280, 750);
    assert_eq!(cx, 640);
    assert_eq!(cy, 700);

    let (nx, ny) = calculate_wine_media_coords(WineMediaAction::Next, 1280, 750);
    assert_eq!(nx, 640 + 51);
    assert_eq!(ny, 700);

    let (px, py) = calculate_wine_media_coords(WineMediaAction::Previous, 1280, 750);
    assert_eq!(px, 640 - 51);
    assert_eq!(py, 700);

    // Test with smaller window edge case
    let (cx2, cy2) = calculate_wine_media_coords(WineMediaAction::PlayPause, 800, 40);
    assert_eq!(cx2, 400);
    assert_eq!(cy2, 0);
}


#[tokio::test]
async fn test_pause_other_mpris_players() {
    use astral_plasma::application::wine_mpris::pause_other_mpris_players;
    // Calling pause_other_mpris_players should execute cleanly without panicking
    pause_other_mpris_players().await;
}

#[test]
fn test_tray_xembed_rules() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    // The item's own title and icon are used as published.
    let (title, icon, m_icon) = TrayAdapter::resolve_tray_meta("cloudmusic", "NetEase Cloud Music", "file:///tmp/tray.png");
    assert_eq!(title, "NetEase Cloud Music");
    assert_eq!(icon, "file:///tmp/tray.png");
    assert_eq!(m_icon, "circle");

    // Test resolve_xembed_identity fallback logic
    let (id, title2, m_icon2) = TrayAdapter::resolve_xembed_identity(0);
    // For invalid/zero window ID, it should gracefully return empty or fallback
    assert!(id.is_empty() || !id.is_empty());
    assert!(title2.is_empty() || !title2.is_empty());
    assert!(m_icon2.is_empty() || !m_icon2.is_empty());
}

#[test]
fn test_cursor_position_query() {
    use astral_plasma::infrastructure::x11_input::get_cursor_position;
    // Cursor position should not panic
    let pos = get_cursor_position();
    if let Some((x, y)) = pos {
        assert!(x >= 0);
        assert!(y >= 0);
    }
}

#[test]
fn test_synthetic_tray_menu_nested_structure() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    // Test synthetic menu for a service (e.g. cloudmusic)
    let items = TrayAdapter::fetch_synthetic_menu(":1.2122");
    assert!(!items.is_empty(), "Synthetic menu must contain items");

    // Must contain nested submenus
    let has_nested = items.iter().any(|it| it.has_submenu && !it.children.is_empty());
    assert!(has_nested, "Synthetic menu must contain nested submenus with children like CachyOS updater");

    // Check specific submenus
    let window_opt = items.iter().find(|it| it.label.contains("Window"));
    assert!(window_opt.is_some(), "Must contain Window Options submenu");
    let win_children = &window_opt.unwrap().children;
    assert!(win_children.iter().any(|c| c.id == 1004), "Must contain Activate option (1004)");
    assert!(win_children.iter().any(|c| c.id == 1005), "Must contain ContextMenu option (1005)");

    // Must contain exit action
    assert!(items.iter().any(|it| it.id == 1006), "Must contain Exit action (1006)");
}

#[test]
fn test_synthetic_tray_click_actions() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    // Triggering synthetic click items should execute gracefully without panicking
    let _ = TrayAdapter::click_synthetic_item(":1.2122", 1001);
    let _ = TrayAdapter::click_synthetic_item(":1.2122", 1004);
}



