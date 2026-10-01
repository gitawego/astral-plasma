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

        // 4. Desktop Integration default state: strictly not installed without user opt-in
        assert(!sysPage.isDesktopInstalled, "Desktop Integration must default to uninstalled");
        assert(sysPage.desktopStatusText === "Not Installed", "Desktop status text must reflect Not Installed");

        // 5. Simulate User opt-in to install Desktop Integration
        sysPage.testDesktopInstalled = true;
        sysPage.testDesktopStatusText = "Installed";
        assert(sysPage.isDesktopInstalled, "isDesktopInstalled must reflect user install");
        assert(sysPage.desktopStatusText === "Installed", "desktopStatusText must reflect Installed");

        // 6. Simulate User removal of Desktop Integration
        sysPage.testDesktopInstalled = false;
        sysPage.testDesktopStatusText = "Not Installed";
        assert(!sysPage.isDesktopInstalled, "isDesktopInstalled must reflect user removal");

        // 7. Debug Mode single toggle defaults to false
        assert(sysPage.debugModeActive === false, "Debug Mode must default to false");

        // 8. Simulate user turning on Debug Mode
        sysPage.testDebugMode = true;
        assert(sysPage.debugModeActive === true, "Debug Mode must be active when user toggles it on");

        // 9. Exit button semantic design system contract
        assert(sysPage.exitButton !== null, "Exit button must exist");
        assert(sysPage.exitButton.accent === "error", "Exit button accent must be 'error'");
        assert(sysPage.exitButton.variant === "tonal", "Exit button variant must be 'tonal'");
        assert(("" + sysPage.exitButton.activeTextColor).toLowerCase() !== "#410002" &&
               ("" + sysPage.exitButton.activeTextColor).toLowerCase() !== "#000000",
               "Exit button font color must be readable and NOT black or dark brown (#410002)");
        assert(("" + sysPage.exitButton.activeTextColor).toLowerCase() === "#ffdad6",
               "Exit button font color in dark mode must be #ffdad6");
        assert(("" + sysPage.exitButton.activeColor).toLowerCase() === "#93000a",
               "Exit button container color in dark mode must be #93000a");

        console.log("PASS: System Settings, Systemd & Desktop Integration Opt-in Unit Tests");
        Qt.exit(0);
    }
}
