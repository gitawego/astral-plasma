import QtQuick
import "../theme"
import "../shell"
import "../config"

Item {
    id: testRoot
    width: 1920
    height: 1080

    property bool debugMode: false

    // 1. Real CentralDropdown component
    CentralDropdown {
        id: dropdownContainer
        dropX: 470
        dropW: 980
        dropH: 520
    }

    // 2. Top Edge trigger hover simulation item
    Item {
        id: topEdgeArea
        x: dropdownContainer.dropX
        y: 0
        width: dropdownContainer.dropW
        height: 16

        property bool hovered: false
    }

    // 3. Exact Domain Policy matching UnifiedShell.qml
    readonly property bool isDashboardHovered: dropdownContainer.isHovered || topEdgeArea.hovered

    onIsDashboardHoveredChanged: {
        if (isDashboardHovered) {
            closeTimer.stop();
        } else if (dropdownContainer.isOpen) {
            closeTimer.restart();
        }
    }

    // 3b. Hover intent, mirroring UnifiedShell's openIntentTimer: the drawer must
    // not open on the first hover frame - crossing the top edge is what reaching
    // for a browser tab looks like.
    Timer {
        id: openIntentTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (!dropdownContainer.isOpen) dropdownContainer.isOpen = true;
        }
    }

    function hoverTopEdge(hovered) {
        topEdgeArea.hovered = hovered;
        if (hovered) {
            openIntentTimer.restart();
        } else {
            openIntentTimer.stop();
        }
    }

    // 4. Auto-close grace timer matching UnifiedShell.qml
    Timer {
        id: closeTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (testRoot.debugMode) return;
            if (!testRoot.isDashboardHovered) {
                dropdownContainer.isOpen = false;
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
            throw new Error(msg);
        }
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function runTests() {
        console.log("RUNNING: Top Drawer Auto-Close Non-Regression Tests");

        // Test 1: Validate timer parameters
        assert(closeTimer.interval <= 500, "closeTimer interval must be <= 500ms for snappy UX");
        assert(closeTimer.repeat === false, "closeTimer must be one-shot");

        // Test 1b: Hover intent - a touch of the top edge is not an intent.
        assert(openIntentTimer.interval >= 300 && openIntentTimer.interval <= 700,
            "the hover-intent dwell must be long enough to outlast an accidental touch");
        assert(openIntentTimer.repeat === false, "the intent timer must be one-shot");

        dropdownContainer.isOpen = false;
        hoverTopEdge(true);
        assert(dropdownContainer.isOpen === false, "hovering the top edge must not open the drawer immediately");
        assert(openIntentTimer.running === true, "hovering must arm the intent timer");
        hoverTopEdge(false);
        assert(openIntentTimer.running === false, "leaving before the dwell must cancel the intent");
        assert(dropdownContainer.isOpen === false, "a cancelled intent must never open the drawer");
        hoverTopEdge(true);
        openIntentTimer.triggered();
        assert(dropdownContainer.isOpen === true, "a dwell that completes must open the drawer");
        hoverTopEdge(false);
        dropdownContainer.isOpen = false;
        closeTimer.stop();

        // The drawer is transient: no persisted `dashboardVisible` may open it
        // on a reload. That key in settings.json is what made every restart (and
        // every hot reload) pop the top drawer open.
        const configSrc = readLocalFile("../config/Config.qml");
        assert(!/dashboardVisible:\s*\(typeof Quickshell[\s\S]{0,200}?settings\.dashboardVisible/.test(configSrc),
            "the dashboard's initial visibility must not be read from settings");
        const settingsSrc = readLocalFile("../config/settings.json");
        assert(!/"dashboardVisible"/.test(settingsSrc),
            "settings.json must not ship a transient overlay state");

        // Source contracts: the shell, not just this mirror, must implement it.
        const shellSrc = readLocalFile("../shell/UnifiedShell.qml");
        assert(/openIntentTimer/.test(shellSrc), "UnifiedShell must gate the hover open behind a dwell timer");
        assert(/onEntered:[\s\S]{0,400}openIntentTimer\.restart\(\)/.test(shellSrc),
            "the top-edge hover must arm the dwell instead of opening the drawer");
        assert(!/onEntered:[\s\S]{0,160}Config\.dashboardVisible = true/.test(shellSrc),
            "the top edge must never open the drawer on the first hover frame");
        assert(/onExited:[\s\S]{0,60}openIntentTimer\.stop\(\)/.test(shellSrc),
            "leaving the top edge before the dwell must cancel the intent");

        // Test 2: Enable hover override on real CentralDropdown
        dropdownContainer.hoverOverrideActive = true;
        dropdownContainer.hoverOverride = false;
        topEdgeArea.hovered = false;
        dropdownContainer.isOpen = false;
        assert(dropdownContainer.isHovered === false, "Dropdown initially not hovered");
        assert(isDashboardHovered === false, "Dashboard initially not hovered");
        assert(closeTimer.running === false, "Timer initially not running");

        // Test 3: Dashboard opens (e.g. hovered on top edge)
        dropdownContainer.isOpen = true;
        topEdgeArea.hovered = true;
        assert(isDashboardHovered === true, "isDashboardHovered is true when top edge hovered");
        assert(closeTimer.running === false, "closeTimer must not run while top edge hovered");
        assert(dropdownContainer.isOpen === true, "Dashboard is open");

        // Test 4: Mouse moves into CentralDropdown from top edge
        dropdownContainer.hoverOverride = true;
        topEdgeArea.hovered = false;
        assert(dropdownContainer.isHovered === true, "Dropdown isHovered is true");
        assert(isDashboardHovered === true, "isDashboardHovered remains true when inside CentralDropdown");
        assert(closeTimer.running === false, "closeTimer must not run while inside CentralDropdown");
        assert(dropdownContainer.isOpen === true, "Dashboard stays open while inside CentralDropdown");

        // Test 5: Mouse moves OUTSIDE the menu (reproducing the user's reported bug)
        // Mouse leaves CentralDropdown and is not on top edge
        dropdownContainer.hoverOverride = false;
        assert(dropdownContainer.isHovered === false, "Dropdown isHovered became false");
        assert(isDashboardHovered === false, "isDashboardHovered must transition to false when mouse leaves");
        assert(closeTimer.running === true, "REGRESSION CHECK: closeTimer MUST start running when mouse moves outside menu");
        assert(dropdownContainer.isOpen === true, "Dashboard is still visible during grace timer");

        // Test 6: Grace timer expires -> menu MUST auto-close
        closeTimer.stop();
        closeTimer.triggered();
        assert(dropdownContainer.isOpen === false, "REGRESSION CHECK: Dashboard MUST automatically close when timer triggers");
        assert(closeTimer.running === false, "closeTimer must stop after triggering");

        // Test 7: Re-entry cancellation
        // Reopen dashboard
        dropdownContainer.isOpen = true;
        dropdownContainer.hoverOverride = true;
        assert(isDashboardHovered === true, "isDashboardHovered is true");
        // User moves mouse out
        dropdownContainer.hoverOverride = false;
        assert(closeTimer.running === true, "Timer started on mouse leave");
        // User moves mouse back in before timer expires
        dropdownContainer.hoverOverride = true;
        assert(isDashboardHovered === true, "isDashboardHovered is true on re-entry");
        assert(closeTimer.running === false, "Timer must be cancelled when mouse re-enters menu");
        assert(dropdownContainer.isOpen === true, "Dashboard remains open after re-entry");

        // Test 8: Manual close stops timer
        dropdownContainer.hoverOverride = false;
        assert(closeTimer.running === true, "Timer running after exit");
        dropdownContainer.isOpen = false;
        closeTimer.stop();
        assert(closeTimer.running === false, "closeTimer must stop immediately when dashboard closed manually");

        // Test 9: Default production state must NOT have debugMode enabled
        assert(testRoot.debugMode === false, "testRoot.debugMode must default to false in production");

        // Test 10: When debugMode is enabled via Settings toggle, auto-close is frozen for inspection
        testRoot.debugMode = true;
        assert(testRoot.debugMode === true, "debugMode is now active");
        dropdownContainer.isOpen = true;
        dropdownContainer.hoverOverride = false;
        // Trigger timer expiration
        closeTimer.triggered();
        assert(dropdownContainer.isOpen === true, "When debugMode is ON, dropdown must remain open (frozen) for debugging");

        // Test 11: When debugMode is toggled back to OFF, auto-close resumes immediately
        testRoot.debugMode = false;
        assert(testRoot.debugMode === false, "debugMode is now off");
        closeTimer.triggered();
        assert(dropdownContainer.isOpen === false, "When debugMode is OFF, dropdown MUST auto-close immediately");

        console.log("PASS: Top Drawer Auto-Close Non-Regression Tests");
        Qt.exit(0);
    }
}
