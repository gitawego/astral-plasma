import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 400
    height: 400

    ThemedIcon {
        id: symbolicIcon
        source: "/usr/share/icons/breeze-dark/actions/16/view-refresh-symbolic.svg"
        color: "#1c1b1f"
        size: 20
    }

    ThemedIcon {
        id: appIcon
        source: "/usr/share/icons/hicolor/scalable/apps/org.kde.dolphin.svg"
        color: "#1c1b1f"
        size: 24
    }

    ThemedIcon {
        id: fallbackIcon
        source: ""
        materialIcon: "settings"
        color: "#1c1b1f"
        size: 18
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
        }
    }

    function runTests() {
        console.log("RUNNING: ThemedIcon Contrast & Symbolism Tests");

        assert(symbolicIcon.isSymbolic, "Icon ending in -symbolic must be identified as symbolic");
        assert(symbolicIcon.color === "#1c1b1f", "Symbolic icon color must match foreground color for maximum contrast");

        assert(!appIcon.isSymbolic, "App icon must not be marked as symbolic");

        assert(fallbackIcon.materialIcon === "settings", "Fallback material icon preserves name");
        assert(fallbackIcon.color === "#1c1b1f", "Fallback icon inherits foreground color");

        console.log("PASS: ThemedIcon Contrast & Symbolism Tests");
        Qt.exit(0);
    }
}
