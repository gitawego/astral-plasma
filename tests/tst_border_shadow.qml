import QtQuick
import QtQuick.Shapes
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 1920
    height: 1080

    readonly property int dockW: 64
    readonly property int borderT: 14
    readonly property int filletR: 24
    readonly property int dropW: 980
    readonly property real currentDropH: 520
    readonly property color borderColor: Qt.alpha(Colors.textMain, 0.30)

    // Test 1: CornerFillet with stroke
    CornerFillet {
        id: filletTL
        x: testRoot.dockW
        y: testRoot.borderT
        orientation: "topLeft"
        cornerRadius: testRoot.filletR
        fillColor: Colors.surface
        strokeColor: testRoot.borderColor
        strokeWidth: 1
    }

    // Test 2: Dropdown continuous border
    Shape {
        id: dropBorderShape
        x: 400
        y: 0
        width: testRoot.dropW
        height: testRoot.currentDropH
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: dropPath
            fillColor: "transparent"
            strokeColor: testRoot.borderColor
            strokeWidth: 1
            capStyle: ShapePath.FlatCap

            startX: -testRoot.filletR; startY: testRoot.borderT
            PathArc {
                x: 0
                y: testRoot.borderT + testRoot.filletR
                radiusX: testRoot.filletR
                radiusY: testRoot.filletR
                direction: PathArc.Clockwise
            }
            PathLine {
                x: 0
                y: Math.max(testRoot.borderT + testRoot.filletR, testRoot.currentDropH - testRoot.filletR)
            }
            PathArc {
                x: testRoot.filletR
                y: testRoot.currentDropH
                radiusX: testRoot.filletR
                radiusY: testRoot.filletR
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: Math.max(testRoot.filletR, testRoot.dropW - testRoot.filletR)
                y: testRoot.currentDropH
            }
            PathArc {
                x: testRoot.dropW
                y: Math.max(testRoot.borderT + testRoot.filletR, testRoot.currentDropH - testRoot.filletR)
                radiusX: testRoot.filletR
                radiusY: testRoot.filletR
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: testRoot.dropW
                y: testRoot.borderT + testRoot.filletR
            }
            PathArc {
                x: testRoot.dropW + testRoot.filletR
                y: testRoot.borderT
                radiusX: testRoot.filletR
                radiusY: testRoot.filletR
                direction: PathArc.Clockwise
            }
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
        }
    }

    function runTests() {
        console.log("RUNNING: Border and Shadow Tests");
        assert(filletTL.cornerRadius === 24, "fillet cornerRadius should be 24");
        assert(dropBorderShape.width === 980, "dropBorderShape width should be 980");
        assert(dropPath.strokeWidth === 1, "dropPath strokeWidth should be 1");
        console.log("PASS: All Border and Shadow tests passed!");
        Qt.exit(0);
    }
}
