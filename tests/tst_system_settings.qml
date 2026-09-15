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

        console.log("PASS: System Settings & Systemd Service Opt-in Unit Tests");
        Qt.exit(0);
    }
}
