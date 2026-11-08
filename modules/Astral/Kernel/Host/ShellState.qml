import QtQuick

// ============================================================================
// ShellState — the shell-owned state a surface may read
// ============================================================================
// The shell creates one of these, fills it from its own settings, and *injects* it
// into every app instance (`AppHost.state`). Injection shares the instance; a
// singleton import does not (spec C.9).
//
// This file deliberately imports **nothing** from the kernel. An earlier version
// bound these properties to `Config` and it failed for exactly the reason it exists:
// a component addressed by file path gets its own `Config` instance, so the values
// never moved. State flows *from* the shell, never from an import.
//
// It is a read model, not the settings object: adding a property here is a
// deliberate widening of what an app can see.
QtObject {
    /// Whether the overview surface is requested open.
    property bool overviewVisible: false
    /// Whether the command launcher is requested open.
    property bool commandLauncherVisible: false
    /// Whether the dashboard is requested open.
    property bool dashboardVisible: false
    /// The daemon binary an app may call for its own IPC (absolute path).
    property string daemonBin: ""
    /// Media card artwork override chosen by the user ("" = the track's own art).
    property string mediaAvatar: ""
    /// `speaker` or `radial`; the surface renders it, the shell stores it.
    property string mediaVisualizerStyle: "radial"

    /// Icon resolution, supplied by the shell so an app needs no icon-theme logic.
    property var iconResolver: null

    function iconUrl(name) {
        return iconResolver !== null ? iconResolver(name) : "";
    }
}
