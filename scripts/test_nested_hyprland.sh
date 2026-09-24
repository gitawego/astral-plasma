#!/bin/bash
# Test Astral Plasma inside a nested Hyprland window on KDE Wayland
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Starting Nested Hyprland Test Environment ==="

if ! command -v Hyprland >/dev/null 2>&1; then
    echo "[!] Hyprland binary not found. Please install it first (e.g. sudo pacman -S hyprland)"
    exit 1
fi

CONF=$(mktemp --suffix=.conf)
cat << 'EOF' > "$CONF"
monitor=,1920x1080,auto,1
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}
EOF

cleanup() {
    echo ""
    echo "[*] Cleaning up nested Hyprland session..."
    if [ -n "${HPID:-}" ]; then
        kill "$HPID" 2>/dev/null || true
    fi
    rm -f "$CONF"
    echo "[✓] Cleaned up."
}
trap cleanup EXIT INT TERM

echo "[*] Launching nested Hyprland compositor window..."
Hyprland -c "$CONF" >/dev/null 2>&1 &
HPID=$!

# Wait for Hyprland socket to become ready
SIG=""
for i in {1..20}; do
    if [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
        SIG=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n 1 || true)
        if [ -n "$SIG" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ]; then
            break
        fi
    fi
    sleep 0.2
done

if [ -z "$SIG" ] || [ ! -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ]; then
    echo "[!] Failed to connect to nested Hyprland socket."
    exit 1
fi

echo "[✓] Nested Hyprland is running!"
echo "    PID:       $HPID"
echo "    Signature: $SIG"
echo ""

echo "[*] Testing Astral Plasma daemon snapshot against Hyprland..."
HYPRLAND_INSTANCE_SIGNATURE="$SIG" "$DIR/bin/astral-plasma" session snapshot
echo ""

echo "------------------------------------------------------------------"
echo "Nested Hyprland window is open on your desktop."
echo "Options:"
echo "  1) Launch Astral Plasma shell inside this nested window"
echo "  2) Keep nested Hyprland open for manual inspection (Ctrl+C to quit)"
echo "------------------------------------------------------------------"

if [ "${1:-}" = "--shell" ] || [ "${1:-}" = "-s" ]; then
    CHOICE="1"
else
    read -p "Select option [1/2] (default: 1): " -r CHOICE || CHOICE="1"
fi

if [ "$CHOICE" = "1" ] || [ -z "$CHOICE" ]; then
    echo "[*] Launching Astral Plasma Quickshell inside nested Hyprland window..."
    echo "[*] Press Ctrl+C at any time to exit and close the window."
    WAYLAND_DISPLAY="wayland-1" HYPRLAND_INSTANCE_SIGNATURE="$SIG" quickshell -p "$DIR" || true
else
    echo "[*] Running nested session. Press Ctrl+C to close."
    wait "$HPID"
fi
