use astral_plasma::domain::model::*;
use astral_plasma::domain::ports::*;
use astral_plasma::infrastructure::hyprland_adapter::HyprlandAdapter;
use std::io::{Read, Write};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::thread;

/// Spawns a mock Hyprland UNIX socket server on a temp directory.
fn spawn_mock_hyprland_socket(socket_dir: PathBuf) -> thread::JoinHandle<()> {
    let socket_path = socket_dir.join(".socket.sock");
    let listener = UnixListener::bind(socket_path).expect("bind mock unix socket");

    thread::spawn(move || {
        while let Ok((mut stream, _)) = listener.accept() {
            let mut line = String::new();
            if stream.read_to_string(&mut line).is_err() {
                continue;
            }
            let cmd = line.trim().to_string();
            if cmd.is_empty() {
                continue;
            }
            let response = match cmd.as_str() {
                "j/monitors" => r#"[{
                    "id": 0,
                    "name": "WAYLAND-1",
                    "description": "",
                    "width": 1280,
                    "height": 720,
                    "refreshRate": 60.0,
                    "x": 0,
                    "y": 0,
                    "activeWorkspace": { "id": 1, "name": "1" },
                    "scale": 1.0,
                    "focused": true
                }]"#,
                "j/workspaces" => r#"[{
                    "id": 1,
                    "name": "1",
                    "monitor": "WAYLAND-1",
                    "windows": 1
                }, {
                    "id": 2,
                    "name": "2",
                    "monitor": "WAYLAND-1",
                    "windows": 0
                }]"#,
                "j/clients" => r#"[{
                    "address": "0x55a4336b65d0",
                    "class": "Alacritty",
                    "title": "Terminal",
                    "initialClass": "Alacritty",
                    "workspace": { "id": 1, "name": "1" },
                    "floating": false,
                    "fullscreen": 0
                }, {
                    "address": "0x55a4336b9999",
                    "class": "Ghostty",
                    "title": "Workspace",
                    "initialClass": "com.mitchellh.ghostty",
                    "workspace": { "id": 1, "name": "1" },
                    "floating": false,
                    "fullscreen": 2
                }]"#,
                "j/activewindow" => r#"{
                    "address": "0x55a4336b65d0",
                    "class": "Alacritty",
                    "title": "Terminal"
                }"#,
                c if c.starts_with("dispatch ") => "ok\n",
                _ => "unknown command\n",
            };
            let _ = stream.write_all(response.as_bytes());
            let _ = stream.flush();
            let _ = stream.shutdown(std::net::Shutdown::Write);
        }
    })
}

#[test]
fn test_hyprland_adapter_window_manager_port() {
    let temp_dir = tempfile::tempdir().unwrap();
    let _server = spawn_mock_hyprland_socket(temp_dir.path().to_path_buf());

    let adapter = HyprlandAdapter::with_socket_dir(temp_dir.path().to_path_buf());

    let (windows, active) = adapter.query_windows().expect("query windows");
    assert_eq!(windows.len(), 2);

    assert_eq!(windows[0].id, "0x55a4336b65d0");
    assert_eq!(windows[0].title, "Terminal");
    assert!(windows[0].is_active);
    assert!(!windows[0].is_maximized);

    assert_eq!(windows[1].id, "0x55a4336b9999");
    assert!(!windows[1].is_active);
    assert!(windows[1].is_maximized, "fullscreen 2 maps to maximized");

    assert!(active.is_some());
    assert_eq!(active.unwrap().id, "0x55a4336b65d0");

    // Test activate and close dispatch
    adapter.activate_window("0x55a4336b9999").expect("activate window");
    adapter.close_window("0x55a4336b9999").expect("close window");
}

#[test]
fn test_hyprland_adapter_workspace_port() {
    let temp_dir = tempfile::tempdir().unwrap();
    let _server = spawn_mock_hyprland_socket(temp_dir.path().to_path_buf());

    let adapter = HyprlandAdapter::with_socket_dir(temp_dir.path().to_path_buf());

    let (curr, count, desktops) = adapter.query_desktops().expect("query desktops");
    assert_eq!(curr, "1");
    assert_eq!(count, 2);
    assert_eq!(desktops.len(), 2);
    assert_eq!(desktops[0].id, "1");
    assert!(desktops[0].active);
    assert_eq!(desktops[1].id, "2");
    assert!(!desktops[1].active);

    adapter.switch_to("2").expect("switch to workspace");
    adapter.create_and_switch(3).expect("create and switch");
}

#[test]
fn test_hyprland_adapter_output_and_effects_ports() {
    let temp_dir = tempfile::tempdir().unwrap();
    let _server = spawn_mock_hyprland_socket(temp_dir.path().to_path_buf());

    let adapter = HyprlandAdapter::with_socket_dir(temp_dir.path().to_path_buf());

    let outputs = adapter.query_outputs().expect("query outputs");
    assert_eq!(outputs.len(), 1);
    assert_eq!(outputs[0].id, "WAYLAND-1");
    assert_eq!(outputs[0].geometry.width, 1280);
    assert_eq!(outputs[0].geometry.height, 720);
    assert!(outputs[0].focused);

    let focused = adapter.focused_output().expect("focused output");
    assert!(focused.is_some());
    assert_eq!(focused.unwrap().id, "WAYLAND-1");

    assert!(adapter.is_blur_supported());
    assert_eq!(adapter.blur_mode(), "layerrule");
    assert!(adapter.can_restore_focus());
    adapter.restore_focus().expect("restore focus");
}

#[test]
fn test_hyprland_adapter_desktop_session_port_and_intents() {
    let temp_dir = tempfile::tempdir().unwrap();
    let _server = spawn_mock_hyprland_socket(temp_dir.path().to_path_buf());

    let adapter = HyprlandAdapter::with_socket_dir(temp_dir.path().to_path_buf());

    let snap = adapter.get_snapshot().expect("get snapshot");
    assert_eq!(snap.profile, "hyprland");
    assert_eq!(snap.connection, SessionConnectionState::Connected);
    assert_eq!(snap.focused_output_id, Some("WAYLAND-1".to_string()));
    assert_eq!(snap.outputs.len(), 1);
    assert_eq!(snap.workspaces.len(), 2);
    assert_eq!(snap.windows.len(), 2);
    assert!(snap.capabilities.get("workspaceSwitch").unwrap().available);
    assert_eq!(
        snap.capabilities.get("backgroundBlur").unwrap().mode.as_deref(),
        Some("layerrule")
    );

    // Test execute_intent
    let res_activate = adapter
        .execute_intent(UserIntent {
            request_id: "req-1".to_string(),
            kind: "activate-window".to_string(),
            target: serde_json::json!({ "windowId": "0x55a4336b65d0" }),
            parameters: serde_json::json!({}),
        })
        .expect("execute intent");
    assert_eq!(res_activate.status, ActionStatus::Applied);

    let res_unsupported = adapter
        .execute_intent(UserIntent {
            request_id: "req-2".to_string(),
            kind: "arbitrary-unknown-command".to_string(),
            target: serde_json::json!({}),
            parameters: serde_json::json!({}),
        })
        .expect("execute intent");
    assert_eq!(res_unsupported.status, ActionStatus::Unsupported);
}
