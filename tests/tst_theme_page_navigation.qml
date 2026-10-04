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

        // 1. Zone Declaration Conformance
        assert(themePage.zones.length === 4, "ThemePage must declare 4 zones");
        assert(themePage.zones[0].id === "style", "Zone 0 must be 'style'");
        assert(themePage.zones[1].id === "colors", "Zone 1 must be 'colors'");
        assert(themePage.zones[2].id === "shape", "Zone 2 must be 'shape'");
        assert(themePage.zones[3].id === "preview", "Zone 3 must be 'preview'");

        // 2. Zone Anchors Monotonically Ascending & Offset Verification
        let yStyle = themePage.sectionY("style");
        let yColors = themePage.sectionY("colors");
        let yShape = themePage.sectionY("shape");
        let yPreview = themePage.sectionY("preview");

        assert(yStyle !== undefined && yStyle >= 0, "style anchor must resolve");
        assert(yColors !== undefined && yColors > yStyle, "colors anchor must be below style");
        assert(yShape !== undefined && yShape > yColors, "shape anchor must be below colors");
        assert(yPreview !== undefined && yPreview > yShape, "preview anchor must be below shape");

        // 3. Navigation Signal Contract
        themePage.zoneRequested.connect(zone => {
            testRoot.lastRequestedZone = zone;
        });

        themePage.jumpToZone("shape");
        assert(testRoot.lastRequestedZone === "shape", "jumpToZone('shape') must emit zoneRequested('shape')");

        themePage.jumpToZone("preview");
        assert(testRoot.lastRequestedZone === "preview", "jumpToZone('preview') must emit zoneRequested('preview')");

        // 4. Section Focus / Active State Reactivity
        themePage.currentSection = "shape";
        assert(themePage.isZoneCurrent("shape") === true, "isZoneCurrent('shape') must be true when currentSection is shape");
        assert(themePage.isZoneCurrent("style") === false, "isZoneCurrent('style') must be false when currentSection is shape");

        // 5. Scroll Runway Height Check
        // Page must have sufficient height so that scrolling to sections is possible on desktop viewports
        assert(themePage.implicitHeight >= 600, "ThemePage implicitHeight must be at least 600px for scrollability, got " + themePage.implicitHeight);

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
