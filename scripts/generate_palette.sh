#!/bin/bash
# Generate Material You colors dynamically using matugen
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/astral-plasma"
mkdir -p "$CACHE_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WALLPAPER=""

# The daemon answers with the wallpaper the desktop is actually showing (Plasma's
# containment image), which is the same value the picker focuses. Parsing the
# config here as well would duplicate that logic and drift from it.
if [ -x "$SCRIPT_DIR/bin/astral-plasma" ]; then
    WALLPAPER=$("$SCRIPT_DIR/bin/astral-plasma" wallpaper get --raw 2>/dev/null || true)
fi

# Fallback wallpaper if none detected
if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    WALLPAPER="$SCRIPT_DIR/theme/assets/wallpaper.webp"
fi

if [ -f "$WALLPAPER" ] && command -v matugen >/dev/null 2>&1; then
    echo "[Palette] Generating Material You palette from: $WALLPAPER"
    matugen image "$WALLPAPER" --source-color-index 0 --json hex > "$CACHE_DIR/colors.json" 2>/dev/null || true
    echo "[Palette] Successfully written to $CACHE_DIR/colors.json"
else
    echo "[Palette] Matugen not found or wallpaper not found; using default pastel palette"
fi
