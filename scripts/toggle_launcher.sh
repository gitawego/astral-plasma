#!/bin/bash
# Resolve symlinks: the installed desktop entries run these scripts through
# ~/.config/quickshell, and Quickshell matches instances by the path it was
# started with - an unresolved path addresses no instance.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if quickshell ipc -p "$DIR" call launcher toggle 2>/dev/null; then
    exit 0
fi

if quickshell ipc call launcher toggle 2>/dev/null; then
    exit 0
fi

exec "$DIR/run.sh" launcher
