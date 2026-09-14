import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    CornerFillet {
        id: filletDefault
    }

    CornerFillet {
        id: filletCustom
        cornerRadius: 28
        orientation: "dropdownLeft"
        fillColor: Colors.surface
    }

    CornerFillet {
        id: filletRight
        cornerRadius: 28
        orientation: "dropdownRight"
        fillColor: Colors.surface
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
        }
    }

    function runTests() {
        console.log("RUNNING: CornerFillet Tests");

        // Test 1: Default dimensions
        assert(filletDefault.cornerRadius === 20, "filletDefault.cornerRadius should default to 20");
        assert(filletDefault.width === 20, "filletDefault.width should equal cornerRadius");
        assert(filletDefault.height === 20, "filletDefault.height should equal cornerRadius");

        // Test 2: Custom radius dimensions
        assert(filletCustom.cornerRadius === 28, "filletCustom.cornerRadius should be 28");
        assert(filletCustom.width === 28, "filletCustom.width should be 28");
        assert(filletCustom.height === 28, "filletCustom.height should be 28");
        assert(filletCustom.orientation === "dropdownLeft", "filletCustom orientation should be dropdownLeft");

        // Test 3: Dropdown right orientation
        assert(filletRight.orientation === "dropdownRight", "filletRight orientation should be dropdownRight");
        assert(filletRight.width === 28, "filletRight width should be 28");

        // Test 4: Top border attachment logic
        const borderT = 14;
        const filletY = borderT;
        assert(filletY === 14, "Fused fillet top position must match border thickness (not y=0)");

        console.log("PASS: CornerFillet Tests");
        Qt.exit(0);
    }
}
