import QtQuick
import "../settings_gui"

// ============================================================================
// Settings rail alignment
// ============================================================================
// The rail is one vertical grid: every section heading and the icon at the
// start of every pill must share the same left x. Centering each pill's content
// made the icons drift with the label width, which read as a misaligned rail.
Item {
    id: testRoot
    width: 1000
    height: 800

    NexusHub {
        id: hub
        width: parent.width
        height: parent.height
        testMode: true
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function findByText(node, text) {
        if (!node) return null;
        if (node.text === text) return node;
        const kids = node.children || [];
        for (let i = 0; i < kids.length; ++i) {
            const hit = findByText(kids[i], text);
            if (hit) return hit;
        }
        return null;
    }

    function findPill(node, label) {
        if (!node) return null;
        if (node.label === label && node.iconItem !== undefined) return node;
        const kids = node.children || [];
        for (let i = 0; i < kids.length; ++i) {
            const hit = findPill(kids[i], label);
            if (hit) return hit;
        }
        return null;
    }

    function runTests() {
        console.log("RUNNING: Settings Rail Alignment");

        const headings = ["PERSONALIZATION", "CONNECTIVITY", "AI & VOICE",
            "HARDWARE", "DESKTOP SHELL", "SYSTEM"];
        let headingX = null;
        for (let i = 0; i < headings.length; ++i) {
            const heading = findByText(hub, headings[i]);
            assert(heading !== null, "the rail renders heading \"" + headings[i] + "\"");
            const x = heading.mapToItem(hub, 0, 0).x;
            if (headingX === null) headingX = x;
            assert(Math.abs(x - headingX) < 0.5,
                "every heading shares one left x (\"" + headings[i] + "\" at " + x
                    + ", expected " + headingX + ")");
        }

        const pill = findPill(hub, "Wallpaper & Style");
        assert(pill !== null, "the rail renders the Wallpaper & Style pill");
        assert(pill.iconItem !== null && pill.iconItem !== undefined,
            "the pill exposes its leading icon");
        const iconX = pill.iconItem.mapToItem(hub, 0, 0).x;
        assert(Math.abs(headingX - iconX) < 0.5,
            "the heading and the pill icon share the left grid (heading at "
                + headingX + ", icon at " + iconX + ")");

        const apps = findPill(hub, "Apps");
        assert(apps !== null, "the rail renders the short Apps pill");
        const appsIconX = apps.iconItem.mapToItem(hub, 0, 0).x;
        assert(Math.abs(iconX - appsIconX) < 0.5,
            "a short label does not shift its icon off the grid ("
                + appsIconX + " vs " + iconX + ")");

        console.log("PASS: Settings Rail Alignment");
        Qt.exit(0);
    }
}
