#!/bin/bash
# Granularly restores only shortcuts modified by Astral Plasma, preserving user modifications
set -euo pipefail

# Same lock as scripts/bind_shortcuts.sh: a restore racing a bind leaves both
# half-applied, and the concurrent KWin script reload has wedged KWin's
# scripting service.
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/astral-plasma-shortcuts.lock"
exec 9>"$LOCK_FILE"
flock 9

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_FILE="$HOME/.local/share/astral-plasma/shortcuts-backup/shortcuts_backup.json"

echo "[*] Restoring original shortcuts..."

# 1. Clean up Hyprland keybindings file if present
if [ -f "$HOME/.config/hypr/astral-binds.conf" ]; then
    rm -f "$HOME/.config/hypr/astral-binds.conf"
    echo "[✓] Removed Hyprland shortcuts file ~/.config/hypr/astral-binds.conf"
fi

# 2. If daemon binary exists, invoke the Rust domain use case
if [ -x "$DIR/bin/astral-plasma" ]; then
    if "$DIR/bin/astral-plasma" shortcuts restore 2>/dev/null; then
        echo "[✓] Shortcuts restored via astral-plasma domain service."
        exit 0
    fi
fi

# 2. Fallback: Native Python / D-Bus / kwriteconfig6 granular restoration
python3 - << 'PYEOF'
import json
import os
import subprocess

backup_file = os.path.expanduser("~/.local/share/astral-plasma/shortcuts-backup/shortcuts_backup.json")
if not os.path.exists(backup_file):
    print("[*] No active shortcuts backup file found. Ensuring Astral shortcuts are deactivated.")
    # Safe cleanup even if no backup file exists
    for key in ("AstralLauncher", "AstralWallpaper", "AstralOverview", "AstralAssistant", "AstralDashboard", "AstralSettings"):
        subprocess.run(["kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", "kwin", "--key", key, "--delete"], check=False)
    subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", "astral-plasma-shortcutsEnabled", "false"], check=False)
else:
    try:
        with open(backup_file, "r") as f:
            data = json.load(f)

        # 1. Revert ONLY affected entries
        for entry in data.get("affected_entries", []):
            grp = entry.get("group")
            key = entry.get("key")
            prev = entry.get("previous_value")
            if grp and key:
                if prev is None:
                    # Key was absent before the session: remove it
                    subprocess.run(["kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", grp, "--key", key, "--delete"], check=False)
                else:
                    # Key existed before: restore its exact previous value
                    subprocess.run(["kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", grp, "--key", key, prev], check=False)

        # 2. Restore displaced shortcuts if other actions had them
        for disp in data.get("displaced_actions", []):
            d_grp = disp.get("group")
            d_key = disp.get("key")
            d_val = disp.get("full_value")
            if d_grp and d_key and d_val:
                subprocess.run(["kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", d_grp, "--key", d_key, d_val], check=False)
        displaced = data.get("displaced_action")
        if displaced:
            d_grp = displaced.get("group")
            d_key = displaced.get("key")
            d_val = displaced.get("full_value")
            if d_grp and d_key and d_val:
                subprocess.run(["kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", d_grp, "--key", d_key, d_val], check=False)

        # 3. Deactivate the Astral KWin script.
        # This flag tells KWin to load the Astral shortcut script at login.
        # Restoring a previously-enabled value keeps KWin registering Astral
        # shortcuts (the bare Meta overview key included) with the theme not
        # running, which costs the user Alt+Tab. Always leave it off.
        subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", "astral-plasma-shortcutsEnabled", "false"], check=False)

        os.remove(backup_file)
    except Exception as e:
        print(f"[!] Warning reading backup file: {e}")

# 3. Unload KWin scripts & reconfigure
subprocess.run(["qdbus6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", "astral-plasma-shortcuts"], check=False)
subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"], check=False)

# 4. Clear active in-memory shortcuts from KGlobalAccel
try:
    import dbus
    bus = dbus.SessionBus()
    accel = dbus.Interface(bus.get_object('org.kde.kglobalaccel', '/kglobalaccel'), 'org.kde.KGlobalAccel')
    for key, label in (
        ("AstralLauncher", "Astral Plasma Launcher"),
        ("AstralWallpaper", "Astral Plasma Wallpaper Picker"),
        ("AstralOverview", "Astral Plasma: Active Apps Overview"),
        ("AstralAssistant", "Astral Plasma: Toggle AI Copilot"),
        ("AstralDashboard", "Astral Plasma: Toggle Dashboard"),
        ("AstralSettings", "Astral Plasma: Toggle Settings"),
    ):
        accel.setForeignShortcut(['kwin', key, 'default', label], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-launcher.desktop', '_launch', 'default', 'Astral Plasma Launcher'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-wallpaper.desktop', '_launch', 'default', 'Astral Plasma Wallpaper Picker'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-assistant.desktop', '_launch', 'default', 'Astral Plasma AI Copilot'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-dashboard.desktop', '_launch', 'default', 'Astral Dashboard'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-settings.desktop', '_launch', 'default', 'Astral Settings'], [dbus.Int32(0)])

    # 5. Hand the user's own keys back to KGlobalAccel.
    # A config rewrite does not move the running registration, so a restored
    # file alone leaves the shortcuts dead until the next login - that is how
    # the launcher's bare Meta and Meta+W (Overview) were silently lost. The
    # journal records the key codes each action held before the session claimed
    # it; replay them exactly.
    def action_label(value):
        fields = str(value or '').split(',')
        return fields[2].strip() if len(fields) > 2 and fields[2].strip() else None

    def rearm(entries, value_of):
        for entry in entries:
            group, key = entry.get('group'), entry.get('key')
            codes = entry.get('keys') or []
            label = action_label(value_of(entry))
            if not (group and key and codes and label):
                continue
            accel.setForeignShortcut([group, key, group, label], [dbus.Int32(int(code)) for code in codes])

    rearm(data.get('affected_entries', []), lambda e: e.get('previous_value'))
    displaced = list(data.get('displaced_actions', []))
    if data.get('displaced_action'):
        displaced.append(data['displaced_action'])
    rearm(displaced, lambda d: d.get('full_value'))
except Exception:
    pass

print("[✓] Live compositor & KGlobalAccel shortcut registration cleared.")
PYEOF

echo "[✓] Astral shortcuts cleanly restored!"
