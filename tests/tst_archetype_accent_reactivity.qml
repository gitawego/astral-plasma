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
    }

    function runTests() {
        console.log("RUNNING: Archetype Accent Reactivity & Geometry Scaling Tests");

        // 1. Verify ThemePage controls update reactively under any archetype
        console.log("Test 1: Setting Archetype to cyberpunk_neon");
        themePage.setThemeArchetype("cyberpunk_neon");
        assert(themePage.currentArchetype === "cyberpunk_neon", "Current archetype must be cyberpunk_neon");

        console.log("Test 2: Setting Preset to Coral under Cyberpunk Neon");
        themePage.setThemePreset("coral");
        assert(themePage.presetName === "coral", "Preset must be coral under Cyberpunk Neon");
        assert(!themePage.isDynamic, "Dynamic colors must be false when preset is set");

        console.log("Test 3: Enabling Dynamic Colors under Cyberpunk Neon");
        themePage.setDynamicColors(true);
        assert(themePage.isDynamic === true, "Dynamic colors must be true under Cyberpunk Neon");

        console.log("Test 4: Setting Corner Radius under Cyberpunk Neon");
        themePage.setThemeCornerRadius(28);
        assert(themePage.cornerRad === 28, "Corner radius must update to 28");

        console.log("Test 5: Setting Blur Strength under Cyberpunk Neon");
        themePage.setBlurStrength(0.45);
        assert(Math.abs(themePage.blurStrengthVal - 0.45) < 0.01, "Blur strength must update to 0.45");

        // 2. Architectural Contract Checks on Colors.qml
        console.log("Test 6: Architectural Contract Check on Colors.qml");
        const colorsSrc = readLocalFile("../theme/Colors.qml");
        assert(colorsSrc.length > 500, "Colors.qml must be readable");

        // Assert Colors.qml does NOT block accent colors when activeArchetype is present
        assert(!/archPalette\[key\]\s*!==\s*undefined[\s\S]*?\/\/\s*1\.\s*If dynamic/.test(colorsSrc),
               "Colors.qml must not prioritize archPalette over dynamic colors and user presets for accent roles");

        // Assert Colors.qml allows dynamicColors to drive accents
        assert(/root\.dynamicColorsEnabled\s*&&\s*root\.dynamicPalette/.test(colorsSrc),
               "Colors.qml must evaluate dynamicPalette for accent colors");

        // 3. Architectural Contract Checks on Theme.qml
        console.log("Test 7: Architectural Contract Check on Theme.qml");
        const themeSrc = readLocalFile("../theme/Theme.qml");
        assert(themeSrc.length > 500, "Theme.qml must be readable");

        // Assert Theme.qml incorporates themeCornerRadius
        assert(/themeCornerRadius/.test(themeSrc),
               "Theme.qml must incorporate Config.themeCornerRadius into corner radius scaling");

        // Assert Theme.qml incorporates themeBlurStrength
        assert(/themeBlurStrength/.test(themeSrc),
               "Theme.qml must incorporate Config.themeBlurStrength into blur/specular intensity");

        console.log("PASS: Archetype Accent Reactivity & Geometry Scaling Tests Passed!");
        Qt.exit(0);
    }
}
