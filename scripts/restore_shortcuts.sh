#!/bin/bash
# Granularly restores only shortcuts modified by Astral Plasma, preserving user modifications
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_FILE="$HOME/.local/share/astral-plasma/shortcuts-backup/shortcuts_backup.json"

echo "[*] Restoring original shortcuts..."

# 1. If daemon binary exists, invoke the Rust domain use case
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
    for key in ("AstralLauncher", "AstralWallpaper"):
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

        # 2. Restore displaced shortcut if another action had it
        displaced = data.get("displaced_action")
        if displaced:
            d_grp = displaced.get("group")
            d_key = displaced.get("key")
            d_val = displaced.get("full_value")
            if d_grp and d_key and d_val:
                subprocess.run(["kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", d_grp, "--key", d_key, d_val], check=False)

        # 3. Restore kwin plugin state
        prev_plugin = data.get("previous_kwin_plugin_enabled", False)
        plugin_val = "true" if prev_plugin else "false"
        subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", "astral-plasma-shortcutsEnabled", plugin_val], check=False)

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
    ):
        accel.setForeignShortcut(['kwin', key, 'default', label], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-launcher.desktop', '_launch', 'default', 'Astral Plasma Launcher'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-wallpaper.desktop', '_launch', 'default', 'Astral Plasma Wallpaper Picker'], [dbus.Int32(0)])
except Exception:
    pass

print("[✓] Live compositor & KGlobalAccel shortcut registration cleared.")
PYEOF

echo "[✓] Astral shortcuts cleanly restored!"
