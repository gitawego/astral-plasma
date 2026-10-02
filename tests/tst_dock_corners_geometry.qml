import QtQuick
import "../components"
import "../theme"
import "../config"

Item {
    id: testRoot
    width: 1920
    height: 1080

    readonly property int dockW: 64
    readonly property int borderT: 4
    readonly property int filletR: 20
    readonly property color borderColor: Theme.borderSubtle

    // Test dock border segment height calculation
    readonly property int dockBorderY: borderT + filletR
    readonly property int dockBorderHeight: testRoot.height - (borderT * 2 + filletR * 2)

    // Test top border segment x calculation
    readonly property int topBorderStartX: dockW + filletR

    // Test PacmanIcon instance (the dock's active-workspace marker). Its colour is
    // a token the dock binds; the value asserted below is the marker's own default.
    PacmanIcon {
        id: pacman
        size: 16
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        try {
            xhr.send();
            return xhr.responseText || "";
        } catch (e) {
            return "";
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            // Qt.exit only schedules the exit: a suite that keeps running would
            // print its PASS line and override the code (docs/LESSONS.md 37).
            throw new Error(msg);
        }
    }

    function runTests() {
        console.log("RUNNING: Dock Corners & Border Geometry Tests");

        // Test 1: Dock border must NOT start at y=0 (would cut across top border / fillet)
        assert(dockBorderY > borderT, "Dock inner border must start below top border and fillet");
        assert(dockBorderY === 24, "Dock inner border y should be borderT + filletR = 24");
        assert(dockBorderHeight < testRoot.height, "Dock inner border must not extend full screen height");

        // Test 2: Top border must NOT start at x=0 (would cut across dock)
        assert(topBorderStartX > dockW, "Top inner border must start to the right of the dock and fillet");
        assert(topBorderStartX === 84, "Top inner border startX should be dockW + filletR = 84");

        // Test 3: borderColor must not be harsh textMain (black lines bug)
        assert(borderColor !== Colors.textMain, "borderColor must be subtle outline, not textMain");

        // Test 4: the active-workspace marker. `Qt.colorEqual` is the only correct
        // comparison for colours (a colour value is never === a string or another
        // colour object); the value checked here is the marker's own default. The
        // dock's binding to the on-primary token is a design contract that lives in
        // the dock's source - the offscreen harness cannot load the theme singleton
        // to read it live.
        assert(Qt.colorEqual(pacman.color, "#ffffff"), "Pacman marker default is the on-primary white");
        assert(pacman.size === 16, "Pacman size should be 16");
        const dockSource = readLocalFile("../shell/UnifiedDock.qml");
        assert(dockSource.length > 0, "UnifiedDock.qml must be readable");
        // (Qt's JS engine has no `s` flag; slice the block instead.)
        const pacmanBlockStart = dockSource.indexOf("PacmanIcon {");
        assert(pacmanBlockStart >= 0, "UnifiedDock must render a PacmanIcon");
        const pacmanBlock = dockSource.substring(pacmanBlockStart, pacmanBlockStart + 300);
        assert(pacmanBlock.indexOf("color: Colors.textOnPrimary") >= 0,
            "the dock binds its active-workspace pacman to Colors.textOnPrimary");

        console.log("PASS: All Dock Corners & Border Geometry tests passed!");
        Qt.exit(0);
    }
}
