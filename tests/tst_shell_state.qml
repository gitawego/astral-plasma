import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// ShellState
// ============================================================================
// The read model the shell fills and injects. Two properties of its design are
// worth a test, because both were the bug in an earlier attempt:
//
//  * it imports **nothing** from the kernel - a `Config` import here would be
//    another stale copy (spec C.9), so the shell binds these values instead;
//  * an app gets a usable answer before the shell fills anything: defaults are
//    honest (nothing is open, no daemon path) rather than undefined.
Item {
    id: testRoot
    width: 400
    height: 300

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function run() {
        const state = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; ShellState { }',
            testRoot, "state");

        // Defaults: nothing is open, and an app renders its empty case.
        assert(state.overviewVisible === false, "the overview starts closed");
        assert(state.commandLauncherVisible === false, "the launcher starts closed");
        assert(state.dashboardVisible === false, "the dashboard starts closed");
        assert(state.daemonBin === "", "no daemon path until the shell provides one");

        // Icon resolution degrades to an empty URL, never to an exception.
        assert(state.iconUrl("terminal") === "", "without a resolver the URL is empty");
        state.iconResolver = function (name) { return "file:///icons/" + name + ".svg"; };
        assert(state.iconUrl("terminal") === "file:///icons/terminal.svg",
            "the shell's resolver is used");

        // The shell drives the values; nothing here reads a settings singleton.
        state.overviewVisible = true;
        assert(state.overviewVisible === true, "the shell can open the overview");
        state.overviewVisible = false;
        assert(state.overviewVisible === false, "and close it");

        // The source must not import the kernel's settings: that is the bug this
        // object exists to avoid.
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../modules/Astral/Kernel/Host/ShellState.qml")
            + "?v=" + Date.now(), false);
        xhr.send();
        const source = xhr.responseText;
        assert(source.indexOf("Kernel/config") === -1 && source.indexOf("Config.") === -1,
            "ShellState must not read Config; the shell binds its values");

        state.destroy();
        console.log("PASS: All shell state tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
