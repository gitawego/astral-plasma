#!/usr/bin/env bash
# build-quickshell-webengine.sh — build a QtWebEngine-capable Quickshell.
#
# WHY THIS EXISTS
# Stock Quickshell cannot host a `WebEngineView`: instantiating one aborts the
# process with
#   FATAL: Argument list is empty, the program name is not passed to
#          QCoreApplication. base::CommandLine cannot be properly initialized.
# QtWebEngine requires `QtWebEngineQuick::initialize()` before `QGuiApplication`
# is constructed, and Chromium needs argv[0]. Quickshell does neither
# (upstream: quickshell-mirror/quickshell#298, open). This script clones
# Quickshell, applies three small edits, and builds it:
#   1. launch.cpp: `auto qArgC = 0;` -> `1`      (Chromium needs argv[0])
#   2. a dlopen shim that calls QtWebEngineQuick::initialize()
#   3. a `//@ pragma UseWebEngine` opt-in that calls the shim before QGuiApplication
#
# After building/installing, a shell enables it by putting this at the very top
# of shell.qml (before any import):
#   //@ pragma UseWebEngine
# ...and then `import QtWebEngine` in the file that instantiates a WebEngineView.
#
# USAGE
#   ./build-quickshell-webengine.sh [options]
#     --ref <git-ref>      Quickshell ref to build            (default: master)
#     --build-root <dir>   workspace for src/deps/tools        (default: /tmp/quickshell-webengine)
#     --src <dir>          use an existing Quickshell checkout (skips clone)
#     --prefix <dir>       install prefix                      (default: /usr/local)
#     --system-deps        assume CLI11 + Vulkan-Headers are installed system-wide
#     --install            run `cmake --install` (needs write access to --prefix)
#     --patch-only         clone + patch, then stop (fast sanity check)
#     -h, --help           this help
#
# BUILD DEPS (Arch example):
#   sudo pacman -S --needed qt6-base qt6-declarative qt6-svg qt6-wayland \
#     qt6-shadertools qt6-webengine wayland-protocols spirv-tools pkgconf \
#     jemalloc cpptrace libdrm mesa
#   cmake + ninja are auto-provisioned into a local venv if absent.
#   CLI11 + Vulkan-Headers are fetched into the build root if absent.

set -euo pipefail

REF="${QS_REF:-master}"
BUILD_ROOT="${QS_WEBENGINE_BUILD_ROOT:-/tmp/quickshell-webengine}"
PREFIX="/usr/local"
SRC=""
INSTALL=0
PATCH_ONLY=0
SYSTEM_DEPS=0

usage() {
  sed -n '2,40p' "$0" | sed 's/^# {0,1}//'
  exit "${1:-0}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)          REF="$2"; shift 2 ;;
    --build-root)   BUILD_ROOT="$2"; shift 2 ;;
    --src)          SRC="$2"; shift 2 ;;
    --prefix)       PREFIX="$2"; shift 2 ;;
    --system-deps)  SYSTEM_DEPS=1; shift ;;
    --install)      INSTALL=1; shift ;;
    --patch-only)   PATCH_ONLY=1; shift ;;
    -h|--help)      usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
log() { printf '[*] %s\n' "$*"; }

# --- toolchain -------------------------------------------------------------
if ! command -v cmake >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
  log "cmake/ninja not found; provisioning a local tool venv"
  mkdir -p "$BUILD_ROOT"
  python3 -m venv "$BUILD_ROOT/tools"
  "$BUILD_ROOT/tools/bin/pip" install --quiet --upgrade pip
  "$BUILD_ROOT/tools/bin/pip" install --quiet cmake ninja
  export PATH="$BUILD_ROOT/tools/bin:$PATH"
fi
command -v cmake >/dev/null || die "cmake unavailable"
command -v ninja >/dev/null || die "ninja unavailable"

command -v pkg-config >/dev/null || die "pkg-config is required"

# Qt WebEngine QML module must be present at runtime for the built shell.
if ! pkg-config --exists Qt6Core 2>/dev/null && ! command -v qmake6 >/dev/null 2>&1; then
  log "warning: could not detect Qt6 via pkg-config; configure may fail without it"
fi

# --- clone -----------------------------------------------------------------
QS_DIR="${SRC:-$BUILD_ROOT/quickshell}"
if [ ! -d "$QS_DIR/src/launch" ]; then
  log "cloning quickshell ($REF) into $QS_DIR"
  mkdir -p "$(dirname "$QS_DIR")"
  git clone --depth 1 --branch "$REF" \
    https://github.com/quickshell-mirror/quickshell.git "$QS_DIR"
else
  log "using existing checkout at $QS_DIR"
fi

# --- patch (idempotent) ----------------------------------------------------
log "applying WebEngine patch"
python3 - "$QS_DIR" <<'PYEOF'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
launch = root / "src/launch/launch.cpp"
if not launch.is_file():
    sys.exit("launch.cpp not found under " + str(root))
s = launch.read_text()

def sub(old, new):
    global s
    n = s.count(old)
    if n == 1:
        s = s.replace(old, new, 1)
        return True
    return False

if "web_engine::init()" in s:
    print("    already patched; nothing to do")
    sys.exit(0)

hdr = root / "src/webengine/webengine.hpp"
hdr.parent.mkdir(parents=True, exist_ok=True)
hdr.write_text('''#pragma once
#include <QDebug>
#include <qlibrary.h>

namespace web_engine {
inline bool init() {
    using InitializeFunc = void (*)();
    QLibrary lib("Qt6WebEngineQuick");
    if (!lib.load()) {
        qWarning() << "Failed to load Qt6WebEngineQuick:" << lib.errorString();
        return false;
    }
    auto initialize = reinterpret_cast<InitializeFunc>(
        lib.resolve("_ZN16QtWebEngineQuick10initializeEv"));
    if (!initialize) {
        qWarning() << "Failed to resolve QtWebEngineQuick::initialize()";
        return false;
    }
    initialize();
    qDebug() << "QtWebEngineQuick initialized successfully";
    return true;
}
}
''')

checks = [
    ("auto qArgC = 0;", "auto qArgC = 1;"),
    ('#include "launch_p.hpp"',
     '#include "launch_p.hpp"\n#include "../webengine/webengine.hpp"'),
    ("bool useSystemStyle = false;",
     "bool useSystemStyle = false;\n\t\tbool useQtWebEngineQuick = false;"),
    ('else if (pragma == "RespectSystemStyle") pragmas.useSystemStyle = true;',
     'else if (pragma == "RespectSystemStyle") pragmas.useSystemStyle = true;\n\t\t\telse if (pragma == "UseWebEngine") pragmas.useQtWebEngineQuick = true;'),
    ("auto qArgC = 1;",
     "auto qArgC = 1;\n\n\tif (pragmas.useQtWebEngineQuick) {\n\t\tweb_engine::init();\n\t}"),
]
for old, new in checks:
    if not sub(old, new):
        sys.exit("patch anchor not found (Quickshell source drifted): " + old)

launch.write_text(s)
print("    patched src/launch/launch.cpp and added src/webengine/webengine.hpp")
PYEOF

if [ "$PATCH_ONLY" = 1 ]; then
  log "patch-only: done ($QS_DIR)"
  exit 0
fi

# --- header-only deps ------------------------------------------------------
CMAKE_DEPS_ARGS=()
if [ "$SYSTEM_DEPS" = 0 ]; then
  DEPS="$BUILD_ROOT/deps"
  mkdir -p "$DEPS"
  if [ ! -d "$DEPS/CLI11/.git" ]; then
    log "fetching CLI11 headers"
    git clone --depth 1 https://github.com/CLIUtils/CLI11.git "$DEPS/CLI11"
  fi
  if [ ! -d "$DEPS/Vulkan-Headers/.git" ]; then
    log "fetching Vulkan-Headers"
    git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git "$DEPS/Vulkan-Headers"
  fi
  mkdir -p "$DEPS/cmake/CLI11" "$DEPS/cmake/VulkanHeaders"
  cat > "$DEPS/cmake/CLI11/CLI11Config.cmake" <<CMAKE
if(NOT TARGET CLI11::CLI11)
  add_library(CLI11::CLI11 INTERFACE IMPORTED)
  set_target_properties(CLI11::CLI11 PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "$DEPS/CLI11/include")
endif()
CMAKE
  cat > "$DEPS/cmake/VulkanHeaders/VulkanHeadersConfig.cmake" <<CMAKE
if(NOT TARGET Vulkan::Headers)
  add_library(Vulkan::Headers INTERFACE IMPORTED)
  set_target_properties(Vulkan::Headers PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "$DEPS/Vulkan-Headers/include")
endif()
CMAKE
  CMAKE_DEPS_ARGS+=(
    "-DCLI11_DIR=$DEPS/cmake/CLI11"
    "-DVulkanHeaders_DIR=$DEPS/cmake/VulkanHeaders"
    "-DVulkan_INCLUDE_DIR=$DEPS/Vulkan-Headers/include"
  )
fi

# --- configure + build -----------------------------------------------------
BUILD_DIR="$QS_DIR/build-webengine"
log "configuring"
cmake -B "$BUILD_DIR" -S "$QS_DIR" -GNinja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DINSTALL_QML_PREFIX=lib/qt6/qml \
  -DBUILD_TESTING=OFF \
  -DCRASH_HANDLER=OFF \
  "${CMAKE_DEPS_ARGS[@]:-}"

log "building (parallel)"
cmake --build "$BUILD_DIR" -j"$(nproc)"

BIN="$BUILD_DIR/src/quickshell"
[ -x "$BIN" ] || die "build finished but $BIN is missing"
if ! strings "$BIN" | grep -q 'UseWebEngine'; then
  die "built binary lacks the UseWebEngine pragma; patch did not take"
fi
log "built: $BIN"

if [ "$INSTALL" = 1 ]; then
  log "installing to $PREFIX"
  cmake --install "$BUILD_DIR"
  log "installed. Ensure $PREFIX/bin precedes /usr/bin on PATH so the daemon"
  log "(`astral-plasma run`, which spawns \`quickshell\`) picks up this build."
else
  log "not installed (pass --install, or run: cmake --install \"$BUILD_DIR\")"
fi
