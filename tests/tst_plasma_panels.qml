import QtQuick

Item {
    id: testRoot
    width: 800
    height: 600

    // Mock settings object simulating Config.qml
    property var settings: ({
        "plasma": {
            "disablePanels": "all",
            "disableNotifications": true,
            "autoRestoreOnExit": true
        }
    })

    // Contract properties simulating Config.qml
    readonly property var disablePlasmaPanels: {
        if (!settings.plasma) return "all";
        if (settings.plasma.disablePanels !== undefined) return settings.plasma.disablePanels;
        if (settings.plasma.disableTopPanel) return "all";
        return "all";
    }
    readonly property bool disablePlasmaNotifications: {
        if (!settings.plasma) return true;
        if (settings.plasma.disableNotifications !== undefined) return settings.plasma.disableNotifications;
        return true;
    }
    readonly property string plasmaBackupDir: settings.plasma?.backupDir ?? ""
    readonly property bool autoRestorePlasmaOnExit: settings.plasma?.autoRestoreOnExit ?? true
    readonly property string daemonBin: "/mnt/data/workspace/caelestia-kde/bin/astral-plasma"

    // Helper functions for command preparation matching shell.qml
    function buildDisableCommand(pid) {
        if (!disablePlasmaPanels) return null;
        const target = (typeof disablePlasmaPanels === "string") ? disablePlasmaPanels : "all";
        return [daemonBin, "plasma", "disable", target, "" + pid];
    }

    function buildRestoreCommand() {
        if (!disablePlasmaPanels || !autoRestorePlasmaOnExit) return null;
        return [daemonBin, "plasma", "restore"];
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
        console.log("RUNNING: Plasma Panels Lifecycle & Configuration Non-Regression Tests");

        // Test 1: Config properties and default contracts
        assert(testRoot.disablePlasmaPanels === "all", "disablePlasmaPanels default must evaluate to 'all'");
        assert(testRoot.autoRestorePlasmaOnExit === true, "autoRestorePlasmaOnExit default must be true");
        assert(testRoot.disablePlasmaNotifications === true, "disablePlasmaNotifications default must be true");
        assert(testRoot.plasmaBackupDir === "", "plasmaBackupDir defaults to empty (system default)");

        // Test 2: Daemon binary path resolution
        assert(testRoot.daemonBin.endsWith("astral-plasma"), "daemonBin must point to 'astral-plasma'");

        // Test 3: Command construction verification for disable
        const dummyPid = 12345;
        const disableCmd = testRoot.buildDisableCommand(dummyPid);
        assert(disableCmd !== null, "disableCmd must not be null when enabled");
        assert(disableCmd.length === 5, "disable command must have 5 arguments");
        assert(disableCmd[0] === testRoot.daemonBin, "disableCmd[0] must be daemonBin");
        assert(disableCmd[1] === "plasma", "disableCmd[1] must be 'plasma'");
        assert(disableCmd[2] === "disable", "disableCmd[2] must be 'disable'");
        assert(disableCmd[3] === "all", "disableCmd[3] must match target 'all'");
        assert(disableCmd[4] === "12345", "disableCmd[4] must match pid string");

        // Test 4: Command construction verification for restore
        const restoreCmd = testRoot.buildRestoreCommand();
        assert(restoreCmd !== null, "restoreCmd must not be null when autoRestore is active");
        assert(restoreCmd.length === 3, "restore command must have 3 arguments");
        assert(restoreCmd[0] === testRoot.daemonBin, "restoreCmd[0] must be daemonBin");
        assert(restoreCmd[1] === "plasma", "restoreCmd[1] must be 'plasma'");
        assert(restoreCmd[2] === "restore", "restoreCmd[2] must be 'restore'");

        // Test 5: Target variations ('top', 'bottom', boolean false)
        testRoot.settings = { "plasma": { "disablePanels": "top", "autoRestoreOnExit": true } };
        assert(testRoot.disablePlasmaPanels === "top", "target 'top' must be recognized");
        const topCmd = testRoot.buildDisableCommand(999);
        assert(topCmd[3] === "top", "disable command target must be 'top'");

        testRoot.settings = { "plasma": { "disablePanels": false, "autoRestoreOnExit": true } };
        assert(testRoot.disablePlasmaPanels === false, "disablePlasmaPanels can be false");
        assert(testRoot.buildDisableCommand(999) === null, "buildDisableCommand must return null when disabled");
        assert(testRoot.buildRestoreCommand() === null, "buildRestoreCommand must return null when panels were not disabled");

        // Test 6: Legacy backward compatibility (empty plasma object defaults safely to 'all')
        testRoot.settings = {};
        assert(testRoot.disablePlasmaPanels === "all", "missing plasma settings section defaults to 'all'");
        assert(testRoot.autoRestorePlasmaOnExit === true, "missing autoRestore defaults to true");

        // Test 7: Auto restore disabled by user
        testRoot.settings = { "plasma": { "disablePanels": "all", "autoRestoreOnExit": false } };
        assert(testRoot.autoRestorePlasmaOnExit === false, "autoRestoreOnExit can be set to false");
        assert(testRoot.buildRestoreCommand() === null, "restore command must be null when autoRestoreOnExit is false");

        console.log("PASS: Plasma Panels Lifecycle & Configuration Non-Regression Tests");
        Qt.exit(0);
    }
}
