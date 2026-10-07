import QtQuick

// ============================================================================
// Time Drawer & Popout Transparent Backdrop Fidelity Contract
// ============================================================================
// Verifies that:
// 1. UnifiedShell declares a transparent backdrop scrim (`popoutScrim`) for all
//    dock popout drawers, providing soft contrast against bright backdrops and
//    click-to-dismiss behavior.
// 2. UnifiedShell's mask includes the envelope region when bottom popout is
//    visible, so the transparent background is interactive.
// 3. UnifiedShell uses `root.glassFill` for `popoutSurface` to preserve authentic
//    liquid glass translucency and seamless zero-overlap fusion with the dock.
// 4. FusedBottomPopout embeds `ghosttySurface`: a Ghostty-style translucent dark
//    substrate that is inset with margins (does not fill the full drawer space)
//    so drawer content is readable over light backgrounds while preserving the
//    liquid glass effect, outer perimeter, and concave shoulder fillets.
// 5. The Time Drawer in FusedBottomPopout renders a clean, airy liquid glass layout:
//    digital time with live seconds, timezone pill, date with icon, World Clock
//    rows, and clean Quick Actions without heavy boxy cards or bloated calendar grid.
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

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Time Drawer & Popout Backdrop Fidelity Tests");

        const shellSrc = readLocalFile("../shell/UnifiedShell.qml");
        assert(shellSrc.length > 1000, "shell/UnifiedShell.qml must be readable");

        // ---- 1. Transparent Backdrop Scrim for Popouts --------------------
        assert(/popoutScrim/.test(shellSrc),
            "UnifiedShell must declare `popoutScrim` to provide transparent contrast shield for all drawers");
        assert(/fusedBottomPopoutWrapper\.offsetProgress\s*>\s*0\.001/.test(shellSrc),
            "popoutScrim visibility must be tied to fusedBottomPopoutWrapper.offsetProgress");
        assert(/Config\.closeBottomPopout\(\)/.test(shellSrc),
            "popoutScrim must click-to-dismiss via Config.closeBottomPopout()");

        // ---- 2. Mask Region Envelope for Popout Scrim ---------------------
        assert(/fusedBottomPopoutWrapper\.offsetProgress\s*>\s*0\.001\)\s*\?\s*root\.width\s*:\s*0/.test(shellSrc),
            "UnifiedShell mask must span root.width when bottom popout is open so scrim is active");

        // ---- 3. Liquid Glass Surface for Popout Shell ---------------------
        assert(/fillColor:\s*root\.glassFill/.test(shellSrc),
            "popoutSurface ShapePaths must use root.glassFill to preserve liquid glass and seamless fusion with the dock");

        // ---- 4. Ghostty-Style Inset Substrate in FusedBottomPopout ---------
        const popoutSrc = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        assert(popoutSrc.length > 1000, "dock/popouts/FusedBottomPopout.qml must be readable");

        assert(/ghosttySurface/.test(popoutSrc),
            "FusedBottomPopout must define `ghosttySurface` for readable drawer content");
        assert(/anchors\.fill:\s*contentLoader/.test(popoutSrc),
            "ghosttySurface must wrap contentLoader so it does not fill the whole drawer space");
        assert(/Theme\.radiusLarge/.test(popoutSrc),
            "ghosttySurface must use Theme.radiusLarge for sleek rounded corners");

        // ---- 5. Time Drawer Clean & Airy Liquid Glass Layout --------------
        assert(/tzBadge/.test(popoutSrc) && /referenceAbbr/.test(popoutSrc),
            "Time drawer must present timezone reference abbreviation pill");
        assert(/calendar_today/.test(popoutSrc),
            "Time drawer must display date row with calendar icon");
        assert(/ClockZoneRow/.test(popoutSrc),
            "Time drawer must support World Clock zones via ClockZoneRow");
        assert(!/heroClockCard/.test(popoutSrc),
            "Time drawer must NOT use a heavy boxy heroClockCard wrapper");
        assert(!/MiniCalendar\s*\{/.test(popoutSrc),
            "Time drawer must NOT embed bloated MiniCalendar grid");

        // ---- 6. ClockZoneRow & Quick Actions Styling ----------------------
        assert(/zoneHover\.hovered\s*\?\s*Colors\.surfaceContainerHigh\s*:\s*"transparent"/.test(popoutSrc),
            "ClockZoneRow must be transparent at rest and highlight on hover");

        console.log("PASS: Time Drawer & Popout Backdrop Fidelity Tests passed!");
        Qt.exit(0);
    }
}
