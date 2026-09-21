#!/bin/bash
# Resolve symlinks: the installed desktop entries run these scripts through
# ~/.config/quickshell, and Quickshell matches instances by the path it was
# started with - an unresolved path addresses no instance.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
quickshell ipc -p "$DIR" call settings toggle 2>/dev/null || quickshell ipc call settings toggle 2>/dev/null || true
