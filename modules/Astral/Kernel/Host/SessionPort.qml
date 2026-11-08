import QtQuick

// ============================================================================
// SessionPort — the window model a surface may read and act on
// ============================================================================
// The second thing a migrated surface needs (the first was `ShellState`). A surface
// shows windows, so it needs the window list, the thumbnails, and three actions.
// It cannot import `Kernel/services`: a Loader-loaded component gets its **own**
// singleton instance, and that instance has no windows (spec C.10 - the migrated
// overview opened with an empty preview grid for exactly this reason).
//
// So the shell fills this object and injects it. Data is plain properties (QML
// notifies on assignment); operations are supplied as callables and default to
// `null`, which makes "this shell cannot do that" a representable state instead of
// a silent no-op. Every call is contained: a throwing implementation returns false
// and reports through `operationFailed`.
QtObject {
    id: root

    // ---- data ---------------------------------------------------------------

    /// Running windows. Shape is the shell's: `{ id, title, appId, icon, desktop,
    /// active, ... }`; a surface reads what it needs and tolerates the rest.
    property var windows: []
    /// Launchable applications: `{ id, name, icon, comment, ... }`.
    property var installedApps: []
    /// `id -> thumbnail url`, filled while an overview is open.
    property var overviewThumbnails: ({})
    /// The focused window's id ("" when nothing is focused).
    property string activeWindowId: ""
    /// Workspaces (virtual desktops): `[{ id, name }]`, in the compositor's order.
    property var workspaces: []

    // ---- operations (supplied by the shell) ---------------------------------

    property var activateWindowImpl: null
    property var closeWindowImpl: null
    property var launchAppImpl: null
    property var reloadInstalledAppsImpl: null
    property var startThumbnailsImpl: null
    property var stopThumbnailsImpl: null
    property var refreshThumbnailsImpl: null
    property var moveWindowToWorkspaceImpl: null

    readonly property bool canActivate: activateWindowImpl !== null
    readonly property bool canClose: closeWindowImpl !== null
    readonly property bool canLaunch: launchAppImpl !== null
    readonly property bool canThumbnail: startThumbnailsImpl !== null
    readonly property bool canMoveToWorkspace: moveWindowToWorkspaceImpl !== null

    /// Reported when an implementation throws or is missing, so a surface can say
    /// why nothing happened.
    signal operationFailed(string operation, string reason)

    // ---- dispatch -----------------------------------------------------------

    function call(operation, impl, args) {
        if (typeof impl !== "function") {
            root.operationFailed(operation, "not supported by this shell");
            return false;
        }
        try {
            const result = impl.apply(null, args || []);
            return result === undefined ? true : !!result;
        } catch (error) {
            root.operationFailed(operation, String(error));
            return false;
        }
    }

    function activateWindow(windowId) {
        return call("activateWindow", activateWindowImpl, [windowId]);
    }

    function closeWindow(windowId) {
        return call("closeWindow", closeWindowImpl, [windowId]);
    }

    function launchApp(target, meta) {
        return call("launchApp", launchAppImpl, [target, meta]);
    }

    function reloadInstalledApps() {
        return call("reloadInstalledApps", reloadInstalledAppsImpl, []);
    }

    function startThumbnails() {
        return call("startThumbnails", startThumbnailsImpl, []);
    }

    function stopThumbnails() {
        return call("stopThumbnails", stopThumbnailsImpl, []);
    }

    function refreshThumbnails() {
        return call("refreshThumbnails", refreshThumbnailsImpl, []);
    }

    /// Thumbnail URL for a window id, or "" when the shell has none.
    /// Move a window to a workspace. A surface that can show workspaces needs this;
    /// it is separate from `activateWindow` because it changes the desktop, not focus.
    function moveWindowToWorkspace(windowId, workspaceId) {
        return call("moveWindowToWorkspace", moveWindowToWorkspaceImpl, [windowId, workspaceId]);
    }

    function thumbnailFor(windowId) {
        const value = overviewThumbnails[windowId];
        return typeof value === "string" ? value : "";
    }
}
