import QtQuick
import "../modules/Astral/Kernel/config/PopoutModes.js" as PopoutModes

/// Retired drawer modes must be inert.
///
/// Volume and brightness moved to the right-edge rail, so `FusedBottomPopout`
/// no longer renders `audio` / `brightness` sections and `Config` sizes the
/// wrapper from the active section. A stale IPC call must therefore not open a
/// glass card with nothing in it - and must not hijack a drawer that is
/// already open.
Item {
    id: testRoot
    width: 400
    height: 400

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: {
            console.log("RUNNING: Retired Popout Modes Are Inert");

            // 1. The retired set is exactly the controls the rail took over.
            assert(PopoutModes.isRetired("audio"), "audio must be retired");
            assert(PopoutModes.isRetired("brightness"), "brightness must be retired");
            assert(PopoutModes.isRetired("Brightness"), "retired matching must ignore case");
            assert(!PopoutModes.isRetired("network"), "network must stay live");
            assert(!PopoutModes.isRetired("bluetooth"), "bluetooth must stay live");
            assert(!PopoutModes.isRetired(""), "an empty mode is not retired (it means 'keep current')");
            assert(!PopoutModes.isRetired(undefined), "undefined mode must not throw");

            // 2. A closed dock stays closed when a retired mode is requested.
            assert(PopoutModes.resolveOpenMode("brightness", "", "power") === "power",
                "a retired mode on a closed dock must fall back, not open an empty card");
            assert(PopoutModes.resolveOpenMode("audio", null, "default") === "default",
                "the same rule must hold for every retired mode");

            // 3. A retired request must not hijack a drawer that is already open.
            assert(PopoutModes.resolveOpenMode("brightness", "network", "power") === "network",
                "a retired request must leave an open drawer on its own mode");

            // 4. Live modes pass through untouched, so nothing else regresses.
            assert(PopoutModes.resolveOpenMode("network", "", "power") === "network",
                "the network drawer must still open");
            assert(PopoutModes.resolveOpenMode("clock", "network", "power") === "clock",
                "switching between live drawers must still work");
            assert(PopoutModes.resolveOpenMode("", "network", "power") === "power",
                "an empty request keeps its documented fallback");

            console.log("PASS: Retired Popout Modes Are Inert");
            Qt.exit(0);
        }
    }
}
