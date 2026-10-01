import QtQuick

ThemeArchetype {
    id: root

    archetypeId: "liquid_glass"
    name: "Liquid Glass"
    description: "Astral Plasma signature: continuous concentric curvature, refractive glass substrates, specular dome glares, and expressive liquid motion."
    author: "Astral Plasma Team"
    version: "1.0.0"

    // Liquid Glass uses large concentric rounds
    radiusFull: 9999
    radiusLarge: 24
    radiusMedium: 16
    radiusSmall: 10
    radiusExtraSmall: 6

    radiusGlassModal: 32
    radiusGlassCard: 18
    radiusGlassItem: 12
    radiusGlassPill: 9999

    // Optical surfaces: Full liquid glass materials
    surfaceStyle: "liquid_glass"
    specularEnabled: true
    causticEnabled: true
    shadowsEnabled: true
    innerRimEnabled: true

    glassSpecularWidth: 1.0
    glassBorderWidth: 1.0
    glassCausticIntensity: 0.06
    shadowElevationScale: 1.0

    // Spring elastic bounce physics
    glassScaleBounce: 0.985
    animGlassPress: 120
    animGlassRelease: 240
    curveGlassElastic: [0.34, 1.35, 0.30, 1.0, 1.0, 1.0]

    // Expressive spatial motion
    animExpressiveFastSpatial: 350
    animExpressiveDefaultSpatial: 500
    animExpressiveSlowSpatial: 650
    curveExpressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]

    fontFamily: "Google Sans Flex, Cantarell, Noto Sans, sans-serif"
    fontMonospace: "JetBrains Mono, monospace"
}
