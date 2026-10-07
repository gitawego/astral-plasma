#!/bin/bash
# Open the DSH web app (DeepSeek Harness). Resolve symlinks: the installed
# desktop entries run these scripts through ~/.config/quickshell, and Quickshell
# matches instances by the path it was started with - an unresolved path
# addresses no instance.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
quickshell ipc -p "$DIR" call dshweb open 2>/dev/null || quickshell ipc call dshweb open 2>/dev/null || true
