#!/bin/bash
# Build the Astral Plasma AppImage.
#
# The AppImage bundles the daemon, Quickshell, Qt and the QML tree so a KDE
# Plasma 6 user can try the shell without adding a package repository. The
# payload is extracted to a stable per-user directory on first launch; see
# packaging/appimage/AppRun.
#
# Toolchain (see README.md in this directory):
#   linuxdeploy, linuxdeploy-plugin-qt, appimagetool, patchelf, mksquashfs
#   qmake6 (Qt 6)
#
# Usage:
#   ./packaging/appimage/build.sh [--no-build] [--output <path>]
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd -P)
NO_BUILD=0
OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --no-build) NO_BUILD=1; shift ;;
        --output) OUTPUT="${2:?--output needs a path}"; shift 2 ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[!] Missing $1. See packaging/appimage/README.md for the toolchain." >&2
        exit 1
    }
}
need linuxdeploy
need appimagetool
need zsyncmake
need patchelf
need mksquashfs
need qmake6
need quickshell
need curl
VERSION=$(grep -m1 '^version' "$ROOT/daemon/Cargo.toml" | sed -E 's/version = "(.*)"/\1/')
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH=x86_64 ;;
    aarch64|arm64) ARCH=aarch64 ;;
    *) echo "[!] Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

BUILD="$ROOT/build/appimage/$ARCH"
APPDIR="$BUILD/AppDir"
DIST="$ROOT/dist"
APPIMAGE="$DIST/astral-plasma-${VERSION}-${ARCH}.AppImage"

# AppImageUpdate is the update implementation: it follows the update
# information embedded below and verifies the zsync result. Pin both halves so
# a changed upstream artifact cannot silently alter a release image.
APPIMAGEUPDATE_VERSION="2.0.0-alpha-1-20251018"
case "$ARCH" in
    x86_64) UPDATER_SHA256="d976cdac667b03dee8cb23fb95ef74b042c406c5cbab3ff294d2b16efeaff84f" ;;
    aarch64) UPDATER_SHA256="7aaf89dd4cf66ebd940d416c67e1c240c57a139cee38d9c0ed3bb9387bc435b0" ;;
esac
UPDATER_NAME="appimageupdatetool-${ARCH}.AppImage"
UPDATER_URL="https://github.com/AppImageCommunity/AppImageUpdate/releases/download/${APPIMAGEUPDATE_VERSION}/${UPDATER_NAME}"
UPDATER_CACHE="$BUILD/updater/$UPDATER_NAME"

REPO_SLUG="${ASTRAL_APPIMAGE_REPO:-gitawego/astral-plasma}"
UPDATE_INFO="${ASTRAL_APPIMAGE_UPDATE_INFO:-gh-releases-zsync|${REPO_SLUG//\//|}|latest|astral-plasma-*-${ARCH}.AppImage.zsync}"

if [ "$NO_BUILD" -eq 0 ]; then
    make -C "$ROOT" build
fi
[ -x "$ROOT/bin/astral-plasma" ] || {
    echo "[!] $ROOT/bin/astral-plasma is missing; run without --no-build." >&2
    exit 1
}

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/scalable/apps" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
         "$APPDIR/usr/share/astral-plasma/package"

cp "$ROOT/bin/astral-plasma" "$APPDIR/usr/bin/astral-plasma"
cp "$(command -v quickshell)" "$APPDIR/usr/bin/quickshell"

# Bundle the AppImageUpdate CLI so updates work without a system package.
mkdir -p "$(dirname "$UPDATER_CACHE")"
if [ ! -f "$UPDATER_CACHE" ]; then
    curl -fsSL -o "$UPDATER_CACHE" "$UPDATER_URL"
fi
printf '%s  %s\n' "$UPDATER_SHA256" "$UPDATER_CACHE" | sha256sum -c - >/dev/null
cp "$UPDATER_CACHE" "$APPDIR/usr/bin/appimageupdatetool.AppImage"
chmod +x "$APPDIR/usr/bin/appimageupdatetool.AppImage"
cp "$ROOT/modules/Astral/Kernel/theme/assets/astral-plasma.svg" "$APPDIR/astral-plasma.svg"
cp "$APPDIR/astral-plasma.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/astral-plasma.svg"
# appimagetool derives .DirIcon from a top-level PNG (or XPM). Render one when
# the build host has librsvg, so a future appimagetool cannot refuse the image.
if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 256 -h 256 "$APPDIR/astral-plasma.svg" -o "$APPDIR/astral-plasma.png"
    cp "$APPDIR/astral-plasma.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/astral-plasma.png"
fi
cp "$HERE/astral-plasma.desktop" "$APPDIR/astral-plasma.desktop"
cp "$HERE/AppRun" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
printf '%s\n' "$VERSION" > "$APPDIR/version"

# The binary owns the QML bundle; extracting it here guarantees the image
# carries exactly the shell the binary was built from.
"$APPDIR/usr/bin/astral-plasma" extract "$APPDIR/usr/share/astral-plasma/package" >/dev/null

# The first-run installer is QML that lives beside the shell bundle.
rm -rf "$APPDIR/usr/share/astral-plasma/package/appimage"
cp -a "$ROOT/appimage" "$APPDIR/usr/share/astral-plasma/package/appimage"
cp "$HERE/appimage-setup.qml" "$APPDIR/usr/share/astral-plasma/package/appimage-setup.qml"

# linuxdeploy's bundled strip predates `.relr.dyn` sections from current Arch
# toolchains, so stripping is disabled rather than treated as a build failure.
export ARCH
export NO_STRIP=1

QML_SRC=$(qmake6 -query QT_INSTALL_QML 2>/dev/null || true)
QT_PLUGINS_SRC=$(qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || true)
QMAKE_BIN=$(command -v qmake6)
QMAKE_PREFIX=$(CDPATH= cd -- "$(dirname -- "$QMAKE_BIN")/.." && pwd -P)
QMAKE_LIBEXECS=$("$QMAKE_BIN" -query QT_INSTALL_LIBEXECS 2>/dev/null || echo "$QMAKE_PREFIX/libexec")

# Stage a filtered Qt plugin tree. Arch's kimageformats ships optional plugins
# whose dependencies (e.g. libjpegxr) are not installed; linuxdeploy treats the
# first unreadable optional plugin as a hard failure. The shell needs the
# Wayland, platform, image, TLS and network plugins, not every KDE image codec.
QT_STAGE="$BUILD/qt"
rm -rf "$QT_STAGE"
mkdir -p "$QT_STAGE/bin" "$QT_STAGE/plugins"
cp "$QMAKE_BIN" "$QT_STAGE/bin/qmake"
cat > "$QT_STAGE/bin/qt.conf" <<EOF
[Paths]
Prefix=$QMAKE_PREFIX
Plugins=$QT_STAGE/plugins
Qml2Imports=$QML_SRC
HostBinaries=$QMAKE_PREFIX/bin
HostLibraryExecutables=$QMAKE_LIBEXECS
HostData=$QMAKE_PREFIX
EOF
if [ -n "$QT_PLUGINS_SRC" ] && [ -d "$QT_PLUGINS_SRC" ]; then
    for family in platforms platforminputcontexts platformthemes iconengines \
                  imageformats tls networkinformation generic \
                  wayland-decoration-client wayland-graphics-integration-client \
                  wayland-shell-integration xcbglintegrations egldeviceintegrations; do
        if [ -d "$QT_PLUGINS_SRC/$family" ]; then
            cp -a "$QT_PLUGINS_SRC/$family" "$QT_STAGE/plugins/"
        fi
    done
    rm -f "$QT_STAGE/plugins/imageformats/kimg_"*.so \
          "$QT_STAGE/plugins/imageformats/libqpdf.so" \
          "$QT_STAGE/plugins/platforms/libqminimal"*.so \
          "$QT_STAGE/plugins/platforms/libqoffscreen.so" \
          "$QT_STAGE/plugins/platforms/libqvnc.so" \
          "$QT_STAGE/plugins/platforms/libqlinuxfb.so" \
          "$QT_STAGE/plugins/platforms/libqeglfs.so" \
          "$QT_STAGE/plugins/platforms/libqvkkhrdisplay.so" 2>/dev/null || true
fi
export QMAKE="$QT_STAGE/bin/qmake"
export PATH="$QT_STAGE/bin:/usr/lib/qt6/bin:$PATH"

# qmlimportscanner (inside linuxdeploy-plugin-qt) blocks on its output pipe when
# the AppDir contains the full shell tree. The QML is copied verbatim after
# linuxdeploy, so keep it out of the AppDir while the plugin scans ELF files.
mv "$APPDIR/usr/share/astral-plasma/package" "$BUILD/package-stash"
trap 'mv "$BUILD/package-stash" "$APPDIR/usr/share/astral-plasma/package" 2>/dev/null || true' EXIT

linuxdeploy \
    --appdir "$APPDIR" \
    --executable "$APPDIR/usr/bin/astral-plasma" \
    --executable "$APPDIR/usr/bin/quickshell" \
    --desktop-file "$APPDIR/astral-plasma.desktop" \
    --icon-file "$APPDIR/astral-plasma.svg" \
    --custom-apprun "$HERE/AppRun" \
    --plugin qt

mv "$BUILD/package-stash" "$APPDIR/usr/share/astral-plasma/package"
trap - EXIT

# linuxdeploy finds the Qt runtime and the platform plugins. The QML tree is
# copied afterwards as well: the plugin's import scanner is best-effort, and a
# shell missing one QML module fails at startup rather than at build time.
mkdir -p "$APPDIR/usr/lib/qt6/qml"
if [ -n "$QML_SRC" ] && [ -d "$QML_SRC" ]; then
    cp -a "$QML_SRC/." "$APPDIR/usr/lib/qt6/qml/"
fi

# Wayland is the session's platform; deploy its plugin family even when the
# build host is running X11.
mkdir -p "$APPDIR/usr/plugins/platforms"
if [ -n "$QT_PLUGINS_SRC" ] && [ -d "$QT_PLUGINS_SRC" ]; then
    cp -a "$QT_PLUGINS_SRC/platforms/libqwayland"*.so "$APPDIR/usr/plugins/platforms/" 2>/dev/null || true
    for family in wayland-decoration-client wayland-graphics-integration-client wayland-shell-integration; do
        if [ -d "$QT_PLUGINS_SRC/$family" ]; then
            mkdir -p "$APPDIR/usr/plugins/$family"
            cp -a "$QT_PLUGINS_SRC/$family/." "$APPDIR/usr/plugins/$family/"
        fi
    done
fi

mkdir -p "$DIST"
if [ -n "$OUTPUT" ]; then
    APPIMAGE="$OUTPUT"
fi

# linuxdeploy names the output after the desktop file; build again with the
# deterministic name users and the release manifest will reference.
rm -f "$APPIMAGE" "$APPIMAGE.zsync"
ARCH="$ARCH" appimagetool --no-appstream -u "$UPDATE_INFO" "$APPDIR" "$APPIMAGE"
# appimagetool's own zsync step is unreliable for an absolute destination.
# zsyncmake is the authoritative producer and is also what AppImageUpdate reads.
zsyncmake -u "$(basename "$APPIMAGE")" -o "$APPIMAGE.zsync" "$APPIMAGE"
[ -s "$APPIMAGE.zsync" ] || {
    echo "[!] zsyncmake did not produce ${APPIMAGE}.zsync; AppImageUpdate needs it." >&2
    exit 1
}

chmod +x "$APPIMAGE"
echo "[✓] $APPIMAGE"
echo "    zsync:   $APPIMAGE.zsync"
echo "    update:  $UPDATE_INFO"
echo "    version: $VERSION"
echo "    size:    $(du -h "$APPIMAGE" | cut -f1)"
echo "    smoke:   $APPIMAGE --appimage-extract && test -x squashfs-root/AppRun"
