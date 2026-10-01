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

    // 5. Semantic Design System Buttons
    PillButton {
        id: errorBtn
        x: 50
        y: 120
        label: "Delete"
        accent: "error"
        active: true
    }

    PillButton {
        id: warningBtn
        x: 180
        y: 120
        label: "Caution"
        accent: "warning"
        active: true
    }

    PillButton {
        id: infoBtn
        x: 310
        y: 120
        label: "Details"
        accent: "info"
        active: true
    }

    PillButton {
        id: successBtn
        x: 440
        y: 120
        label: "Confirm"
        accent: "success"
        active: true
    }

    PillButton {
        id: neutralBtn
        x: 570
        y: 120
        label: "More"
        accent: "neutral"
        active: true
    }

    PillButton {
        id: filledErrorBtn
        x: 50
        y: 180
        label: "Destroy"
        accent: "error"
        variant: "filled"
        active: true
    }

    PillButton {
        id: outlinedWarningBtn
        x: 180
        y: 180
        label: "Warning"
        accent: "warning"
        variant: "outlined"
        active: true
    }

    PillButton {
        id: ghostInfoBtn
        x: 310
        y: 180
        label: "Info"
        accent: "info"
        variant: "ghost"
        active: true
    }

    PillButton {
        id: customOverrideBtn
        x: 440
        y: 180
        label: "Custom"
        activeColor: "#123456"
        activeTextColor: "#ABCDEF"
        activeBorderColor: "#56789A"
        active: true
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function srgbToLin(c) {
        c = c / 255.0;
        return (c <= 0.04045) ? (c / 12.92) : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function lum(colorObj) {
        // colorObj in QML has r, g, b in [0, 1]
        let r = srgbToLin(Math.round(colorObj.r * 255));
        let g = srgbToLin(Math.round(colorObj.g * 255));
        let b = srgbToLin(Math.round(colorObj.b * 255));
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    function contrastRatio(c1, c2) {
        let l1 = lum(Qt.color(c1));
        let l2 = lum(Qt.color(c2));
        let lighter = Math.max(l1, l2);
        let darker = Math.min(l1, l2);
        return (lighter + 0.05) / (darker + 0.05);
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
        let circleGlare = iconOnlyBtn.topGlareItem;
        assert(circleGlare !== undefined && circleGlare !== null, "iconOnlyBtn must expose topGlareItem");
        assert(circleGlare.visible === false || circleGlare.width <= 0, 
            "CRITICAL: On square/circular pill button, topGlare must not draw an overhanging flat line! Got visible=" + circleGlare.visible + " width=" + circleGlare.width);

        // ========================================================
        // 4. GlassPill Liquid Glass Optics
        // ========================================================
        assert(glassPillItem.contactShadowItem !== undefined && glassPillItem.contactShadowItem !== null, 
            "GlassPill must expose contactShadowItem");

        // ========================================================
        // 5. Semantic Accent & Variant Design System
        // ========================================================
        // Error / Destructive button
        assert(errorBtn.accent === "error", "errorBtn accent is error");
        assert(errorBtn.variant === "tonal", "default variant is tonal");
        assert(("" + errorBtn.activeTextColor).toLowerCase() !== "#410002" &&
               ("" + errorBtn.activeTextColor).toLowerCase() !== "#000000",
               "Error button text color must be readable and NOT black or dark brown (#410002)");
        let errorCr = contrastRatio(errorBtn.activeColor, errorBtn.activeTextColor);
        console.log("Error Tonal contrast ratio:", errorCr.toFixed(2));
        assert(errorCr >= 7.0, "Error tonal button contrast must meet WCAG AAA (>= 7:1), got: " + errorCr);

        // Warning button
        assert(warningBtn.accent === "warning", "warningBtn accent is warning");
        let warnCr = contrastRatio(warningBtn.activeColor, warningBtn.activeTextColor);
        console.log("Warning Tonal contrast ratio:", warnCr.toFixed(2));
        assert(warnCr >= 7.0, "Warning tonal button contrast must meet WCAG AAA (>= 7:1), got: " + warnCr);

        // Info button
        assert(infoBtn.accent === "info", "infoBtn accent is info");
        let infoCr = contrastRatio(infoBtn.activeColor, infoBtn.activeTextColor);
        console.log("Info Tonal contrast ratio:", infoCr.toFixed(2));
        assert(infoCr >= 7.0, "Info tonal button contrast must meet WCAG AAA (>= 7:1), got: " + infoCr);

        // Success button
        assert(successBtn.accent === "success", "successBtn accent is success");
        let succCr = contrastRatio(successBtn.activeColor, successBtn.activeTextColor);
        console.log("Success Tonal contrast ratio:", succCr.toFixed(2));
        assert(succCr >= 7.0, "Success tonal button contrast must meet WCAG AAA (>= 7:1), got: " + succCr);

        // Neutral button
        assert(neutralBtn.accent === "neutral", "neutralBtn accent is neutral");
        let neutCr = contrastRatio(neutralBtn.activeColor, neutralBtn.activeTextColor);
        console.log("Neutral Tonal contrast ratio:", neutCr.toFixed(2));
        assert(neutCr >= 7.0, "Neutral tonal button contrast must meet WCAG AAA (>= 7:1), got: " + neutCr);

        // Filled Variant
        assert(filledErrorBtn.variant === "filled", "filledErrorBtn variant is filled");
        let filledCr = contrastRatio(filledErrorBtn.activeColor, filledErrorBtn.activeTextColor);
        console.log("Filled Error contrast ratio:", filledCr.toFixed(2));
        assert(filledCr >= 4.5, "Filled Error button contrast must meet WCAG AA (>= 4.5:1), got: " + filledCr);

        // Outlined Variant
        assert(outlinedWarningBtn.variant === "outlined", "outlinedWarningBtn variant is outlined");
        assert(outlinedWarningBtn.border.width >= 1.0, "outlined button must have border");

        // Ghost Variant
        assert(ghostInfoBtn.variant === "ghost", "ghostInfoBtn variant is ghost");

        // Custom Override Preservation
        assert(("" + customOverrideBtn.activeColor).toLowerCase() === "#123456", "Explicit activeColor override preserved");
        assert(("" + customOverrideBtn.activeTextColor).toLowerCase() === "#abcdef", "Explicit activeTextColor override preserved");
        assert(("" + customOverrideBtn.activeBorderColor).toLowerCase() === "#56789a", "Explicit activeBorderColor override preserved");

        // Anti-Cropping & Scale Bounds Contract
        assert(pillBtn.hoverScale === false, "hoverScale must default to false to prevent clipping against clipped parent containers");
        assert(pillBtn.scale === 1.0, "PillButton scale must be exactly 1.0 by default to stay within bounding box");

        console.log("PASS: PillButton & GlassPill Liquid Glass Tests");
        Qt.exit(0);
    }
}
