import QtQuick
import "../settings_gui/pages"

Item {
    id: testRoot
    width: 800
    height: 600

    SystemPage {
        id: sysPage
        anchors.fill: parent
        testMode: true
        testInstalled: false
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
        console.log("RUNNING: System Settings & Systemd Service Opt-in Unit Tests");

        // 1. Initial default state: strictly not installed
        assert(!sysPage.isInstalled, "Service must default to uninstalled");
        assert(sysPage.statusText === "Not Installed", "Status text must reflect Not Installed");

        // 2. Simulate User opt-in to install
        sysPage.testInstalled = true;
        sysPage.testStatusText = "Active & Installed";
        assert(sysPage.isInstalled, "isInstalled must reflect user install");
        assert(sysPage.statusText === "Active & Installed", "statusText must reflect active state");

        // 3. Simulate User removal
        sysPage.testInstalled = false;
        sysPage.testStatusText = "Not Installed";
        assert(!sysPage.isInstalled, "isInstalled must reflect user removal");

        // 4. Debug Mode single toggle defaults to false
        assert(sysPage.debugModeActive === false, "Debug Mode must default to false");

        // 5. Simulate user turning on Debug Mode
        sysPage.testDebugMode = true;
        assert(sysPage.debugModeActive === true, "Debug Mode must be active when user toggles it on");

        // 6. Simulate user turning off Debug Mode
        sysPage.testDebugMode = false;
        assert(sysPage.debugModeActive === false, "Debug Mode must be inactive when user toggles it off");

        console.log("PASS: System Settings & Systemd Service Opt-in Unit Tests");
        Qt.exit(0);
    }
}
