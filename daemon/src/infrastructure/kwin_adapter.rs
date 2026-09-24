use crate::domain::app_identity::shared_index;
use crate::domain::branding;
use crate::domain::meta_resolver::resolve_window_meta_with;
use crate::domain::model::{Desktop, Window};
use crate::domain::ports::{
    CompositorEffectsPort, DesktopSessionPort, DynResult, FocusPort, WindowManagerPort,
    WorkspacePort,
};
use crate::domain::sys_parser::parse_kwin_desktops;
use regex::Regex;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::process::Command;

pub struct KWinAdapter;

/// Build the KWin script that activates a window.
///
/// KWin does not emit `windowActivated` for script-driven activation, so the
/// script reports the activation to the watcher itself. Without that report the
/// daemon's Xwayland focus guard would keep treating the previously active
/// native window as active and hand the keyboard focus straight back - "Bring
/// to Front" would raise the window but leave it unable to receive typing.
pub fn activate_script(target_uuid: &str) -> String {
    format!(
        r#"
var target = "{target_uuid}";
var wins = workspace.windowList();
for (var i = 0; i < wins.length; i++) {{
    var w = wins[i];
    var wid = ("" + w.internalId).replace("{{", "").replace("}}", "");
    if (wid === target) {{
        console.warn("ASTRAL_PLASMA ACTIVATING: " + w.caption);
        workspace.activeWindow = w;
        callDBus("{dbus_name}", "{dbus_path}", "{dbus_name}", "WindowActivated",
                 "" + (w.caption || ""),
                 "" + (w.resourceClass || ""),
                 "" + (w.desktopFileName || ""),
                 ("" + w.internalId).replace("{{","").replace("}}",""));
        break;
    }}
}}
"#,
        dbus_name = branding::DBUS_WATCHER_NAME,
        dbus_path = branding::DBUS_WATCHER_PATH,
    )
}

impl KWinAdapter {
    pub fn new() -> Self {
        Self
    }

    fn query_krunner_icons(&self) -> HashMap<String, String> {
        let mut icons = HashMap::new();
        if let Ok(out) = Command::new("qdbus6")
            .args(["--literal", "org.kde.KWin", "/WindowsRunner", "org.kde.krunner1.Match", ""])
            .output()
        {
            let text = String::from_utf8_lossy(&out.stdout);
            let re = Regex::new(r#"\[Argument:\s*\(sssida\{sv\}\)\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]*)""#).unwrap();
            for cap in re.captures_iter(&text) {
                let title = cap[2].to_string();
                let icon = cap[3].to_string();
                if !icon.is_empty() {
                    icons.insert(title, icon);
                }
            }
        }
        icons
    }
}

impl Default for KWinAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl WindowManagerPort for KWinAdapter {
    fn query_windows(&self) -> DynResult<(Vec<Window>, Option<Window>)> {
        let script = r#"
var cur = workspace.currentDesktop;
var activeId = workspace.activeWindow ? ('' + workspace.activeWindow.internalId).replace('{','').replace('}','') : '';
var wins = workspace.windowList();
var res = [];
for (var i = 0; i < wins.length; i++) {
    var w = wins[i];
    if (w.normalWindow && w.caption && w.resourceClass !== 'quickshell') {
        var onCurrent = w.desktops ? (w.desktops.indexOf(cur) !== -1 || w.onAllDesktops) : true;
        res.push({
            id: ('' + w.internalId).replace('{','').replace('}',''),
            title: w.caption,
            cls: '' + w.resourceClass,
            app: '' + w.desktopFileName,
            active: ('' + w.internalId).replace('{','').replace('}','') === activeId,
            maximized: (w.maximizeMode === 3) && !w.minimized && onCurrent,
            fullScreen: Boolean(w.fullScreen) && !w.minimized && onCurrent
        });
    }
}
console.warn('ASTRAL_PLASMA_WINS:' + JSON.stringify(res));
"#;
        let script_file = branding::tmp_file("kwin_query.js");
        fs::write(&script_file, script)?;

        let num_out = Command::new("qdbus6")
            .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", &script_file.to_string_lossy()])
            .output()?;
        let num = String::from_utf8_lossy(&num_out.stdout).trim().to_string();

        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", &format!("/Scripting/Script{}", num), "org.kde.kwin.Script.run"])
            .output();
        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", &format!("/Scripting/Script{}", num), "org.kde.kwin.Script.stop"])
            .output();

        let j_out = Command::new("journalctl")
            .args(["--user", "-b", "-n", "10", "-o", "cat"])
            .output()?;
        let j_text = String::from_utf8_lossy(&j_out.stdout);

        let mut raw_wins_opt: Option<Value> = None;
        for line in j_text.lines().rev() {
            if let Some(idx) = line.find("ASTRAL_PLASMA_WINS:") {
                let json_str = &line[idx + "ASTRAL_PLASMA_WINS:".len()..];
                if let Ok(v) = serde_json::from_str::<Value>(json_str) {
                    raw_wins_opt = Some(v);
                    break;
                }
            }
        }

        let krunner_icons = self.query_krunner_icons();
        let index = shared_index();
        let mut windows = Vec::new();
        let mut active_win = None;
        let mut seen_ids = HashSet::new();

        if let Some(Value::Array(items)) = raw_wins_opt {
            for item in items {
                let wid = item["id"].as_str().unwrap_or_default().to_string();
                if wid.is_empty() || seen_ids.contains(&wid) {
                    continue;
                }
                seen_ids.insert(wid.clone());

                let title = item["title"].as_str().unwrap_or_default();
                let cls = item["cls"].as_str().unwrap_or_default();
                let app = item["app"].as_str().unwrap_or_default();
                let is_active = item["active"].as_bool().unwrap_or(false);
                let is_maximized = item["maximized"].as_bool().unwrap_or(false);
                let is_fullscreen = item["fullScreen"].as_bool().unwrap_or(false);

                let k_icon = krunner_icons.get(title).map(|s| s.as_str()).unwrap_or("");
                let meta = resolve_window_meta_with(Some(&index), title, cls, app, k_icon);

                let win_obj = Window {
                    id: wid,
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
                    active_win = Some(win_obj.clone());
                }
                windows.push(win_obj);
            }
        }

        Ok((windows, active_win))
    }

    fn activate_window(&self, window_id: &str) -> DynResult<()> {
        let target_uuid = window_id
            .replace("0_", "")
            .replace('{', "")
            .replace('}', "")
            .trim()
            .to_string();

        let script = activate_script(&target_uuid);

        let script_file = branding::tmp_file("kwin_activate.js");
        fs::write(&script_file, script)?;

        let num_out = Command::new("qdbus6")
            .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", &script_file.to_string_lossy()])
            .output()?;
        let num = String::from_utf8_lossy(&num_out.stdout).trim().to_string();

        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", &format!("/Scripting/Script{}", num), "org.kde.kwin.Script.run"])
            .output();
        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", &format!("/Scripting/Script{}", num), "org.kde.kwin.Script.stop"])
            .output();

        Ok(())
    }

    fn close_window(&self, window_id: &str) -> DynResult<()> {
        let target_uuid = window_id
            .replace("0_", "")
            .replace('{', "")
            .replace('}', "")
            .trim()
            .to_string();

        let script = format!(
            r#"
var target = "{target_uuid}";
var wins = workspace.windowList();
for (var i = 0; i < wins.length; i++) {{
    var w = wins[i];
    var wid = ("" + w.internalId).replace("{{", "").replace("}}", "");
    if (wid === target) {{
        w.closeWindow();
        break;
    }}
}}
"#
        );

        let script_file = branding::tmp_file("kwin_close.js");
        fs::write(&script_file, script)?;

        let num_out = Command::new("qdbus6")
            .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", &script_file.to_string_lossy()])
            .output()?;
        let num = String::from_utf8_lossy(&num_out.stdout).trim().to_string();

        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", &format!("/Scripting/Script{}", num), "org.kde.kwin.Script.run"])
            .output();
        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", &format!("/Scripting/Script{}", num), "org.kde.kwin.Script.stop"])
            .output();

        Ok(())
    }
}

impl WorkspacePort for KWinAdapter {
    fn query_desktops(&self) -> DynResult<(String, u32, Vec<Desktop>)> {
        let out = match Command::new("qdbus6")
            .args(["--literal", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.desktops"])
            .output() {
                Ok(o) if o.status.success() => o,
                _ => return Ok((String::new(), 0, Vec::new())),
            };
        let curr_out = match Command::new("qdbus6")
            .args(["org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.current"])
            .output() {
                Ok(o) if o.status.success() => o,
                _ => return Ok((String::new(), 0, Vec::new())),
            };

        let out_str = String::from_utf8_lossy(&out.stdout);
        let curr = String::from_utf8_lossy(&curr_out.stdout).trim().to_string();

        let desktops = parse_kwin_desktops(&out_str, &curr);
        let count = desktops.len() as u32;

        Ok((curr, count, desktops))
    }

    fn switch_to(&self, id: &str) -> DynResult<()> {
        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.current", id])
            .output()?;
        Ok(())
    }

    fn create_and_switch(&self, target_index: u32) -> DynResult<()> {
        let (_, _, current_desktops) = self.query_desktops()?;
        let current_len = current_desktops.len() as u32;

        for i in current_len..=target_index {
            let name = format!("Desktop {}", i + 1);
            let _ = Command::new("qdbus6")
                .args(["org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.createDesktop", &i.to_string(), &name])
                .output();
        }

        let (_, _, updated) = self.query_desktops()?;
        if let Some(target) = updated.get(target_index as usize) {
            self.switch_to(&target.id)?;
        }

        Ok(())
    }
}

impl FocusPort for KWinAdapter {
    fn restore_focus(&self) -> DynResult<()> {
        let script = r#"
var wins = workspace.windowList();
for (var i = 0; i < wins.length; i++) {
    var w = wins[i];
    if (w.normalWindow && w.caption && w.resourceClass !== 'quickshell') {
        workspace.activeWindow = w;
        break;
    }
}
"#;
        let script_file = branding::tmp_file("kwin_focus_restore.js");
        fs::write(&script_file, script)?;
        let num_out = Command::new("qdbus6")
            .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", &script_file.to_string_lossy()])
            .output()?;
        let num = String::from_utf8_lossy(&num_out.stdout).trim().to_string();
        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", &format!("/Scripting/Script{}", num), "org.kde.kwin.Script.run"])
            .output();
        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", &format!("/Scripting/Script{}", num), "org.kde.kwin.Script.stop"])
            .output();
        Ok(())
    }

    fn can_restore_focus(&self) -> bool {
        true
    }
}

impl CompositorEffectsPort for KWinAdapter {
    fn is_blur_supported(&self) -> bool {
        true
    }

    fn blur_mode(&self) -> String {
        "kwin_blurRegion".to_string()
    }
}

impl DesktopSessionPort for KWinAdapter {
    fn get_snapshot(&self) -> DynResult<crate::domain::model::DesktopSessionSnapshot> {
        let (windows, _) = self.query_windows()?;
        let (_, _, desktops) = self.query_desktops().unwrap_or_else(|_| (String::new(), 0, Vec::new()));
        let workspaces = desktops.into_iter().map(|d| crate::domain::model::Workspace {
            id: d.id,
            name: d.name,
            index: d.index,
            output_id: None,
            active: d.active,
        }).collect();

        let mut capabilities = HashMap::new();
        capabilities.insert("workspaceSwitch".to_string(), crate::domain::model::Capability {
            available: true,
            mode: Some("virtual_desktops".to_string()),
            reason: None,
            owner: Some("kwin".to_string()),
        });
        capabilities.insert("backgroundBlur".to_string(), crate::domain::model::Capability {
            available: true,
            mode: Some("kwin_blurRegion".to_string()),
            reason: None,
            owner: Some("kwin".to_string()),
        });
        capabilities.insert("focusRestore".to_string(), crate::domain::model::Capability {
            available: true,
            mode: Some("kwin_scripting".to_string()),
            reason: None,
            owner: Some("kwin".to_string()),
        });
        capabilities.insert("windowPreview".to_string(), crate::domain::model::Capability {
            available: true,
            mode: Some("ScreenShot2".to_string()),
            reason: None,
            owner: Some("kwin".to_string()),
        });

        Ok(crate::domain::model::DesktopSessionSnapshot {
            schema_version: 1,
            session_id: "kde-kwin".to_string(),
            revision: 1,
            connection: crate::domain::model::SessionConnectionState::Connected,
            profile: "kde".to_string(),
            focused_output_id: None,
            outputs: vec![],
            workspaces,
            windows,
            capabilities,
            last_updated: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or(0),
        })
    }

    fn get_capabilities(&self) -> DynResult<HashMap<String, crate::domain::model::Capability>> {
        let snap = self.get_snapshot()?;
        Ok(snap.capabilities)
    }

    fn execute_intent(&self, intent: crate::domain::model::UserIntent) -> DynResult<crate::domain::model::ActionResult> {
        match intent.kind.as_str() {
            "activate-window" => {
                if let Some(id) = intent.target.get("windowId").and_then(|v| v.as_str()) {
                    self.activate_window(id)?;
                    Ok(crate::domain::model::ActionResult {
                        request_id: intent.request_id,
                        status: crate::domain::model::ActionStatus::Applied,
                        message_key: "window-activated".to_string(),
                        details: serde_json::json!({ "windowId": id }),
                        revision: 1,
                    })
                } else {
                    Ok(crate::domain::model::ActionResult {
                        request_id: intent.request_id,
                        status: crate::domain::model::ActionStatus::Invalid,
                        message_key: "missing-window-id".to_string(),
                        details: serde_json::json!({}),
                        revision: 1,
                    })
                }
            }
            "close-window" => {
                if let Some(id) = intent.target.get("windowId").and_then(|v| v.as_str()) {
                    self.close_window(id)?;
                    Ok(crate::domain::model::ActionResult {
                        request_id: intent.request_id,
                        status: crate::domain::model::ActionStatus::Applied,
                        message_key: "window-closed".to_string(),
                        details: serde_json::json!({ "windowId": id }),
                        revision: 1,
                    })
                } else {
                    Ok(crate::domain::model::ActionResult {
                        request_id: intent.request_id,
                        status: crate::domain::model::ActionStatus::Invalid,
                        message_key: "missing-window-id".to_string(),
                        details: serde_json::json!({}),
                        revision: 1,
                    })
                }
            }
            "switch-workspace" => {
                if let Some(id) = intent.target.get("workspaceId").and_then(|v| v.as_str()) {
                    self.switch_to(id)?;
                    Ok(crate::domain::model::ActionResult {
                        request_id: intent.request_id,
                        status: crate::domain::model::ActionStatus::Applied,
                        message_key: "workspace-switched".to_string(),
                        details: serde_json::json!({ "workspaceId": id }),
                        revision: 1,
                    })
                } else {
                    Ok(crate::domain::model::ActionResult {
                        request_id: intent.request_id,
                        status: crate::domain::model::ActionStatus::Invalid,
                        message_key: "missing-workspace-id".to_string(),
                        details: serde_json::json!({}),
                        revision: 1,
                    })
                }
            }
            "restore-focus" => {
                self.restore_focus()?;
                Ok(crate::domain::model::ActionResult {
                    request_id: intent.request_id,
                    status: crate::domain::model::ActionStatus::Applied,
                    message_key: "focus-restored".to_string(),
                    details: serde_json::json!({}),
                    revision: 1,
                })
            }
            _ => Ok(crate::domain::model::ActionResult {
                request_id: intent.request_id,
                status: crate::domain::model::ActionStatus::Unsupported,
                message_key: "unsupported-intent".to_string(),
                details: serde_json::json!({ "kind": intent.kind }),
                revision: 1,
            }),
        }
    }
}

