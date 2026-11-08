import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// WorkspacesPort
// ============================================================================
// Desktops are a separate concern from windows, so they are a separate port: a
// workspace surface needs to read them and change them, and a Loader-loaded surface
// cannot read the shell's singleton (spec C.10).
//
// What is asserted: an empty port is honest, desktops reach the surface, every
// operation reaches the shell with its arguments, `desktopOf` reads the window's
// desktop list, and unsupported or throwing operations are stated failures.
Item {
    id: testRoot
    width: 400
    height: 300

    property var failures: []

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function run() {
        const port = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; WorkspacesPort { }',
            testRoot, "workspaces");
        port.operationFailed.connect(function (operation, reason) {
            failures.push({ operation: operation, reason: reason });
        });

        // ---- empty -----------------------------------------------------------
        assert(port.desktops.length === 0 && port.count === 0, "no desktops until the shell says so");
        assert(port.currentId === "", "no current desktop yet");
        assert(!port.canSwitch && !port.canCreate && !port.canRemove && !port.canMoveWindow,
            "no capabilities until the shell supplies them");
        assert(port.switchTo("1") === false, "switching is unsupported");
        assert(failures.length === 1 && failures[0].operation === "switchTo",
            "and says which operation failed");

        // ---- data ------------------------------------------------------------
        port.desktops = [
            { id: "1", name: "One", index: 0 },
            { id: "2", name: "Two", index: 1 }
        ];
        port.currentId = "2";
        assert(port.count === 2, "the desktop list reaches the surface");
        assert(port.desktops[1].name === "Two", "desktop fields are intact");

        // A window's desktop comes from its own list, not from the active one.
        assert(port.desktopOf({ desktopIds: ["2"] }) === "2", "desktopOf reads the window");
        assert(port.desktopOf({ desktopIds: [] }) === "", "a window on all desktops has none");
        assert(port.desktopOf(null) === "", "a missing window is handled");

        // ---- operations ------------------------------------------------------
        let switched = "";
        let created = null;
        let removed = "";
        let refreshed = 0;
        let moved = null;
        port.switchToImpl = function (id) { switched = id; };
        port.createImpl = function (name) { created = name; };
        port.removeImpl = function (id) { removed = id; };
        port.refreshImpl = function () { refreshed++; };
        port.moveWindowImpl = function (windowId, desktopId) {
            moved = { window: windowId, desktop: desktopId };
        };

        assert(port.canSwitch && port.canCreate && port.canRemove && port.canRefresh && port.canMoveWindow,
            "capabilities are advertised once supplied");
        assert(port.switchTo("2"), "switch works");
        assert(port.create("Three"), "create works");
        assert(port.remove("1"), "remove works");
        assert(port.refresh(), "refresh works");
        assert(port.moveWindow("w1", "2"), "move works");
        assert(switched === "2" && created === "Three" && removed === "1" && refreshed === 1,
            "the shell received the commands");
        assert(moved.window === "w1" && moved.desktop === "2", "both move arguments arrive");

        // Creating without a name is allowed: the compositor names it.
        port.create();
        assert(created === "", "an unnamed desktop is created with an empty name");

        // ---- containment -----------------------------------------------------
        port.switchToImpl = function () { throw new Error("kwin went away"); };
        assert(port.switchTo("1") === false, "a throwing implementation returns false");
        assert(failures.some(function (item) { return item.operation === "switchTo"; }),
            "and is reported");

        port.destroy();
        console.log("PASS: All workspaces port tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
