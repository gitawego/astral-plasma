use crate::domain::meta_resolver::resolve_window_meta;
use crate::domain::model::{
    ActiveWindowPayload, FullStatePayload, TrayItem, TrayPayload, Window, WindowsListPayload,
};
use crate::domain::ports::{DynResult, TrayPort, WindowManagerPort};
use crate::infrastructure::kwin_adapter::KWinAdapter;
use crate::infrastructure::tray_adapter::TrayAdapter;
use serde_json::Value;
use std::collections::HashSet;
use std::fs;
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::sync::Mutex;
use zbus::connection::Builder;

const KWIN_SCRIPT_NAME: &str = "caelestia-watcher";

pub struct DaemonState {
    pub cached_windows: Vec<Window>,
    pub cached_tray: Vec<TrayItem>,
    pub active_title: String,
    pub active_material_icon: String,
    pub active_icon_name: String,
    pub active_app_id: String,
    pub active_id: String,
}

impl Default for DaemonState {
    fn default() -> Self {
        Self {
            cached_windows: Vec::new(),
            cached_tray: Vec::new(),
            active_title: "Desktop".to_string(),
            active_material_icon: "desktop_windows".to_string(),
            active_icon_name: String::new(),
            active_app_id: String::new(),
            active_id: String::new(),
        }
    }
}

pub struct WatcherService {
    state: Arc<Mutex<DaemonState>>,
}

#[zbus::interface(name = "org.caelestia.WindowWatcher")]
impl WatcherService {
    async fn window_activated(&self, title: &str, cls: &str, app: &str, wid: &str) {
        let meta = resolve_window_meta(title, cls, app, "");
        let mut st = self.state.lock().await;

        st.active_title = meta.app_name.clone();
        st.active_material_icon = meta.material_icon.clone();
        st.active_icon_name = meta.icon_name.clone();
        st.active_app_id = meta.app_id.clone();
        st.active_id = wid.to_string();

        for w in &mut st.cached_windows {
            w.is_active = w.id == wid;
        }

        let payload = ActiveWindowPayload {
            msg_type: "active".to_string(),
            active_title: meta.app_name,
            active_material_icon: meta.material_icon,
            active_icon_name: meta.icon_name,
            active_app_id: meta.app_id,
            active_id: wid.to_string(),
            windows: st.cached_windows.clone(),
        };

        if let Ok(serialized) = serde_json::to_string(&payload) {
            println!("{}", serialized);
        }
    }

    async fn update_window_list(&self, json_str: &str) {
        let Ok(raw) = serde_json::from_str::<Value>(json_str) else {
            return;
        };
        let Some(items) = raw.as_array() else {
            return;
        };

        let mut enriched = Vec::new();
        let mut st = self.state.lock().await;
        let active_wid = st.active_id.clone();
        let mut seen_ids = HashSet::new();

        for item in items {
            let wid = item["id"].as_str().unwrap_or_default().to_string();
            if wid.is_empty() || seen_ids.contains(&wid) {
                continue;
            }
            seen_ids.insert(wid.clone());

            let t = item["title"].as_str().unwrap_or_default();
            let c = item["cls"].as_str().unwrap_or_default();
            let a = item["app"].as_str().unwrap_or_default();

            let meta = resolve_window_meta(t, c, a, "");
            let is_active = if !active_wid.is_empty() {
                wid == active_wid
            } else {
                item["active"].as_bool().unwrap_or(false)
            };

            enriched.push(Window {
                id: wid,
                title: t.to_string(),
                app_name: meta.app_name,
                icon_name: meta.icon_name,
                material_icon: meta.material_icon,
                app_id: meta.app_id,
                desktop_file: meta.desktop_file,
                is_active,
            });
        }

        st.cached_windows = enriched.clone();

        let payload = WindowsListPayload {
            msg_type: "windows".to_string(),
            windows: enriched,
            active_title: st.active_title.clone(),
            active_material_icon: st.active_material_icon.clone(),
            active_icon_name: st.active_icon_name.clone(),
            active_app_id: st.active_app_id.clone(),
        };

        if let Ok(serialized) = serde_json::to_string(&payload) {
            println!("{}", serialized);
        }
    }

    async fn window_list_changed(&self) {
        let kwin = KWinAdapter::new();
        let query_res = kwin.query_windows();
        if let Ok((windows, active_opt)) = query_res {
            let mut st = self.state.lock().await;
            st.cached_windows = windows.clone();
            if let Some(act) = active_opt {
                st.active_title = act.app_name;
                st.active_material_icon = act.material_icon;
                st.active_icon_name = act.icon_name;
                st.active_app_id = act.app_id;
                st.active_id = act.id;
            }
            let payload = WindowsListPayload {
                msg_type: "windows".to_string(),
                windows,
                active_title: st.active_title.clone(),
                active_material_icon: st.active_material_icon.clone(),
                active_icon_name: st.active_icon_name.clone(),
                active_app_id: st.active_app_id.clone(),
            };
            if let Ok(serialized) = serde_json::to_string(&payload) {
                println!("{}", serialized);
            }
        }
    }
}

pub fn cleanup_kwin_script() {
    let _ = Command::new("qdbus6")
        .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", KWIN_SCRIPT_NAME])
        .output();
}

pub async fn run_event_daemon() -> DynResult<()> {
    cleanup_kwin_script();

    let state = Arc::new(Mutex::new(DaemonState::default()));
    let kwin = KWinAdapter::new();
    let tray_adapter = TrayAdapter::new();

    // Query initial state
    let (initial_wins, initial_active) = kwin.query_windows().unwrap_or_default();
    let initial_tray = tray_adapter.query_tray().unwrap_or_default();

    {
        let mut st = state.lock().await;
        st.cached_windows = initial_wins.clone();
        st.cached_tray = initial_tray.clone();

        if let Some(act) = &initial_active {
            st.active_title = act.app_name.clone();
            st.active_material_icon = act.material_icon.clone();
            st.active_icon_name = act.icon_name.clone();
            st.active_app_id = act.app_id.clone();
            st.active_id = act.id.clone();
        } else if let Some(first) = initial_wins.first() {
            st.active_title = first.app_name.clone();
            st.active_material_icon = first.material_icon.clone();
            st.active_icon_name = first.icon_name.clone();
            st.active_app_id = first.app_id.clone();
            st.active_id = first.id.clone();
        }

        let full_payload = FullStatePayload {
            windows: st.cached_windows.clone(),
            tray: st.cached_tray.clone(),
            active_title: st.active_title.clone(),
            active_material_icon: st.active_material_icon.clone(),
            active_icon_name: st.active_icon_name.clone(),
            active_app_id: st.active_app_id.clone(),
        };

        if let Ok(serialized) = serde_json::to_string(&full_payload) {
            println!("{}", serialized);
        }
    }

    // Register DBus server
    let watcher_service = WatcherService {
        state: Arc::clone(&state),
    };

    let _conn = Builder::session()?
        .name("org.caelestia.WindowWatcher")?
        .serve_at("/Watcher", watcher_service)?
        .build()
        .await?;

    // Install and start KWin script
    let kwin_js = r#"
function notifyActive(c) {
    try {
        if (c) {
            callDBus("org.caelestia.WindowWatcher", "/Watcher", "org.caelestia.WindowWatcher", "windowActivated",
                     "" + (c.caption || ""),
                     "" + (c.resourceClass || ""),
                     "" + (c.desktopFileName || ""),
                     ("" + c.internalId).replace("{","").replace("}",""));
        } else {
            callDBus("org.caelestia.WindowWatcher", "/Watcher", "org.caelestia.WindowWatcher", "windowActivated",
                     "Desktop", "", "", "");
        }
    } catch(e) {}
}

function getWindowList() {
    var wins = workspace.windowList();
    var res = [];
    var activeId = workspace.activeWindow ? ("" + workspace.activeWindow.internalId).replace("{","").replace("}","") : "";
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i];
        if (w.normalWindow && w.caption && w.resourceClass !== "quickshell") {
            res.push({
                id: ("" + w.internalId).replace("{","").replace("}",""),
                title: "" + (w.caption || ""),
                cls: "" + (w.resourceClass || ""),
                app: "" + (w.desktopFileName || ""),
                active: ("" + w.internalId).replace("{","").replace("}","") === activeId
            });
        }
    }
    return res;
}

function notifyList() {
    try {
        var list = getWindowList();
        callDBus("org.caelestia.WindowWatcher", "/Watcher", "org.caelestia.WindowWatcher", "updateWindowList", JSON.stringify(list));
    } catch(e) {}
}

function connectWindow(c) {
    if (!c || c._caelestiaHooked) return;
    c._caelestiaHooked = true;
    try {
        c.captionChanged.connect(function() {
            if (workspace.activeWindow === c) {
                notifyActive(c);
            }
        });
    } catch(e) {}
}

function onActiveChanged(c) {
    connectWindow(c);
    notifyActive(c);
}

workspace.windowActivated.connect(onActiveChanged);
workspace.windowAdded.connect(function(c) {
    connectWindow(c);
    notifyList();
});
workspace.windowRemoved.connect(notifyList);

try {
    var wins = workspace.stackingOrder;
    for (var i = 0; i < wins.length; i++) {
        connectWindow(wins[i]);
    }
} catch(e) {}

notifyActive(workspace.activeWindow);
notifyList();
"#;
    let script_file = "/tmp/caelestia_kwin_watcher.js";
    fs::write(script_file, kwin_js)?;

    let _ = Command::new("qdbus6")
        .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", script_file, KWIN_SCRIPT_NAME])
        .output();
    let _ = Command::new("qdbus6")
        .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start"])
        .output();

    // Spawn periodic tray poller
    let tray_state = Arc::clone(&state);
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_millis(5000));
        let tray_ad = TrayAdapter::new();
        loop {
            interval.tick().await;
            if let Ok(new_tray) = tray_ad.query_tray() {
                let mut st = tray_state.lock().await;
                if new_tray != st.cached_tray {
                    st.cached_tray = new_tray.clone();
                    let payload = TrayPayload {
                        msg_type: "tray".to_string(),
                        tray: new_tray,
                    };
                    if let Ok(serialized) = serde_json::to_string(&payload) {
                        println!("{}", serialized);
                    }
                }
            }
        }
    });

    // Watch stdin for EOF
    tokio::spawn(async {
        let mut stdin = tokio::io::stdin();
        let mut buf = [0u8; 1024];
        loop {
            match stdin.read(&mut buf).await {
                Ok(0) | Err(_) => {
                    cleanup_kwin_script();
                    std::process::exit(0);
                }
                _ => {}
            }
        }
    });

    // Handle termination signals
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            cleanup_kwin_script();
        }
    }

    Ok(())
}
