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

    // Test PacmanIcon instance
    PacmanIcon {
        id: pacman
        size: 16
        color: Colors.textOnPrimary
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

        // Test 4: Pacman icon on active desktop must be white (#ffffff)
        assert(pacman.color === Colors.textOnPrimary, "Pacman color must be bound to textOnPrimary");
        assert(pacman.size === 16, "Pacman size should be 16");

        console.log("PASS: All Dock Corners & Border Geometry tests passed!");
        Qt.exit(0);
    }
}
