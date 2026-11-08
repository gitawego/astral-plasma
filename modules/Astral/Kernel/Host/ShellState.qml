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
    /// The dashboard's width, as the user set it.
    property real dashboardWidth: 980
    /// Which tabs the user enabled, in order.
    property var dashboardTabs: []
    /// The tab the user last selected.
    property string activeDashboardTab: "dashboard"
    /// The daemon binary an app may call for its own IPC (absolute path).
    property string daemonBin: ""

    /// Icon resolution, supplied by the shell so an app needs no icon-theme logic.
    property var iconResolver: null

    function iconUrl(name) {
        return iconResolver !== null ? iconResolver(name) : "";
    }

    /// Media card artwork override chosen by the user ("" = the track's own art).
    property string mediaAvatar: ""
    /// `speaker` or `radial`; the surface renders it, the shell stores it.
    property string mediaVisualizerStyle: "radial"

    /// Which downloads segment the user last looked at (`active`, `waiting`, …).
    property string downloadsSegment: "active"
    /// The download directory, as the user configured it.
    property string downloadsDir: ""
    /// Whether the tab splits into columns or shows one list.
    property bool downloadsSplit: false
    /// Concurrent download slots the user asked for.
    property int downloadsMaxConcurrent: 3
    /// Speed limit in bytes/s (0 = unlimited).
    property int downloadsSpeedLimit: 0
    /// Whether the download rows use the blurred glass border.
    property bool downloadsBorderEffect: true

    /// Whether the assistant window is requested open.
    property bool assistantVisible: false
    /// Whether the assistant's session list is expanded.
    property bool assistantSessionsVisible: false

    /// The dashboard host's avatar and its backing (user-chosen).
    property string hostAvatar: ""
    property string hostAvatarBg: ""
    property real hostAvatarBgOpacity: 0.2
    property bool hostAvatarBorder: false
    /// The bongo-cat mascot source, when the user picked one.
    property string bongoCatAvatar: ""

    /// Whether the user has AI privacy mode on.
    property bool aiPrivacyMode: true
    /// Provider brand icon resolution, supplied by the shell (it knows the assets).
    property var providerIconResolver: null

    function providerIconUrl(name) {
        return providerIconResolver !== null ? providerIconResolver(name) : "";
    }
}
