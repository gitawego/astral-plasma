use crate::domain::app_identity::{
    is_shell_owned_surface, shared_index, shell_classes_js, should_skip_taskbar,
};
use crate::domain::branding;
use crate::domain::meta_resolver::resolve_window_meta_with;
use crate::domain::wine_media::parse_wine_media;
use crate::application::wine_mpris::{WineMprisService, WineMprisSlot, WINE_MPRIS_BUS_NAME};
use crate::domain::model::{
    ActiveWindowPayload, FullStatePayload, TrayItem, TrayPayload, Window, WindowsListPayload,
};
use crate::domain::ports::{DynResult, TrayPort, WindowManagerPort};
use crate::infrastructure::kwin_adapter::KWinAdapter;
use crate::infrastructure::window_icons;
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

const KWIN_SCRIPT_NAME: &str = branding::KWIN_SCRIPT_WATCHER;

/// Identifier tokens inside the KWin JavaScript. Rust values cannot be
/// interpolated into a raw JS literal without escaping every brace, so the
/// scripts carry explicit tokens and [`render_kwin_script`] substitutes them.
const TOKEN_DBUS_NAME: &str = "@DBUS_WATCHER_NAME@";
const TOKEN_SHELL_CLASSES: &str = "@SHELL_WINDOW_CLASSES@";

/// Substitute branding identifiers into a KWin JavaScript template.
fn render_kwin_script(template: &str) -> String {
    template
        .replace(TOKEN_DBUS_NAME, branding::DBUS_WATCHER_NAME)
        .replace(TOKEN_SHELL_CLASSES, &shell_classes_js())
}

pub struct DaemonState {
    pub cached_windows: Vec<Window>,
    pub cached_tray: Vec<TrayItem>,
    pub active_title: String,
    pub active_material_icon: String,
    pub active_icon_name: String,
    pub active_app_id: String,
    pub active_id: String,
    /// Raw window class of the active window, used by the Xwayland focus guard.
    pub active_cls: String,
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
            active_cls: String::new(),
        }
    }
}

/// Whitelisted shell IPC actions the desktop may trigger through the daemon.
///
/// A KWin script cannot launch processes, and kglobalaccel's `invokeShortcut` on
/// a `.desktop` service only emits a signal - nobody launches the entry (Plasma's
/// own panel does that for the shortcuts it registers). So the shortcut forwards
/// here and the daemon runs the shell's IPC command. The names are a whitelist:
/// a D-Bus method that executes arbitrary commands would be a privilege hole.
pub fn shell_ipc_arguments(action: &str) -> Option<Vec<&'static str>> {
    match action {
        "launcher.toggle" => Some(vec!["call", "launcher", "toggle"]),
        "launcher.wallpaper" => Some(vec!["call", "launcher", "open", "wallpaper"]),
        "dashboard.toggle" => Some(vec!["call", "dashboard", "toggle"]),
        "settings.toggle" => Some(vec!["call", "settings", "toggle"]),
        "overview.toggle" => Some(vec!["call", "overview", "toggle"]),
        _ => None,
    }
}

/// Serves the window/tray event interface. Cheap to clone: every field is a
/// shared handle, so a connection attempt can be retried without rebuilding
/// state.
#[derive(Clone)]
pub struct WatcherService {
    state: Arc<Mutex<DaemonState>>,
    /// Filled asynchronously: the bridge may first have to wait for a previous
    /// shell instance to release its singleton bus name.
    wine_mpris: WineMprisSlot,
}

impl WatcherService {
    /// The Wine MPRIS bridge, re-created by the supervisor whenever it loses the
    /// bus name. Shared with the bridge task, which owns it for the session.
    fn bridge(&self) -> Option<Arc<WineMprisService>> {
        self.wine_mpris.read().ok().and_then(|guard| guard.clone())
    }
}

#[zbus::interface(name = "org.astralplasma.WindowWatcher")]
impl WatcherService {
    /// Run a whitelisted shell IPC action (the KWin shortcut script's target).
    #[zbus(name = "ShellIpc")]
    async fn shell_ipc(&self, action: &str) -> bool {
        let Some(arguments) = shell_ipc_arguments(action) else {
            eprintln!("[shell-ipc] refused unknown action {action:?}");
            return false;
        };

        // The shell was started from the checkout (development) or from the
        // extracted package (installed); both are addressed the same way.
        let directory = crate::application::shell_lifecycle::shell_config_dir();

        let status = Command::new("quickshell")
            .arg("ipc")
            .arg("-p")
            .arg(&directory)
            .args(&arguments)
            .status();

        match status {
            Ok(status) if status.success() => true,
            _ => {
                eprintln!(
                    "[shell-ipc] {action} failed (no running shell at {})",
                    directory.display()
                );
                false
            }
        }
    }

    #[zbus(name = "WindowActivated")]
    async fn window_activated(&self, title: &str, cls: &str, app: &str, wid: &str) {
        // Wine windows are X11 clients: activating one leaves Xwayland's
        // keyboard focus on it, and KWin keeps forwarding keys there once a
        // native window becomes active - so typing in a Wayland app would also
        // drive the Wine app (Enter in a chat box would press its play button).
        // Hand the X11 focus back as soon as the Wine window is no longer
        // active; the periodic guard below keeps enforcing it, because Wine
        // re-asserts its focus right after it is cleared.
        {
            let mut st = self.state.lock().await;
            st.active_cls = cls.to_string();
        }
        crate::infrastructure::x11_input::release_stale_wine_focus(cls);

        if let Some(mpris) = self.bridge() {
            if let Some(media) = parse_wine_media(title, cls) {
                let _ = mpris.update_media(&media).await;
            }
        }

        // Defence in depth: the KWin script already suppresses shell surfaces, but
        // this interface is independently addressable on the bus, so re-check here.
        // A shell surface must never overwrite the genuine active application.
        if is_shell_owned_surface(cls, app, title) {
            return;
        }

        let mut meta = resolve_window_meta_with(Some(&shared_index()), title, cls, app, "");
        // Wine applications ship no desktop entry; the icon their own window
        // publishes (`_NET_WM_ICON`) is the only truthful identity, and it is what
        // the desktop's own taskbar falls back to. A desktop-entry icon wins.
        if let Some(icon) = window_icons::resolve_window_icon(cls, &meta.icon_name) {
            meta.icon_name = icon.to_string_lossy().to_string();
        }
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
                is_maximized: false,
                is_fullscreen: false,
            });
        }

        let has_max = st.cached_windows.iter().any(|w| w.is_maximized || w.is_fullscreen);
        let payload = ActiveWindowPayload {
            msg_type: "active".to_string(),
            active_title: meta.app_name,
            active_material_icon: meta.material_icon,
            active_icon_name: meta.icon_name,
            active_app_id: meta.app_id,
            active_id: clean_wid.to_string(),
            windows: st.cached_windows.clone(),
            has_maximized_window: has_max,
        };

        if let Ok(serialized) = serde_json::to_string(&payload) {
            println!("{}", serialized);
        }
    }

    #[zbus(name = "UpdateWinePlaybackStatus")]
    async fn update_wine_playback_status(&self, is_playing: bool) {
        if let Some(mpris) = self.bridge() {
            let _ = mpris.update_playback_status(is_playing).await;
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

        let index = shared_index();
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

            if should_skip_taskbar(
                item["skipTaskbar"].as_bool().unwrap_or(false), c, a, t,
            ) {
                continue;
            }

            let mut meta = resolve_window_meta_with(Some(&index), t, c, a, "");
            if let Some(icon) = window_icons::resolve_window_icon(c, &meta.icon_name) {
                meta.icon_name = icon.to_string_lossy().to_string();
            }
            let is_active = if !active_wid.is_empty() {
                wid == active_wid
            } else {
                item["active"].as_bool().unwrap_or(false)
            };

            let is_maximized = item["maximized"].as_bool().unwrap_or(false);
            let is_fullscreen = item["fullScreen"].as_bool().unwrap_or(false);

            enriched.push(Window {
                id: wid,
                title: t.to_string(),
                app_name: meta.app_name,
                icon_name: meta.icon_name,
                material_icon: meta.material_icon,
                app_id: meta.app_id,
                desktop_file: meta.desktop_file,
                is_active,
                is_maximized,
                is_fullscreen,
            });
        }

        st.cached_windows = enriched.clone();

        let has_max = enriched.iter().any(|w| w.is_maximized || w.is_fullscreen);
        let payload = WindowsListPayload {
            msg_type: "windows".to_string(),
            windows: enriched,
            active_title: st.active_title.clone(),
            active_material_icon: st.active_material_icon.clone(),
            active_icon_name: st.active_icon_name.clone(),
            active_app_id: st.active_app_id.clone(),
            has_maximized_window: has_max,
        };

        if let Ok(serialized) = serde_json::to_string(&payload) {
            println!("{}", serialized);
        }

        if let Some(mpris) = self.bridge() {
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
        if let Some(mpris) = self.bridge() {
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
            let has_max = windows.iter().any(|w| w.is_active && (w.is_maximized || w.is_fullscreen));
            let payload = WindowsListPayload {
                msg_type: "windows".to_string(),
                windows,
                active_title: st.active_title.clone(),
                active_material_icon: st.active_material_icon.clone(),
                active_icon_name: st.active_icon_name.clone(),
                active_app_id: st.active_app_id.clone(),
                has_maximized_window: has_max,
            };
            if let Ok(serialized) = serde_json::to_string(&payload) {
                println!("{}", serialized);
            }
        }
    }

    #[zbus(name = "RefreshTray")]
    async fn refresh_tray(&self) {
        let tray_ad = TrayAdapter::new();
        if let Ok(new_tray) = tray_ad.query_tray() {
            let mut st = self.state.lock().await;
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

pub fn get_kwin_watcher_script() -> String {
    render_kwin_script(r#"
// A window that asked not to appear in a taskbar (EWMH skipTaskbar), or one of
// the shell's own layer surfaces, must never be reported as the active window.
// Hovering a drawer or opening a popout can make such a surface KWin's "active
// window"; without this filter the dock's active-app pill shows a bogus
// "Quickshell" entry instead of the program the user is actually working in.
function isShellSurface(c) {
    if (!c) return true;
    try {
        if (c.skipTaskbar) return true;
    } catch(e) {}
    var cls = ("" + (c.resourceClass || "")).toLowerCase();
    var app = ("" + (c.desktopFileName || "")).toLowerCase();
    var known = @SHELL_WINDOW_CLASSES@;
    for (var pass = 0; pass < 2; pass++) {
        var v = pass === 0 ? cls : app;
        if (!v) continue;
        for (var i = 0; i < known.length; i++) {
            if (v === known[i] || v.indexOf(known[i] + ".") === 0 || v.indexOf(known[i] + "-") === 0) {
                return true;
            }
        }
    }
    return false;
}

// KWin does NOT hand activation back when a layer surface stops grabbing it:
// after a drawer closes, `workspace.activeWindow` stays on the (now invisible)
// shell surface indefinitely. That starves the whole watcher - no further
// windowActivated events ever fire - so the dock would sit frozen on whatever app
// happened to be active before the interaction.
//
// The shell must therefore release activation explicitly. Restoring the last real
// window we saw returns focus where the user expects it, and re-arms the watcher.
var lastRealWindow = null;

function restoreActivationAfterShellSurface() {
    try {
        var cur = workspace.activeWindow;
        if (cur && !isShellSurface(cur)) return;   // nothing to do
        if (lastRealWindow && lastRealWindow.normalWindow && lastRealWindow.caption) {
            workspace.activeWindow = lastRealWindow;
        } else {
            // Fall back to the topmost real window on the current desktop.
            var wins = workspace.stackingOrder || [];
            for (var i = wins.length - 1; i >= 0; i--) {
                var w = wins[i];
                if (w.normalWindow && w.caption && !isShellSurface(w)) {
                    workspace.activeWindow = w;
                    break;
                }
            }
        }
    } catch(e) {}
}

function notifyActive(c) {
    try {
        if (c && isShellSurface(c)) {
            // A shell surface took activation. Do NOT report it as the active
            // application. We do not restore activation here either: the only
            // surface that legitimately requests keyboard focus is the power
            // confirmation modal, and yanking activation away from it would break
            // its Enter/Escape handling. Restoration is an explicit, timed action
            // (see the `focus restore` CLI), invoked when the modal closes.
            return;
        }
        if (c) {
            lastRealWindow = c;
            callDBus("@DBUS_WATCHER_NAME@", "/Watcher", "@DBUS_WATCHER_NAME@", "WindowActivated",
                     "" + (c.caption || ""),
                     "" + (c.resourceClass || ""),
                     "" + (c.desktopFileName || ""),
                     ("" + c.internalId).replace("{","").replace("}",""));
        } else {
            callDBus("@DBUS_WATCHER_NAME@", "/Watcher", "@DBUS_WATCHER_NAME@", "WindowActivated",
                     "Desktop", "", "", "");
        }
    } catch(e) {}
}

function getWindowList() {
    var cur = workspace.currentDesktop;
    var wins = workspace.windowList();
    var res = [];
    var activeId = workspace.activeWindow ? ("" + workspace.activeWindow.internalId).replace("{","").replace("}","") : "";
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i];
        var isShell = false;
        try { isShell = !!w.skipTaskbar; } catch(e) {}
        if (!isShell) {
            var wcls = ("" + (w.resourceClass || "")).toLowerCase();
            if (wcls === "quickshell" || wcls === "org.quickshell") isShell = true;
        }
        if (!isShell && w.normalWindow && w.caption) {
            var onCurrent = w.desktops ? (w.desktops.indexOf(cur) !== -1 || w.onAllDesktops) : true;
            res.push({
                id: ("" + w.internalId).replace("{","").replace("}",""),
                title: "" + (w.caption || ""),
                cls: "" + (w.resourceClass || ""),
                app: "" + (w.desktopFileName || ""),
                active: ("" + w.internalId).replace("{","").replace("}","") === activeId,
                maximized: (w.maximizeMode === 3) && !w.minimized && onCurrent,
                fullScreen: Boolean(w.fullScreen) && !w.minimized && onCurrent,
                skipTaskbar: isShell
            });
        }
    }
    return res;
}

function notifyList() {
    try {
        var list = getWindowList();
        callDBus("@DBUS_WATCHER_NAME@", "/Watcher", "@DBUS_WATCHER_NAME@", "UpdateWindowList", JSON.stringify(list));
    } catch(e) {}
}

function notifyMedia(c) {
    try {
        if (c) {
            callDBus("@DBUS_WATCHER_NAME@", "/Watcher", "@DBUS_WATCHER_NAME@", "MediaWindowChanged",
                     "" + (c.caption || ""),
                     "" + (c.resourceClass || ""));
        }
    } catch(e) {}
}

function isWineMediaWindow(c) {
    if (!c) return false;
    var cls = ("" + (c.resourceClass || "")).toLowerCase();
    var app = ("" + (c.desktopFileName || "")).toLowerCase();
    var known = [
        "cloudmusic", "netease", "qqmusic", "tencent", "spotify",
        "kugou", "kuwo", "kwmusic", "foobar2000", "aimp", "musicbee",
        "yesplaymusic"
    ];
    for (var i = 0; i < known.length; i++) {
        if (cls.indexOf(known[i]) !== -1 || app.indexOf(known[i]) !== -1) {
            return true;
        }
    }
    return false;
}

function connectWindow(c) {
    if (!c || c._astralPlasmaHooked) return;
    c._astralPlasmaHooked = true;
    try {
        c.captionChanged.connect(function() {
            if (workspace.activeWindow === c) {
                notifyActive(c);
            }
            if (isWineMediaWindow(c)) {
                notifyMedia(c);
            }
        });
        c.maximizedChanged.connect(function() { notifyList(); });
        c.fullScreenChanged.connect(function() { notifyList(); });
        c.minimizedChanged.connect(function() { notifyList(); });
        c.desktopsChanged.connect(function() { notifyList(); });
        if (isWineMediaWindow(c)) {
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
    workspace.currentDesktopChanged.connect(function() { notifyList(); });
} catch(e) {}

try {
    var wins = workspace.stackingOrder;
    for (var i = 0; i < wins.length; i++) {
        connectWindow(wins[i]);
    }
} catch(e) {}

notifyActive(workspace.activeWindow);
notifyList();
"#)
}

/// One-shot KWin script that hands activation back to the user's real window.
///
/// Used by `astral-plasma focus restore`. KWin does not reassign activation when
/// a layer surface stops requesting keyboard focus, so after the power modal
/// closes the compositor would otherwise leave its invisible full-screen surface
/// as the active window - freezing the dock's active-app display and starving the
/// watcher of `windowActivated` events.
pub fn get_focus_restore_script() -> String {
    render_kwin_script(r#"
var wins = workspace.stackingOrder || workspace.windowList();
var target = null;
var known = @SHELL_WINDOW_CLASSES@;
function isShell(c) {
    if (!c) return true;
    try { if (c.skipTaskbar) return true; } catch(e) {}
    var v = ("" + (c.resourceClass || "")).toLowerCase();
    var a = ("" + (c.desktopFileName || "")).toLowerCase();
    for (var i = 0; i < known.length; i++) {
        for (var j = 0; j < 2; j++) {
            var s = j === 0 ? v : a;
            if (!s) continue;
            if (s === known[i] || s.indexOf(known[i] + ".") === 0 || s.indexOf(known[i] + "-") === 0) {
                return true;
            }
        }
    }
    return false;
}
// Prefer the most recently used real window, which is what the user expects.
for (var i = wins.length - 1; i >= 0; i--) {
    var w = wins[i];
    if (w.normalWindow && w.caption && !isShell(w)) { target = w; break; }
}
if (target) {
    workspace.activeWindow = target;
    console.warn("ASTRAL_PLASMA_FOCUS_RESTORED:" + target.resourceClass);
} else {
    console.warn("ASTRAL_PLASMA_FOCUS_RESTORED:none");
}
"#)
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

        let has_max = st.cached_windows.iter().any(|w| w.is_maximized || w.is_fullscreen);
        let full_payload = FullStatePayload {
            windows: st.cached_windows.clone(),
            tray: st.cached_tray.clone(),
            active_title: st.active_title.clone(),
            active_material_icon: st.active_material_icon.clone(),
            active_icon_name: st.active_icon_name.clone(),
            active_app_id: st.active_app_id.clone(),
            has_maximized_window: has_max,
        };

        if let Ok(serialized) = serde_json::to_string(&full_payload) {
            println!("{}", serialized);
        }
    }

    // The bridge is a session singleton. A shell reload starts this daemon
    // before the outgoing one has necessarily released the bus name, and a
    // lost race must not cost the session its Wine player: retry in the
    // background while the rest of the daemon starts serving.
    let wine_mpris: WineMprisSlot = Arc::new(std::sync::RwLock::new(None));
    {
        let slot = Arc::clone(&wine_mpris);
        let initial = initial_wins.clone();
        tokio::spawn(async move {
            // This task owns the slot for the whole session: the bridge - and the
            // bus name it holds - must live as long as the daemon, so the shell
            // always has the Wine player to show. A service that stops owning its
            // name (a lost connection, a restart race) is replaced, and the media
            // that is already playing is re-published onto the new one.
            let mut interval = tokio::time::interval(Duration::from_secs(5));
            loop {
                interval.tick().await;

                let healthy = match slot.read().ok().and_then(|guard| guard.clone()) {
                    Some(service) => service.is_name_owner().await,
                    None => false,
                };
                if healthy {
                    continue;
                }

                match WineMprisService::new().await {
                    Ok(service) => {
                        let service = Arc::new(service);
                        for w in &initial {
                            if let Some(media) = parse_wine_media(&w.title, &w.app_id)
                                .or_else(|| parse_wine_media(&w.title, &w.icon_name))
                                .or_else(|| parse_wine_media(&w.title, &w.app_name))
                            {
                                let _ = service.update_media(&media).await;
                                break;
                            }
                        }
                        eprintln!(
                            "[{}] Wine MPRIS bridge attached as {}",
                            branding::APP_NAME,
                            WINE_MPRIS_BUS_NAME
                        );
                        if let Ok(mut guard) = slot.write() {
                            *guard = Some(service);
                        }
                    }
                    Err(error) => eprintln!(
                        "[{}] Wine MPRIS bridge reconnecting: {}",
                        branding::APP_NAME,
                        error
                    ),
                }
            }
        });
    }

    // Register DBus server
    let watcher_service = WatcherService {
        state: Arc::clone(&state),
        wine_mpris: Arc::clone(&wine_mpris),
    };

    // The watcher name is a singleton too: during a reload the outgoing daemon
    // may still hold it for a moment, and losing it would leave the taskbar
    // frozen for the rest of the session.
    let _conn: zbus::Connection =
        crate::application::retry::retry_async(120, Duration::from_millis(250), || {
            let service = watcher_service.clone();
            async move {
                let conn: zbus::Connection = Builder::session()?
                    .name(branding::DBUS_WATCHER_NAME)?
                    .serve_at(branding::DBUS_WATCHER_PATH, service)?
                    .build()
                    .await?;
                Ok::<zbus::Connection, crate::domain::ports::DynError>(conn)
            }
        })
        .await?;

    {
        let slot = Arc::clone(&wine_mpris);
        tokio::spawn(async move {
            use crate::application::audio_streams::{another_app_owns_audio, audible_streams};
            use crate::application::wine_mpris::WINE_MPRIS_BUS_NAME;

            let mut interval = tokio::time::interval(Duration::from_millis(2000));
            loop {
                interval.tick().await;
                // The bridge may not be attached yet (see above); skip until it is.
                let Some(mpris_audio) = slot.read().ok().and_then(|guard| guard.clone()) else {
                    continue;
                };
                // The sound server decides who owns the audio. Asking the other
                // MPRIS players (as this used to) let a browser session that
                // merely claims Playing silence the bridge while the bridge was
                // the one actually making sound.
                let identity = mpris_audio.identity().await;
                if let Ok(streams) = audible_streams() {
                    if another_app_owns_audio(&streams, &identity, WINE_MPRIS_BUS_NAME) {
                        let _ = mpris_audio.update_playback_status(false).await;
                    }
                }
            }
        });
    }

    // Install and start KWin script
    cleanup_kwin_script();
    let script_file = branding::tmp_file("kwin_watcher.js");
    fs::write(&script_file, get_kwin_watcher_script())?;

    let _ = Command::new("qdbus6")
        .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", &script_file.to_string_lossy(), KWIN_SCRIPT_NAME])
        .output();
    let _ = Command::new("qdbus6")
        .args(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start"])
        .output();

    // Xwayland focus guard.
    //
    // While the active window is a native application, no Wine window may hold
    // Xwayland's keyboard focus: KWin forwards keystrokes there regardless, so
    // typing in a native app would silently drive the Wine app as well. The
    // activation handler clears it once, but Wine re-asserts its focus right
    // after, so the invariant is re-enforced until it sticks.
    {
        let guard_state = Arc::clone(&state);
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_millis(500));
            loop {
                interval.tick().await;
                let active_cls = {
                    let st = guard_state.lock().await;
                    st.active_cls.clone()
                };
                if active_cls.is_empty() {
                    continue;
                }
                // A Wine window is active: it may keep the X11 focus.
                if crate::infrastructure::x11_input::is_wine_class(&active_cls) {
                    continue;
                }
                crate::infrastructure::x11_input::release_stale_wine_focus(&active_cls);
            }
        });
    }

    // Spawn periodic tray poller
    let tray_state = Arc::clone(&state);
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_millis(1000));
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
