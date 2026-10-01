import QtQuick

ThemeArchetype {
    id: root

    archetypeId: "nordic_minimal"
    name: "Nordic Minimal"
    description: "Clean, flat Scandinavian aesthetic: subtle compact corner radii, high-opacity matte substrates, crisp hairline borders, zero specular glint, and snappy linear-cubic motion."
    author: "Astral Plasma Team"
    version: "1.0.0"

    // Geometry: Subtle, disciplined radii
    radiusFull: 9999
    radiusLarge: 12
    radiusMedium: 8
    radiusSmall: 4
    radiusExtraSmall: 2

    radiusGlassModal: 12
    radiusGlassCard: 6
    radiusGlassItem: 4
    radiusGlassPill: 9999

    // Optical surfaces: Flat matte surfaces, NO specular or caustics
    surfaceStyle: "flat_minimal"
    specularEnabled: false
    causticEnabled: false
    shadowsEnabled: false
    innerRimEnabled: false

    glassSpecularWidth: 0.0
    glassBorderWidth: 1.0
    glassCausticIntensity: 0.0
    shadowElevationScale: 0.25

    // Glass parameters: High opacity, matte legibility
    glassParams: ({
        dark: {
            surfaceBase: [0.08, 0.09, 0.11],
            surfaceAlpha: 0.88,
            surfaceTint: 0.02,
            cardBase: [0.12, 0.13, 0.16],
            cardAlpha: 0.92,
            cardTint: 0.02,
            cardHoverAlpha: 0.96,
            cardHoverTint: 0.04,
            cardActiveAlpha: 0.98,
            cardActiveTint: 0.06,
            cardVibrantAlpha: 0.85,
            cardVibrantTint: 0.10,
            panelBase: [0.08, 0.09, 0.11],
            panelAlpha: 0.94
        },
        light: {
            surfaceBase: [0.97, 0.97, 0.98],
            surfaceAlpha: 0.90,
            surfaceTint: 0.02,
            cardBase: [1.0, 1.0, 1.0],
            cardAlpha: 0.95,
            cardTint: 0.02,
            cardHoverAlpha: 0.98,
            cardHoverTint: 0.04,
            cardActiveAlpha: 1.0,
            cardActiveTint: 0.06,
            cardVibrantAlpha: 0.92,
            cardVibrantTint: 0.08,
            panelBase: [0.97, 0.97, 0.98],
            panelAlpha: 0.95
        }
    })

    // Motion: Snappy, non-elastic transitions
    glassScaleBounce: 1.0
    animGlassPress: 80
    animGlassRelease: 140
    curveGlassElastic: [0.20, 0.0, 0.0, 1.0, 1.0, 1.0]

    animDurationFast: 100
    animDurationNormal: 180
    animDurationSlow: 280

    animExpressiveFastSpatial: 180
    animExpressiveDefaultSpatial: 260
    animExpressiveSlowSpatial: 360
    curveExpressiveDefaultSpatial: [0.16, 1.0, 0.3, 1.0, 1.0, 1.0]

    fontFamily: "Inter, Cantarell, Noto Sans, sans-serif"
    fontMonospace: "JetBrains Mono, monospace"
}
