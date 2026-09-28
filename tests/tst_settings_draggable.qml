import QtQuick

/**
 * Settings window contract.
 *
 * The settings surface must behave like the Copilot (docs/LESSONS.md §8.9):
 * a real xdg-toplevel that stacks, can be pushed to the background by the
 * compositor and shows in Alt+Tab - not a layer-shell overlay, which protocol
 * keeps above every application window and which Alt+Tab can never reach.
 *
 * FloatingWindow cannot be instantiated in the offscreen test harness, so the
 * contract is asserted against the real source, the same way
 * `tst_assistant_drawer.qml` pins the Copilot toplevel.
 */
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
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
        return true;
    }

    function runTests() {
        console.log("RUNNING: Settings Window Toplevel Contract");

        const src = readLocalFile("../settings_gui/SettingsWindow.qml");
        assert(src.length > 1000, "SettingsWindow.qml must be readable by the harness");

        // ------------------------------------------------------------------
        // 1. A real window, not a layer-shell overlay
        // ------------------------------------------------------------------
        assert(/FloatingWindow\s*\{/.test(src),
            "SettingsWindow must be a FloatingWindow (real xdg-toplevel), like the Copilot");
        assert(!/PanelWindow\s*\{/.test(src),
            "SettingsWindow must not be a PanelWindow: a layer-shell surface is pinned above every application window");
        assert(!/WlrLayershell/.test(src),
            "SettingsWindow must not be a layer-shell surface: those can never be backgrounded or reached from Alt+Tab");
        assert(!/mask:\s*Region/.test(src),
            "SettingsWindow must not declare a clickthrough mask: the toplevel is card-sized");
        assert(/title:\s*"Astral Settings"/.test(src),
            "SettingsWindow must carry a window title for Alt+Tab and taskbars");
        assert(/visible:\s*Config\.settingsVisible/.test(src),
            "SettingsWindow must map exactly while settings are open");
        assert(/screen:\s*targetScreen/.test(src),
            "SettingsWindow must place the toplevel on the target screen");

        // ------------------------------------------------------------------
        // 2. Geometry: size published before mapping, compositor owns the rest
        // ------------------------------------------------------------------
        assert(/implicitWidth:/.test(src) && /implicitHeight:/.test(src),
            "SettingsWindow must publish its opening size through implicitWidth/implicitHeight");
        assert(/minimumSize:/.test(src) && /maximumSize:/.test(src),
            "SettingsWindow must travel its size limits as the window's size hints");
        const minMatch = /readonly property int minCardWidth:\s*([^\n]+)/.exec(src);
        const minHMatch = /readonly property int minCardHeight:\s*([^\n]+)/.exec(src);
        const maxMatch = /readonly property int maxCardWidth:\s*([^\n]+)/.exec(src);
        const maxHMatch = /readonly property int maxCardHeight:\s*([^\n]+)/.exec(src);
        assert(minMatch !== null && minHMatch !== null && maxMatch !== null && maxHMatch !== null,
            "SettingsWindow must declare explicit min/max card bounds");
        assert(/940/.test(minMatch[1]) && /640/.test(minHMatch[1]),
            "SettingsWindow must keep the 940x640 lower bound the hub's layout needs");
        assert(/1240/.test(maxMatch[1]) && /860/.test(maxHMatch[1]),
            "SettingsWindow must keep the 1240x860 upper bound the hub's layout needs");
        assert(/minimumSize:\s*Qt\.size\(\s*root\.minCardWidth\s*,\s*root\.minCardHeight\s*\)/.test(src),
            "the minimum size hint must come from the card bounds, not a literal");
        assert(/maximumSize:\s*Qt\.size\(\s*root\.maxCardWidth\s*,\s*root\.maxCardHeight\s*\)/.test(src),
            "the maximum size hint must come from the card bounds, not a literal");

        // ------------------------------------------------------------------
        // 3. Drag belongs to the compositor now
        // ------------------------------------------------------------------
        assert(/startSystemMove/.test(src),
            "SettingsWindow drag zones must start a compositor-native window move");
        assert(!/drag\.target/.test(src),
            "item-coordinate dragging no longer moves a toplevel window");
        assert(!/userMoved|clampPosition|resetPosition/.test(src),
            "the overlay-era position bookkeeping (userMoved/clamping/recentering) must be retired");

        // ------------------------------------------------------------------
        // 4. Blur follows the card, and the plate stays the shared substrate
        // ------------------------------------------------------------------
        assert(/BackgroundEffect\.blurRegion:\s*Region\s*\{[\s\S]{0,160}?item:\s*dialogBox/.test(src),
            "the blur region must track the card item: the window surface is exactly the card");
        assert(/id:\s*dialogBox[\s\S]{0,900}?Colors\.glassPanelSubstrate/.test(src),
            "the settings card must keep carrying the shared readable glass substrate");
        assert(/NexusHub\s*\{/.test(src), "the Nexus hub must stay hosted inside the toplevel");

        console.log("PASS: Settings Window Toplevel Contract");
        Qt.exit(0);
    }
}
