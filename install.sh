#!/bin/bash
# Plug-and-play installer for Caelestia Shell
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.config/quickshell"

echo "=== Installing Caelestia KDE Shell ==="

# Check dependencies
if ! command -v quickshell >/dev/null 2>&1; then
    echo "[!] Quickshell is not installed. Please run: sudo pacman -S quickshell"
    exit 1
fi

if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    echo "[*] Backing up existing quickshell config to ${TARGET}.backup..."
    mv "$TARGET" "${TARGET}.backup"
elif [ -L "$TARGET" ]; then
    rm "$TARGET"
fi

mkdir -p "$HOME/.config"
ln -s "$DIR" "$TARGET"
echo "[✓] Symlinked $DIR -> $TARGET"

# Install desktop entries for app menu and shortcut binding
mkdir -p "$HOME/.local/share/applications"
cp -f "$DIR/shortcuts/"*.desktop "$HOME/.local/share/applications/"
echo "[✓] Installed desktop shortcuts in ~/.local/share/applications"

# Generate palette
bash "$DIR/scripts/generate_palette.sh" || true

echo "=== Installation Complete! ==="
echo "You can launch the shell using: quickshell"
echo "To uninstall cleanly at any time, simply run: $DIR/uninstall.sh"
