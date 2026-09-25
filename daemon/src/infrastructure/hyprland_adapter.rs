use crate::domain::app_identity::{shared_index, should_skip_taskbar};
use crate::domain::meta_resolver::resolve_window_meta_with;
use crate::domain::model::{
    ActionResult, ActionStatus, Capability, Desktop, DesktopSessionSnapshot, Output,
    OutputGeometry, SessionConnectionState, UserIntent, Window, Workspace,
};
use crate::infrastructure::window_icons;
use crate::domain::ports::{
    CompositorEffectsPort, DesktopSessionPort, DynResult, FocusPort, OutputPort,
    WindowManagerPort, WorkspacePort,
};
use serde_json::Value;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

pub struct HyprlandAdapter {
    custom_socket_dir: Option<PathBuf>,
}

impl HyprlandAdapter {
    pub fn new() -> Self {
        Self {
            custom_socket_dir: None,
        }
    }

    pub fn with_socket_dir(path: PathBuf) -> Self {
        Self {
            custom_socket_dir: Some(path),
        }
    }

    /// Resolves the directory containing `.socket.sock` and `.socket2.sock`.
    pub fn resolve_socket_dir(&self) -> Option<PathBuf> {
        if let Some(ref dir) = self.custom_socket_dir {
            return Some(dir.clone());
        }

        let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })));

        if let Ok(sig) = std::env::var("HYPRLAND_INSTANCE_SIGNATURE") {
            let p = runtime_dir.join("hypr").join(sig);
            if p.join(".socket.sock").exists() {
                return Some(p);
            }
        }

        // Fallback: discover latest hypr instance directory
        let hypr_dir = runtime_dir.join("hypr");
        if let Ok(entries) = std::fs::read_dir(&hypr_dir) {
            let mut candidates: Vec<PathBuf> = entries
                .flatten()
                .filter(|e| e.path().is_dir() && e.path().join(".socket.sock").exists())
                .map(|e| e.path())
                .collect();
            candidates.sort_by_key(|p| {
                p.metadata()
                    .and_then(|m| m.modified())
                    .unwrap_or(std::time::SystemTime::UNIX_EPOCH)
            });
            if let Some(latest) = candidates.pop() {
                return Some(latest);
            }
        }

        None
    }

    /// Sends a query or command to `.socket.sock` and returns the response string.
    pub fn send_command(&self, cmd: &str) -> DynResult<String> {
        let socket_dir = self
            .resolve_socket_dir()
            .ok_or_else(|| "Hyprland socket directory not found".to_string())?;
        let socket_path = socket_dir.join(".socket.sock");

        let mut stream = UnixStream::connect(socket_path)?;
        stream.set_read_timeout(Some(Duration::from_millis(1500)))?;
        stream.set_write_timeout(Some(Duration::from_millis(1500)))?;

        let payload = cmd.trim_end_matches('\n');
        stream.write_all(payload.as_bytes())?;
        stream.flush()?;
        let _ = stream.shutdown(std::net::Shutdown::Write);

        let mut response = String::new();
        stream.read_to_string(&mut response)?;
        Ok(response)
    }

    /// Helper to parse monitors JSON array from Hyprland
    fn query_monitors_json(&self) -> DynResult<Vec<Value>> {
        let out = self.send_command("j/monitors")?;
        let val: Value = serde_json::from_str(&out)?;
        Ok(val.as_array().cloned().unwrap_or_default())
    }

    /// Helper to parse workspaces JSON array from Hyprland
    fn query_workspaces_json(&self) -> DynResult<Vec<Value>> {
        let out = self.send_command("j/workspaces")?;
        let val: Value = serde_json::from_str(&out)?;
        Ok(val.as_array().cloned().unwrap_or_default())
    }

    /// Helper to parse clients JSON array from Hyprland
    fn query_clients_json(&self) -> DynResult<Vec<Value>> {
        let out = self.send_command("j/clients")?;
        let val: Value = serde_json::from_str(&out)?;
        Ok(val.as_array().cloned().unwrap_or_default())
    }

    /// Helper to query activewindow JSON object from Hyprland
    fn query_active_window_json(&self) -> DynResult<Option<Value>> {
        let out = self.send_command("j/activewindow")?;
        if out.trim().is_empty() || out.trim() == "{}" {
            return Ok(None);
        }
        let val: Value = serde_json::from_str(&out)?;
        Ok(Some(val))
    }
}

impl Default for HyprlandAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl WindowManagerPort for HyprlandAdapter {
    fn query_windows(&self) -> DynResult<(Vec<Window>, Option<Window>)> {
        let clients = self.query_clients_json().unwrap_or_default();
        let active_win_json = self.query_active_window_json().unwrap_or(None);
        let active_addr = active_win_json
            .as_ref()
            .and_then(|v| v.get("address"))
            .and_then(|a| a.as_str())
            .unwrap_or("");

        let index = shared_index();
        let mut windows = Vec::new();
        let mut active_window = None;

        for c in clients {
            let addr = c.get("address").and_then(|v| v.as_str()).unwrap_or("");
            if addr.is_empty() {
                continue;
            }

            let class = c.get("class").and_then(|v| v.as_str()).unwrap_or("");
            let title = c.get("title").and_then(|v| v.as_str()).unwrap_or("");
            let initial_class = c.get("initialClass").and_then(|v| v.as_str()).unwrap_or("");
            let desktop_file = if !initial_class.is_empty() {
                initial_class
            } else {
                class
            };

            if should_skip_taskbar(false, class, desktop_file, title) {
                continue;
            }

            let is_active = addr == active_addr;
            let fullscreen_num = c.get("fullscreen").and_then(|v| v.as_i64()).unwrap_or(0);
            let is_fullscreen = fullscreen_num == 1;
            let is_maximized = fullscreen_num == 2;

            let mut meta = resolve_window_meta_with(Some(&index), title, class, desktop_file, "");
            if let Some(icon) = window_icons::resolve_window_icon(class, &meta.icon_name) {
                meta.icon_name = icon.to_string_lossy().to_string();
            }

            let win = Window {
                id: addr.to_string(),
                title: title.to_string(),
                app_name: meta.app_name,
                icon_name: meta.icon_name,
                material_icon: meta.material_icon,
                app_id: meta.app_id,
                desktop_file: meta.desktop_file,
                is_active,
                is_maximized,
                is_fullscreen,
            };

            if is_active {
                active_window = Some(win.clone());
            }
            windows.push(win);
        }

        Ok((windows, active_window))
    }

    fn activate_window(&self, window_id: &str) -> DynResult<()> {
        let cmd = format!("dispatch focuswindow address:{}", window_id);
        self.send_command(&cmd)?;
        Ok(())
    }

    fn close_window(&self, window_id: &str) -> DynResult<()> {
        let cmd = format!("dispatch closewindow address:{}", window_id);
        self.send_command(&cmd)?;
        Ok(())
    }
}

impl WorkspacePort for HyprlandAdapter {
    fn query_desktops(&self) -> DynResult<(String, u32, Vec<Desktop>)> {
        let monitors = self.query_monitors_json()?;
        let focused_mon = monitors.iter().find(|m| m.get("focused").and_then(|f| f.as_bool()).unwrap_or(false));
        let active_ws_id = focused_mon
            .and_then(|m| m.get("activeWorkspace"))
            .and_then(|w| w.get("id"))
            .and_then(|i| i.as_i64())
            .unwrap_or(1);

        let ws_list = self.query_workspaces_json()?;
        let mut desktops = Vec::new();

        for w in ws_list {
            let id_num = w.get("id").and_then(|v| v.as_i64()).unwrap_or(1);
            let name = w.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let is_active = id_num == active_ws_id;

            desktops.push(Desktop {
                index: id_num.max(1) as u32,
                id: id_num.to_string(),
                name: if name.is_empty() { id_num.to_string() } else { name },
                active: is_active,
            });
        }

        desktops.sort_by_key(|d| d.index);
        let count = desktops.len() as u32;
        let curr = active_ws_id.to_string();

        Ok((curr, count, desktops))
    }

    fn switch_to(&self, id: &str) -> DynResult<()> {
        let cmd = format!("dispatch workspace {}", id);
        self.send_command(&cmd)?;
        Ok(())
    }

    fn create_and_switch(&self, index: u32) -> DynResult<()> {
        let cmd = format!("dispatch workspace {}", index);
        self.send_command(&cmd)?;
        Ok(())
    }
}

impl OutputPort for HyprlandAdapter {
    fn query_outputs(&self) -> DynResult<Vec<Output>> {
        let monitors = self.query_monitors_json()?;
        let mut outputs = Vec::new();

        for (idx, m) in monitors.into_iter().enumerate() {
            let name = m.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let x = m.get("x").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
            let y = m.get("y").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
            let width = m.get("width").and_then(|v| v.as_i64()).unwrap_or(1920) as u32;
            let height = m.get("height").and_then(|v| v.as_i64()).unwrap_or(1080) as u32;
            let scale = m.get("scale").and_then(|v| v.as_f64()).unwrap_or(1.0);
            let refresh_rate = m.get("refreshRate").and_then(|v| v.as_f64()).unwrap_or(60.0);
            let focused = m.get("focused").and_then(|v| v.as_bool()).unwrap_or(false);

            outputs.push(Output {
                id: name.clone(),
                name,
                geometry: OutputGeometry {
                    x,
                    y,
                    width,
                    height,
                },
                scale,
                refresh_rate,
                focused,
                primary: idx == 0 || focused,
            });
        }

        Ok(outputs)
    }

    fn focused_output(&self) -> DynResult<Option<Output>> {
        let outputs = self.query_outputs()?;
        Ok(outputs.into_iter().find(|o| o.focused))
    }
}

impl FocusPort for HyprlandAdapter {
    fn restore_focus(&self) -> DynResult<()> {
        // Bring focus to top window on current workspace
        let _ = self.send_command("dispatch focuswindow urgent");
        Ok(())
    }

    fn can_restore_focus(&self) -> bool {
        true
    }
}

impl CompositorEffectsPort for HyprlandAdapter {
    fn is_blur_supported(&self) -> bool {
        true
    }

    fn blur_mode(&self) -> String {
        "layerrule".to_string()
    }
}

impl DesktopSessionPort for HyprlandAdapter {
    fn get_snapshot(&self) -> DynResult<DesktopSessionSnapshot> {
        let (windows, _) = self.query_windows().unwrap_or_default();
        let (_, _, desktops) = self
            .query_desktops()
            .unwrap_or_else(|_| ("1".to_string(), 1, Vec::new()));
        let outputs = self.query_outputs().unwrap_or_default();
        let focused_out = outputs.iter().find(|o| o.focused).map(|o| o.id.clone());

        let workspaces = desktops
            .into_iter()
            .map(|d| Workspace {
                id: d.id,
                name: d.name,
                index: d.index,
                output_id: focused_out.clone(),
                active: d.active,
            })
            .collect();

        let mut capabilities = HashMap::new();
        capabilities.insert(
            "workspaceSwitch".to_string(),
            Capability {
                available: true,
                mode: Some("dispatcher".to_string()),
                reason: None,
                owner: Some("hyprland".to_string()),
            },
        );
        capabilities.insert(
            "backgroundBlur".to_string(),
            Capability {
                available: true,
                mode: Some("layerrule".to_string()),
                reason: None,
                owner: Some("hyprland".to_string()),
            },
        );
        capabilities.insert(
            "focusRestore".to_string(),
            Capability {
                available: true,
                mode: Some("dispatcher".to_string()),
                reason: None,
                owner: Some("hyprland".to_string()),
            },
        );
        capabilities.insert(
            "windowPreview".to_string(),
            Capability {
                available: true,
                mode: Some("screencopy".to_string()),
                reason: None,
                owner: Some("hyprland".to_string()),
            },
        );
        capabilities.insert(
            "globalShortcuts".to_string(),
            Capability {
                available: true,
                mode: Some("hyprland".to_string()),
                reason: None,
                owner: Some("hyprland".to_string()),
            },
        );

        Ok(DesktopSessionSnapshot {
            schema_version: 1,
            session_id: "hyprland".to_string(),
            revision: 1,
            connection: SessionConnectionState::Connected,
            profile: "hyprland".to_string(),
            focused_output_id: focused_out,
            outputs,
            workspaces,
            windows,
            capabilities,
            last_updated: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or(0),
        })
    }

    fn get_capabilities(&self) -> DynResult<HashMap<String, Capability>> {
        let snap = self.get_snapshot()?;
        Ok(snap.capabilities)
    }

    fn execute_intent(&self, intent: UserIntent) -> DynResult<ActionResult> {
        match intent.kind.as_str() {
            "activate-window" => {
                if let Some(id) = intent.target.get("windowId").and_then(|v| v.as_str()) {
                    self.activate_window(id)?;
                    Ok(ActionResult {
                        request_id: intent.request_id,
                        status: ActionStatus::Applied,
                        message_key: "window-activated".to_string(),
                        details: serde_json::json!({ "windowId": id }),
                        revision: 1,
                    })
                } else {
                    Ok(ActionResult {
                        request_id: intent.request_id,
                        status: ActionStatus::Invalid,
                        message_key: "missing-window-id".to_string(),
                        details: serde_json::json!({}),
                        revision: 1,
                    })
                }
            }
            "close-window" => {
                if let Some(id) = intent.target.get("windowId").and_then(|v| v.as_str()) {
                    self.close_window(id)?;
                    Ok(ActionResult {
                        request_id: intent.request_id,
                        status: ActionStatus::Applied,
                        message_key: "window-closed".to_string(),
                        details: serde_json::json!({ "windowId": id }),
                        revision: 1,
                    })
                } else {
                    Ok(ActionResult {
                        request_id: intent.request_id,
                        status: ActionStatus::Invalid,
                        message_key: "missing-window-id".to_string(),
                        details: serde_json::json!({}),
                        revision: 1,
                    })
                }
            }
            "switch-workspace" => {
                if let Some(id) = intent.target.get("workspaceId").and_then(|v| v.as_str()) {
                    self.switch_to(id)?;
                    Ok(ActionResult {
                        request_id: intent.request_id,
                        status: ActionStatus::Applied,
                        message_key: "workspace-switched".to_string(),
                        details: serde_json::json!({ "workspaceId": id }),
                        revision: 1,
                    })
                } else {
                    Ok(ActionResult {
                        request_id: intent.request_id,
                        status: ActionStatus::Invalid,
                        message_key: "missing-workspace-id".to_string(),
                        details: serde_json::json!({}),
                        revision: 1,
                    })
                }
            }
            "restore-focus" => {
                self.restore_focus()?;
                Ok(ActionResult {
                    request_id: intent.request_id,
                    status: ActionStatus::Applied,
                    message_key: "focus-restored".to_string(),
                    details: serde_json::json!({}),
                    revision: 1,
                })
            }
            _ => Ok(ActionResult {
                request_id: intent.request_id,
                status: ActionStatus::Unsupported,
                message_key: "unsupported-intent".to_string(),
                details: serde_json::json!({ "kind": intent.kind }),
                revision: 1,
            }),
        }
    }
}
