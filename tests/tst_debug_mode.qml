import QtQuick
import "../settings_gui/pages"
import "../services"

Item {
    id: testRoot
    width: 800
    height: 600

    // Mock settings object simulating Config.qml
    property var settings: ({
        "debugMode": false
    })

    readonly property bool debugMode: settings.debugMode ?? false
    readonly property bool freezeAutoClose: debugMode

    function setDebugMode(val) {
        let copy = JSON.parse(JSON.stringify(settings));
        copy.debugMode = val;
        settings = copy;
    }

    SystemPage {
        id: sysPage
        anchors.fill: parent
        testMode: true
        testDebugMode: testRoot.debugMode
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
        console.log("RUNNING: Single Debug Mode Toggle & Decoupled Debug System Tests");

        // 1. Initial State: debugMode MUST default to false in production
        assert(testRoot.debugMode === false, "Debug Mode must default to false");
        assert(testRoot.freezeAutoClose === false, "freezeAutoClose must be false by default");
        assert(sysPage.debugModeActive === false, "SystemPage must report debugMode as inactive");

        // 2. Toggling Debug Mode ON
        testRoot.setDebugMode(true);
        sysPage.testDebugMode = testRoot.debugMode;
        assert(testRoot.debugMode === true, "Debug Mode must become active when toggled on");
        assert(testRoot.freezeAutoClose === true, "freezeAutoClose must be active when debugMode is true");
        assert(sysPage.debugModeActive === true, "SystemPage must reflect active debugMode");

        // 3. Toggling Debug Mode OFF
        testRoot.setDebugMode(false);
        sysPage.testDebugMode = testRoot.debugMode;
        assert(testRoot.debugMode === false, "Debug Mode must become inactive when toggled off");
        assert(testRoot.freezeAutoClose === false, "freezeAutoClose must be false when debugMode is false");
        assert(sysPage.debugModeActive === false, "SystemPage must reflect inactive debugMode");

        console.log("PASS: Single Debug Mode Toggle & Decoupled Debug System Tests");
        Qt.exit(0);
    }
}
