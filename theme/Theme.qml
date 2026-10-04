pragma Singleton

import QtQuick
import Quickshell
import "../config"
import "./archetypes"

Singleton {
    id: root

    // =========================================================================
    // Active Theme Archetype Delegation
    // =========================================================================
    // Built-in theme archetype instances
    readonly property LiquidGlassArchetype archetypeLiquidGlass: LiquidGlassArchetype {}
    readonly property NordicMinimalArchetype archetypeNordicMinimal: NordicMinimalArchetype {}
    readonly property CyberpunkNeonArchetype archetypeCyberpunkNeon: CyberpunkNeonArchetype {}

    // Registry table mapping archetype ID to instance
    readonly property var archetypes: ({
        "liquid_glass": root.archetypeLiquidGlass,
        "nordic_minimal": root.archetypeNordicMinimal,
        "cyberpunk_neon": root.archetypeCyberpunkNeon
    })

    // Active archetype name (reactively bound to Config)
    readonly property string archetypeName: {
        if (typeof Config !== "undefined" && Config.themeArchetype) {
            return Config.themeArchetype;
        }
        return "liquid_glass";
    }

    // Active archetype instance (defaults to liquid_glass)
    readonly property ThemeArchetype activeArchetype: {
        const key = (root.archetypeName || "liquid_glass").toLowerCase();
        return root.archetypes[key] || root.archetypeLiquidGlass;
    }

    // Helper: list of registered archetype descriptors
    function listArchetypes() {
        return [
            { id: "liquid_glass", name: root.archetypeLiquidGlass.name, description: root.archetypeLiquidGlass.description },
            { id: "nordic_minimal", name: root.archetypeNordicMinimal.name, description: root.archetypeNordicMinimal.description },
            { id: "cyberpunk_neon", name: root.archetypeCyberpunkNeon.name, description: root.archetypeCyberpunkNeon.description }
        ];
    }

    // Material & Optical Surface Tokens Facade
    readonly property QtObject material: QtObject {
        id: materialTokens
        readonly property string surfaceStyle: root.activeArchetype ? root.activeArchetype.surfaceStyle : "liquid_glass"
        readonly property bool specularEnabled: root.activeArchetype ? root.activeArchetype.specularEnabled : true
        readonly property bool causticEnabled: root.activeArchetype ? root.activeArchetype.causticEnabled : true
        readonly property bool shadowsEnabled: root.activeArchetype ? root.activeArchetype.shadowsEnabled : true
        readonly property bool innerRimEnabled: root.activeArchetype ? root.activeArchetype.innerRimEnabled : true
        readonly property real specularWidth: root.activeArchetype ? root.activeArchetype.glassSpecularWidth : 1.0
        readonly property real borderWidth: root.activeArchetype ? root.activeArchetype.glassBorderWidth : 1.0
        readonly property real causticIntensity: root.activeArchetype ? root.activeArchetype.glassCausticIntensity : 0.06
        readonly property real shadowElevationScale: root.activeArchetype ? root.activeArchetype.shadowElevationScale : 1.0
    }

    // Corner radius multiplier from user configuration (default 20px -> scale 1.0)
    readonly property int userCornerRadius: (typeof Config !== "undefined" && Config.themeCornerRadius !== undefined) ? Config.themeCornerRadius : 20
    readonly property real cornerRadiusScale: Math.max(0.2, root.userCornerRadius / 20.0)

    // Blur & Specular intensity multiplier from user configuration (default 0.85 -> scale 1.0)
    readonly property real blurStrength: (typeof Config !== "undefined" && Config.themeBlurStrength !== undefined) ? Config.themeBlurStrength : 0.85
    readonly property real blurStrengthScale: Math.max(0.1, root.blurStrength / 0.85)

    // =========================================================================
    // 1. Corner Radii (Dynamically Delegated to Active Archetype & Config)
    // =========================================================================
    readonly property int filletRounding: {
        if (!root.activeArchetype) return root.userCornerRadius;
        if (root.activeArchetype.filletRounding === 0) {
            return Math.max(0, root.userCornerRadius - 20);
        }
        return Math.max(0, Math.round(root.activeArchetype.filletRounding * root.cornerRadiusScale));
    }
    readonly property int radiusFull: root.activeArchetype ? root.activeArchetype.radiusFull : 9999
    readonly property int radiusLarge: root.activeArchetype ? Math.round(root.activeArchetype.radiusLarge * root.cornerRadiusScale) : Math.round(24 * root.cornerRadiusScale)
    readonly property int radiusMedium: root.activeArchetype ? Math.round(root.activeArchetype.radiusMedium * root.cornerRadiusScale) : Math.round(16 * root.cornerRadiusScale)
    readonly property int radiusSmall: root.activeArchetype ? Math.round(root.activeArchetype.radiusSmall * root.cornerRadiusScale) : Math.round(10 * root.cornerRadiusScale)
    readonly property int radiusExtraSmall: root.activeArchetype ? Math.round(root.activeArchetype.radiusExtraSmall * root.cornerRadiusScale) : Math.round(6 * root.cornerRadiusScale)

    // =========================================================================
    // 2. Spacing and Margins
    // =========================================================================
    readonly property int spaceExtraLarge: root.activeArchetype ? root.activeArchetype.spaceExtraLarge : 24
    readonly property int spaceLarge: root.activeArchetype ? root.activeArchetype.spaceLarge : 16
    readonly property int spaceMedium: root.activeArchetype ? root.activeArchetype.spaceMedium : 12
    readonly property int spaceSmall: root.activeArchetype ? root.activeArchetype.spaceSmall : 8
    readonly property int spaceExtraSmall: root.activeArchetype ? root.activeArchetype.spaceExtraSmall : 4

    // =========================================================================
    // 3. Padding
    // =========================================================================
    readonly property int padExtraLarge: root.activeArchetype ? root.activeArchetype.padExtraLarge : 20
    readonly property int padLarge: root.activeArchetype ? root.activeArchetype.padLarge : 16
    readonly property int padMedium: root.activeArchetype ? root.activeArchetype.padMedium : 12
    readonly property int padSmall: root.activeArchetype ? root.activeArchetype.padSmall : 8
    readonly property int padExtraSmall: root.activeArchetype ? root.activeArchetype.padExtraSmall : 4

    // =========================================================================
    // 4. Typography - Retina Scaled
    // =========================================================================
    readonly property string fontFamily: root.activeArchetype ? root.activeArchetype.fontFamily : "Google Sans Flex, Cantarell, Noto Sans, sans-serif"
    readonly property string fontMonospace: root.activeArchetype ? root.activeArchetype.fontMonospace : "JetBrains Mono, monospace"

    readonly property int fontTitleLarge: root.activeArchetype ? root.activeArchetype.fontTitleLarge : 26
    readonly property int fontTitleMedium: root.activeArchetype ? root.activeArchetype.fontTitleMedium : 21
    readonly property int fontTitleSmall: root.activeArchetype ? root.activeArchetype.fontTitleSmall : 16
    readonly property int fontBodyMedium: root.activeArchetype ? root.activeArchetype.fontBodyMedium : 15
    readonly property int fontBodySmall: root.activeArchetype ? root.activeArchetype.fontBodySmall : 13
    readonly property int fontLabelSmall: root.activeArchetype ? root.activeArchetype.fontLabelSmall : 12

    readonly property int fontSmall: root.fontBodySmall
    readonly property int fontMedium: root.fontBodyMedium
    readonly property int fontLarge: root.fontTitleMedium

    // =========================================================================
    // 5. Animation Presets & Motion Tokens (Canonical DESIGN.md Specification)
    // =========================================================================
    readonly property int animDurationFast: 150
    readonly property int animDurationNormal: 250
    readonly property int animDurationSlow: 400
    readonly property var animEasing: Easing.OutCubic

    // Upper bound on decorative idle motion update rate
    readonly property int decorativeMaxFps: 30

    // Expressive Motion Durations (ms)
    readonly property int animExpressiveFastSpatial: 350
    readonly property int animExpressiveDefaultSpatial: 500
    readonly property int animExpressiveSlowSpatial: 650
    readonly property int animExpressiveFastEffects: 150
    readonly property int animExpressiveDefaultEffects: 200
    readonly property int animExpressiveSlowEffects: 300
    readonly property int animEmphasized: 400

    // Expressive Cubic Bezier Spline Curves
    readonly property var curveExpressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
    readonly property var curveExpressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
    readonly property var curveExpressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1.0, 1.0]
    readonly property var curveExpressiveFastEffects: [0.31, 0.94, 0.34, 1.0, 1.0, 1.0]
    readonly property var curveExpressiveDefaultEffects: [0.34, 0.80, 0.34, 1.0, 1.0, 1.0]
    readonly property var curveExpressiveSlowEffects: [0.34, 0.88, 0.34, 1.0, 1.0, 1.0]
    readonly property var curveEmphasizedDecel: [0.05, 0.70, 0.10, 1.0, 1.0, 1.0]
    readonly property var curveStandard: [0.20, 0.0, 0.0, 1.0, 1.0, 1.0]

    // Soft drop shadow
    readonly property color shadowColor: Qt.rgba(0, 0, 0, 0.08)
    readonly property color borderSubtle: Qt.alpha(Colors.outline, 0.18)

    // =========================================================================
    // 6. Surface & Component Tokens
    // =========================================================================
    readonly property int radiusGlassModal: {
        if (!root.activeArchetype) return root.userCornerRadius;
        if (root.activeArchetype.radiusGlassModal === 0) return Math.max(0, root.userCornerRadius - 20);
        return Math.max(0, Math.round(root.activeArchetype.radiusGlassModal * root.cornerRadiusScale));
    }
    readonly property int radiusGlassCard: {
        if (!root.activeArchetype) return Math.max(0, root.userCornerRadius - 2);
        if (root.activeArchetype.radiusGlassCard === 0) return Math.max(0, root.userCornerRadius - 20);
        return Math.max(0, Math.round(root.activeArchetype.radiusGlassCard * root.cornerRadiusScale));
    }
    readonly property int radiusGlassItem: {
        if (!root.activeArchetype) return Math.max(0, root.userCornerRadius - 8);
        if (root.activeArchetype.radiusGlassItem === 0) return Math.max(0, Math.round((root.userCornerRadius - 20) / 2));
        return Math.max(0, Math.round(root.activeArchetype.radiusGlassItem * root.cornerRadiusScale));
    }
    readonly property int radiusGlassPill: root.activeArchetype ? root.activeArchetype.radiusGlassPill : 9999

    readonly property real glassSpecularWidth: root.activeArchetype ? root.activeArchetype.glassSpecularWidth : 1.0
    readonly property real glassBorderWidth: root.activeArchetype ? root.activeArchetype.glassBorderWidth : 1.0
    readonly property real glassCausticIntensity: root.activeArchetype ? (root.activeArchetype.glassCausticIntensity * root.blurStrengthScale) : 0.06

    // Interactive scale bounce & liquid compression physics
    readonly property real glassScaleBounce: root.activeArchetype ? root.activeArchetype.glassScaleBounce : 0.985
    readonly property int animGlassPress: root.activeArchetype ? root.activeArchetype.animGlassPress : 120
    readonly property int animGlassRelease: root.activeArchetype ? root.activeArchetype.animGlassRelease : 240
    readonly property var curveGlassElastic: root.activeArchetype ? root.activeArchetype.curveGlassElastic : [0.34, 1.35, 0.30, 1.0, 1.0, 1.0]

    // =========================================================================
    // 7. Media & Visualizer Archetype Tokens
    // =========================================================================
    readonly property bool mediaCircularCover: root.activeArchetype ? root.activeArchetype.mediaCircularCover : true
    readonly property bool mediaOrbitalRing: root.activeArchetype ? root.activeArchetype.mediaOrbitalRing : true
    readonly property bool mediaVinylSpin: root.activeArchetype ? root.activeArchetype.mediaVinylSpin : true
    readonly property string mediaCoverStyle: root.activeArchetype ? root.activeArchetype.mediaCoverStyle : "circular"
    readonly property string surfaceStyle: root.activeArchetype ? root.activeArchetype.surfaceStyle : "liquid_glass"
    readonly property bool isCyberpunk: surfaceStyle === "neon_cyber"
}

