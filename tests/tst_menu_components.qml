import QtQuick
import "../menus"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    MenuCard {
        id: menuCard
        width: 220

        MenuHeader {
            id: menuHeader
            title: "Firefox"
            subtitle: "Running • Pinned"
            materialIcon: "web"
        }

        MenuDivider {
            id: menuDivider
        }

        MenuItem {
            id: menuItemPin
            text: "Unpin from dock"
            materialIcon: "keep_off"
            checked: true
        }

        MenuItem {
            id: menuItemClose
            text: "Close Window"
            materialIcon: "close"
            isDangerous: true
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            // Qt.exit only schedules the exit: a suite that keeps running would
            // print its PASS line and override the code (docs/LESSONS.md 37).
            throw new Error(message);
        }
    }

    function runTests() {
        console.log("RUNNING: Menu Components Tests");

        // Test 1: MenuCard geometry and tokens
        // The fused card takes its radius from the shell's glass-card token (with
        // the component's documented fallback) and draws its perimeter with a
        // Shape, so the dock-fused left edge stays seamless - a rectangle border
        // there would draw a second, straight edge over it.
        const expectedRadius = (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined)
            ? Theme.radiusGlassCard : 20;
        assert(menuCard.radius === expectedRadius, "MenuCard radius must follow Theme.radiusGlassCard");
        assert(menuCard.border.width === 0, "MenuCard draws a Shape perimeter, not a rectangle border");
        assert(menuCard.width === 220, "MenuCard width should be 220");
        assert(menuCard.implicitHeight > 100, "MenuCard should calculate implicit height from contents");

        // Test 2: MenuItem geometry and tokens
        assert(menuItemPin.height === 38, "MenuItem height must be 38px for consistent ergonomic target");
        assert(menuItemPin.radius === 8, "MenuItem radius must be 8px");
        assert(menuItemPin.text === "Unpin from dock", "MenuItem text preserved");
        assert(menuItemPin.materialIcon === "keep_off", "MenuItem materialIcon preserved");

        // Test 3: Dangerous item styling
        assert(menuItemClose.isDangerous === true, "MenuItem close isDangerous must be true");

        // Test 4: MenuDivider
        assert(menuDivider.height === 1, "MenuDivider height must be 1");

        // Test 5: MenuHeader
        assert(menuHeader.title === "Firefox", "MenuHeader title preserved");
        assert(menuHeader.subtitle === "Running • Pinned", "MenuHeader subtitle preserved");

        console.log("PASS: Menu Components Tests");
        Qt.exit(0);
    }
}
