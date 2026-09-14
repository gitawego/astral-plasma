#!/bin/bash
# Clean uninstaller for Caelestia Shell (zero residue)
set -euo pipefail

TARGET="$HOME/.config/quickshell"
CACHE_DIR="$HOME/.cache/astral"

echo "=== Uninstalling Astral Plasma Shell ==="

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
rm -f "$HOME/.local/share/applications/astral-dashboard.desktop" "$HOME/.local/share/applications/astral-settings.desktop"
echo "[✓] Removed desktop shortcuts"

# Clean cache
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "[✓] Cleaned cache at $CACHE_DIR"
fi

echo "=== Uninstallation Complete! Desktop restored to original state. ==="
