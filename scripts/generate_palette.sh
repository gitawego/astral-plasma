#!/bin/bash
# Generate Material You colors dynamically using matugen
set -euo pipefail

CACHE_DIR="$HOME/.cache/caelestia"
mkdir -p "$CACHE_DIR"

WALLPAPER=""

# Detect wallpaper from KDE Plasma config if available
if [ -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
    WALLPAPER=$(grep -m 1 -E "Image=" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" | cut -d '=' -f 2 | sed 's|file://||' || true)
fi

# Fallback wallpaper if none detected
if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    WALLPAPER="$SCRIPT_DIR/theme/assets/wallpaper.webp"
fi

if [ -f "$WALLPAPER" ] && command -v matugen >/dev/null 2>&1; then
    echo "[Palette] Generating Material You palette from: $WALLPAPER"
    matugen image "$WALLPAPER" --source-color-index 0 --json hex > "$CACHE_DIR/colors.json" 2>/dev/null || true
    echo "[Palette] Successfully written to $CACHE_DIR/colors.json"
else
    echo "[Palette] Matugen not found or wallpaper not found; using Caelestia pastel defaults"
fi
