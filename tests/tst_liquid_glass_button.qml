import QtQuick
import "../theme"
import "../components"

Item {
    id: testRoot
    width: 800
    height: 600

    property int clickCount: 0

    // 1. Standard button (matching "Get Now" reference)
    LiquidGlassButton {
        id: testButton
        x: 50
        y: 50
        text: "Get Now"
        onClicked: testRoot.clickCount++
    }

    // 2. Icon + Text button
    LiquidGlassButton {
        id: iconButton
        x: 250
        y: 50
        text: "Download"
        iconText: "download"
    }

    // 3. Primary variant button
    LiquidGlassButton {
        id: primaryButton
        x: 450
        y: 50
        text: "Primary Action"
        isPrimary: true
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
        console.log("RUNNING: LiquidGlassButton Optical & Behavioral Tests");

        // ========================================================
        // 1. Stadium Pill Geometry
        // ========================================================
        assert(testButton.text === "Get Now", "testButton text matches");
        assert(testButton.height > 0, "testButton height must be positive");
        assert(testButton.radius === Math.round(testButton.height / 2), 
            "LiquidGlassButton must have stadium pill geometry (radius == height / 2). Got radius=" + testButton.radius + " height=" + testButton.height);

        // ========================================================
        // 2. Anti-Overhang Specular Glare Invariants
        // ========================================================
        let glare = testButton.topGlareItem;
        assert(glare !== undefined && glare !== null, "testButton must expose topGlareItem");
        if (glare.visible) {
            assert(glare.x >= testButton.radius, 
                "Anti-Overhang Invariant: topGlare.x (" + glare.x + ") must be >= radius (" + testButton.radius + ")");
            assert((glare.x + glare.width) <= (testButton.width - testButton.radius), 
                "Anti-Overhang Invariant: topGlare right edge must be <= width - radius");
        }

        // ========================================================
        // 3. Floating 3D Text & Depth Shadow
        // ========================================================
        let labelItem = testButton.labelItem;
        assert(labelItem !== undefined && labelItem !== null, "testButton must expose labelItem");
        assert(labelItem.text === "Get Now", "labelItem text must be 'Get Now'");

        let shadowItem = testButton.textShadowItem;
        assert(shadowItem !== undefined && shadowItem !== null, "testButton must expose textShadowItem");
        assert(shadowItem.text === "Get Now", "textShadowItem text must match label");

        let shadowRow = testButton.shadowRowItem;
        let contentRow = testButton.contentRowItem;
        assert(shadowRow !== undefined && contentRow !== undefined, "Rows must be exposed");
        assert(shadowRow.y > contentRow.y, 
            "shadowRow must be vertically offset downwards to simulate 3D depth. contentRow.y=" + contentRow.y + " shadowRow.y=" + shadowRow.y);

        // ========================================================
        // 4. Contact Elevation Shadow
        // ========================================================
        let contactShadow = testButton.contactShadowItem;
        assert(contactShadow !== undefined && contactShadow !== null, "testButton must expose contactShadowItem");
        assert(contactShadow.visible === true, "contactShadowItem must be visible");

        // ========================================================
        // 5. Click Signal Propagation
        // ========================================================
        assert(testRoot.clickCount === 0, "clickCount starts at 0");
        testButton.clicked();
        assert(testRoot.clickCount === 1, "testButton.clicked() increments clickCount");

        // ========================================================
        // 6. Micro-Physics: Pressed Scale & Hover Glare
        // ========================================================
        assert(testButton.targetScale === 1.0, "default targetScale is 1.0");
        testButton.pressed = true;
        assert(testButton.targetScale === 0.96, "pressed targetScale must be 0.96 (spring bounce). Got " + testButton.targetScale);
        testButton.pressed = false;

        // ========================================================
        // 7. Icon Integration
        // ========================================================
        assert(iconButton.iconText === "download", "iconButton iconText matches");
        let iconItem = iconButton.iconItem;
        assert(iconItem !== undefined && iconItem !== null, "iconButton must expose iconItem");
        assert(iconItem.visible === true, "iconItem must be visible when iconText is provided");

        console.log("PASS: LiquidGlassButton Optical & Behavioral Tests");
        Qt.exit(0);
    }
}
