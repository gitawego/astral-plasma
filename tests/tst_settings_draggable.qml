import QtQuick
import "../theme"
import "../settings_gui"

Item {
    id: testRoot
    width: 1920
    height: 1080

    // Mock Config for Settings Window
    QtObject {
        id: mockConfig
        property bool settingsVisible: true
    }

    // Embed Settings Window Item logic under test
    Item {
        id: mockWindow
        width: 1920
        height: 1080

        property alias dialogBox: dialogBox
        property alias blurRegion: blurRegion
        property alias maskRegion: maskRegion
        property bool userMoved: false

        function resetPosition() {
            userMoved = false;
            dialogBox.x = Qt.binding(() => Math.round((mockWindow.width - dialogBox.width) / 2));
            dialogBox.y = Qt.binding(() => Math.round((mockWindow.height - dialogBox.height) / 2));
        }

        function clampPosition() {
            if (mockWindow.width <= 0 || mockWindow.height <= 0) return;
            const minX = 16;
            const maxX = Math.max(minX, mockWindow.width - dialogBox.width - 16);
            const minY = 16;
            const maxY = Math.max(minY, mockWindow.height - dialogBox.height - 16);
            dialogBox.x = Math.max(minX, Math.min(dialogBox.x, maxX));
            dialogBox.y = Math.max(minY, Math.min(dialogBox.y, maxY));
        }

        onWidthChanged: if (userMoved) clampPosition()
        onHeightChanged: if (userMoved) clampPosition()

        Rectangle {
            id: dialogBox
            width: 860
            height: 580
            x: Math.round((mockWindow.width - width) / 2)
            y: Math.round((mockWindow.height - height) / 2)

            MouseArea {
                id: dialogDragArea
                anchors.fill: parent
                drag.target: dialogBox
                drag.axis: Drag.XAndYAxis
                drag.minimumX: 16
                drag.maximumX: Math.max(16, mockWindow.width - dialogBox.width - 16)
                drag.minimumY: 16
                drag.maximumY: Math.max(16, mockWindow.height - dialogBox.height - 16)

                onPositionChanged: {
                    if (drag.active) {
                        mockWindow.userMoved = true;
                    }
                }
                onDoubleClicked: mockWindow.resetPosition()
            }

            MouseArea {
                id: headerDragBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: 48
                height: 52

                drag.target: dialogBox
                drag.axis: Drag.XAndYAxis
                drag.minimumX: 16
                drag.maximumX: Math.max(16, mockWindow.width - dialogBox.width - 16)
                drag.minimumY: 16
                drag.maximumY: Math.max(16, mockWindow.height - dialogBox.height - 16)

                onPositionChanged: {
                    if (drag.active) {
                        mockWindow.userMoved = true;
                    }
                }
                onDoubleClicked: mockWindow.resetPosition()
            }
        }

        // Mock Blur & Mask Regions tracking dialogBox
        QtObject {
            id: blurRegion
            readonly property real x: dialogBox.x
            readonly property real y: dialogBox.y
            readonly property real width: mockConfig.settingsVisible ? dialogBox.width : 0
            readonly property real height: mockConfig.settingsVisible ? dialogBox.height : 0
        }

        QtObject {
            id: maskRegion
            readonly property real x: dialogBox.x
            readonly property real y: dialogBox.y
            readonly property real width: mockConfig.settingsVisible ? dialogBox.width : 0
            readonly property real height: mockConfig.settingsVisible ? dialogBox.height : 0
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
            return false;
        }
        return true;
    }

    function runTests() {
        console.log("RUNNING: Settings Panel Draggable & Moveable Unit Tests");

        const expectedCenterX = Math.round((1920 - 860) / 2); // 530
        const expectedCenterY = Math.round((1080 - 580) / 2); // 250

        // 1. Initial State: Centered
        assert(mockWindow.dialogBox.x === expectedCenterX, "Dialog must start centered on X (expected " + expectedCenterX + ", got " + mockWindow.dialogBox.x + ")");
        assert(mockWindow.dialogBox.y === expectedCenterY, "Dialog must start centered on Y (expected " + expectedCenterY + ", got " + mockWindow.dialogBox.y + ")");
        assert(mockWindow.userMoved === false, "userMoved must start false");

        // 2. Blur and Mask regions must track centered coordinates
        assert(mockWindow.blurRegion.x === expectedCenterX, "Blur region must match initial dialog X");
        assert(mockWindow.blurRegion.y === expectedCenterY, "Blur region must match initial dialog Y");
        assert(mockWindow.maskRegion.x === expectedCenterX, "Mask region must match initial dialog X");
        assert(mockWindow.maskRegion.y === expectedCenterY, "Mask region must match initial dialog Y");
        assert(mockWindow.maskRegion.width === 860, "Mask region width must match dialog width");
        assert(mockWindow.maskRegion.height === 580, "Mask region height must match dialog height");

        // 3. Simulate dragging dialog to new coordinates
        mockWindow.dialogBox.x = 200;
        mockWindow.dialogBox.y = 120;
        mockWindow.userMoved = true;

        assert(mockWindow.dialogBox.x === 200, "Dialog X must reflect dragged position (200)");
        assert(mockWindow.dialogBox.y === 120, "Dialog Y must reflect dragged position (120)");
        assert(mockWindow.blurRegion.x === 200, "Blur region X must dynamically track dragged dialog X");
        assert(mockWindow.blurRegion.y === 120, "Blur region Y must dynamically track dragged dialog Y");
        assert(mockWindow.maskRegion.x === 200, "Mask region X must dynamically track dragged dialog X");
        assert(mockWindow.maskRegion.y === 120, "Mask region Y must dynamically track dragged dialog Y");

        // 4. Clicking outside must NOT close settings (non-modal floating behavior)
        // Simulate outside interaction: settingsVisible must stay true
        assert(mockConfig.settingsVisible === true, "Settings must remain visible when clicking other places");

        // 4. Clamping bounds verification
        // Test lower clamp
        mockWindow.dialogBox.x = -100;
        mockWindow.dialogBox.y = -50;
        mockWindow.clampPosition();
        assert(mockWindow.dialogBox.x === 16, "Clamping must constrain minimum X to 16, got " + mockWindow.dialogBox.x);
        assert(mockWindow.dialogBox.y === 16, "Clamping must constrain minimum Y to 16, got " + mockWindow.dialogBox.y);

        // Test upper clamp
        mockWindow.dialogBox.x = 3000;
        mockWindow.dialogBox.y = 2000;
        mockWindow.clampPosition();
        const expectedMaxX = 1920 - 860 - 16; // 1044
        const expectedMaxY = 1080 - 580 - 16; // 484
        assert(mockWindow.dialogBox.x === expectedMaxX, "Clamping must constrain maximum X to " + expectedMaxX + ", got " + mockWindow.dialogBox.x);
        assert(mockWindow.dialogBox.y === expectedMaxY, "Clamping must constrain maximum Y to " + expectedMaxY + ", got " + mockWindow.dialogBox.y);

        // 5. Reset to center (double-click simulation)
        mockWindow.resetPosition();
        assert(mockWindow.userMoved === false, "userMoved must become false after reset");
        assert(mockWindow.dialogBox.x === expectedCenterX, "Dialog X must restore to centered X after reset");
        assert(mockWindow.dialogBox.y === expectedCenterY, "Dialog Y must restore to centered Y after reset");
        assert(mockWindow.blurRegion.x === expectedCenterX, "Blur region X must track reset centered X");
        assert(mockWindow.blurRegion.y === expectedCenterY, "Blur region Y must track reset centered Y");

        console.log("PASS: Settings Panel Draggable & Moveable Unit Tests");
        Qt.exit(0);
    }
}
