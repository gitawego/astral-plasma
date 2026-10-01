import QtQuick

QtObject {
    id: root

    // Metadata
    property string archetypeId: "base"
    property string name: "Base Archetype"
    property string description: "Base contract for Astral Plasma theme archetypes"
    property string author: "Astral Plasma Team"
    property string version: "1.0.0"

    // =========================================================================
    // 1. Geometry Tokens
    // =========================================================================
    // Corner Radii
    property int radiusFull: 9999
    property int radiusLarge: 24
    property int radiusMedium: 16
    property int radiusSmall: 10
    property int radiusExtraSmall: 6

    // Liquid Glass / Modal Radii
    property int radiusGlassModal: 32
    property int radiusGlassCard: 18
    property int radiusGlassItem: 12
    property int radiusGlassPill: 9999

    // Spacing and Margins
    property int spaceExtraLarge: 24
    property int spaceLarge: 16
    property int spaceMedium: 12
    property int spaceSmall: 8
    property int spaceExtraSmall: 4

    // Padding
    property int padExtraLarge: 20
    property int padLarge: 16
    property int padMedium: 12
    property int padSmall: 8
    property int padExtraSmall: 4

    // =========================================================================
    // 2. Material & Optical Surface Tokens
    // =========================================================================
    // Surface Paradigm: "liquid_glass" | "acrylic" | "flat_minimal" | "neon_cyber"
    property string surfaceStyle: "liquid_glass"

    // Optical features toggles
    property bool specularEnabled: true
    property bool causticEnabled: true
    property bool shadowsEnabled: true
    property bool innerRimEnabled: true

    // Specular and border physical dimensions
    property real glassSpecularWidth: 1.0
    property real glassBorderWidth: 1.0
    property real glassCausticIntensity: 0.06
    property real shadowElevationScale: 1.0

    // Glass Substrate Parameters (Evaluated over arbitrary wallpaper)
    property var glassParams: ({
        dark: {
            surfaceBase: [0.0, 0.0, 0.0],
            surfaceAlpha: 0.45,
            surfaceTint: 0.04,
            cardBase: [0.0, 0.0, 0.0],
            cardAlpha: 0.10,
            cardTint: 0.10,
            cardHoverAlpha: 0.30,
            cardHoverTint: 0.14,
            cardActiveAlpha: 0.40,
            cardActiveTint: 0.20,
            cardVibrantAlpha: 0.30,
            cardVibrantTint: 0.30,
            panelBase: [0.07, 0.08, 0.12],
            panelAlpha: 0.82
        },
        light: {
            surfaceBase: [1.0, 1.0, 1.0],
            surfaceAlpha: 0.45,
            surfaceTint: 0.06,
            cardBase: [1.0, 1.0, 1.0],
            cardAlpha: 0.10,
            cardTint: 0.06,
            cardHoverAlpha: 0.26,
            cardHoverTint: 0.14,
            cardActiveAlpha: 0.36,
            cardActiveTint: 0.22,
            cardVibrantAlpha: 0.28,
            cardVibrantTint: 0.30,
            panelBase: [0.95, 0.96, 0.99],
            panelAlpha: 0.84
        }
    })

    // =========================================================================
    // 3. Motion & Physics Tokens
    // =========================================================================
    // Standard durations (ms)
    property int animDurationFast: 150
    property int animDurationNormal: 250
    property int animDurationSlow: 400
    property var animEasing: Easing.OutCubic

    // Expressive motion durations (ms)
    property int animExpressiveFastSpatial: 350
    property int animExpressiveDefaultSpatial: 500
    property int animExpressiveSlowSpatial: 650
    property int animExpressiveFastEffects: 150
    property int animExpressiveDefaultEffects: 200
    property int animExpressiveSlowEffects: 300
    property int animEmphasized: 400

    // Expressive Cubic Bezier Spline Curves: [c1x, c1y, c2x, c2y, endX, endY]
    property var curveExpressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
    property var curveExpressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
    property var curveExpressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1.0, 1.0]
    property var curveExpressiveFastEffects: [0.31, 0.94, 0.34, 1.0, 1.0, 1.0]
    property var curveExpressiveDefaultEffects: [0.34, 0.80, 0.34, 1.0, 1.0, 1.0]
    property var curveExpressiveSlowEffects: [0.34, 0.88, 0.34, 1.0, 1.0, 1.0]
    property var curveEmphasizedDecel: [0.05, 0.70, 0.10, 1.0, 1.0, 1.0]
    property var curveStandard: [0.20, 0.0, 0.0, 1.0, 1.0, 1.0]

    // Elastic micro-physics
    property real glassScaleBounce: 0.985
    property int animGlassPress: 120
    property int animGlassRelease: 240
    property var curveGlassElastic: [0.34, 1.35, 0.30, 1.0, 1.0, 1.0]

    // Decorative continuous animation budget
    property int decorativeMaxFps: 30

    // =========================================================================
    // 4. Typography Tokens
    // =========================================================================
    property string fontFamily: "Google Sans Flex, Cantarell, Noto Sans, sans-serif"
    property string fontMonospace: "JetBrains Mono, monospace"

    property int fontTitleLarge: 26
    property int fontTitleMedium: 21
    property int fontTitleSmall: 16
    property int fontBodyMedium: 15
    property int fontBodySmall: 13
    property int fontLabelSmall: 12
}
