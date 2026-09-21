#!/bin/bash
# Helper script to bind Astral Plasma keyboard shortcuts in KDE Plasma 6
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The desktop entries launch through the Quickshell config symlink, so they
# survive moving the checkout instead of hardcoding this machine's path.
QS_CONFIG="$HOME/.config/quickshell"
if [ ! -e "$QS_CONFIG" ]; then
    mkdir -p "$HOME/.config"
    ln -s "$DIR" "$QS_CONFIG"
fi

# Ensure desktop entries are installed in ~/.local/share/applications
mkdir -p "$HOME/.local/share/applications"
cp -f "$DIR/shortcuts/"*.desktop "$HOME/.local/share/applications/"
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true

MODE="${1:-meta-space}"

# 0. Atomically snapshot original shortcuts before applying overrides (idempotent)
if [ -x "$DIR/bin/astral-plasma" ]; then
    "$DIR/bin/astral-plasma" shortcuts snapshot "$MODE" 2>/dev/null || true
fi

case "$MODE" in
    "meta-space"|"space")
        echo "[*] Setting Astral Plasma Launcher shortcut to: Meta+Space (Super+Space)"
        LAUNCHER_KEY="Meta+Space"
        ;;
    "meta"|"super")
        echo "[*] Setting Astral Plasma Launcher shortcut to: Meta key (Super key alone via Alt+F1)"
        LAUNCHER_KEY="Alt+F1"
        # Avoid conflict with default plasmashell menu
        kwriteconfig6 --file kglobalshortcutsrc --group "plasmashell" --key "activate application launcher" "none,none,Activate Application Launcher"
        ;;
    "alt-space")
        echo "[*] Setting Astral Plasma Launcher shortcut to: Alt+Space"
        LAUNCHER_KEY="Alt+Space"
        ;;
    *)
        echo "Usage: $0 [meta-space | meta | alt-space]"
        exit 1
        ;;
esac

# The KWin actions own the shortcuts. Their handler forwards to the daemon,
# which runs the shell's IPC (a KWin script cannot launch processes, and
# kglobalaccel's invokeShortcut on a .desktop service only emits a signal nobody
# launches). The `services` entries must stay unbound: two owners of one key
# means neither reliably fires.
kwriteconfig6 --file kglobalshortcutsrc --group "kwin" --key "AstralLauncher" "$LAUNCHER_KEY,none,Astral Plasma: Toggle Launcher"
kwriteconfig6 --file kglobalshortcutsrc --group "kwin" --key "AstralWallpaper" "Meta+Shift+W,none,Astral Plasma: Open Wallpaper Picker"
for entry in astral-launcher.desktop astral-wallpaper.desktop; do
    kwriteconfig6 --file kglobalshortcutsrc --group "services" --group "$entry" --key "_launch" --delete 2>/dev/null || true
done

# 1. Install / update KWin script package
KWIN_SCRIPT_SRC="$DIR/kwin/astral-plasma-shortcuts"
KWIN_SCRIPT_DEST="$HOME/.local/share/kwin/scripts/astral-plasma-shortcuts"
mkdir -p "$KWIN_SCRIPT_DEST/contents/code"
cp -f "$KWIN_SCRIPT_SRC/metadata.json" "$KWIN_SCRIPT_DEST/"
cp -f "$KWIN_SCRIPT_SRC/contents/code/main.js" "$KWIN_SCRIPT_DEST/contents/code/"

# Enable in kwinrc
kwriteconfig6 --file kwinrc --group "Plugins" --key "astral-plasma-shortcutsEnabled" "true"

# 2. Dynamically reload KWin script in running session
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "astral-plasma-shortcuts" 2>/dev/null || true
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$KWIN_SCRIPT_DEST/contents/code/main.js" "astral-plasma-shortcuts" 2>/dev/null || true
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start 2>/dev/null || true

# 3. Ensure kglobalaccel registration and conflict-free single ownership
python3 - <<EOF
import dbus

KEY_CODES = {
    "meta-space": 268435488,   # Meta+Space
    "space": 268435488,
    "meta": 150994992,         # Alt+F1 (Super key trigger)
    "super": 150994992,
    "alt-space": 134217760,     # Alt+Space
}

mode = "$MODE"
launcher_key = KEY_CODES.get(mode, 268435488)
wallpaper_key = 301989975       # Meta+Shift+W

try:
    bus = dbus.SessionBus()
    accel = dbus.Interface(bus.get_object('org.kde.kglobalaccel', '/kglobalaccel'), 'org.kde.KGlobalAccel')

    # Register desktop targets for launch invocation
    accel.doRegister(['astral-launcher.desktop', '_launch', 'astral-launcher.desktop', 'Astral Plasma Launcher'])
    accel.doRegister(['astral-wallpaper.desktop', '_launch', 'astral-wallpaper.desktop', 'Astral Plasma Wallpaper Picker'])

    # Clear the .desktop services so the KWin action has sole ownership of the key
    accel.setForeignShortcut(['astral-launcher.desktop', '_launch', 'default', 'Astral Plasma Launcher'], [dbus.Int32(0)])
    accel.setForeignShortcut(['astral-wallpaper.desktop', '_launch', 'default', 'Astral Plasma Wallpaper Picker'], [dbus.Int32(0)])

    # The KWin actions own the shortcuts; their script forwards to the daemon,
    # which runs the shell IPC.
    accel.setForeignShortcut(['kwin', 'AstralLauncher', 'default', 'Astral Plasma: Toggle Launcher'], [dbus.Int32(launcher_key)])
    accel.setForeignShortcut(['kwin', 'AstralWallpaper', 'default', 'Astral Plasma: Open Wallpaper Picker'], [dbus.Int32(wallpaper_key)])

    print("[✓] Dynamically registered in KWin compositor & KGlobalAccel")
except Exception as e:
    print(f"[!] DBus registration notice: {e}")
EOF

# Reload KWin
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
echo "[✓] Global shortcut configured and active!"
