import QtQuick
import "../settings_gui/pages"

// The Preview section is a read-only gallery, not a settings surface. The
// theme pickers live in Colors (preset swatches) and Style (archetype cards);
// the preview's pills/chip must not pretend to be clickable controls.
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

    function runTests() {
        console.log("RUNNING: Theme Preview Read-Only Tests");

        assert(themePage.previewFilledSample.interactive === false,
            "preview filled sample must not be interactive");
        assert(themePage.previewTonalSample.interactive === false,
            "preview tonal sample must not be interactive");
        assert(themePage.previewFilledSample.variant === "filled",
            "preview still renders the filled variant");
        assert(themePage.previewTonalSample.variant === "tonal",
            "preview still renders the tonal variant");
        assert(themePage.previewChipLabel.text === "Sample Chip",
            "the chip must read as a sample, not a shell/theme option");
        assert(themePage.previewHeaderItem.eyebrow.toLowerCase().indexOf("read-only") !== -1,
            "the section eyebrow must say the preview is read-only");

        // The real theme controls remain functional and update the page state.
        themePage.setThemePreset("nord");
        assert(themePage.testPreset === "nord", "preset control can still change the theme");
        themePage.setThemePreset("iris");
        themePage.setThemeArchetype("nordic_minimal");
        assert(themePage.testArchetype === "nordic_minimal", "archetype control can still change the style");

        console.log("PASS: Theme Preview Read-Only Tests");
        Qt.exit(0);
    }
}
