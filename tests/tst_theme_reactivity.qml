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
        assert(themePage.surfaceColor.toString() === "#121318", "Dark surface must be #121318");

        // 2. Switch to Light Mode
        console.log("Test 2: Switch to Light Mode");
        themePage.testDarkMode = false;
        assert(!themePage.isDark, "Theme mode must reflect Light Mode");
        console.log("Light surface color:", themePage.surfaceColor.toString());
        assert(themePage.surfaceColor.toString() === "#faf8f5", "Light surface must be #faf8f5");
        assert(themePage.surfaceContainerColor.toString() === "#f2ede7", "Light surface container must be #f2ede7");
        assert(themePage.onSurfaceColor.toString() === "#1d1b20", "Light text must be #1d1b20");

        // 3. Switch back to Dark Mode
        console.log("Test 3: Switch back to Dark Mode");
        themePage.testDarkMode = true;
        assert(themePage.isDark, "Theme mode must reflect Dark Mode");
        assert(themePage.surfaceColor.toString() === "#121318", "Dark surface must be #121318");
        assert(themePage.onSurfaceColor.toString() === "#e4e2e6", "Dark text must be #e4e2e6");

        // 4. Preset Palettes Switching
        console.log("Test 4: Switch Preset to Coral");
        themePage.testPreset = "coral";
        assert(themePage.presetName === "coral", "Preset must be coral");

        console.log("Test 5: Switch Preset to Ocean");
        themePage.testPreset = "ocean";
        assert(themePage.presetName === "ocean", "Preset must be ocean");

        // 5. Corner Radius Reactivity
        console.log("Test 6: Corner Radius Reactivity");
        themePage.testCornerRadius = 28;
        assert(themePage.cornerRad === 28, "Corner radius must update to 28");
        themePage.testCornerRadius = 16;
        assert(themePage.cornerRad === 16, "Corner radius must update to 16");

        console.log("PASS: Theme & Immediate Settings Reactivity Unit Tests");
        Qt.exit(0);
    }
}
