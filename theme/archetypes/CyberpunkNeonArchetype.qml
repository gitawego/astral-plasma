import QtQuick

ThemeArchetype {
    id: root

    archetypeId: "cyberpunk_neon"
    name: "Cyberpunk Neon"
    description: "High-tech dystopian sci-fi aesthetic: sharp angular geometry, deep OLED black substrates, neon perimeter bloom, high-contrast borders, mechanical snappy physics, and monospace-first typography."
    author: "Astral Plasma Team"
    version: "1.0.0"

    // Geometry: Sharp, angular, high-density
    radiusFull: 9999
    radiusLarge: 4
    radiusMedium: 2
    radiusSmall: 0
    radiusExtraSmall: 0

    radiusGlassModal: 6
    radiusGlassCard: 2
    radiusGlassItem: 0
    radiusGlassPill: 4

    // Optical surfaces: High-intensity neon glow & OLED black
    surfaceStyle: "neon_cyber"
    specularEnabled: true
    causticEnabled: true
    shadowsEnabled: true
    innerRimEnabled: true

    glassSpecularWidth: 2.0
    glassBorderWidth: 1.5
    glassCausticIntensity: 0.18
    shadowElevationScale: 1.5

    // Glass parameters: OLED Black substrate with vibrant laser neon tinting
    glassParams: ({
        dark: {
            surfaceBase: [0.02, 0.02, 0.04],
            surfaceAlpha: 0.92,
            surfaceTint: 0.08,
            cardBase: [0.03, 0.03, 0.06],
            cardAlpha: 0.88,
            cardTint: 0.14,
            cardHoverAlpha: 0.94,
            cardHoverTint: 0.22,
            cardActiveAlpha: 0.96,
            cardActiveTint: 0.30,
            cardVibrantAlpha: 0.70,
            cardVibrantTint: 0.45,
            panelBase: [0.01, 0.01, 0.03],
            panelAlpha: 0.96
        },
        light: {
            surfaceBase: [0.92, 0.93, 0.98],
            surfaceAlpha: 0.88,
            surfaceTint: 0.08,
            cardBase: [0.96, 0.97, 1.0],
            cardAlpha: 0.92,
            cardTint: 0.12,
            cardHoverAlpha: 0.96,
            cardHoverTint: 0.18,
            cardActiveAlpha: 0.98,
            cardActiveTint: 0.24,
            cardVibrantAlpha: 0.80,
            cardVibrantTint: 0.35,
            panelBase: [0.90, 0.91, 0.95],
            panelAlpha: 0.94
        }
    })

    // Motion: Mechanical, hyper-snappy transitions
    glassScaleBounce: 0.97
    animGlassPress: 60
    animGlassRelease: 120
    curveGlassElastic: [0.1, 0.9, 0.2, 1.0, 1.0, 1.0]

    animDurationFast: 80
    animDurationNormal: 140
    animDurationSlow: 220

    animExpressiveFastSpatial: 140
    animExpressiveDefaultSpatial: 200
    animExpressiveSlowSpatial: 280
    curveExpressiveDefaultSpatial: [0.0, 0.0, 0.15, 1.0, 1.0, 1.0]

    fontFamily: "JetBrains Mono, Fira Code, monospace"
    fontMonospace: "JetBrains Mono, monospace"
}
