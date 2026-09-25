//! Unit tests for watch_events: payload serialization, state transitions,
//! KWin script generation, and D-Bus IPC interface contracts.

use astral_plasma::application::watch_events::{get_kwin_watcher_script, DaemonState};
use astral_plasma::domain::branding;
use astral_plasma::domain::model::{ActiveWindowPayload, FullStatePayload, Window, WindowsListPayload};

#[test]
fn test_daemon_state_default() {
    let state = DaemonState::default();
    assert_eq!(state.active_title, "Desktop");
    assert_eq!(state.active_material_icon, "desktop_windows");
    assert_eq!(state.active_icon_name, "");
    assert_eq!(state.active_app_id, "");
    assert_eq!(state.active_id, "");
    assert!(state.cached_windows.is_empty());
    assert!(state.cached_tray.is_empty());
}

#[test]
fn test_active_window_payload_serialization() {
    let payload = ActiveWindowPayload {
        msg_type: "active".to_string(),
        active_title: "Visual Studio Code".to_string(),
        active_material_icon: "code".to_string(),
        active_icon_name: "com.microsoft.VSCode".to_string(),
        active_app_id: "com.microsoft.VSCode".to_string(),
        active_id: "win-12345".to_string(),
        windows: vec![Window {
            id: "win-12345".to_string(),
            title: "astral-plasma - Visual Studio Code".to_string(),
            app_name: "Visual Studio Code".to_string(),
            icon_name: "com.microsoft.VSCode".to_string(),
            material_icon: "code".to_string(),
            app_id: "com.microsoft.VSCode".to_string(),
            desktop_file: "com.microsoft.VSCode.desktop".to_string(),
            is_active: true,
            is_maximized: true,
            is_fullscreen: false,
        }],
        has_maximized_window: true,
    };

    let json_str = serde_json::to_string(&payload).expect("payload must serialize to JSON");
    assert!(json_str.contains(r#""type":"active""#));
    assert!(json_str.contains(r#""activeTitle":"Visual Studio Code""#));
    assert!(json_str.contains(r#""activeMaterialIcon":"code""#));
    assert!(json_str.contains(r#""activeIconName":"com.microsoft.VSCode""#));
    assert!(json_str.contains(r#""activeAppId":"com.microsoft.VSCode""#));
    assert!(json_str.contains(r#""hasMaximizedWindow":true"#));

    // Verify roundtrip deserialization
    let deserialized: ActiveWindowPayload =
        serde_json::from_str(&json_str).expect("payload must deserialize from JSON");
    assert_eq!(deserialized.active_title, "Visual Studio Code");
    assert_eq!(deserialized.active_material_icon, "code");
    assert_eq!(deserialized.active_icon_name, "com.microsoft.VSCode");
    assert!(deserialized.has_maximized_window);
    assert_eq!(deserialized.windows.len(), 1);
    assert_eq!(deserialized.windows[0].app_name, "Visual Studio Code");
}

#[test]
fn test_windows_list_payload_serialization() {
    let payload = WindowsListPayload {
        msg_type: "windows".to_string(),
        windows: vec![],
        active_title: "Terminal".to_string(),
        active_material_icon: "terminal".to_string(),
        active_icon_name: "com.mitchellh.ghostty".to_string(),
        active_app_id: "com.mitchellh.ghostty".to_string(),
        active_id: "win-789".to_string(),
        has_maximized_window: false,
    };

    let json_str = serde_json::to_string(&payload).expect("must serialize");
    assert!(json_str.contains(r#""activeTitle":"Terminal""#));
    assert!(json_str.contains(r#""activeMaterialIcon":"terminal""#));
    assert!(json_str.contains(r#""activeIconName":"com.mitchellh.ghostty""#));
    assert!(json_str.contains(r#""activeId":"win-789""#));

    let deserialized: WindowsListPayload =
        serde_json::from_str(&json_str).expect("must deserialize");
    assert_eq!(deserialized.active_id, "win-789");
    assert_eq!(deserialized.active_title, "Terminal");
}

#[test]
fn test_full_state_payload_serialization() {
    let payload = FullStatePayload {
        windows: vec![],
        tray: vec![],
        active_title: "Desktop".to_string(),
        active_material_icon: "desktop_windows".to_string(),
        active_icon_name: "".to_string(),
        active_app_id: "".to_string(),
        active_id: "win-init".to_string(),
        has_maximized_window: false,
    };

    let json_str = serde_json::to_string(&payload).expect("must serialize");
    assert!(json_str.contains(r#""activeTitle":"Desktop""#));
    assert!(json_str.contains(r#""activeMaterialIcon":"desktop_windows""#));
    assert!(json_str.contains(r#""activeId":"win-init""#));

    let deserialized: FullStatePayload =
        serde_json::from_str(&json_str).expect("must deserialize");
    assert_eq!(deserialized.active_id, "win-init");
    assert_eq!(deserialized.active_title, "Desktop");
}

#[test]
fn test_kwin_watcher_script_contracts() {
    let script = get_kwin_watcher_script();

    // Must interpolate the canonical D-Bus watcher name
    assert!(
        script.contains(branding::DBUS_WATCHER_NAME),
        "Script must contain DBUS_WATCHER_NAME '{}'",
        branding::DBUS_WATCHER_NAME
    );

    // Must bind to KWin workspace signals
    assert!(
        script.contains("workspace.windowActivated.connect"),
        "Script must connect to windowActivated"
    );
    assert!(
        script.contains("workspace.windowAdded.connect"),
        "Script must connect to windowAdded"
    );
    assert!(
        script.contains("workspace.windowRemoved.connect"),
        "Script must connect to windowRemoved"
    );

    // Must invoke WindowActivated and UpdateWindowList over D-Bus
    assert!(
        script.contains(r#"WindowActivated"#),
        "Script must call WindowActivated"
    );
    assert!(
        script.contains(r#"UpdateWindowList"#),
        "Script must call UpdateWindowList"
    );

    // Must filter shell-owned surfaces to avoid polluting active window
    assert!(
        script.contains("isShellSurface"),
        "Script must define isShellSurface filter"
    );
}
