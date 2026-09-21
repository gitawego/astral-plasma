import QtQuick

// ============================================================================
// Active Window Spacing Contract
// ============================================================================
// The active app icon + vertical title sits directly below the desktops
// (workspaces) switcher pill. Two defects were reported:
//
//   1. The active app block is too close to the switcher (cramped 8px gap).
//   2. The vertical app name is too small (hardcoded 11px).
//
// Contract:
//   - activeWindowPill topMargin >= 16 (clear module separation)
//   - activeTitleRotated topMargin >= 10 (icon/title breathing room)
//   - title font must be a Theme body token >= 13px, never hardcoded 11px.
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
            console.log("FAIL: " + message);
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
        console.log("RUNNING: Active Window Spacing Contract");

        const dock = readLocalFile("../shell/UnifiedDock.qml");
        assert(dock.length > 1000, "UnifiedDock.qml source must be readable");

        // 1. Outer gap: active block must stand clear of the workspace pill.
        const pill = dock.match(/id:\s*activeWindowPill[\s\S]{0,400}/);
        assert(pill !== null, "UnifiedDock must declare activeWindowPill");
        const pillMargin = pill[0].match(/anchors\.topMargin:\s*(\d+)/);
        assert(pillMargin !== null, "activeWindowPill must set anchors.topMargin");
        assert(parseInt(pillMargin[1], 10) >= 16,
            "activeWindowPill topMargin must be >= 16px so the active app clears the "
            + "desktops switcher, got " + pillMargin[1] + "px");

        // 2. Inner gap: icon and vertical title need breathing room.
        const titleBox = dock.match(/id:\s*activeTitleRotated[\s\S]{0,400}/);
        assert(titleBox !== null, "UnifiedDock must declare activeTitleRotated");
        const titleMargin = titleBox[0].match(/anchors\.topMargin:\s*(\d+)/);
        assert(titleMargin !== null, "activeTitleRotated must set anchors.topMargin");
        assert(parseInt(titleMargin[1], 10) >= 10,
            "activeTitleRotated topMargin must be >= 10px, got " + titleMargin[1] + "px");

        // 3. Title size: must be a Theme body token (>= 13px), never 11px.
        const metrics = dock.match(/id:\s*titleMetrics[\s\S]{0,400}/);
        assert(metrics !== null, "UnifiedDock must declare titleMetrics");
        assert(!/font\.pixelSize:\s*11\b/.test(metrics[0]),
            "active app title must not use hardcoded 11px (too small)");
        const usesBodySmall = /font\.pixelSize:\s*Theme\.fontBodySmall\b/.test(metrics[0]);
        const usesBodyMedium = /font\.pixelSize:\s*Theme\.fontBodyMedium\b/.test(metrics[0]);
        const usesTitleToken = /font\.pixelSize:\s*Theme\.fontTitle\w+\b/.test(metrics[0]);
        const hardSize = metrics[0].match(/font\.pixelSize:\s*(\d+)/);
        const hardOk = hardSize !== null && parseInt(hardSize[1], 10) >= 13;
        assert(usesBodySmall || usesBodyMedium || usesTitleToken || hardOk,
            "active app title font must be a Theme body token >= 13px (e.g. "
            + "Theme.fontBodySmall/Theme.fontBodyMedium)");

        console.log("PASS: Active Window Spacing Contract (gap >= 16px, title gap >= 10px, title >= 13px)");
        Qt.exit(0);
    }
}
