import QtQuick
import "../components"
import "../theme"
import "../shell"

Item {
    id: testRoot
    width: 1920
    height: 1080

    property bool cancelSignalReceived: false
    property bool confirmSignalReceived: false

    PowerConfirmDialog {
        id: dialog
        anchors.fill: parent

        onCanceled: testRoot.cancelSignalReceived = true
        onConfirmed: testRoot.confirmSignalReceived = true
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
        console.log("RUNNING: Power Confirmation Dialog Unit Tests");

        const primaryViolet = "#6B4FA0";
        const dangerRed = "#BA1A1A";

        // 1. Initial State: Must be hidden
        assert(!dialog.isDialogVisible, "Dialog must initially not be visible");
        assert(dialog.opacity === 0.0, "Dialog visual opacity must initially be 0.0");
        assert(dialog.width === 1920, "Dialog root width must span 1920");
        assert(dialog.height === 1080, "Dialog root height must span 1080");

        // 2. Request Log Out State
        dialog.testAction = "logout";
        dialog.testTitle = "Log Out";
        dialog.testMessage = "Are you sure you want to end your current session and log out?";
        dialog.testIcon = "logout";
        dialog.testConfirmLabel = "Log Out";
        dialog.testAccentColor = primaryViolet;
        dialog.testVisible = true;

        assert(dialog.isDialogVisible, "Dialog must be visible when requested");
        assert(dialog.currentAction === "logout", "currentAction must be 'logout'");
        assert(dialog.currentTitle === "Log Out", "currentTitle must be 'Log Out'");
        assert(dialog.currentIcon === "logout", "currentIcon must be 'logout'");
        assert(dialog.currentConfirmLabel === "Log Out", "currentConfirmLabel must be 'Log Out'");
        assert(Qt.colorEqual(dialog.currentAccentColor, primaryViolet), "currentAccentColor must match primary violet");

        // 3. Cancel Action Interaction
        testRoot.cancelSignalReceived = false;
        dialog.cancelAction();
        assert(testRoot.cancelSignalReceived, "cancelAction must trigger canceled signal");

        // 4. Request Restart State
        dialog.testVisible = false;
        dialog.testAction = "restart";
        dialog.testTitle = "Restart";
        dialog.testMessage = "Are you sure you want to restart your computer? Any unsaved work will be lost.";
        dialog.testIcon = "restart_alt";
        dialog.testConfirmLabel = "Restart";
        dialog.testAccentColor = primaryViolet;
        dialog.testVisible = true;

        assert(dialog.isDialogVisible, "Dialog must be visible for restart");
        assert(dialog.currentAction === "restart", "currentAction must be 'restart'");
        assert(dialog.currentTitle === "Restart", "currentTitle must be 'Restart'");
        assert(dialog.currentIcon === "restart_alt", "currentIcon must be 'restart_alt'");
        assert(dialog.currentConfirmLabel === "Restart", "currentConfirmLabel must be 'Restart'");
        assert(Qt.colorEqual(dialog.currentAccentColor, primaryViolet), "currentAccentColor must match primary violet");

        // 5. Request Shut Down State (Destructive / Material 3 Error Accent)
        dialog.testVisible = false;
        dialog.testAction = "shutdown";
        dialog.testTitle = "Shut Down";
        dialog.testMessage = "Are you sure you want to shut down your computer? Any unsaved work will be lost.";
        dialog.testIcon = "power_settings_new";
        dialog.testConfirmLabel = "Shut Down";
        dialog.testAccentColor = dangerRed;
        dialog.testVisible = true;

        assert(dialog.isDialogVisible, "Dialog must be visible for shutdown");
        assert(dialog.currentAction === "shutdown", "currentAction must be 'shutdown'");
        assert(dialog.currentTitle === "Shut Down", "currentTitle must be 'Shut Down'");
        assert(dialog.currentIcon === "power_settings_new", "currentIcon must be 'power_settings_new'");
        assert(dialog.currentConfirmLabel === "Shut Down", "currentConfirmLabel must be 'Shut Down'");
        assert(Qt.colorEqual(dialog.currentAccentColor, dangerRed), "currentAccentColor must match danger red (#BA1A1A)");

        // 6. Liquid Glass Design System Optical Stack Assertions
        dialog.testVisible = true;
        dialog.testAction = "logout";
        assert(dialog.dialogCardItem !== undefined, "dialogCardItem must be exposed");
        assert(dialog.dialogCardItem.radius >= 24, "dialogCardItem radius must be >= 24 for organic liquid glass");
        assert(dialog.cardW === 440, "cardW must be 440px");
        assert(dialog.cardH > 200, "cardH must be > 200px");
        assert(dialog.cardX === Math.round((1920 - 440) / 2), "cardX must be centered");
        assert(dialog.refractionGradientItem !== undefined, "refractionGradientItem must be present");
        assert(dialog.causticGlowItem !== undefined, "causticGlowItem must be present");
        assert(dialog.topGlareItem !== undefined, "topGlareItem must be present");
        assert(dialog.bottomRimItem !== undefined, "bottomRimItem must be present");
        assert(dialog.cursorGlintItem !== undefined, "cursorGlintItem must be present");
        assert(dialog.cancelButtonItem !== undefined, "cancelButtonItem must be exposed");
        assert(dialog.confirmButtonItem !== undefined, "confirmButtonItem must be exposed");
        assert(dialog.headerBadgeItem !== undefined, "headerBadgeItem must be exposed");

        // 7. Confirm Action Interaction
        testRoot.confirmSignalReceived = false;
        dialog.confirmAction();
        assert(testRoot.confirmSignalReceived, "confirmAction must trigger confirmed signal");

        // 8. Reset to Hidden State
        dialog.testVisible = false;
        dialog.testAction = "";
        assert(!dialog.isDialogVisible, "Dialog must return to hidden state when closed");

        console.log("PASS: Power Confirmation Dialog Unit Tests");
        Qt.exit(0);
    }
}
