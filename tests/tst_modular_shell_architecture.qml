import QtQuick
import "../shell"
import "../config"
import "../theme"

Item {
    id: testRoot
    width: 1920
    height: 1080

    UnifiedFrame {
        id: frame
        width: parent.width
        height: parent.height
        dockW: 70
        borderT: 14
        filletR: 20
        borderColor: "#33ffffff"
        dropX: 470
        dropW: 980
        currentDropH: 300
        dropdownOffsetProgress: 1.0
        currentPopW: 280
        popoutY: 800
        popoutHeight: 240
        popoutOffsetProgress: 1.0
        fusedProgress: 1.0
    }

    CentralDropdown {
        id: dropdown
        dropX: 470
        dropW: 980
        dropH: 520
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
        console.log("RUNNING: Modular Shell Architecture Unit Tests");

        // 1. UnifiedFrame verification
        assert(frame.dockW === 70, "Frame dockW matches");
        assert(frame.borderT === 14, "Frame borderT matches");
        assert(frame.filletR === 20, "Frame filletR matches");
        assert(frame.currentDropH === 300, "Frame dropdown height bound");
        assert(frame.topBorderRightLimit === (1920 - 14 - 20), "Top border right limit connects to TR fillet");
        assert(frame.cornerFilletR === 20, "cornerFilletR is always 20px");
        assert(frame.innerFilletTLItem.visible === (frame.cornerFilletR > 1), "TL fillet visibility matches cornerFilletR");

        // 2. CentralDropdown verification
        assert(dropdown.dropW === 980, "Dropdown width matches");
        assert(dropdown.dropH === 520, "Dropdown height matches");
        assert(dropdown.tabs.length === 4, "Dropdown contains 4 tabs");
        assert(dropdown.tabs[0].id === "dashboard", "Tab 0 is dashboard");
        assert(dropdown.tabs[1].id === "media", "Tab 1 is media");
        assert(dropdown.tabs[2].id === "performance", "Tab 2 is performance");
        assert(dropdown.tabs[3].id === "workspaces", "Tab 3 is workspaces");

        console.log("PASS: Modular Shell Architecture Unit Tests");
        Qt.exit(0);
    }
}
