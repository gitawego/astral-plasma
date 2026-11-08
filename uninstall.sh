#!/bin/bash
# Remove Astral Plasma.
#
#   ./uninstall.sh              asks once, keeps your settings
#   ./uninstall.sh --yes        no prompt
#   ./uninstall.sh --purge      also remove settings, palette and imported avatars
#
# The installed layout is removed by the binary itself (`astral-plasma
# uninstall`), so there is one implementation of what an install owns. This
# script only adds the two things a binary must not do unasked: editing KDE's
# shortcut configuration, and removing the Omarchy plugin directory.
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DATA_DIR="$DATA_HOME/astral-plasma"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$DATA_DIR/bin/astral-plasma"

ASSUME_YES=0
PASSTHROUGH=()
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        --purge) PASSTHROUGH+=("--purge") ;;
        --force) PASSTHROUGH+=("--force") ;;
        -h|--help)
            sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "[!] Unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

if [ ! -x "$BIN" ]; then
    for candidate in "$HOME/.local/bin/astral-plasma" "$(dirname "${BASH_SOURCE[0]}")/bin/astral-plasma"; do
        [ -x "$candidate" ] && BIN="$candidate" && break
    done
fi

if [ "$ASSUME_YES" -eq 0 ]; then
    echo "=== Uninstalling Astral Plasma ==="
    echo "This removes the shell, its QML bundle and the files it installed."
    echo "Your settings are kept unless you pass --purge."
    confirm=""
    read -rp "Continue? [y/N]: " confirm || true
    case "$confirm" in
        [yY]*) ;;
        *) echo "Nothing was changed."; exit 0 ;;
    esac
fi

# Stop the shell first; a removed binary under a running supervisor is a crash.
if [ -x "$BIN" ]; then
    "$BIN" shell exit >/dev/null 2>&1 || true
fi
pkill -f "quickshell -p $DATA_DIR/package" 2>/dev/null || true

if [ -x "$BIN" ]; then
    "$BIN" uninstall --yes "${PASSTHROUGH[@]}"
else
    # A half-removed install: remove the artifacts we know are ours, and leave
    # the rest of the data directory alone - it also holds AI sessions and the
    # Plasma backup, which an uninstall must not destroy.
    rm -rf "$DATA_DIR/package" "$DATA_DIR/package.prev" "$DATA_DIR/package.next"
    rm -f "$DATA_DIR/bin/astral-plasma" "$DATA_DIR/bin/astral-plasma.prev" "$DATA_DIR/install.json"
    rmdir "$DATA_DIR/bin" "$DATA_DIR" 2>/dev/null || true
    rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/astral-plasma/migrations"
    rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/astral-plasma/update.json" \
          "${XDG_STATE_HOME:-$HOME/.local/state}/astral-plasma/update.log"
    rm -f "$HOME/.local/bin/astral-plasma"
    echo "[✓] Removed leftover files"
fi

# KDE integration the binary deliberately does not touch: its own shortcut keys
# and the KWin script package.
if command -v kwriteconfig6 >/dev/null 2>&1; then
    for key in AstralLauncher AstralWallpaper AstralOverview AstralAssistant AstralDashboard AstralSettings; do
        kwriteconfig6 --file kglobalshortcutsrc --group "kwin" --key "$key" --delete 2>/dev/null || true
    done
    kwriteconfig6 --file kwinrc --group "Plugins" --key "astral-plasma-shortcutsEnabled" --delete 2>/dev/null || true
fi
rm -rf "$DATA_HOME/kwin/scripts/astral-plasma-shortcuts" 2>/dev/null || true

# Hosted-Omarchy plugin, if it was installed.
OMARCHY_PLUGIN_DIR="$CONFIG_HOME/omarchy/plugins/org.astralplasma.omarchy"
if [ -d "$OMARCHY_PLUGIN_DIR" ]; then
    rm -rf "$OMARCHY_PLUGIN_DIR"
    echo "[✓] Removed Omarchy plugin"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DATA_HOME/applications" 2>/dev/null || true
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 2>/dev/null || true
fi

echo "=== Uninstallation complete ==="
if [ ! -d "${XDG_CONFIG_HOME:-$HOME/.config}/astral-plasma" ]; then
    echo "Settings were purged."
else
    echo "Settings kept in ${XDG_CONFIG_HOME:-$HOME/.config}/astral-plasma."
    echo "Remove them too with: ./uninstall.sh --purge --yes"
fi
