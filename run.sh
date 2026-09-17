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
    export CAELESTIA_LAUNCHER_OPEN=1
    export CAELESTIA_LAUNCHER_MODE=wallpaper
elif [ "$MODE" = "launcher" ] || [ "$MODE" = "--launcher" ]; then
    if quickshell ipc -p "$DIR" call launcher toggle 2>/dev/null; then
        echo "[*] Quickshell is already running. Launcher toggled via IPC."
        exit 0
    fi
    export CAELESTIA_LAUNCHER_OPEN=1
    export CAELESTIA_LAUNCHER_MODE=apps
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

# Cleanup trap to restore original shortcuts when Astral shell exits
cleanup() {
    echo ""
    echo "[*] Astral closed - cleanly restoring original shortcuts..."
    bash "$DIR/scripts/restore_shortcuts.sh" || true
}
trap cleanup EXIT INT TERM

# Run quickshell and monitor process
quickshell -p "$DIR" &
QS_PID=$!

# Spawn watchdog to ensure original shortcuts and panels are restored even if killed abruptly
if [ -x "$DIR/bin/astral-plasma" ]; then
    "$DIR/bin/astral-plasma" plasma watchdog "$QS_PID" >/dev/null 2>&1 &
fi

# Wait for quickshell to exit
wait "$QS_PID" || true
