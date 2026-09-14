#!/usr/bin/env python3
import subprocess
import re
import json

def get_window_meta(title, wid, krunner_icon):
    t_lower = title.lower()
    
    app_name = 'Window'
    icon_name = krunner_icon if krunner_icon else ''
    mat_icon = 'desktop_windows'
    
    if 'edge' in t_lower:
        app_name = 'Edge'
        icon_name = icon_name or 'microsoft-edge'
        mat_icon = 'language'
    elif 'code' in t_lower or 'visual studio' in t_lower:
        app_name = 'VS Code'
        icon_name = icon_name or 'vscode'
        mat_icon = 'code'
    elif 'dolphin' in t_lower:
        app_name = 'Files'
        icon_name = icon_name or 'org.kde.dolphin'
        mat_icon = 'folder'
    elif 'ghostty' in t_lower or 'terminal' in t_lower or 'konsole' in t_lower or 'workspace' in t_lower:
        app_name = 'Terminal'
        icon_name = icon_name or 'utilities-terminal'
        mat_icon = 'terminal'
    elif 'haruna' in t_lower or 'mp4' in t_lower or 'mkv' in t_lower:
        app_name = 'Haruna'
        icon_name = icon_name or 'haruna'
        mat_icon = 'movie'
    elif 'lutris' in t_lower:
        app_name = 'Lutris'
        icon_name = icon_name or 'net.lutris.Lutris'
        mat_icon = 'sports_esports'
    elif 'token tracker' in t_lower:
        app_name = 'Tracker'
        icon_name = icon_name or 'token-tracker'
        mat_icon = 'insights'
    elif 'discord' in t_lower or 'vesktop' in t_lower:
        app_name = 'Discord'
        icon_name = icon_name or 'discord'
        mat_icon = 'chat'
    elif 'steam' in t_lower:
        app_name = 'Steam'
        icon_name = icon_name or 'steam'
        mat_icon = 'sports_esports'
    elif 'spotify' in t_lower or 'music' in t_lower or 'raye' in t_lower or 'bikabreezy' in t_lower or 'song' in t_lower:
        app_name = 'Music'
        icon_name = icon_name or 'org.strawberrymusicplayer.strawberry'
        mat_icon = 'music_note'
    elif 'antigravity' in t_lower or 'caelestia' in t_lower:
        app_name = 'Antigravity'
        icon_name = icon_name or 'ai.opencode.desktop'
        mat_icon = 'smart_toy'
    elif 'gradia' in t_lower:
        app_name = 'Gradia'
        icon_name = icon_name or 'image-viewer'
        mat_icon = 'palette'
    else:
        parts = re.split(r' [—\-] ', title)
        if len(parts) > 1:
            app_name = parts[-1].strip()[:14]
        else:
            app_name = title[:14]
        mat_icon = 'window'

    return app_name, icon_name, mat_icon

def get_active_uuid():
    try:
        script = """
        var w = workspace.activeWindow;
        if (w) {
            console.warn("CAELESTIA_ACTIVE_ID:" + ("" + w.internalId).replace("{", "").replace("}", ""));
        } else {
            console.warn("CAELESTIA_ACTIVE_ID:NONE");
        }
        """
        with open('/tmp/caelestia_active_query.js', 'w') as f:
            f.write(script)

        num = subprocess.check_output(
            ['qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.loadScript', '/tmp/caelestia_active_query.js'],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        subprocess.run(['qdbus6', 'org.kde.KWin', f'/Scripting/Script{num}', 'org.kde.kwin.Script.run'], stderr=subprocess.DEVNULL)
        subprocess.run(['qdbus6', 'org.kde.KWin', f'/Scripting/Script{num}', 'org.kde.kwin.Script.stop'], stderr=subprocess.DEVNULL)

        j = subprocess.check_output(['journalctl', '--user', '-b', '-n', '3', '-o', 'cat'], stderr=subprocess.DEVNULL).decode()
        for line in j.splitlines():
            if 'CAELESTIA_ACTIVE_ID:' in line:
                return line.split('CAELESTIA_ACTIVE_ID:')[-1].strip()
    except Exception:
        pass
    return ""

def main():
    active_uuid = get_active_uuid()

    windows = []
    active_win = None
    try:
        out = subprocess.check_output(
            ['qdbus6', '--literal', 'org.kde.KWin', '/WindowsRunner', 'org.kde.krunner1.Match', ''],
            stderr=subprocess.DEVNULL
        ).decode('utf-8')
        pattern = r'\[Argument:\s*\(sssida\{sv\}\)\s*\"([^\"]+)\",\s*\"([^\"]+)\",\s*\"([^\"]*)\"'
        matches = re.findall(pattern, out)
        seen = set()
        for idx, (wid, title, icon) in enumerate(matches):
            if title in seen:
                continue
            seen.add(title)
            app_name, icon_name, mat_icon = get_window_meta(title, wid, icon)
            is_active = (active_uuid and active_uuid in wid) if active_uuid else (idx == 0)
            win_obj = {
                'id': wid,
                'title': title,
                'appName': app_name,
                'iconName': icon_name,
                'materialIcon': mat_icon,
                'isActive': is_active
            }
            if is_active:
                active_win = win_obj
            windows.append(win_obj)
    except Exception:
        pass

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
