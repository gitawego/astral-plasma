#!/usr/bin/env python3
import subprocess
import re
import json
import sys
import os
import time
import signal
import atexit

def get_window_meta(title, cls, app, krunner_icon=''):
    cls_lower = (cls or '').lower()
    app_lower = (app or '').lower()
    t_lower = (title or '').lower()
    
    # 1. High-priority exact or class-based matches
    if 'cloudmusic' in cls_lower or 'netease' in cls_lower or 'cloudmusic' in app_lower:
        return 'CloudMusic', 'netease-cloud-music', 'music_note', 'cloudmusic', 'lutris:rungame/netease-cloud-music'
    
    if 'antigravity' in cls_lower or 'antigravity' in app_lower or 'opencode' in cls_lower or 'opencode' in app_lower:
        return 'Antigravity', 'antigravity', 'smart_toy', 'antigravity', 'ai.opencode.desktop'

    if 'edge' in cls_lower or 'msedge' in cls_lower:
        return 'Edge', 'microsoft-edge', 'language', 'microsoft-edge', 'microsoft-edge'

    if 'ghostty' in cls_lower or 'ghostty' in app_lower:
        return 'Terminal', 'com.mitchellh.ghostty', 'terminal', 'ghostty', 'com.mitchellh.ghostty'

    if 'code' in cls_lower:
        return 'VS Code', 'vscode', 'code', 'code', 'code'

    if 'dolphin' in cls_lower:
        return 'Files', 'org.kde.dolphin', 'folder', 'org.kde.dolphin', 'org.kde.dolphin'

    if 'lutris' in cls_lower:
        return 'Lutris', 'net.lutris.Lutris', 'sports_esports', 'net.lutris.Lutris', 'net.lutris.Lutris'

    if 'token-tracker' in cls_lower or 'token-tracker' in app_lower:
        return 'Tracker', 'token-tracker', 'insights', 'token-tracker', 'com.gitawego.token-tracker-dashboard'

    if 'haruna' in cls_lower or 'mp4' in t_lower or 'mkv' in t_lower:
        return 'Haruna', 'org.kde.haruna', 'movie', 'haruna', 'org.kde.haruna'

    if 'gradia' in cls_lower:
        return 'Gradia', 'be.alexandervanhee.gradia', 'palette', 'gradia', 'be.alexandervanhee.gradia'

    if 'spectacle' in cls_lower:
        return 'Spectacle', 'org.kde.spectacle', 'photo_camera', 'spectacle', 'org.kde.spectacle'

    if 'discord' in cls_lower or 'vesktop' in cls_lower:
        return 'Discord', 'discord', 'chat', 'discord', 'discord'

    if 'steam' in cls_lower:
        return 'Steam', 'steam', 'sports_esports', 'steam', 'steam'

    if 'spotify' in cls_lower:
        return 'Spotify', 'spotify', 'music_note', 'spotify', 'spotify'

    # 2. Wine executable recognition
    if cls_lower.endswith('.exe'):
        clean = cls[:-4]
        clean_lower = clean.lower()
        if 'cloudmusic' in clean_lower or 'netease' in clean_lower:
            return 'CloudMusic', 'netease-cloud-music', 'music_note', 'cloudmusic', 'lutris:rungame/netease-cloud-music'
        if 'wechat' in clean_lower:
            return 'WeChat', 'wechat', 'chat', 'wechat', 'wechat'
        if 'qq' in clean_lower:
            return 'QQ', 'qq', 'chat', 'qq', 'qq'
        return clean.capitalize()[:14], krunner_icon or 'wine', 'window', clean_lower, clean_lower

    # 3. Title-based fallbacks
    if 'antigravity' in t_lower:
        return 'Antigravity', 'antigravity', 'smart_toy', 'antigravity', 'ai.opencode.desktop'
    if 'netease' in t_lower or 'cloudmusic' in t_lower:
        return 'CloudMusic', 'netease-cloud-music', 'music_note', 'cloudmusic', 'lutris:rungame/netease-cloud-music'
    if 'visual studio code' in t_lower:
        return 'VS Code', 'vscode', 'code', 'code', 'code'
    if 'terminal' in t_lower or 'konsole' in t_lower or 'workspace' in t_lower:
        return 'Terminal', 'utilities-terminal', 'terminal', 'terminal', 'utilities-terminal'

    # 4. General fallback
    icon_candidate = krunner_icon or app or cls
    if icon_candidate == 'ai.opencode.desktop':
        icon_candidate = 'antigravity'

    parts = re.split(r' [—\-] ', title) if title else []
    if len(parts) > 1:
        app_name = parts[-1].strip()[:14]
    elif cls:
        app_name = cls.split('.')[-1].capitalize()[:14]
    else:
        app_name = (title or 'Window')[:14]

    app_id = (app or cls or app_name).lower().replace(' ', '-')
    desktop_file = app or cls or app_id

    return app_name, icon_candidate, 'window', app_id, desktop_file

def query_kwin():
    script = """
    var activeId = workspace.activeWindow ? ('' + workspace.activeWindow.internalId).replace('{','').replace('}','') : '';
    var wins = workspace.windowList();
    var res = [];
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i];
        if (w.normalWindow && w.caption && w.resourceClass !== 'quickshell') {
            res.push({
                id: ('' + w.internalId).replace('{','').replace('}',''),
                title: w.caption,
                cls: '' + w.resourceClass,
                app: '' + w.desktopFileName,
                active: ('' + w.internalId).replace('{','').replace('}','') === activeId
            });
        }
    }
    console.warn('CAELESTIA_WINS:' + JSON.stringify(res));
    """
    with open('/tmp/caelestia_kwin_query.js', 'w') as f:
        f.write(script)

    try:
        num = subprocess.check_output(
            ['qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.loadScript', '/tmp/caelestia_kwin_query.js'],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        subprocess.run(['qdbus6', 'org.kde.KWin', f'/Scripting/Script{num}', 'org.kde.kwin.Script.run'], stderr=subprocess.DEVNULL)
        subprocess.run(['qdbus6', 'org.kde.KWin', f'/Scripting/Script{num}', 'org.kde.kwin.Script.stop'], stderr=subprocess.DEVNULL)

        j = subprocess.check_output(['journalctl', '--user', '-b', '-n', '5', '-o', 'cat'], stderr=subprocess.DEVNULL).decode()
        for line in j.splitlines():
            if 'CAELESTIA_WINS:' in line:
                return json.loads(line.split('CAELESTIA_WINS:')[-1])
    except Exception:
        pass
    return []

def query_krunner():
    krunner_icons = {}
    try:
        out = subprocess.check_output(
            ['qdbus6', '--literal', 'org.kde.KWin', '/WindowsRunner', 'org.kde.krunner1.Match', ''],
            stderr=subprocess.DEVNULL
        ).decode('utf-8')
        pattern = r'\[Argument:\s*\(sssida\{sv\}\)\s*\"([^\"]+)\",\s*\"([^\"]+)\",\s*\"([^\"]*)\"'
        matches = re.findall(pattern, out)
        for wid, title, icon in matches:
            if icon:
                krunner_icons[title] = icon
    except Exception:
        pass
    return krunner_icons

def query_tray():
    tray = []
    try:
        items_out = subprocess.check_output(
            ['qdbus6', 'org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher', 'org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems'],
            stderr=subprocess.DEVNULL
        ).decode('utf-8')
        for line in items_out.strip().splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split('/', 1)
            svc = parts[0]
            path = '/' + parts[1]
            item_id = ""
            item_icon = ""
            item_title = ""
            try:
                item_id = subprocess.check_output(['qdbus6', svc, path, 'org.kde.StatusNotifierItem.Id'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
            except Exception:
                pass
            try:
                item_icon = subprocess.check_output(['qdbus6', svc, path, 'org.kde.StatusNotifierItem.IconName'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
            except Exception:
                pass
            try:
                item_title = subprocess.check_output(['qdbus6', svc, path, 'org.kde.StatusNotifierItem.Title'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
            except Exception:
                pass

            if not item_id and not item_title:
                continue
            if item_id.isdigit() and not item_icon and not item_title:
                continue

            m_icon = 'circle'
            id_lower = (item_id + ' ' + item_title + ' ' + item_icon).lower()
            im_badge = ''

            if 'keyboard' in id_lower or 'fcitx' in id_lower or 'input' in id_lower:
                m_icon = 'keyboard'
                try:
                    cur_im = subprocess.check_output(['fcitx5-remote', '-n'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
                    if cur_im:
                        if 'rime' in cur_im.lower():
                            item_icon = 'fcitx-rime'
                            m_icon = 'rime'
                            im_badge = '中'
                            item_title = 'Input Method: Rime (中)'
                        elif 'pinyin' in cur_im.lower():
                            item_icon = 'fcitx-pinyin'
                            m_icon = 'translate'
                            im_badge = '拼'
                            item_title = 'Input Method: Pinyin (拼)'
                        elif 'us' in cur_im.lower() or 'keyboard' in cur_im.lower():
                            item_icon = 'input-keyboard'
                            m_icon = 'keyboard'
                            im_badge = 'EN'
                            item_title = 'Input Method: English (EN)'
                        else:
                            im_badge = cur_im[:2].upper()
                            item_title = f'Input Method: {cur_im}'
                except Exception:
                    pass
            elif 'update' in id_lower or 'cachy' in id_lower:
                m_icon = 'system_update'
            elif 'sunshine' in id_lower or 'stream' in id_lower:
                m_icon = 'cast'
            elif 'token' in id_lower:
                m_icon = 'toll'
            elif 'dropbox' in id_lower or 'cloud' in id_lower:
                m_icon = 'cloud'
            elif 'bluetooth' in id_lower:
                m_icon = 'bluetooth'
            elif 'volume' in id_lower or 'audio' in id_lower:
                m_icon = 'volume_up'
            elif 'wifi' in id_lower or 'network' in id_lower:
                m_icon = 'wifi'

            tray.append({
                'service': svc,
                'path': path,
                'id': item_id,
                'title': item_title,
                'materialIcon': m_icon,
                'rawIcon': item_icon,
                'imBadge': im_badge
            })
    except Exception:
        pass
    return tray

def query_full_state():
    raw_wins = query_kwin()
    krunner_icons = query_krunner()

    windows = []
    active_win = None
    seen_ids = set()

    for w in raw_wins:
        wid = w['id']
        if wid in seen_ids:
            continue
        seen_ids.add(wid)

        title = w['title']
        cls = w['cls']
        app = w['app']
        is_active = w.get('active', False)

        k_icon = krunner_icons.get(title, '')
        app_name, icon_name, mat_icon, app_id, desktop_file = get_window_meta(title, cls, app, k_icon)

        win_obj = {
            'id': wid,
            'title': title,
            'appName': app_name,
            'iconName': icon_name,
            'materialIcon': mat_icon,
            'appId': app_id,
            'desktopFile': desktop_file,
            'isActive': is_active
        }
        if is_active:
            active_win = win_obj
        windows.append(win_obj)

    tray = query_tray()

    active_title = 'Desktop'
    active_mat_icon = 'desktop_windows'
    active_icon_name = ''
    active_app_id = ''

    if active_win:
        active_title = active_win['appName']
        active_mat_icon = active_win['materialIcon']
        active_icon_name = active_win['iconName']
        active_app_id = active_win['appId']
    elif windows:
        active_title = windows[0]['appName']
        active_mat_icon = windows[0]['materialIcon']
        active_icon_name = windows[0]['iconName']
        active_app_id = windows[0]['appId']

    return {
        'windows': windows,
        'tray': tray,
        'activeTitle': active_title,
        'activeMaterialIcon': active_mat_icon,
        'activeIconName': active_icon_name,
        'activeAppId': active_app_id
    }

# ==============================================================================
# Real-Time Event-Driven Daemon
# ==============================================================================
KWIN_SCRIPT_NAME = "caelestia-watcher"

def cleanup_kwin_script():
    try:
        subprocess.run(
            ['qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.unloadScript', KWIN_SCRIPT_NAME],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except Exception:
        pass

def run_daemon():
    import dbus
    import dbus.service
    import dbus.mainloop.glib
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()

    cached_windows = []
    cached_tray = []
    cached_active = {
        'activeTitle': 'Desktop',
        'activeMaterialIcon': 'desktop_windows',
        'activeIconName': '',
        'activeAppId': '',
        'activeId': ''
    }

    class KWinWatcherService(dbus.service.Object):
        def __init__(self):
            bus_name = dbus.service.BusName("org.caelestia.WindowWatcher", bus=dbus.SessionBus(), replace_existing=True)
            super().__init__(bus_name, "/Watcher")
            self.debounce_timer_id = 0

        @dbus.service.method("org.caelestia.WindowWatcher", in_signature="ssss", out_signature="")
        def windowActivated(self, title, cls, app, wid):
            nonlocal cached_active, cached_windows
            title_str = str(title)
            cls_str = str(cls)
            app_str = str(app)
            wid_str = str(wid)

            app_name, icon_name, mat_icon, app_id, desktop_file = get_window_meta(title_str, cls_str, app_str)

            cached_active['activeTitle'] = app_name
            cached_active['activeMaterialIcon'] = mat_icon
            cached_active['activeIconName'] = icon_name
            cached_active['activeAppId'] = app_id
            cached_active['activeId'] = wid_str

            for w in cached_windows:
                w['isActive'] = (w.get('id') == wid_str)

            payload = {
                'type': 'active',
                'activeTitle': app_name,
                'activeMaterialIcon': mat_icon,
                'activeIconName': icon_name,
                'activeAppId': app_id,
                'activeId': wid_str,
                'windows': cached_windows
            }
            print(json.dumps(payload), flush=True)

        @dbus.service.method("org.caelestia.WindowWatcher", in_signature="s", out_signature="")
        def updateWindowList(self, json_str):
            nonlocal cached_windows, cached_active
            try:
                raw_wins = json.loads(str(json_str))
                enriched = []
                active_wid = cached_active.get('activeId', '')
                for w in raw_wins:
                    t = w.get('title', '')
                    c = w.get('cls', '')
                    a = w.get('app', '')
                    wid = str(w.get('id', ''))
                    app_name, icon_name, mat_icon, app_id, desktop_file = get_window_meta(t, c, a)
                    is_active = (wid == active_wid) if active_wid else bool(w.get('active', False))
                    enriched.append({
                        'id': wid,
                        'title': t,
                        'appName': app_name,
                        'iconName': icon_name,
                        'materialIcon': mat_icon,
                        'appId': app_id,
                        'desktopFile': desktop_file,
                        'isActive': is_active
                    })
                cached_windows = enriched
                payload = {
                    'type': 'windows',
                    'windows': cached_windows,
                    'activeTitle': cached_active['activeTitle'],
                    'activeMaterialIcon': cached_active['activeMaterialIcon'],
                    'activeIconName': cached_active['activeIconName'],
                    'activeAppId': cached_active['activeAppId']
                }
                print(json.dumps(payload), flush=True)
            except Exception as e:
                pass

        @dbus.service.method("org.caelestia.WindowWatcher", in_signature="", out_signature="")
        def windowListChanged(self):
            if self.debounce_timer_id > 0:
                GLib.source_remove(self.debounce_timer_id)
            self.debounce_timer_id = GLib.timeout_add(100, self._reload_windows)

        def _reload_windows(self):
            self.debounce_timer_id = 0
            nonlocal cached_windows, cached_active
            try:
                state = query_full_state()
                cached_windows = state['windows']
                if not cached_active['activeTitle'] or cached_active['activeTitle'] == 'Desktop':
                    cached_active['activeTitle'] = state['activeTitle']
                    cached_active['activeMaterialIcon'] = state['activeMaterialIcon']
                    cached_active['activeIconName'] = state['activeIconName']
                    cached_active['activeAppId'] = state['activeAppId']
                payload = {
                    'type': 'windows',
                    'windows': cached_windows,
                    'activeTitle': cached_active['activeTitle'],
                    'activeMaterialIcon': cached_active['activeMaterialIcon'],
                    'activeIconName': cached_active['activeIconName'],
                    'activeAppId': cached_active['activeAppId']
                }
                print(json.dumps(payload), flush=True)
            except Exception:
                pass
            return False

    srv = KWinWatcherService()

    # Initial query
    try:
        initial = query_full_state()
        cached_windows = initial['windows']
        cached_tray = initial['tray']
        cached_active['activeTitle'] = initial['activeTitle']
        cached_active['activeMaterialIcon'] = initial['activeMaterialIcon']
        cached_active['activeIconName'] = initial['activeIconName']
        cached_active['activeAppId'] = initial['activeAppId']
        print(json.dumps(initial), flush=True)
    except Exception:
        pass

    # Install KWin script
    cleanup_kwin_script()

    kwin_js = """
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
    """
    script_path = "/tmp/caelestia_kwin_watcher.js"
    with open(script_path, "w") as f:
        f.write(kwin_js)

    try:
        subprocess.check_output(
            ["qdbus6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", script_path, KWIN_SCRIPT_NAME],
            stderr=subprocess.DEVNULL
        )
        subprocess.run(["qdbus6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start"], stderr=subprocess.DEVNULL)
    except Exception as e:
        sys.stderr.write(f"Failed to load KWin watcher script: {e}\\n")

    def reload_tray():
        nonlocal cached_tray
        try:
            new_tray = query_tray()
            if new_tray != cached_tray:
                cached_tray = new_tray
                print(json.dumps({'type': 'tray', 'tray': cached_tray}), flush=True)
        except Exception:
            pass

    tray_debounce_timer = 0
    def on_tray_event(*args, **kwargs):
        nonlocal tray_debounce_timer
        if tray_debounce_timer > 0:
            GLib.source_remove(tray_debounce_timer)
        def _do():
            nonlocal tray_debounce_timer
            tray_debounce_timer = 0
            reload_tray()
            return False
        tray_debounce_timer = GLib.timeout_add(150, _do)

    try:
        session_bus = dbus.SessionBus()
        session_bus.add_signal_receiver(
            on_tray_event,
            signal_name="StatusNotifierItemRegistered",
            dbus_interface="org.kde.StatusNotifierWatcher"
        )
        session_bus.add_signal_receiver(
            on_tray_event,
            signal_name="StatusNotifierItemUnregistered",
            dbus_interface="org.kde.StatusNotifierWatcher"
        )
        session_bus.add_signal_receiver(
            on_tray_event,
            signal_name="CurrentInputMethodChanged",
            dbus_interface="org.fcitx.Fcitx.InputMethod"
        )
    except Exception:
        pass

    def on_tray_tick():
        reload_tray()
        return True

    GLib.timeout_add_seconds(10, on_tray_tick)

    # Watch stdin: if parent process closes pipe, exit immediately and cleanup
    def on_stdin_hangup(source, condition):
        loop.quit()
        return False

    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_HUP | GLib.IO_ERR, on_stdin_hangup)

    def on_signal(sig, frame):
        cleanup_kwin_script()
        sys.exit(0)

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)
    atexit.register(cleanup_kwin_script)

    try:
        loop.run()
    finally:
        cleanup_kwin_script()

def main():
    if '--daemon' in sys.argv:
        run_daemon()
    else:
        state = query_full_state()
        print(json.dumps(state))

if __name__ == '__main__':
    main()
