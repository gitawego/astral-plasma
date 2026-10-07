import QtQuick
import "../components"

// The dock's leading indicator bar must not touch the app icon. The item has to
// reserve the indicator's gutter on both sides so the centred icon clears it.
Item {
    id: testRoot
    width: 400
    height: 400

    DockItemMetrics {
        id: metrics
        iconSize: 40
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        try {
            xhr.send();
            return xhr.responseText || "";
        } catch (e) {
            return "";
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

    function runTests() {
        console.log("RUNNING: Dock Item Indicator Gap");
        assert(metrics.gap > 0,
            "the indicator bar must leave a gap against the icon");
        assert(metrics.gap === metrics.indicatorGap,
            "the gap must equal the declared indicator gap");
        assert(metrics.itemSize === metrics.iconSize + 2 * metrics.indicatorReserve,
            "the item must reserve the indicator gutter on both sides");
        assert(metrics.iconLeft === Math.round((metrics.itemSize - metrics.iconSize) / 2),
            "the icon must stay centred in the item");
        assert(metrics.iconLeft >= metrics.indicatorRight + metrics.indicatorGap,
            "the icon must clear the indicator by at least the gap");
        // A tiny icon must keep the same relationship (no negative/dense gap).
        metrics.iconSize = 18;
        assert(metrics.gap > 0 && metrics.iconLeft > metrics.indicatorRight,
            "small icons keep the gap too");
        // The selected app fill must use the dock's liquid-glass pill archetype,
        // not an opaque M3 container (which reads as a solid slab on the glass dock).
        const dockSource = readLocalFile("../shell/UnifiedDock.qml");
        assert(dockSource.indexOf("modelData.isActive ? Colors.glassPillActive") !== -1,
            "the selected dock item must use the liquid-glass active pill fill");
        assert(dockSource.indexOf("modelData.isActive ? Colors.primaryContainer") === -1,
            "the selected dock item must not paint an opaque primaryContainer slab");

        console.log("PASS: Dock Item Indicator Gap");
        Qt.exit(0);
    }
}
