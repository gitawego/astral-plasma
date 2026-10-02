pragma Singleton

import QtQuick
import Quickshell
import "../config"
import "Logging.js" as Logging

// ============================================================================
// The shell's diagnostic logger
// ============================================================================
// Every diagnostic line the shell prints goes through here, so verbosity is a
// setting instead of a rebuild:
//
//   services/Log.qml                       Log.debug("blur", "active: " + n)
//   ~/.config/astral-plasma/settings.json  { "logging": { "level": "info" } }
//   environment                            ASTRAL_PLASMA_LOG_LEVEL=debug
//                                          ASTRAL_PLASMA_LOG_CATEGORIES=blur=debug
//
// The default is quiet: `info` keeps lifecycle events, warnings and errors, and
// the per-frame trails stay off until somebody asks for them - per category, for
// one run if they like. The precedence table lives in `services/Logging.js`.
//
// Per-frame call sites must guard their *string building* with
// `Log.debugEnabled(category)` (not just rely on the level check inside
// `debug()`), so a disabled trail costs nothing but a boolean test per frame.
Singleton {
    id: root

    // Reactive: settings live in the Config singleton, so a level edited in the
    // UI applies to the next message with no reload.
    readonly property var settings: (typeof Config !== "undefined" && Config.settings) ? Config.settings : ({})

    // One-run overrides. Read once at startup: the environment cannot change
    // under a running process.
    readonly property string envLevel: root.envValue("ASTRAL_PLASMA_LOG_LEVEL")
    readonly property var envCategories: Logging.parseCategories(root.envValue("ASTRAL_PLASMA_LOG_CATEGORIES"))
    readonly property var env: ({ "level": root.envLevel, "categories": root.envCategories })

    // Messages actually printed. Diagnostics for the diagnostics: a test or the
    // settings UI can prove that a quiet level is quiet.
    property int emitted: 0

    function envValue(name) {
        return (typeof Quickshell !== "undefined" && Quickshell.env) ? (Quickshell.env(name) || "") : "";
    }

    /// Effective level of `category` ("off" ... "trace").
    function levelFor(category) {
        return Logging.levelFor(category, root.settings, root.env);
    }

    /// Should a message of `level` in `category` be printed?
    function enabled(category, level) {
        return Logging.isEnabled(category, level, root.settings, root.env);
    }

    function traceEnabled(category) {
        return root.enabled(category, "trace");
    }

    function debugEnabled(category) {
        return root.enabled(category, "debug");
    }

    function trace(category, message) {
        root.emit(category, "trace", message);
    }

    function debug(category, message) {
        root.emit(category, "debug", message);
    }

    function info(category, message) {
        root.emit(category, "info", message);
    }

    function warn(category, message) {
        root.emit(category, "warn", message);
    }

    function error(category, message) {
        root.emit(category, "error", message);
    }

    /// The single call site that decides which console channel a line uses, so
    /// the level a reader sees in Qt's prefix (`DEBUG`/`INFO`/`WARN`/`ERROR qml:`)
    /// is the level the shell assigned.
    function emit(category, level, message) {
        if (!root.enabled(category, level)) {
            return;
        }
        var line = Logging.format(category, message);
        root.emitted += 1;
        if (level === "error") {
            console.error(line);
        } else if (level === "warn") {
            console.warn(line);
        } else if (level === "info") {
            console.info(line);
        } else {
            console.debug(line);
        }
    }
}
