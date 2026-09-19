import QtQuick
import "../theme"
import "../components"

Item {
    id: testRoot
    width: 800
    height: 600

    // 1. Standard rectangular card
    LiquidGlassCard {
        id: rectCard
        x: 50
        y: 50
        width: 400
        height: 200
        radius: 16
    }

    // 2. Vertical stadium pill (matching UnifiedDock appsContainer: width 48, radius 24)
    LiquidGlassCard {
        id: verticalPill
        x: 500
        y: 50
        width: 48
        height: 200
        radius: 24
    }

    // 3. Compact capsule (matching UnifiedDock wsContainer: width 30, radius 15)
    LiquidGlassCard {
        id: compactPill
        x: 600
        y: 50
        width: 30
        height: 120
        radius: 15
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
        console.log("RUNNING: LiquidGlassCard Geometry & Anti-Regression Tests");

        // ========================================================
        // 1. Rectangular Card Geometry & Specular Clamping
        // ========================================================
        assert(rectCard.radius === 16, "rectCard radius must be 16");
        assert(rectCard.showSpecular === true, "rectCard showSpecular must default to true");

        let rectTopGlare = rectCard.topGlareItem;
        assert(rectTopGlare !== undefined && rectTopGlare !== null, "rectCard must expose topGlareItem");
        assert(rectTopGlare.visible === true, "topGlare must be visible on wide rectangular card");

        // Mathematical invariant: topGlare MUST NOT extend into the rounded corner radius
        assert(rectTopGlare.x >= rectCard.radius, 
            "Anti-Regression: topGlare.x (" + rectTopGlare.x + ") must be >= radius (" + rectCard.radius + ") to prevent overhang");
        assert((rectTopGlare.x + rectTopGlare.width) <= (rectCard.width - rectCard.radius), 
            "Anti-Regression: topGlare right edge (" + (rectTopGlare.x + rectTopGlare.width) + ") must be <= (width - radius) (" + (rectCard.width - rectCard.radius) + ")");

        let rectSubGlare = rectCard.subGlareItem;
        assert(rectSubGlare !== undefined && rectSubGlare !== null, "rectCard must expose subGlareItem");
        if (rectSubGlare.visible) {
            assert(rectSubGlare.x >= rectCard.radius, "subGlare.x must be >= radius");
            assert((rectSubGlare.x + rectSubGlare.width) <= (rectCard.width - rectCard.radius), "subGlare right edge must be <= (width - radius)");
        }

        let rectBottomRim = rectCard.bottomRimItem;
        assert(rectBottomRim !== undefined && rectBottomRim !== null, "rectCard must expose bottomRimItem");
        if (rectBottomRim.visible) {
            assert(rectBottomRim.x >= rectCard.radius, "bottomRim.x must be >= radius");
            assert((rectBottomRim.x + rectBottomRim.width) <= (rectCard.width - rectCard.radius), "bottomRim right edge must be <= (width - radius)");
        }

        // ========================================================
        // 2. Vertical Pill (appsContainer) Top-Line Anti-Regression
        // ========================================================
        // For a vertical pill (width 48, radius 24), width <= radius * 2.
        // No flat top edge physically exists! topGlare MUST NOT be visible or have width > 0.
        let pillTopGlare = verticalPill.topGlareItem;
        assert(pillTopGlare !== undefined && pillTopGlare !== null, "verticalPill must expose topGlareItem");
        assert(pillTopGlare.visible === false || pillTopGlare.width <= 0, 
            "CRITICAL REGRESSION PREVENTED: On vertical pill where width <= radius * 2, topGlare must NOT be drawn as a straight line! Got visible=" + pillTopGlare.visible + " width=" + pillTopGlare.width);

        let pillSubGlare = verticalPill.subGlareItem;
        assert(pillSubGlare !== undefined && pillSubGlare !== null, "verticalPill must expose subGlareItem");
        assert(pillSubGlare.visible === false || pillSubGlare.width <= 0, 
            "CRITICAL REGRESSION PREVENTED: On vertical pill where width <= radius * 2, subGlare must NOT be drawn as a straight line!");

        let pillBottomRim = verticalPill.bottomRimItem;
        assert(pillBottomRim !== undefined && pillBottomRim !== null, "verticalPill must expose bottomRimItem");
        assert(pillBottomRim.visible === false || pillBottomRim.width <= 0, 
            "CRITICAL REGRESSION PREVENTED: On vertical pill where width <= radius * 2, bottomRim must NOT be drawn as a straight line!");

        // ========================================================
        // 3. Compact Pill (wsContainer) Top-Line Anti-Regression
        // ========================================================
        let compactTopGlare = compactPill.topGlareItem;
        assert(compactTopGlare.visible === false || compactTopGlare.width <= 0, 
            "CRITICAL REGRESSION PREVENTED: On compact pill, topGlare must not be drawn as a straight line!");

        // ========================================================
        // 4. Elevation Drop Shadow Verification
        // ========================================================
        assert(rectCard.showShadow !== undefined, "LiquidGlassCard must expose showShadow property");
        let shadowItem = rectCard.shadowItem;
        assert(shadowItem !== undefined && shadowItem !== null, "LiquidGlassCard must expose shadowItem");
        assert(shadowItem.opacity > 0, "LiquidGlassCard shadowItem must have visible opacity");

        console.log("PASS: LiquidGlassCard Geometry & Anti-Regression Tests");
        Qt.exit(0);
    }
}
