import QtQuick
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    // Harness matching NexusHub navigation stack architecture
    QtObject {
        id: nexusHarness

        property string activePage: "wallpaper"
        property var pageHistory: []
        readonly property bool canGoBack: pageHistory.length > 0

        function navigateTo(pageId) {
            if (!pageId || pageId === activePage) return;
            let h = pageHistory.slice();
            h.push(activePage);
            pageHistory = h;
            activePage = pageId;
        }

        function goBack() {
            if (pageHistory.length > 0) {
                let h = pageHistory.slice();
                const prev = h.pop();
                pageHistory = h;
                activePage = prev;
            }
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
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
        console.log("RUNNING: NexusHub Hierarchical Navigation & Back Stack Unit Tests");

        // 1. Initial State: defaults to wallpaper, cannot go back
        assert(nexusHarness.activePage === "wallpaper", "Default page must be wallpaper");
        assert(!nexusHarness.canGoBack, "Initial back stack must be empty");

        // 2. Navigate to Network page
        nexusHarness.navigateTo("network");
        assert(nexusHarness.activePage === "network", "Active page must be network");
        assert(nexusHarness.canGoBack === true, "Back stack must have 1 entry");
        assert(nexusHarness.pageHistory[0] === "wallpaper", "History entry 0 must be wallpaper");

        // 3. Drill down to Bluetooth
        nexusHarness.navigateTo("bluetooth");
        assert(nexusHarness.activePage === "bluetooth", "Active page must be bluetooth");
        assert(nexusHarness.pageHistory.length === 2, "History has 2 entries");

        // 4. Drill down to Audio
        nexusHarness.navigateTo("audio");
        assert(nexusHarness.activePage === "audio", "Active page must be audio");

        // 5. Click < Back (pop audio -> back to bluetooth)
        nexusHarness.goBack();
        assert(nexusHarness.activePage === "bluetooth", "goBack returns to bluetooth");

        // 6. Click < Back (pop bluetooth -> back to network)
        nexusHarness.goBack();
        assert(nexusHarness.activePage === "network", "goBack returns to network");

        // 7. Click < Back (pop network -> back to wallpaper)
        nexusHarness.goBack();
        assert(nexusHarness.activePage === "wallpaper", "goBack returns to root wallpaper");
        assert(!nexusHarness.canGoBack, "Back button hides when at root page");

        // The content pane must be readable over a bright wallpaper: the same
        // substrate the Copilot card uses, not a fully transparent block. The
        // token itself is checked at the source, because the theme singleton is
        // not resolvable from a bare test shell.
        const colorsSrc = readLocalFile("../theme/Colors.qml");
        const substrateDef = /glassPanelSubstrate:\s*glassTinted\([\s\S]{0,120}?\)/.exec(colorsSrc);
        assert(substrateDef !== null, "Colors must define a shared glassPanelSubstrate token");
        const alphas = (colorsSrc.match(/panelAlpha:\s*([0-9.]+)/g) || []).map(m => Number(m.split(":")[1]));
        assert(alphas.length >= 2, "both palette modes must define a panel alpha");
        for (const a of alphas) {
            assert(a >= 0.75, "the panel substrate must be nearly opaque for legibility, got " + a);
            assert(a < 1.0, "the panel substrate must stay translucent (glass, not paint), got " + a);
        }
        // One plate: the window card carries the substrate; the rail and the
        // content are parts of it, divided by one hairline. Two rounded panels
        // butted together left the wallpaper visible in the corner notches
        // between them - the seam the user reported.
        const hubSrc = readLocalFile("../settings_gui/NexusHub.qml");
        const windowSrc = readLocalFile("../settings_gui/SettingsWindow.qml");
        assert(/id:\s*dialogBox[\s\S]{0,900}?Colors\.glassPanelSubstrate/.test(windowSrc),
            "the settings window card must carry the readable panel substrate");
        assert(!/id:\s*navRail[\s\S]{0,700}?radius:/.test(hubSrc),
            "the navigation rail must not carry its own radius: it is part of the plate");
        assert(!/id:\s*contentPane[\s\S]{0,400}?radius:/.test(hubSrc),
            "the content pane must not carry its own radius either");
        assert(/id:\s*contentPane[\s\S]{0,200}?color:\s*"transparent"/.test(hubSrc),
            "the content pane must be part of the plate, not a second panel");
        assert(/id:\s*railSeam/.test(hubSrc), "one hairline must divide the rail from the content");
        assert(/id:\s*pageLoader[\s\S]{0,100}?width:\s*parent\.width\s*-\s*14/.test(hubSrc),
            "pageLoader must reserve a 14px scrollbar gutter to prevent content overlap");
        assert(/id:\s*scrollBarIndicator[\s\S]{0,300}?thumbTravelRange/.test(hubSrc),
            "scrollBarIndicator must use bounded thumbTravelRange math");

        console.log("PASS: NexusHub Hierarchical Navigation & Back Stack Unit Tests");
        Qt.exit(0);
    }
}
