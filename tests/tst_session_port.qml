import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// SessionPort
// ============================================================================
// A surface shows windows, so it needs the window model. It cannot import
// `WindowService` (a Loader-loaded component gets its own instance with no windows
// - spec C.10), so the shell fills this port and injects it.
//
// What is asserted: data reaches the surface, operations reach the shell with their
// arguments, an unsupported operation is a *stated* failure rather than a silent
// no-op, and a throwing implementation cannot take the surface down.
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
            'import QtQuick; import "../modules/Astral/Kernel/Host"; SessionPort { }',
            testRoot, "session");
        port.operationFailed.connect(function (operation, reason) {
            failures.push({ operation: operation, reason: reason });
        });

        // ---- defaults: empty, and honestly unsupported -----------------------
        assert(Array.isArray(port.windows) && port.windows.length === 0, "no windows yet");
        assert(port.activeWindowId === "", "nothing focused yet");
        assert(port.thumbnailFor("anything") === "", "no thumbnail for an unknown id");
        assert(!port.canActivate && !port.canClose && !port.canLaunch, "no operations yet");

        assert(port.activateWindow("w1") === false, "an unsupported operation returns false");
        assert(failures.length === 1, "and says so");
        assert(failures[0].operation === "activateWindow", "the failure names the operation");
        assert(failures[0].reason.indexOf("not supported") >= 0, "and the reason");

        // ---- the shell fills data -------------------------------------------
        port.windows = [
            { id: "w1", title: "Editor", appId: "code" },
            { id: "w2", title: "Browser", appId: "chrome" }
        ];
        port.installedApps = [{ id: "code", name: "Editor" }];
        port.overviewThumbnails = { w1: "image://thumbnail/w1" };
        port.activeWindowId = "w1";

        assert(port.windows.length === 2, "the window list reaches the surface");
        assert(port.windows[1].title === "Browser", "window fields are intact");
        assert(port.thumbnailFor("w1") === "image://thumbnail/w1", "the thumbnail is found");
        assert(port.thumbnailFor("w2") === "", "a missing thumbnail is an empty string");

        // ---- operations reach the shell with their arguments ----------------
        let activated = null;
        port.activateWindowImpl = function (id) { activated = id; return true; };
        assert(port.canActivate, "the capability is now advertised");
        assert(port.activateWindow("w2") === true, "the operation succeeds");
        assert(activated === "w2", "the argument reached the shell");

        let launched = null;
        port.launchAppImpl = function (target, meta) { launched = { target: target, meta: meta }; };
        assert(port.launchApp("code", { desktop: 1 }) === true,
            "an implementation that returns nothing still counts as success");
        assert(launched.target === "code" && launched.meta.desktop === 1,
            "both launch arguments reach the shell");

        // ---- a throwing implementation is contained -------------------------
        port.closeWindowImpl = function () { throw new Error("kwin refused"); };
        assert(port.closeWindow("w1") === false, "a throwing implementation returns false");
        assert(failures.some(function (item) { return item.operation === "closeWindow"; }),
            "and is reported");

        // ---- thumbnails are a lifecycle, not a one-shot ---------------------
        let started = 0;
        let stopped = 0;
        port.startThumbnailsImpl = function () { started++; };
        port.stopThumbnailsImpl = function () { stopped++; };
        assert(port.startThumbnails(), "thumbnails can start");
        assert(port.stopThumbnails(), "thumbnails can stop");
        assert(started === 1 && stopped === 1, "the lifecycle reached the shell");

        port.destroy();
        console.log("PASS: All session port tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
