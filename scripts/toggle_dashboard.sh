#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
quickshell ipc -p "$DIR" call dashboard toggle 2>/dev/null || quickshell ipc call dashboard toggle 2>/dev/null || true
