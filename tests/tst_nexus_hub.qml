import QtQuick
import "../modules/Astral/Kernel/theme"

Item {
    id: testRoot
    width: 800
    height: 600

    // Harness matching NexusHub's single-level navigation.
    QtObject {
        id: nexusHarness

        property string activePage: "wallpaper"

        function navigateTo(pageId) {
            if (!pageId || pageId === activePage) return;
            activePage = pageId;
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
            throw new Error(msg);
        }
        return true;
    }

    function runTests() {
        console.log("RUNNING: NexusHub single-level navigation & page chrome Unit Tests");

        // 1. Initial State: defaults to wallpaper.
        assert(nexusHarness.activePage === "wallpaper", "Default page must be wallpaper");

        // 2. Rail navigation is single-level: the destination is the state.
        nexusHarness.navigateTo("network");
        assert(nexusHarness.activePage === "network", "Active page must be network");
        nexusHarness.navigateTo("bluetooth");
        assert(nexusHarness.activePage === "bluetooth", "Active page must be bluetooth");
        nexusHarness.navigateTo("audio");
        assert(nexusHarness.activePage === "audio", "Active page must be audio");

        // 3. The dead drill-down chrome is gone, not merely hidden.
        const hubSource = readLocalFile("../settings_gui/NexusHub.qml");
        assert(hubSource.indexOf("arrow_back") === -1, "the dead Back arrow is removed");
        assert(hubSource.indexOf("goBack") === -1, "the dead goBack handler is removed");
        assert(hubSource.indexOf("canGoBack") === -1, "the unused back-stack state is removed");
        assert(hubSource.indexOf("pageHistory") === -1, "the unused page history is removed");
        assert(hubSource.indexOf('text: "Back"') === -1, "the Back label is removed");

        // 4. Rail navigation still selects the page.
        assert(/active:\s*root\.activePage\s*===\s*modelData\.id/.test(hubSource),
            "the sidebar must use the page-level active state");

        // The content pane must be readable over a bright wallpaper: the same
        // substrate the Copilot card uses, not a fully transparent block. The
        // token itself is checked at the source, because the theme singleton is
        // not resolvable from a bare test shell.
        const colorsSrc = readLocalFile("../modules/Astral/Kernel/theme/Colors.qml");
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
        assert(/title:\s*"AI & Voice"/.test(hubSrc), "NexusHub must feature an AI & Voice category");
        assert(/id:\s*"voice",\s*label:\s*"Voice Dictation"/.test(hubSrc),
            "NexusHub must offer a first-class Voice Dictation navigation entry");
        assert(/case\s*"voice":\s*return\s*voicePageComp;/.test(hubSrc),
            "NexusHub pageLoader must route 'voice' to voicePageComp");
        assert(/Component\s*\{\s*id:\s*voicePageComp;\s*VoicePage/.test(hubSrc),
            "NexusHub must declare voicePageComp component");

        // Verify that sidebar delegate is decoupled from in-page scroll spy
        assert(/active:\s*root\.activePage\s*===\s*modelData\.id/.test(hubSrc),
            "NexusHub sidebar must strictly use page-level active state, decoupled from in-page scroll sections");

        // Test direct navigation to the voice page.
        nexusHarness.navigateTo("voice");
        assert(nexusHarness.activePage === "voice", "Harness can navigate directly to voice page");

        console.log("PASS: NexusHub single-level navigation & page chrome Unit Tests");
        Qt.exit(0);
    }
}
