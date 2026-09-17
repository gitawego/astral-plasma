use crate::domain::meta_resolver::resolve_window_meta;
use crate::domain::model::{Desktop, Window};
use crate::domain::ports::{DynResult, WindowManagerPort, WorkspacePort};
use crate::domain::sys_parser::parse_kwin_desktops;
use regex::Regex;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::process::Command;

pub struct KWinAdapter;

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
console.warn('CAELESTIA_WINS:' + JSON.stringify(res));
"#;
        let script_file = "/tmp/caelestia_kwin_query.js";
        fs::write(script_file, script)?;

        let num_out = Command::new("qdbus6")
            .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", script_file])
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
            if let Some(idx) = line.find("CAELESTIA_WINS:") {
                let json_str = &line[idx + "CAELESTIA_WINS:".len()..];
                if let Ok(v) = serde_json::from_str::<Value>(json_str) {
                    raw_wins_opt = Some(v);
                    break;
                }
            }
        }

        let krunner_icons = self.query_krunner_icons();
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
                let meta = resolve_window_meta(title, cls, app, k_icon);

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

        let script = format!(
            r#"
var target = "{target_uuid}";
var wins = workspace.windowList();
for (var i = 0; i < wins.length; i++) {{
    var w = wins[i];
    var wid = ("" + w.internalId).replace("{{", "").replace("}}", "");
    if (wid === target) {{
        console.warn("CAELESTIA ACTIVATING: " + w.caption);
        workspace.activeWindow = w;
        break;
    }}
}}
"#
        );

        let script_file = "/tmp/caelestia_activate.js";
        fs::write(script_file, script)?;

        let num_out = Command::new("qdbus6")
            .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", script_file])
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

        let script_file = "/tmp/caelestia_close.js";
        fs::write(script_file, script)?;

        let num_out = Command::new("qdbus6")
            .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", script_file])
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
        let out = Command::new("qdbus6")
            .args(["--literal", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.desktops"])
            .output()?;
        let curr_out = Command::new("qdbus6")
            .args(["org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.current"])
            .output()?;

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
