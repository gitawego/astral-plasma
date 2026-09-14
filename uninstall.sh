#!/bin/bash
# Clean uninstaller for Caelestia Shell (zero residue)
set -euo pipefail

TARGET="$HOME/.config/quickshell"
CACHE_DIR="$HOME/.cache/caelestia"

echo "=== Uninstalling Caelestia Shell ==="

# Stop any running quickshell instance
pkill -f "quickshell" 2>/dev/null || true

# Remove symlink or restore backup
if [ -L "$TARGET" ]; then
    rm "$TARGET"
    echo "[✓] Removed symlink $TARGET"
fi

if [ -d "${TARGET}.backup" ]; then
    mv "${TARGET}.backup" "$TARGET"
    echo "[✓] Restored previous configuration from ${TARGET}.backup"
fi

# Remove desktop entries
rm -f "$HOME/.local/share/applications/caelestia-dashboard.desktop" "$HOME/.local/share/applications/caelestia-settings.desktop"
echo "[✓] Removed desktop shortcuts"

# Clean cache
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "[✓] Cleaned cache at $CACHE_DIR"
fi

echo "=== Uninstallation Complete! Desktop restored to original state. ==="
