#!/bin/bash
# Resolve symlinks: the installed desktop entries run these scripts through
# ~/.config/quickshell, and Quickshell matches instances by the path it was
# started with - an unresolved path addresses no instance.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

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
