#!/bin/bash
# Plug-and-play installer for Astral Plasma Shell
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.config/quickshell"

echo "=== Installing Astral Plasma Shell ==="

# Check dependencies
if ! command -v quickshell >/dev/null 2>&1; then
    echo "[!] Quickshell is not installed. Please run: sudo pacman -S quickshell"
    exit 1
fi

IS_OMARCHY=0
if [ "${1:-}" = "--omarchy" ] || [ -n "${OMARCHY_SESSION_ID:-}" ] || [ -n "${OMARCHY_DIR:-}" ] || [ -n "${OMARCHY_SESSION:-}" ]; then
    IS_OMARCHY=1
fi

if [ "$IS_OMARCHY" -eq 1 ]; then
    echo "[*] Detected Omarchy environment. Installing Astral Plasma as an Omarchy plugin..."
    if [ ! -f "$DIR/bin/astral-plasma" ]; then
        echo "[*] Building daemon binary..."
        make -C "$DIR" build
    fi
    "$DIR/bin/astral-plasma" omarchy install
    echo "[✓] Installed into Omarchy plugins directory"
else
    if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
        echo "[*] Backing up existing quickshell config to ${TARGET}.backup..."
        mv "$TARGET" "${TARGET}.backup"
    elif [ -L "$TARGET" ]; then
        rm "$TARGET"
    fi

    mkdir -p "$HOME/.config"
    ln -s "$DIR" "$TARGET"
    echo "[✓] Symlinked $DIR -> $TARGET"
fi

# Desktop shortcuts and Wayland session files are NOT installed automatically.
# Users can explicitly install/remove them anytime from Settings -> System & Services.

# Generate palette if matugen is available
if command -v matugen >/dev/null 2>&1; then
    bash "$DIR/scripts/generate_palette.sh" || true
fi

echo "=== Installation Complete! ==="
if [ "$IS_OMARCHY" -eq 1 ]; then
    echo "Astral Plasma is installed in Omarchy. Restart omarchy-shell to load the plugin."
else
    echo "You can launch the shell using: ./run.sh (or quickshell)"
    echo "Or select 'Astral Plasma (KWin)' directly from your display manager (SDDM/GDM)."
fi
echo "To uninstall cleanly at any time, simply run: $DIR/uninstall.sh"
