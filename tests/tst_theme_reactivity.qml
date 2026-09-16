import QtQuick
import "../settings_gui/pages"

Item {
    id: testRoot
    width: 800
    height: 600

    ThemePage {
        id: themePage
        anchors.fill: parent
        testMode: true
        testDarkMode: true
        testDynamicColors: false
        testPreset: "iris"
        testCornerRadius: 20
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
            return false;
        }
        return true;
    }

    function runTests() {
        console.log("RUNNING: Theme & Immediate Settings Reactivity Unit Tests");

        // 1. Initial State
        console.log("Test 1: Initial Theme Mode (Dark)");
        assert(themePage.isDark, "Default theme mode must be Dark");
        assert(themePage.presetName === "iris", "Default preset must be iris");
        assert(themePage.cornerRad === 20, "Default corner radius must be 20");
        assert(!themePage.isDynamic, "Default dynamic colors must be false");

        // 2. Switch to Light Mode via setter
        console.log("Test 2: Switch to Light Mode via setDarkMode(false)");
        themePage.setDarkMode(false);
        assert(!themePage.isDark, "Theme mode must reflect Light Mode");

        // 3. Switch back to Dark Mode via setter
        console.log("Test 3: Switch back to Dark Mode via setDarkMode(true)");
        themePage.setDarkMode(true);
        assert(themePage.isDark, "Theme mode must reflect Dark Mode");

        // 4. Preset Palettes Switching
        console.log("Test 4: Switch Preset to Coral");
        themePage.setThemePreset("coral");
        assert(themePage.presetName === "coral", "Preset must be coral");

        console.log("Test 5: Switch Preset to Ocean");
        themePage.setThemePreset("ocean");
        assert(themePage.presetName === "ocean", "Preset must be ocean");

        // 5. Dynamic Colors Switching
        console.log("Test 6: Switch Dynamic Colors to True");
        themePage.setDynamicColors(true);
        assert(themePage.isDynamic, "Dynamic colors must be true");

        // 6. Corner Radius Reactivity
        console.log("Test 7: Corner Radius Reactivity");
        themePage.setThemeCornerRadius(28);
        assert(themePage.cornerRad === 28, "Corner radius must update to 28");
        themePage.setThemeCornerRadius(16);
        assert(themePage.cornerRad === 16, "Corner radius must update to 16");

        console.log("PASS: Theme & Immediate Settings Reactivity Unit Tests");
        Qt.exit(0);
    }
}
