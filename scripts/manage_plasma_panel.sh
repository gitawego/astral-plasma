#!/bin/bash
# Generic, agnostic, config-driven script to manage KDE Plasma panels & theme settings for Caelestia
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SETTINGS_FILE="${SCRIPT_DIR}/../config/settings.json"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"

# 1. Config-driven resolution of backup directory
resolve_backup_dir() {
    if [ -n "${CAELESTIA_PLASMA_BACKUP_DIR:-}" ]; then
        echo "$CAELESTIA_PLASMA_BACKUP_DIR"
        return
    fi

    if [ -f "$SETTINGS_FILE" ]; then
        local configured_dir
        configured_dir=$(python3 -c "
import json, os, sys
try:
    with open('$SETTINGS_FILE') as f:
        data = json.load(f)
    b = data.get('plasma', {}).get('backupDir', '')
    if b:
        print(os.path.expanduser(b))
except Exception:
    pass
" 2>/dev/null || true)
        if [ -n "$configured_dir" ]; then
            echo "$configured_dir"
            return
        fi
    fi

    echo "${DATA_DIR}/caelestia/plasma-backup"
}

BACKUP_DIR="$(resolve_backup_dir)"
WATCHDOG_PID_FILE="/tmp/caelestia_plasma_watchdog.pid"
NOTIF_HELPER="$SCRIPT_DIR/manage_plasma_notifications.py"

APPLETSRC="$CONFIG_DIR/plasma-org.kde.plasma.desktop-appletsrc"
SHELLRC="$CONFIG_DIR/plasmashellrc"
SESSION_ACTIVE_FLAG="$BACKUP_DIR/session_active"

ACTION="${1:-disable}"
TARGET="${2:-all}"
PID_PARAM="${3:-}"

stop_watchdog() {
    if [ -f "$WATCHDOG_PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)
        if [ -n "$old_pid" ]; then
            kill "$old_pid" 2>/dev/null || true
        fi
        rm -f "$WATCHDOG_PID_FILE" 2>/dev/null || true
    fi
}

start_watchdog() {
    local target_pid="$1"
    if [ -z "$target_pid" ] || [ "${CAELESTIA_TEST_MODE:-0}" = "1" ]; then
        return
    fi

    stop_watchdog

    # Launch detached background watchdog monitoring Quickshell PID
    nohup bash -c '
        target_pid="$1"
        script_path="$2"
        pid_file="$3"
        echo "$$" > "$pid_file"

        while kill -0 "$target_pid" 2>/dev/null; do
            sleep 0.5
        done

        # When quickshell exits, automatically restore original Plasma panels and theme
        "$script_path" restore
        rm -f "$pid_file" 2>/dev/null || true
    ' _ "$target_pid" "$SCRIPT_PATH" "$WATCHDOG_PID_FILE" >/dev/null 2>&1 &
}

case "$ACTION" in
    disable|remove|backup)
        mkdir -p "$BACKUP_DIR"

        # 1. Config-driven snapshot of active KDE Plasma theme & panel settings
        # Guard: Only create a new snapshot if no session is currently active.
        # This guarantees repeated calls (e.g. on reload) never overwrite the pristine backup.
        if [ ! -f "$SESSION_ACTIVE_FLAG" ]; then
            if [ -f "$APPLETSRC" ]; then
                cp -p "$APPLETSRC" "$BACKUP_DIR/plasma-org.kde.plasma.desktop-appletsrc"
            fi
            if [ -f "$SHELLRC" ]; then
                cp -p "$SHELLRC" "$BACKUP_DIR/plasmashellrc"
            fi
            date +%s > "$BACKUP_DIR/backup_timestamp"
            touch "$SESSION_ACTIVE_FLAG"
            echo "Created generic theme & panel backup at: $BACKUP_DIR"
        else
            echo "Active session backup already exists in $BACKUP_DIR; preserving pristine snapshot."
        fi

        # 2. Disable matching panels in Plasma (if not in test mode)
        if [ "${CAELESTIA_TEST_MODE:-0}" != "1" ] && command -v qdbus6 >/dev/null 2>&1; then
            qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
                var ps = panels();
                var count = 0;
                var target = '$TARGET';
                var targets = target.split(',');
                for (var i = ps.length - 1; i >= 0; --i) {
                    var loc = ps[i].location;
                    if (target === 'all' || targets.indexOf(loc) !== -1) {
                        ps[i].remove();
                        count++;
                    }
                }
                print('Removed ' + count + ' panel(s) [target: ' + target + ']');
            " 2>/dev/null || true
            echo "KDE Plasma panels ($TARGET) are now hidden/disabled."
        fi

        # 3. Suppress native notifications if helper exists
        if [ -f "$NOTIF_HELPER" ] && [ "${CAELESTIA_TEST_MODE:-0}" != "1" ]; then
            python3 "$NOTIF_HELPER" inhibit >/dev/null 2>&1 &
            echo "Suppressed native KDE notifications (handled by Caelestia)."
        fi

        # 4. Start watchdog for quickshell process
        MONITOR_PID="$PID_PARAM"
        if [ -z "$MONITOR_PID" ]; then
            MONITOR_PID=$(pgrep -x quickshell | head -n 1 || true)
        fi
        if [ -z "$MONITOR_PID" ] && [ -n "${PPID:-}" ] && [ "$PPID" -gt 1 ]; then
            MONITOR_PID="$PPID"
        fi

        if [ -n "$MONITOR_PID" ]; then
            start_watchdog "$MONITOR_PID"
            echo "Watchdog started for PID $MONITOR_PID."
        fi
        ;;

    enable|restore)
        stop_watchdog

        # 1. Restore native notifications
        if [ -f "$NOTIF_HELPER" ] && [ "${CAELESTIA_TEST_MODE:-0}" != "1" ]; then
            python3 "$NOTIF_HELPER" restore >/dev/null 2>&1 || true
            echo "Native KDE notifications restored."
        fi

        # 2. Restore active KDE Plasma theme and panel configurations from generic backup
        local_restored=0
        if [ -f "$BACKUP_DIR/plasma-org.kde.plasma.desktop-appletsrc" ]; then
            if [ "${CAELESTIA_TEST_MODE:-0}" != "1" ]; then
                # Cleanly stop plasmashell so it does not overwrite config upon exit
                systemctl --user stop plasma-plasmashell 2>/dev/null || kquitapp6 plasmashell 2>/dev/null || killall plasmashell 2>/dev/null || true
                sleep 0.5
            fi

            cp -p "$BACKUP_DIR/plasma-org.kde.plasma.desktop-appletsrc" "$APPLETSRC"
            if [ -f "$BACKUP_DIR/plasmashellrc" ]; then
                cp -p "$BACKUP_DIR/plasmashellrc" "$SHELLRC"
            fi

            if [ "${CAELESTIA_TEST_MODE:-0}" != "1" ]; then
                systemctl --user start plasma-plasmashell 2>/dev/null || nohup plasmashell --no-respawn >/dev/null 2>&1 &
            fi
            local_restored=1
            echo "KDE Plasma authentic theme & panels faithfully restored from $BACKUP_DIR"
        fi

        # Clean up session flag so subsequent runs will freshly capture whatever theme the user is using
        rm -f "$SESSION_ACTIVE_FLAG"

        if [ "$local_restored" -eq 0 ]; then
            echo "No active session backup found in $BACKUP_DIR to restore."
        fi
        ;;

    status)
        if [ "${CAELESTIA_TEST_MODE:-0}" != "1" ] && command -v qdbus6 >/dev/null 2>&1; then
            qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
                var ps = panels();
                var res = [];
                for (var i = 0; i < ps.length; ++i) {
                    res.push({ id: ps[i].id, location: ps[i].location, hiding: ps[i].hiding, height: ps[i].height });
                }
                print(JSON.stringify(res));
            ' 2>/dev/null || true
        fi

        echo "Backup directory: $BACKUP_DIR"
        if [ -f "$SESSION_ACTIVE_FLAG" ]; then
            echo "Session status: ACTIVE (backup preserved)"
        else
            echo "Session status: INACTIVE"
        fi

        if [ -f "$WATCHDOG_PID_FILE" ]; then
            W_PID=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)
            if [ -n "$W_PID" ] && kill -0 "$W_PID" 2>/dev/null; then
                echo "Watchdog running: PID $W_PID"
            else
                echo "Watchdog not running."
            fi
        else
            echo "Watchdog not running."
        fi
        ;;

    *)
        echo "Usage: $0 {disable|enable|restore|remove|backup|status} [all|top|bottom|left|right] [monitor_pid]"
        exit 1
        ;;
esac
