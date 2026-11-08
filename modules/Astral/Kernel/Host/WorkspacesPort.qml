import QtQuick

// ============================================================================
// WorkspacesPort — desktops as a surface may read and change them
// ============================================================================
// A workspace surface groups windows by desktop, switches desktops, creates and
// removes them, and moves windows between them. That is a different concern from
// `SessionPort` (the window model), so it is a different port: keeping them apart is
// what stops the window model from growing six unrelated operations.
//
// The shell fills it from its own `KWinWorkspaces` and injects it, because a
// Loader-loaded surface gets its own copy of that singleton and would see one
// desktop (spec C.9/C.10).
QtObject {
    id: root

    /// `[{ id, name, index }]`, in the compositor's order.
    property var desktops: []
    /// The active desktop's id ("" when the shell has not published one yet).
    property string currentId: ""
    readonly property int count: desktops.length

    property var switchToImpl: null
    property var createImpl: null
    property var removeImpl: null
    property var refreshImpl: null
    property var moveWindowImpl: null

    readonly property bool canSwitch: switchToImpl !== null
    readonly property bool canCreate: createImpl !== null
    readonly property bool canRemove: removeImpl !== null
    readonly property bool canRefresh: refreshImpl !== null
    readonly property bool canMoveWindow: moveWindowImpl !== null

    signal operationFailed(string operation, string reason)

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

    function switchTo(desktopId) {
        return call("switchTo", switchToImpl, [String(desktopId || "")]);
    }

    function create(name) {
        return call("create", createImpl, [name === undefined ? "" : String(name)]);
    }

    function remove(desktopId) {
        return call("remove", removeImpl, [String(desktopId || "")]);
    }

    function refresh() {
        return call("refresh", refreshImpl, []);
    }

    function moveWindow(windowId, desktopId) {
        return call("moveWindow", moveWindowImpl, [String(windowId || ""), String(desktopId || "")]);
    }

    /// The desktop a window belongs to, or "" when it is on the active one only.
    function desktopOf(window) {
        const ids = window && window.desktopIds ? window.desktopIds : [];
        return ids.length > 0 ? String(ids[0]) : "";
    }
}
