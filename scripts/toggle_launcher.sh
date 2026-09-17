#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if quickshell ipc -p "$DIR" call launcher toggle 2>/dev/null; then
    exit 0
fi

if quickshell ipc call launcher toggle 2>/dev/null; then
    exit 0
fi

exec "$DIR/run.sh" launcher
