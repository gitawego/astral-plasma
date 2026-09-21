#!/bin/bash
# Clean uninstaller for Astral Plasma Shell (zero residue)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.config/quickshell"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

echo "=== Uninstalling Astral Plasma Shell ==="

# Stop any running quickshell instance
pkill -f "quickshell" 2>/dev/null || true

# Remove user service
if [ -f "$CONFIG_HOME/systemd/user/astral-plasma.service" ]; then
    systemctl --user disable --now astral-plasma.service 2>/dev/null || true
    rm -f "$CONFIG_HOME/systemd/user/astral-plasma.service"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "[✓] Removed user service astral-plasma.service"
fi

# Remove symlink or restore backup
if [ -L "$TARGET" ]; then
    rm "$TARGET"
    echo "[✓] Removed symlink $TARGET"
fi

if [ -d "${TARGET}.backup" ]; then
    mv "${TARGET}.backup" "$TARGET"
    echo "[✓] Restored previous configuration from ${TARGET}.backup"
fi

# Remove KWin script package
if [ -d "$DATA_HOME/kwin/scripts/astral-plasma-shortcuts" ]; then
    rm -rf "$DATA_HOME/kwin/scripts/astral-plasma-shortcuts"
    echo "[✓] Removed KWin script astral-plasma-shortcuts"
fi

# Unbind global shortcuts and drop the plugin toggle
for key in AstralLauncher AstralWallpaper; do
    kwriteconfig6 --file kglobalshortcutsrc --group "kwin" --key "$key" --delete 2>/dev/null || true
done
kwriteconfig6 --file kwinrc --group "Plugins" --key "astral-plasma-shortcutsEnabled" --delete 2>/dev/null || true

# Remove desktop entries
rm -f "$DATA_HOME/applications/astral-dashboard.desktop" \
      "$DATA_HOME/applications/astral-settings.desktop" \
      "$DATA_HOME/applications/astral-launcher.desktop" \
      "$DATA_HOME/applications/astral-wallpaper.desktop" \
      "$DATA_HOME/applications/astral-plasma.desktop"
kbuildsycoca6 2>/dev/null || true
echo "[✓] Removed desktop shortcuts"

# Clean data, cache and state
for dir in "$DATA_HOME/astral-plasma" "$CACHE_HOME/astral-plasma" "$STATE_HOME/astral-plasma"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        echo "[✓] Removed $dir"
    fi
done

# Clean temporary runtime artifacts
rm -rf /tmp/astral_plasma_* /tmp/astral-plasma.sock 2>/dev/null || true

echo "=== Uninstallation Complete! Desktop restored to original state. ==="
