import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 400
    height: 400

    MaterialIcon {
        id: iconByName
        iconName: "auto_awesome"
        size: 20
    }

    MaterialIcon {
        id: iconByText
        text: "psychology"
        size: 18
    }

    MaterialIcon {
        id: iconChevron
        iconName: "expand_more"
        size: 16
    }

    MaterialIcon {
        id: iconRefresh
        iconName: "refresh"
        size: 16
    }

    MaterialIcon {
        id: iconArrowUpward
        iconName: "arrow_upward"
        size: 16
    }

    MaterialIcon {
        id: iconStop
        iconName: "stop"
        size: 16
    }

    MaterialIcon {
        id: iconSend
        iconName: "send"
        size: 16
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
        console.log("RUNNING: MaterialIcon Resolution Tests");

        // 1. iconName resolution
        assert(iconByName.hasIcon === true, "iconByName must have hasIcon === true");
        assert(iconByName.displaySymbol === "󰄧", "auto_awesome iconName must resolve to sparkle symbol");

        // 2. text resolution
        assert(iconByText.hasIcon === true, "iconByText must have hasIcon === true");
        assert(iconByText.displaySymbol === "󰧑", "psychology text must resolve to brain symbol");

        // 3. chevron resolution
        assert(iconChevron.hasIcon === true, "iconChevron must have hasIcon === true");
        assert(iconChevron.displaySymbol === "󰅀", "expand_more iconName must resolve to chevron");

        // 4. refresh resolution
        assert(iconRefresh.hasIcon === true, "iconRefresh must have hasIcon === true");
        assert(iconRefresh.displaySymbol === "󰑓" || iconRefresh.displaySymbol === "󰑐", "refresh iconName must resolve to refresh glyph");

        // 5. arrow_upward resolution
        assert(iconArrowUpward.hasIcon === true, "iconArrowUpward must have hasIcon === true");
        assert(iconArrowUpward.displaySymbol === "󰁝", "arrow_upward iconName must resolve to arrow upward glyph");

        // 6. stop resolution
        assert(iconStop.hasIcon === true, "iconStop must have hasIcon === true");
        assert(iconStop.displaySymbol === "󰓛", "stop iconName must resolve to stop square glyph");

        // 7. send resolution
        assert(iconSend.hasIcon === true, "iconSend must have hasIcon === true");
        assert(iconSend.displaySymbol === "󰒭", "send iconName must resolve to send paper plane glyph");

        console.log("PASS: MaterialIcon Resolution Tests");
        Qt.exit(0);
    }
}
