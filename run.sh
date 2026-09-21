#!/bin/bash
# Safe live testing script - runs without modifying KDE Plasma system config
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if an instance is already running and handle IPC commands
MODE="${1:-}"
if [ "$MODE" = "wallpaper" ] || [ "$MODE" = "--wallpaper" ] || [ "$MODE" = "-w" ]; then
    if quickshell ipc -p "$DIR" call launcher open wallpaper 2>/dev/null; then
        echo "[*] Quickshell is already running. Wallpaper picker opened via IPC."
        exit 0
    fi
    export ASTRAL_PLASMA_LAUNCHER_OPEN=1
    export ASTRAL_PLASMA_LAUNCHER_MODE=wallpaper
elif [ "$MODE" = "launcher" ] || [ "$MODE" = "--launcher" ]; then
    if quickshell ipc -p "$DIR" call launcher toggle 2>/dev/null; then
        echo "[*] Quickshell is already running. Launcher toggled via IPC."
        exit 0
    fi
    export ASTRAL_PLASMA_LAUNCHER_OPEN=1
    export ASTRAL_PLASMA_LAUNCHER_MODE=apps
fi

echo "=========================================================="
echo " Starting Astral Plasma Shell (Dev Preview)"
echo " Safe mode: does NOT modify your existing desktop settings."
echo " Press Ctrl+C at any time to exit safely."
echo "=========================================================="

# Generate initial dynamic palette if needed
bash "$DIR/scripts/generate_palette.sh" || true

# Ensure astral-plasma daemon binary is built
if [ ! -f "$DIR/bin/astral-plasma" ]; then
    echo "[*] Building astral-plasma daemon binary..."
    cargo build --release --manifest-path "$DIR/daemon/Cargo.toml"
    mkdir -p "$DIR/bin"
    cp -f "$DIR/daemon/target/release/astral-plasma" "$DIR/bin/astral-plasma"
fi

# Ensure shortcuts are bound and original state is snapshotted
bash "$DIR/scripts/bind_shortcuts.sh" meta-space || true

# Tune KWin compositor blur for the shell's liquid glass. KWin executes the
# BackgroundEffect blur regions behind the panel, and an excessive radius
# homogenises the backdrop into flat grey - which makes even a genuinely
# translucent panel read as an opaque slab. This applies the configured glass
# fidelity to kwinrc; without it that setting is dead config.
if [ -x "$DIR/bin/astral-plasma" ]; then
    BLUR_PREF=$(python3 -c "
import json,sys
try:
    import os
    user = os.path.join(os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')), 'astral-plasma', 'settings.json')
    path = user if os.path.exists(user) else '$DIR/config/settings.json'
    print(json.load(open(path)).get('theme',{}).get('blurStrength', 0.85))
except Exception:
    print(0.85)
" 2>/dev/null || echo 0.85)
    "$DIR/bin/astral-plasma" blur fidelity "$BLUR_PREF" >/dev/null 2>&1 || true
fi

# Cleanup trap to restore original shortcuts and Plasma panels when Astral shell exits
cleanup() {
    trap - EXIT INT TERM
    echo ""
    echo "[*] Astral closed - cleanly restoring original shortcuts and Plasma panels..."
    if [ -n "${QS_PID:-}" ] && kill -0 "$QS_PID" 2>/dev/null; then
        kill -TERM "$QS_PID" 2>/dev/null || true
        sleep 0.3
        if kill -0 "$QS_PID" 2>/dev/null; then
            kill -9 "$QS_PID" 2>/dev/null || true
        fi
    fi
    bash "$DIR/scripts/restore_shortcuts.sh" || true
    if [ -x "$DIR/bin/astral-plasma" ]; then
        "$DIR/bin/astral-plasma" plasma restore || true
    fi
}
trap cleanup EXIT INT TERM

# Run quickshell and monitor process
quickshell -p "$DIR" &
QS_PID=$!

# Disable Plasma panels and launch watchdog monitoring Quickshell
if [ -x "$DIR/bin/astral-plasma" ]; then
    "$DIR/bin/astral-plasma" plasma disable all "$QS_PID" >/dev/null 2>&1 || true
fi

# Wait for quickshell to exit
wait "$QS_PID" || true
