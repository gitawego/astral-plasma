#!/usr/bin/env bash
# install-quickshell-webengine-shim.sh — let a stock Quickshell host QtWebEngine.
#
# Builds the LD_PRELOAD shim and installs it under ~/.local, so no root and no
# Quickshell rebuild are needed. `astral-plasma run` picks it up automatically
# (see daemon/src/domain/quickshell_host.rs).
#
#   ./install-quickshell-webengine-shim.sh [--uninstall]
#
# Requires: g++ (or $CXX) and qt6-webengine at runtime.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/quickshell-webengine-shim.cpp"
LIB_DIR="$HOME/.local/lib/astral-plasma"
LIB="$LIB_DIR/libquickshell-webengine-shim.so"

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$LIB"
  echo "removed $LIB"
  exit 0
fi

if [ ! -f "$SRC" ]; then
  echo "error: $SRC not found" >&2
  exit 1
fi

CXX_BIN="${CXX:-g++}"
command -v "$CXX_BIN" >/dev/null 2>&1 || { echo "error: $CXX_BIN not found (install gcc)" >&2; exit 1; }
[ -e /usr/lib/libQt6WebEngineQuick.so.6 ] || echo "warning: libQt6WebEngineQuick.so.6 not found; install qt6-webengine" >&2

mkdir -p "$LIB_DIR"
"$CXX_BIN" -shared -fPIC -O2 -std=c++17 -o "$LIB" "$SRC" -ldl

if [ -f "$LIB" ]; then
  echo "installed $LIB"
  echo "Astral will now launch Quickshell with this shim automatically."
  echo "Disable with ASTRAL_QUICKSHELL_PRELOAD=0, or override the path with"
  echo "ASTRAL_QUICKSHELL_PRELOAD=/path/to/other.so."
else
  echo "error: build produced no library" >&2
  exit 1
fi
