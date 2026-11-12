import QtQuick
import "../settings_gui/pages"

Item {
    id: testRoot
    width: 900
    height: 700

    ThemePage {
        id: themePage
        anchors.fill: parent
        testMode: true
        testDarkMode: true
        testDynamicColors: false
        testPreset: "iris"
        testCornerRadius: 20
        testArchetype: "liquid_glass"
        testBlurStrength: 0.85
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

    property string lastRequestedZone: ""

    function runTests() {
        console.log("RUNNING: Theme Page Navigation & Rich Settings Tests");

        // 1. Atlas tab declaration
        assert(themePage.tabs.length === 4, "ThemePage must declare 4 tabs");
        assert(themePage.tabs[0].id === "style", "Tab 0 must be 'style'");
        assert(themePage.tabs[1].id === "colors", "Tab 1 must be 'colors'");
        assert(themePage.tabs[2].id === "shape", "Tab 2 must be 'shape'");
        assert(themePage.tabs[3].id === "preview", "Tab 3 must be 'preview'");
        for (let i = 0; i < themePage.tabs.length; ++i) {
            const tab = themePage.tabs[i];
            assert(tab.label && tab.label !== "", "tab '" + tab.id + "' must carry a label");
            assert(tab.icon && tab.icon !== "", "tab '" + tab.id + "' must carry an icon");
        }

        // 2. Tabs switch the body; they never scroll to an anchor
        assert(themePage.zones.length === 0, "ThemePage must not declare a scroll rail");
        assert(themePage.hasRail === false, "ThemePage must not render the legacy rail");
        assert(themePage.currentTab === "style", "ThemePage opens on Style");
        themePage.selectTab("shape");
        assert(themePage.currentTab === "shape", "selectTab('shape') must select the Shape tab");
        themePage.selectTab("preview");
        assert(themePage.currentTab === "preview", "selectTab('preview') must select the Preview tab");
        themePage.selectTab("nonsense");
        assert(themePage.currentTab === "preview", "an unknown tab id must be ignored");

        // 6. Archetype Selector Reactivity
        assert(themePage.currentArchetype === "liquid_glass", "Default archetype must be liquid_glass");
        themePage.setThemeArchetype("nordic_minimal");
        assert(themePage.currentArchetype === "nordic_minimal", "Archetype must update to nordic_minimal");
        themePage.setThemeArchetype("cyberpunk_neon");
        assert(themePage.currentArchetype === "cyberpunk_neon", "Archetype must update to cyberpunk_neon");

        // 7. Blur Strength Reactivity
        assert(Math.abs(themePage.blurStrengthVal - 0.85) < 0.01, "Default blur strength must be 0.85");
        themePage.setBlurStrength(0.50);
        assert(Math.abs(themePage.blurStrengthVal - 0.50) < 0.01, "Blur strength must update to 0.50");

        // 9. Archetype Selector Individual Card Self-Styling
        const themeSrc = readLocalFile("../settings_gui/pages/ThemePage.qml");
        assert(/archId\s*===\s*"liquid_glass"\s*\?\s*18\s*:\s*\(\s*archId\s*===\s*"nordic_minimal"\s*\?\s*6\s*:\s*2\s*\)/.test(themeSrc),
            "ThemePage must assign distinct radii to Liquid Glass (18), Nordic Minimal (6), and Cyberpunk Neon (2)");
        assert(/id:\s*liquidSpecularGlint[\s\S]{0,120}?visible:\s*archCard\.archId\s*===\s*"liquid_glass"/.test(themeSrc),
            "ThemePage must render specular glint for Liquid Glass card");
        assert(/id:\s*cyberNeonStrip[\s\S]{0,120}?visible:\s*archCard\.archId\s*===\s*"cyberpunk_neon"/.test(themeSrc),
            "ThemePage must render cyber neon accent strip for Cyberpunk Neon card");
        assert(/archCard\.archId\s*===\s*"cyberpunk_neon"[\s\S]{0,120}?Theme\.fontMonospace/.test(themeSrc),
            "ThemePage must use monospace font for Cyberpunk Neon card");

        console.log("PASS: Theme Page Navigation & Rich Settings Tests");
        Qt.exit(0);
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }
}
