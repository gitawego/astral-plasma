import QtQuick
import "../theme"
import "../components"

Item {
    id: testRoot
    width: 600
    height: 600

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
        return true;
    }

    // 1. Text only button
    ActionPill {
        id: textOnlyPill
        text: "Switch"
        paddingHorizontal: 8
    }

    // 2. Icon + Text button
    ActionPill {
        id: iconTextPill
        icon: "add"
        text: "Add"
        paddingHorizontal: 8
        spacing: 4
    }

    // 3. Fixed width pill
    ActionPill {
        id: fixedPill
        text: "Active"
        fixedWidth: 46
        variant: "active"
        interactive: false
    }

    // 4. Danger pill
    ActionPill {
        id: dangerPill
        icon: "delete_outline"
        text: "Remove"
        variant: "danger"
    }

    function runTests() {
        console.log("RUNNING: ActionPill Component Unit Tests");

        // 1. Text only sizing
        assert(textOnlyPill.implicitWidth > 0, "textOnlyPill must have positive implicitWidth");
        assert(textOnlyPill.text === "Switch", "textOnlyPill text must be Switch");

        // 2. Icon + Text sizing must be wider than text alone
        assert(iconTextPill.implicitWidth > textOnlyPill.implicitWidth * 0.7, "iconTextPill must account for icon");
        assert(iconTextPill.icon === "add", "iconTextPill icon must be add");

        // 3. Fixed width enforcement
        assert(fixedPill.implicitWidth === 46, "fixedPill implicitWidth must be exactly 46, got " + fixedPill.implicitWidth);
        assert(fixedPill.variant === "active", "fixedPill variant must be active");
        assert(!fixedPill.interactive, "fixedPill must be non-interactive");

        // 4. Danger variant
        assert(dangerPill.variant === "danger", "dangerPill variant must be danger");
        assert(dangerPill.icon === "delete_outline", "dangerPill icon must be delete_outline");

        console.log("PASS: ActionPill Component Unit Tests");
        Qt.exit(0);
    }
}
