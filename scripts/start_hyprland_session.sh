#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Clean up any existing nested Hyprland instance
pkill -f "Hyprland" 2>/dev/null || true
sleep 0.5

echo "[*] Starting nested Hyprland window..."
Hyprland >/tmp/hyprland_nested.log 2>&1 &
HPID=$!

# 2. Wait for Hyprland instance signature
SIG=""
for i in {1..30}; do
    if [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
        SIG=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n 1 || true)
        if [ -n "$SIG" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ]; then
            break
        fi
    fi
    sleep 0.2
done

if [ -z "$SIG" ]; then
    echo "[!] Hyprland socket did not appear."
    exit 1
fi

echo "[✓] Hyprland active (PID: $HPID, SIG: $SIG)"

# 3. Determine the Wayland display name for this nested compositor
NESTED_WAYLAND="wayland-1"
for s in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$s" ] && [ "$(basename "$s")" != "wayland-0" ]; then
        NESTED_WAYLAND=$(basename "$s")
        break
    fi
done

echo "[*] Found nested Wayland display: $NESTED_WAYLAND"

# 4. Start Astral Plasma shell inside nested Hyprland
echo "[*] Starting Astral Plasma theme on $NESTED_WAYLAND..."
WAYLAND_DISPLAY="$NESTED_WAYLAND" HYPRLAND_INSTANCE_SIGNATURE="$SIG" quickshell -p "$DIR" >/tmp/astral_nested_quickshell.log 2>&1 &
QPID=$!

echo "[✓] Astral Plasma launched inside nested Hyprland (PID: $QPID)"
echo "HPID=$HPID" > /tmp/astral_nested_session.env
echo "SIG=$SIG" >> /tmp/astral_nested_session.env
echo "QPID=$QPID" >> /tmp/astral_nested_session.env
echo "WAYLAND_DISPLAY=$NESTED_WAYLAND" >> /tmp/astral_nested_session.env

echo "=== Session Ready! ==="
