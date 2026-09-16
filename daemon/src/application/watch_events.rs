use crate::domain::meta_resolver::resolve_window_meta;
use crate::domain::wine_media::parse_wine_media;
use crate::application::wine_mpris::WineMprisService;
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
    wine_mpris: Option<Arc<WineMprisService>>,
}

#[zbus::interface(name = "org.caelestia.WindowWatcher")]
impl WatcherService {
    #[zbus(name = "WindowActivated")]
    async fn window_activated(&self, title: &str, cls: &str, app: &str, wid: &str) {
        if let Some(mpris) = &self.wine_mpris {
            if let Some(media) = parse_wine_media(title, cls) {
                let _ = mpris.update_media(&media).await;
            }
        }

        let meta = resolve_window_meta(title, cls, app, "");
        let mut st = self.state.lock().await;

        let clean_wid = wid.trim_matches(|c| c == '{' || c == '}');

        st.active_title = meta.app_name.clone();
        st.active_material_icon = meta.material_icon.clone();
        st.active_icon_name = meta.icon_name.clone();
        st.active_app_id = meta.app_id.clone();
        st.active_id = clean_wid.to_string();

        let mut found = false;
        for w in &mut st.cached_windows {
            let w_clean_id = w.id.trim_matches(|c| c == '{' || c == '}');
            if !clean_wid.is_empty() && w_clean_id == clean_wid {
                w.is_active = true;
                w.title = title.to_string();
                found = true;
            } else {
                w.is_active = false;
            }
        }

        if !found && !clean_wid.is_empty() {
            st.cached_windows.push(Window {
                id: clean_wid.to_string(),
                title: title.to_string(),
                app_name: meta.app_name.clone(),
                icon_name: meta.icon_name.clone(),
                material_icon: meta.material_icon.clone(),
                app_id: meta.app_id.clone(),
                desktop_file: meta.desktop_file.clone(),
                is_active: true,
            });
        }

        let payload = ActiveWindowPayload {
            msg_type: "active".to_string(),
            active_title: meta.app_name,
            active_material_icon: meta.material_icon,
            active_icon_name: meta.icon_name,
            active_app_id: meta.app_id,
            active_id: clean_wid.to_string(),
            windows: st.cached_windows.clone(),
        };

        if let Ok(serialized) = serde_json::to_string(&payload) {
            println!("{}", serialized);
        }
    }

    #[zbus(name = "UpdateWindowList")]
    async fn update_window_list(&self, json_str: &str) {
        let Ok(raw) = serde_json::from_str::<Value>(json_str) else {
            return;
        };
        let Some(items) = raw.as_array() else {
            return;
        };

        let mut enriched = Vec::new();
        let mut st = self.state.lock().await;
        let active_wid = st.active_id.trim_matches(|c| c == '{' || c == '}').to_string();
        let mut seen_ids = HashSet::new();

        for item in items {
            let raw_wid = item["id"].as_str().unwrap_or_default();
            let wid = raw_wid.trim_matches(|c| c == '{' || c == '}').to_string();
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

        if let Some(mpris) = &self.wine_mpris {
            for item in items {
                let t = item["title"].as_str().unwrap_or_default();
                let c = item["cls"].as_str().unwrap_or_default();
                if let Some(media) = parse_wine_media(t, c) {
                    let _ = mpris.update_media(&media).await;
                    break;
                }
            }
        }
    }

    #[zbus(name = "MediaWindowChanged")]
    async fn media_window_changed(&self, caption: &str, cls: &str) {
        if let Some(mpris) = &self.wine_mpris {
            if let Some(media) = parse_wine_media(caption, cls) {
                let _ = mpris.update_media(&media).await;
            }
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

pub fn get_kwin_watcher_script() -> &'static str {
    r#"
function notifyActive(c) {
    try {
        if (c) {
            callDBus("org.caelestia.WindowWatcher", "/Watcher", "org.caelestia.WindowWatcher", "WindowActivated",
                     "" + (c.caption || ""),
                     "" + (c.resourceClass || ""),
                     "" + (c.desktopFileName || ""),
                     ("" + c.internalId).replace("{","").replace("}",""));
        } else {
            callDBus("org.caelestia.WindowWatcher", "/Watcher", "org.caelestia.WindowWatcher", "WindowActivated",
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
        callDBus("org.caelestia.WindowWatcher", "/Watcher", "org.caelestia.WindowWatcher", "UpdateWindowList", JSON.stringify(list));
    } catch(e) {}
}

function notifyMedia(c) {
    try {
        if (c) {
            callDBus("org.caelestia.WindowWatcher", "/Watcher", "org.caelestia.WindowWatcher", "MediaWindowChanged",
                     "" + (c.caption || ""),
                     "" + (c.resourceClass || ""));
        }
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
            var cls = "" + (c.resourceClass || "");
            if (cls.indexOf("cloudmusic") !== -1 || cls.indexOf("netease") !== -1) {
                notifyMedia(c);
            }
        });
        var cls = "" + (c.resourceClass || "");
        if (cls.indexOf("cloudmusic") !== -1 || cls.indexOf("netease") !== -1) {
            notifyMedia(c);
        }
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
"#
}

pub fn cleanup_kwin_script() {
    let _ = Command::new("qdbus6")
        .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", KWIN_SCRIPT_NAME])
        .output();
}

pub async fn run_event_daemon() -> DynResult<()> {
    #[cfg(target_os = "linux")]
    unsafe {
        libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
    }
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

    let wine_mpris = WineMprisService::new().await.ok().map(Arc::new);

    if let Some(mpris) = &wine_mpris {
        for w in &initial_wins {
            if let Some(media) = parse_wine_media(&w.title, &w.app_id)
                .or_else(|| parse_wine_media(&w.title, &w.icon_name))
                .or_else(|| parse_wine_media(&w.title, &w.app_name))
            {
                let _ = mpris.update_media(&media).await;
                break;
            }
        }
    }

    // Register DBus server
    let watcher_service = WatcherService {
        state: Arc::clone(&state),
        wine_mpris: wine_mpris.clone(),
    };

    let _conn = Builder::session()?
        .name("org.caelestia.WindowWatcher")?
        .serve_at("/Watcher", watcher_service)?
        .build()
        .await?;

    if let Some(mpris_audio) = wine_mpris.clone() {
        tokio::spawn(async move {
            use tokio::io::AsyncBufReadExt;
            use tokio::process::Command;
            let mut cmd = Command::new("pactl");
            cmd.arg("subscribe");
            cmd.stdout(std::process::Stdio::piped());
            cmd.stderr(std::process::Stdio::null());
            if let Ok(mut child) = cmd.spawn() {
                if let Some(stdout) = child.stdout.take() {
                    let mut reader = tokio::io::BufReader::new(stdout).lines();
                    while let Ok(Some(line)) = reader.next_line().await {
                        if line.contains("sink-input") {
                            if let Ok(output) = Command::new("pactl").args(["list", "sink-inputs"]).output().await {
                                let text = String::from_utf8_lossy(&output.stdout);
                                let mut in_cm = false;
                                for l in text.lines() {
                                    if l.contains("NetEase Cloud Music") || l.contains("cloudmusic") {
                                        in_cm = true;
                                    }
                                    if in_cm && l.contains("Corked:") {
                                        let is_playing = l.contains("no");
                                        let _ = mpris_audio.update_playback_status(is_playing).await;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        });
    }

    // Install and start KWin script
    cleanup_kwin_script();
    let script_file = "/tmp/caelestia_kwin_watcher.js";
    fs::write(script_file, get_kwin_watcher_script())?;

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
