import QtQuick
import "../theme"
import "../components"

Item {
    id: testRoot
    width: 800
    height: 600

    property int clickCount: 0

    // 1. Standard PillButton
    PillButton {
        id: pillBtn
        x: 50
        y: 50
        label: "Settings"
        iconText: "settings"
        onClicked: testRoot.clickCount++
    }

    // 2. Active PillButton
    PillButton {
        id: activePillBtn
        x: 200
        y: 50
        label: "Active"
        active: true
    }

    // 3. Icon-only PillButton (e.g. Media Controls)
    PillButton {
        id: iconOnlyBtn
        x: 350
        y: 50
        iconText: "play_arrow"
        implicitWidth: 40
        implicitHeight: 40
    }

    // 4. GlassPill
    GlassPill {
        id: glassPillItem
        x: 450
        y: 50
        implicitWidth: 120
        implicitHeight: 36
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
            throw new Error(message);
        }
    }

    function runTests() {
        console.log("RUNNING: PillButton & GlassPill Liquid Glass Tests");

        // ========================================================
        // 1. Backward Compatibility & Basic Properties
        // ========================================================
        assert(pillBtn.label === "Settings", "label matches");
        assert(pillBtn.iconText === "settings", "iconText matches");
        assert(pillBtn.active === false, "default active is false");
        assert(activePillBtn.active === true, "active is true");

        // Click signal
        assert(testRoot.clickCount === 0, "clickCount starts at 0");
        pillBtn.clicked();
        assert(testRoot.clickCount === 1, "pillBtn.clicked() fires");

        // ========================================================
        // 2. Liquid Glass Optical Stack in PillButton
        // ========================================================
        assert(pillBtn.contactShadowItem !== undefined && pillBtn.contactShadowItem !== null, 
            "PillButton must have a contactShadowItem for physical elevation");
        assert(pillBtn.contactShadowItem.visible === true, "PillButton contactShadowItem must be visible");

        assert(pillBtn.textShadowItem !== undefined && pillBtn.textShadowItem !== null, 
            "PillButton must have textShadowItem for floating 3D depth");

        // Top specular glare anti-overhang
        let glare = pillBtn.topGlareItem;
        assert(glare !== undefined && glare !== null, "PillButton must expose topGlareItem");
        if (glare.visible) {
            assert(glare.x >= (pillBtn.height / 2), "Anti-Overhang: topGlare.x must be >= radius");
            assert((glare.x + glare.width) <= (pillBtn.width - pillBtn.height / 2), "Anti-Overhang: topGlare right edge must be <= width - radius");
        }

        // ========================================================
        // 3. Compact / Circular Icon-Only Button Anti-Overhang
        // ========================================================
        // When width == height (circular/pill 40x40), width <= radius * 2. No flat edge exists!
        let circleGlare = iconOnlyBtn.topGlareItem;
        assert(circleGlare !== undefined && circleGlare !== null, "iconOnlyBtn must expose topGlareItem");
        assert(circleGlare.visible === false || circleGlare.width <= 0, 
            "CRITICAL: On square/circular pill button, topGlare must not draw an overhanging flat line! Got visible=" + circleGlare.visible + " width=" + circleGlare.width);

        // ========================================================
        // 4. GlassPill Liquid Glass Optics
        // ========================================================
        assert(glassPillItem.contactShadowItem !== undefined && glassPillItem.contactShadowItem !== null, 
            "GlassPill must expose contactShadowItem");

        console.log("PASS: PillButton & GlassPill Liquid Glass Tests");
        Qt.exit(0);
    }
}
