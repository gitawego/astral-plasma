#!/usr/bin/env python3
import subprocess
import re
import json

def get_window_meta(title, cls, app, krunner_icon=''):
    cls_lower = (cls or '').lower()
    app_lower = (app or '').lower()
    t_lower = (title or '').lower()
    
    # 1. High-priority exact or class-based matches
    if 'cloudmusic' in cls_lower or 'netease' in cls_lower or 'cloudmusic' in app_lower:
        return 'CloudMusic', 'netease-cloud-music', 'music_note', 'cloudmusic', 'lutris:rungame/netease-cloud-music'
    
    if 'antigravity' in cls_lower or 'antigravity' in app_lower or 'opencode' in cls_lower:
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

def main():
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

    # Tray items
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
            try:
                item_id = subprocess.check_output(['qdbus6', svc, path, 'org.kde.StatusNotifierItem.Id'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
                item_icon = subprocess.check_output(['qdbus6', svc, path, 'org.kde.StatusNotifierItem.IconName'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
                item_title = subprocess.check_output(['qdbus6', svc, path, 'org.kde.StatusNotifierItem.Title'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
                m_icon = 'circle'
                id_lower = (item_id + ' ' + item_title + ' ' + item_icon).lower()
                if 'keyboard' in id_lower or 'fcitx' in id_lower or 'input' in id_lower:
                    m_icon = 'keyboard'
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
                    'rawIcon': item_icon
                })
            except Exception:
                pass
    except Exception:
        pass

    active_title = 'Desktop'
    active_mat_icon = 'desktop_windows'
    active_icon_name = ''

    if active_win:
        active_title = active_win['appName']
        active_mat_icon = active_win['materialIcon']
        active_icon_name = active_win['iconName']
    elif windows:
        active_title = windows[0]['appName']
        active_mat_icon = windows[0]['materialIcon']
        active_icon_name = windows[0]['iconName']

    print(json.dumps({
        'windows': windows,
        'tray': tray,
        'activeTitle': active_title,
        'activeMaterialIcon': active_mat_icon,
        'activeIconName': active_icon_name
    }))

if __name__ == '__main__':
    main()
