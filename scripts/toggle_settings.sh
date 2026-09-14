#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
quickshell ipc -p "$DIR" call settings toggle 2>/dev/null || quickshell ipc call settings toggle 2>/dev/null || true
