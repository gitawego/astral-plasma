#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Try quickshell IPC first if running
if quickshell ipc -p "$DIR" call launcher open wallpaper 2>/dev/null; then
    exit 0
fi

# Fallback IPC without -p
if quickshell ipc call launcher open wallpaper 2>/dev/null; then
    exit 0
fi

# If shell is not running, launch it with wallpaper picker active
exec "$DIR/run.sh" wallpaper
